extends Node
## SONDE DU CANON — la compétence spéciale, photographiée en séquence.
##
## LE RETOUR DE TEST : « des ronds rouges au sol, c'est nul — on attend
## une explosion fidèle à la planche ». L'explosion a été refaite en
## quatre temps (éclair, feu, éclats, fumée) ; cette sonde en apporte la
## preuve : elle déclenche le Bombardement dans une vraie partie, au
## ralenti, et photographie chaque étape à travers la caméra du jeu. La
## planche obtenue doit montrer l'anticipation, la chute, le CŒUR
## éclatant, la boule orange, la fumée — sinon c'est à refaire.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_canon.tscn \
##       --rendering-driver opengl3 -- --solo

const PHOTOS := 24
## Une image sur N : la séquence entière dure ~3 s de jeu.
const PAS := 4
const RALENTI := 0.35

var _joueur: Node3D
var _dossier := ""
var _photo := 0
var _attente := 10
var _lancee := false
var _tic := 0
var _prete := false

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_dossier = ProjectSettings.globalize_path("user://sonde_canon")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			p.queue_free()
		else:
			_joueur = p
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	Engine.time_scale = RALENTI
	_prete = true
	RenderingServer.frame_post_draw.connect(_capturer)


func _capturer() -> void:
	if not _prete:
		return
	if _attente > 0:
		_attente -= 1
		return
	if not _lancee:
		_joueur.set(&"want_special", true)
		_lancee = true
		return
	_tic += 1
	if _tic % PAS != 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dossier.path_join("canon_%02d.png" % _photo))
	var bomb := get_tree().root.find_child("Bombardement", true, false)
	var cam := get_viewport().get_camera_3d()
	if bomb != null and cam != null:
		var e := cam.unproject_position((bomb as Node3D).global_position)
		print("ZONE %02d %d %d" % [_photo, int(e.x), int(e.y)])
	_photo += 1
	if _photo >= PHOTOS:
		_prete = false
		Engine.time_scale = 1.0
		print("=== 0 échec(s) sur 1 vérification ===")
		get_tree().quit(0)
