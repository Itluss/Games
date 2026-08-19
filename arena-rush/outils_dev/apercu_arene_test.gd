extends Node3D
## APERÇU DE L'ARÈNE DE COMBAT — vues choisies pour JUGER LE NIVEAU.
##
## La vue « caméra réelle » est la seule qui compte pour valider : elle est
## posée à la hauteur, au recul et à l'ouverture exacts de la caméra de
## jeu. Les autres servent à comprendre la composition, pas à l'approuver.
const LARGEUR := 1280
const HAUTEUR := 720
const CHAUFFE := 6

## Réglages COPIÉS de arena_camera.gd. S'ils y changent, ils doivent
## changer ici : une vue « caméra réelle » qui ne l'est plus mentirait.
const CAM_HAUTEUR := 10.4
const CAM_RECUL := 8.0
const CAM_FOV := 58.0
const CAM_YEUX := 1.4

var _cam: Camera3D
var _dossier := ""
var _vue := 0
var _chauffe := 0

var _vues := [
	# PLAN COMPLET : la composition d'un seul coup d'œil.
	{"nom": "plan", "pos": Vector3(0.0, 62.0, 0.1), "cible": Vector3(0, 0, 0),
		"fov": 58.0},
	# LES CINQ VUES « CAMÉRA RÉELLE ». Chacune place le joueur à un endroit
	# de jeu et regarde ce qu'il voit vraiment.
	{"joueur": Vector3(0.0, 0.0, 0.0), "nom": "reel_place"},
	{"joueur": Vector3(-11.0, 0.0, -11.0), "nom": "reel_bastion_no"},
	{"joueur": Vector3(0.0, 0.0, -14.5), "nom": "reel_passe_nord"},
	{"joueur": Vector3(-16.0, 0.0, 0.0), "nom": "reel_route_ouest"},
	{"joueur": Vector3(0.0, 0.0, -17.6), "nom": "reel_apparition_nord"},
]

func _ready() -> void:
	Cfg.arene_test = true
	_dossier = ProjectSettings.globalize_path("user://apercu_arene")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)

	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)

	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_placer()

func _placer() -> void:
	var v: Dictionary = _vues[_vue]
	if v.has("joueur"):
		# LA CAMÉRA DE JEU, À L'IDENTIQUE : hauteur, recul le long de l'axe
		# -Z, visée sur les yeux du joueur.
		var j: Vector3 = v["joueur"]
		_cam.fov = CAM_FOV
		_cam.position = j + Vector3(0.0, CAM_HAUTEUR, CAM_RECUL)
		_cam.look_at(j + Vector3(0, CAM_YEUX, 0), Vector3.UP)
	else:
		_cam.fov = v.get("fov", 58.0)
		_cam.position = v["pos"]
		_cam.look_at(v["cible"], Vector3.UP)

func _process(_d: float) -> void:
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	_chauffe = 0
	var v: Dictionary = _vues[_vue]
	var img := get_viewport().get_texture().get_image()
	var chemin := "%s/arene_%s.png" % [_dossier, v["nom"]]
	img.save_png(chemin)
	print("→ ", chemin)
	_vue += 1
	if _vue >= _vues.size():
		get_tree().quit()
		return
	_placer()
