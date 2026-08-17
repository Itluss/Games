extends Node
## APERÇU DE L'INTERFACE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER EXISTE : une interface ne se juge pas au code. Les
## réglages qui la font vivre — épaisseur d'un anneau, force d'une ombre,
## inclinaison d'une lettre — n'ont aucun sens lus dans un fichier, et
## chacun d'eux peut ruiner l'ensemble sans qu'aucun test ne bronche.
##
## Le banc lance une vraie partie, la met dans un état DIGNE D'ÊTRE
## REGARDÉ — vie entamée, deux armes en main, une annonce à l'écran — et
## capture. Une capture d'interface au repos ne montrerait ni la barre
## partiellement vidée, ni la plaque d'élimination, c'est-à-dire
## précisément les pièces les plus délicates à régler.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_interface.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 1280
const HAUTEUR := 720

var _main: Node

func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	await _mettre_en_scene()
	await _capturer()
	get_tree().quit()


func _joueur() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			return p
	return null


## Compose la situation à photographier. Rien ici ne doit ressembler à un
## état de repos : c'est en plein combat que l'interface doit tenir.
func _mettre_en_scene() -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	var j := _joueur()
	if j == null or hud == null:
		push_error("Ni joueur ni interface : la scène n'est pas montée.")
		return

	# Une deuxième arme, pour que les deux cartes soient remplies et qu'on
	# voie la différence entre la carte active et l'autre.
	j.server_pickup(&"shotgun")
	await get_tree().process_frame

	# Vie entamée : une barre pleine ne dit rien de la jauge ni du dégradé.
	var pv = j.get(&"health")
	if pv != null:
		pv.apply_damage(31.0, j.global_position)
	await get_tree().process_frame

	if hud.has_method(&"_on_alive_changed"):
		hud.call(&"_on_alive_changed", 2)
	if hud.has_method(&"_on_announce"):
		hud.call(&"_on_announce", "BOT 3 ÉLIMINÉ", Color("ffb43a"))
	# On laisse la plaque finir son arrivée : capturée en cours
	# d'animation, elle paraîtrait mal centrée ou trop petite.
	await get_tree().create_timer(0.45).timeout

	# Bouton de tir MAINTENU : l'état enfoncé est celui que le joueur voit
	# la moitié du temps, et c'est celui qu'on oublie de vérifier.
	if hud.has_method(&"_marquer_tir"):
		hud.call(&"_marquer_tir", true)
	for i in 3:
		await get_tree().process_frame


func _capturer() -> void:
	var dossier := ProjectSettings.globalize_path("user://apercu")
	DirAccess.make_dir_recursive_absolute(dossier)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nom := dossier + "/interface.png"
	img.save_png(nom)
	print("→ ", nom)
