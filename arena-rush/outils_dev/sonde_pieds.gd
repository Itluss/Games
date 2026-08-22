extends Node
## SONDE DES PIEDS — le contact au sol, vu de profil, dans le vrai jeu.
##
## LE RETOUR DE TEST : « les personnages sont enfoncés dans le sol ». La
## caméra du jeu, en plongée, ne permet pas d'en juger : l'enfoncement s'y
## confond avec la perspective. Cette sonde pose une caméra AU RAS DU SOL,
## de profil, sur le joueur et sur un bot voisin — la ligne des pieds
## devient une mesure, plus une impression. Une photo à l'arrêt, une photo
## au cœur de la roulade : le retour cite les deux cas.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_pieds.tscn \
##       --rendering-driver opengl3 -- --solo

var _joueur: Node3D
var _bot: Node3D
var _cam: Camera3D
var _dossier := ""
var _etape := 0
var _attente := 8
var _prete := false

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_dossier = ProjectSettings.globalize_path("user://sonde_pieds")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			if _bot == null:
				_bot = p
			else:
				p.queue_free()
		else:
			_joueur = p
	if _joueur == null or _bot == null:
		push_error("Joueur ou bot manquant.")
		get_tree().quit(1)
		return
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	_bot.global_position = _joueur.global_position + Vector3(2.4, 0.0, 0.0)
	_bot.set(&"move_input", Vector2.ZERO)
	_bot.set(&"want_fire", false)
	_bot.set_physics_process(false)
	_bot.set_process(false)
	# Caméra de profil, presque à hauteur de sol : notre propre caméra,
	# pour ne rien devoir à celle du jeu.
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.make_current()
	var base: Vector3 = _joueur.global_position
	_cam.global_position = base + Vector3(-5.8, 1.7, 0.6)
	_cam.look_at(base + Vector3(0.6, 0.9, 0.0), Vector3.UP)
	_prete = true
	RenderingServer.frame_post_draw.connect(_capturer)


func _capturer() -> void:
	if not _prete:
		return
	if _attente > 0:
		_attente -= 1
		return
	var img := get_viewport().get_texture().get_image()
	if _etape == 0:
		img.save_png(_dossier.path_join("debout.png"))
		# Deuxième temps : la roulade, photographiée à mi-course.
		Engine.time_scale = 0.25
		_joueur.set(&"want_dash", true)
		_attente = 10
		_etape = 1
		return
	img.save_png(_dossier.path_join("roulade.png"))
	Engine.time_scale = 1.0
	_prete = false
	print("=== 0 échec(s) sur 1 vérification ===")
	get_tree().quit(0)
