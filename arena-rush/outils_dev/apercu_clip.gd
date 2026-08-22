extends Node3D
## APERÇU D'UN CLIP — le contenu d'une animation, vu de près, sans le jeu.
##
## POURQUOI. La sonde de roulade a montré un pirate qui glisse sans
## tourner : impossible d'y distinguer un clip muet d'un clip pauvre. Ce
## banc lève l'ambiguïté : il charge le modèle seul, joue UN clip nommé,
## et photographie N instants répartis sur sa durée, en gros plan 3/4.
## Ce qu'on voit ici est ce que le clip CONTIENT — s'il est plat ici, il
## sera plat partout.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_clip.tscn \
##       --rendering-driver opengl3
## Modèle et clip se règlent ci-dessous.

const MODELE := "res://assets/models/mascotte_corsair.glb"
const CLIP := "roulade"
const PRISES := 10
const CHAUFFE := 4

var _cam: Camera3D
var _anim: AnimationPlayer
var _dossier := ""
var _prise := 0
var _chauffe := 0

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu_clip")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(512, 512)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("f4f1ea")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffffff")
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -34, 0)
	add_child(sun)

	var n := (load(MODELE) as PackedScene).instantiate() as Node3D
	add_child(n)
	_anim = _trouver(n, "AnimationPlayer") as AnimationPlayer
	if _anim == null or not _anim.has_animation(CLIP):
		push_error("Clip « %s » introuvable. Disponibles : %s"
				% [CLIP, ", ".join(_anim.get_animation_list()) if _anim else "aucun"])
		get_tree().quit(1)
		return
	print("clip « %s » : %.2f s" % [CLIP, _anim.get_animation(CLIP).length])

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 40.0
	var centre := Vector3(0, 0.95, 0)
	_cam.position = centre + Vector3(2.1, 1.0, 3.4)
	add_child(_cam)
	_cam.look_at(centre, Vector3.UP)
	_poser(0)


func _poser(i: int) -> void:
	var clip := _anim.get_animation(CLIP)
	# L'AnimationPlayer est utilisé en table de montage : on SAUTE à
	# l'instant voulu puis on fige — chaque photo est une pose exacte,
	# indépendante de la cadence de rendu de la machine.
	_anim.play(CLIP)
	_anim.seek(clip.length * float(i) / float(PRISES - 1), true)
	_anim.pause()
	_chauffe = CHAUFFE


func _process(_dt: float) -> void:
	_chauffe -= 1
	if _chauffe > 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/clip_%02d.png" % [_dossier, _prise])
	_prise += 1
	if _prise >= PRISES:
		get_tree().quit()
		return
	_poser(_prise)


func _trouver(n: Node, classe: String) -> Node:
	if n.is_class(classe):
		return n
	for c in n.get_children():
		var t := _trouver(c, classe)
		if t:
			return t
	return null
