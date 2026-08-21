extends Node3D
## VITRINE — l'arène photographiée pour être JUGÉE, pas pour être jouée.
##
## Qualité HAUTE (ombres réelles), focales choisies : on compare la
## direction artistique à la planche de référence, plan large et vues
## rapprochées. La lisibilité de JEU, elle, se juge sur l'aperçu à la
## caméra réelle — deux instruments, deux questions.

const LARGEUR := 1920
const HAUTEUR := 1080
const CHAUFFE := 12

var _vues := [
	{"nom": "vitrine_large", "pos": Vector3(-58, 44, 58),
		"cible": Vector3(0, 0, 0), "fov": 40.0},
	{"nom": "vitrine_place", "pos": Vector3(-26, 15, 28),
		"cible": Vector3(0, 1.0, 0), "fov": 44.0},
	{"nom": "vitrine_oasis", "pos": Vector3(-44, 13, -6),
		"cible": Vector3(-22, 0.5, -23), "fov": 44.0},
	{"nom": "vitrine_canyon", "pos": Vector3(8, 13, -44),
		"cible": Vector3(26, 1.0, -24), "fov": 44.0},
]

var _cam: Camera3D
var _i := -1
var _n := 0
var _dossier := ""


func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://vitrine")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=%s" % _dossier)
	Cfg.arene_test = true
	Cfg.quality = Cfg.Quality.HIGH
	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)
	_cam = Camera3D.new()
	_cam.far = 500.0
	add_child(_cam)
	_cam.current = true
	await get_tree().process_frame
	_suivant()


func _suivant() -> void:
	_i += 1
	if _i >= _vues.size():
		print("=== 0 échec(s) ===")
		get_tree().quit(0)
		return
	var v: Dictionary = _vues[_i]
	_cam.fov = float(v["fov"])
	_cam.look_at_from_position(v["pos"], v["cible"], Vector3.UP)
	_n = 0
	set_process(true)


func _process(_d: float) -> void:
	_n += 1
	if _n < CHAUFFE:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dossier, _vues[_i]["nom"]])
	print("→ %s" % _vues[_i]["nom"])
	_suivant()
