extends Node
## SONDE DE RECONNAISSANCE — outil de développement, hors jeu.
##
## LA QUESTION POSÉE PAR LE TEST UTILISATEUR : « je ne reconnais pas les
## autres participants — des boules blanches sans aucune identification
## visuelle ». La réponse envisagée est un angle de caméra plus rasant ;
## cette sonde est l'instrument qui permet d'en juger SUR IMAGE au lieu de
## le supposer.
##
## Elle lance une vraie partie, aligne six bots-mascottes en arc devant le
## joueur aux distances réelles de combat (4 à 9 m), et photographie à
## travers LA caméra du jeu sous deux plongées : l'ancienne (52°) et la
## nouvelle (42°). Deux images, mêmes personnages, mêmes distances — la
## seule variable est l'angle. Si les visages et chapeaux n'apparaissent
## qu'à 42°, la baisse est justifiée ; sinon il faudra autre chose.
##
## Usage :
##   godot --path arena-rush res://outils_dev/sonde_reconnaissance.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 1280
const HAUTEUR := 720
## Les deux plongées comparées : nom de fichier → hauteur / recul.
## Même distance totale (14,8 m) : seule l'inclinaison change.
const ANGLES := [
	{"nom": "angle52", "h": 11.7, "d": 9.0},
	{"nom": "angle42", "h": 9.9, "d": 11.0},
]
## Position des bots : arc face à la caméra, distances de combat.
const POSTES := [
	Vector3(-4.5, 0.0, -4.0), Vector3(-2.0, 0.0, -6.5),
	Vector3(0.5, 0.0, -8.5), Vector3(3.0, 0.0, -7.0),
	Vector3(5.0, 0.0, -4.5), Vector3(1.5, 0.0, -3.0),
]
const REPOS := 8

var _joueur: Node3D
var _cam: Camera3D
var _etape := 0
var _attente := 0
var _dossier := ""
var _prete := false

func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://sonde_reco")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	_installer()
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	_prete = true
	_regler(0)
	RenderingServer.frame_post_draw.connect(_capturer)


## Fige la partie et pose les bots en arc devant le joueur.
func _installer() -> void:
	var bots: Array = []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			bots.append(p)
		else:
			_joueur = p
	if _joueur == null:
		return
	# Le monde s'arrête : mobs supprimés, pondeur et chef d'orchestre coupés.
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	var monde := get_tree().get_first_node_in_group(&"game_world")
	if monde:
		monde.set_process(false)
	# Les bots deviennent des statues aux postes prévus, tournées vers la
	# caméra : c'est l'orientation sous laquelle on doit les reconnaître.
	var base: Vector3 = _joueur.global_position
	for i in bots.size():
		var b: Node3D = bots[i]
		if i < POSTES.size():
			b.global_position = base + POSTES[i]
			b.set(&"move_input", Vector2.ZERO)
			b.set(&"want_fire", false)
			b.set(&"_facing", 0.0)
		else:
			b.queue_free()
		b.set_physics_process(false)
		b.set_process(false)
	_joueur.set(&"move_input", Vector2.ZERO)
	_joueur.set(&"want_fire", false)
	_joueur.set_physics_process(false)
	_cam = get_viewport().get_camera_3d()


func _regler(i: int) -> void:
	var a: Dictionary = ANGLES[i]
	# Les NOMINALES sont la source de vérité : l'adaptation de zone
	# recalcule hauteur et recul à partir d'elles chaque image.
	_cam.set(&"_hauteur_nominale", a["h"])
	_cam.set(&"_recul_nominal", a["d"])
	_cam.set(&"height", a["h"])
	_cam.set(&"distance", a["d"])
	if _cam.has_method(&"_snap"):
		_cam.call(&"_snap")
	_attente = REPOS


func _capturer() -> void:
	if not _prete:
		return
	if _attente > 0:
		_attente -= 1
		return
	var img := get_viewport().get_texture().get_image()
	var a: Dictionary = ANGLES[_etape]
	img.save_png(_dossier.path_join(a["nom"] + ".png"))
	print("  photo %s (h %.1f / d %.1f)" % [a["nom"], a["h"], a["d"]])
	_etape += 1
	if _etape >= ANGLES.size():
		_prete = false
		print("=== 0 échec(s) sur 1 vérification ===")
		get_tree().quit(0)
		return
	_regler(_etape)
