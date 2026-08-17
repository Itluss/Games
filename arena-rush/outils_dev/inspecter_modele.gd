extends Node
## MESURE DE LA LATENCE DU BOUTON DE TIR — outil de développement.
##
## Retour de test : « quand j'appuie, ça ne tire pas immédiatement ».
## On ne cherche pas la cause à la lecture du code : on injecte un appui
## et on COMPTE les trames jusqu'à l'apparition d'un projectile.

var _main: Node

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	await _mesurer()
	get_tree().quit()

## Les projectiles ne sont pas groupés : on les compte par leur classe,
## en balayant la scène courante.
func _projectiles() -> int:
	return _compter(get_tree().current_scene)

func _compter(n: Node) -> int:
	var total := 0
	if n is Projectile and (n as Node3D).visible:
		total += 1
	for c in n.get_children():
		total += _compter(c)
	return total

func _clic(pos: Vector2, appui: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = appui
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)

func _mesurer() -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	var bouton: Control = hud.get(&"_fire_button")
	var joueur: Node = null
	for p in get_tree().get_nodes_in_group(&"players"):
		joueur = p
		break
	if bouton == null or joueur == null:
		print("ÉCHEC : bouton ou joueur introuvable")
		return
	print("groupes de projectiles au départ : ", _projectiles())

	var cd: float = joueur.weapon.data.cooldown()
	print("cadence de l'arme : %.3f s de recharge" % cd)

	# CAS 1 — arme PRÊTE. On attend une réponse immédiate.
	await _essai(joueur, bouton, 0.0, "arme prête")
	# CAS 2 — appui EN PLEINE RECHARGE. C'est le cas rapporté : l'appui
	# était jeté et rien ne partait. Il doit désormais être mémorisé et
	# repartir seul.
	await _essai(joueur, bouton, cd * 0.95, "appui pendant la recharge")
	await _essai(joueur, bouton, cd * 0.60, "appui à mi-recharge")

func _essai(joueur: Node, bouton: Control, cooldown: float, libelle: String) -> void:
	joueur.weapon._cooldown = 0.0
	for i in 15:
		await get_tree().process_frame
	joueur.weapon._cooldown = cooldown
	var avant := _projectiles()
	# UN SEUL appui bref : on relâche tout de suite, pour qu'aucun
	# maintien ne vienne masquer le comportement de la mémoire.
	_clic(bouton.get_global_rect().get_center(), true)
	await get_tree().process_frame
	await get_tree().process_frame
	_clic(bouton.get_global_rect().get_center(), false)
	# On mesure en SECONDES : sous rendu logiciel le jeu tourne à une
	# dizaine d'images par seconde, si bien qu'un compte de trames ne dit
	# rien de la durée réellement écoulée.
	var debut := Time.get_ticks_msec()
	var delai := -1.0
	for i in 200:
		await get_tree().process_frame
		if _projectiles() > avant:
			delai = (Time.get_ticks_msec() - debut) / 1000.0
			break
	print("  %-28s recharge=%.2f s → tir %s"
			% [libelle, cooldown,
			("après %.2f s" % delai) if delai >= 0.0 else "JAMAIS (appui perdu)"])
