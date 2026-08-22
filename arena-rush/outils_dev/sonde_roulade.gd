extends Node
## SONDE DE ROULADE — outil de développement, hors jeu.
##
## LE RETOUR DE TEST : « la roulade du pirate : bien trop rapide, le
## mouvement n'est pas assez décomposé, on ne voit absolument rien ». La
## correction ralentit la culbute et la profile (départ doux, accroupi au
## milieu, fin douce) ; cette sonde en apporte la preuve en images.
##
## Elle lance une vraie partie, fige tout sauf le joueur, passe le temps
## au quart de sa vitesse et déclenche une esquive : chaque image rendue
## pendant la roulade est photographiée. La planche obtenue doit montrer
## des poses INTERMÉDIAIRES distinctes — tête en bas, accroupi — sinon le
## mouvement reste illisible et le réglage est à refaire.
##
## Usage :
##   godot --path arena-rush res://outils_dev/sonde_roulade.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 1280
const HAUTEUR := 720
const PHOTOS := 14
## Le quart de vitesse : au rythme de rendu du banc, chaque image couvre
## ainsi une tranche courte et régulière de l'esquive.
const RALENTI := 0.25

var _joueur: Node3D
var _dossier := ""
var _photo := 0
var _attente := 10
var _lancee := false
var _prete := false

func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://sonde_roulade")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	_installer()
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	Engine.time_scale = RALENTI
	_prete = true
	RenderingServer.frame_post_draw.connect(_capturer)


## Fige tout ce qui n'est pas le joueur : la roulade doit être la seule
## chose qui bouge sur la planche.
func _installer() -> void:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			p.queue_free()
		else:
			_joueur = p
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	var monde := get_tree().get_first_node_in_group(&"game_world")
	if monde:
		monde.set_process(false)


func _capturer() -> void:
	if not _prete:
		return
	if _attente > 0:
		_attente -= 1
		return
	if not _lancee:
		_joueur.set(&"want_dash", true)
		_lancee = true
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dossier.path_join("roulade_%02d.png" % _photo))
	_photo += 1
	if _photo >= PHOTOS:
		_prete = false
		Engine.time_scale = 1.0
		print("=== 0 échec(s) sur 1 vérification ===")
		get_tree().quit(0)
