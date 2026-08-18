extends Node
## APERÇU DE COMBAT — outil de développement, hors jeu.
##
## POURQUOI CELUI-CI EN PLUS DES AUTRES. `apercu_arene` photographie le
## monde depuis une caméra libre posée à la main : elle dit à quoi ressemble
## le décor, jamais à quoi ressemble LE JEU. Or la consigne visuelle porte
## sur un rapport — le joueur, les mobs, les armes et les tirs doivent se
## détacher du décor — et un rapport ne se juge que dans le cadre réel, à la
## distance réelle, avec l'interface par-dessus.
##
## Ce banc lance donc une vraie partie, emmène le joueur dans les ruines,
## pose UN mob de chaque famille autour de lui et photographie à travers la
## caméra du jeu, arme après arme. C'est l'instrument qui permet de dire
## « le personnage est plus visible » autrement qu'en le supposant.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_combat.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 1280
const HAUTEUR := 720
## Cœur du secteur des ruines — la zone d'essai visuel.
const RUINES := Vector3(-46.0, 0.0, -38.0)
## Armes photographiées, dans l'ordre. Chacune doit être reconnaissable à sa
## seule silhouette : c'est ce que ces quatre images servent à vérifier.
const ARMES: Array[StringName] = [&"basic_blaster", &"shotgun",
		&"energy_blaster", &"grenade_launcher"]

var _main: Node
var _dossier := ""


func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://apercu")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	await _installer()
	for arme: StringName in ARMES:
		await _photographier_arme(arme)
	await _photographier_le_pont()
	get_tree().quit()


func _joueur() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			return p
	return null


## Emmène le joueur dans les ruines et pose les trois familles de mobs.
##
## LES MOBS SONT POSÉS À LA MAIN, PAS ATTENDUS. Le pondeur choisit ses
## positions selon la pression de la partie : on photographierait alors ce
## que le hasard a bien voulu donner, et deux captures ne seraient jamais
## comparables. Ici les trois familles sont côte à côte, à distance égale,
## toujours au même endroit — c'est la seule façon de comparer un avant et
## un après.
func _trouver_monde() -> Node:
	var principal := get_tree().get_first_node_in_group(&"main")
	if principal == null:
		principal = _main
	for n in principal.get_children():
		if n.get(&"controller") != null:
			return n
	return null


func _installer() -> void:
	var j := _joueur()
	if j == null:
		push_error("Aucun joueur local : la scène n'est pas montée.")
		return
	j.global_position = RUINES + Vector3(0, 0.6, 0)
	PlanMonde.ancre = j.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame

	var monde := _trouver_monde()
	if monde == null:
		push_error("Monde introuvable : impossible de poser les mobs.")
		return

	# Trois familles, trois azimuts, même distance : la comparaison des
	# silhouettes ne doit rien devoir à la perspective.
	var poses := {
		&"charger": RUINES + Vector3(-4.5, 0.0, -5.0),
		&"shooter": RUINES + Vector3(0.0, 0.0, -6.5),
		&"exploder": RUINES + Vector3(4.5, 0.0, -5.0),
	}
	var id := 9000
	for famille: StringName in poses:
		monde.call(&"net_spawn_mob", id, famille, poses[famille])
		id += 1
	await get_tree().create_timer(0.6).timeout

	# On empêche les mobs de charger : un banc de photo n'a pas à mesurer
	# une poursuite, et un fonceur arrivé au contact masquerait le joueur.
	for m in get_tree().get_nodes_in_group(&"mobs"):
		m.set_physics_process(false)

	# Vie entamée et session en cours : l'interface au repos ne montre ni
	# jauge partielle ni compteur, donc rien de ce qu'il faut juger.
	var pv = j.get(&"health")
	if pv != null:
		pv.apply_damage(28.0, j.global_position)


## Photographie une arme, tir en cours.
##
## LE TIR EST DÉCLENCHÉ, PAS SIMULÉ. Ce qu'on veut voir, c'est le projectile
## en vol et l'éclair de bouche tels que le jeu les produit — un effet posé
## à la main ne dirait rien de ce que le joueur verra.
func _photographier_arme(arme: StringName) -> void:
	var j := _joueur()
	if j == null:
		return
	# ON DÉBRANCHE LE CONTRÔLEUR PENDANT LA POSE.
	#
	# Premier jet : on posait `aim_input` et le contrôleur le réécrivait à
	# l'image suivante. Sa visée automatique accrochait un bot situé DERRIÈRE
	# le joueur, l'avance de caméra partait donc en arrière, et le
	# personnage se retrouvait minuscule en haut du cadre, à moitié caché par
	# l'interface. La photo montrait un défaut de cadrage qui n'existait que
	# dans le banc.
	var monde := _trouver_monde()
	var ctrl: Node = monde.get(&"controller") if monde else null
	if ctrl:
		ctrl.set_process(false)
	j.server_pickup(arme)
	await get_tree().process_frame
	j.set(&"aim_input", Vector3(0, 0, -1))
	j.set(&"want_fire", true)
	# Quelques images : le temps qu'un projectile quitte le canon et qu'on
	# le voie EN VOL, à mi-chemin de sa cible. Tiré à la première image, il
	# serait encore collé à l'arme et ne prouverait rien.
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nom := "%s/combat_%s.png" % [_dossier, arme]
	img.save_png(nom)
	print("→ ", nom)
	j.set(&"want_fire", false)
	for i in 6:
		await get_tree().process_frame
	if ctrl:
		ctrl.set_process(true)


## SOUS LE PONT — la capture de non-régression du défaut « écran opaque ».
##
## Le pont est décrit comme « une arche que l'on franchit par-dessous » et
## son tablier passe à 8,3 m, sous la caméra. C'est l'endroit qui a rempli
## l'écran de pierre pendant cinq signalements. Toute modification de la
## caméra ou des repères doit repasser par cette image.
func _photographier_le_pont() -> void:
	var j := _joueur()
	if j == null:
		return
	var pont := PlanMonde.point_interet(&"pont")
	var p := PlanMonde.position_poi(pont)
	var ou := Vector3(p.x, 0.6, p.y)
	# ON LE REMET DEBOUT. Le banc a mis quatre minutes à faire ses quatre
	# premières photos, et les bots avaient eu le temps de le tuer : la
	# capture montrait l'écran d'élimination, pas le pont.
	j.revivre(ou)
	PlanMonde.ancre = ou
	# Le temps que la caméra se recale et que le voile s'applique.
	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nom := _dossier + "/combat_sous_pont.png"
	img.save_png(nom)
	print("→ ", nom)
