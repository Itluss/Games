extends Node3D
## APERÇU DES MASCOTTES — rendu studio, pour instruire une question précise.
##
## LE RETOUR DE TEST : « je ne reconnais pas les autres participants ». La
## question posée est binaire : est-ce le MODÈLE Meshy qui a perdu
## l'identité de la planche, ou notre AFFICHAGE (angle, distance, lumière)
## qui la détruit ? Ce banc isole le premier terme : chaque mascotte est
## photographiée seule, en lumière neutre, sous deux vues —
##   3/4    — la pose de la planche, pour comparer trait à trait ;
##   JEU    — la plongée et la taille réelles de la caméra du jeu, pour
##            voir ce qu'il en reste à l'écran.
## Si le 3/4 ressemble à la planche mais que la vue JEU est illisible,
## l'affichage est coupable ; si le 3/4 est déjà méconnaissable, c'est le
## modèle.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_mascottes.tscn \
##       --rendering-driver opengl3

const LARGEUR := 512
const HAUTEUR := 512
const CHAUFFE := 6
## Hauteur en jeu de toute mascotte (character_visual.MODELE_HAUTEUR).
const HAUTEUR_JEU := 1.9

## Les vingt modèles livrés, dans l'ordre de la planche des trente.
const NOMS: Array[String] = [
	"ruby", "flare", "root", "bone", "ninja", "pixel",
	"spore", "corsair", "gizmo", "knight", "prick", "shade",
	"frost", "boom", "buzz", "pumpkin", "ram", "tiki",
	"wisp", "slime",
]

var _cam: Camera3D
var _dossier := ""
var _i := 0
var _vue := 0
var _chauffe := 0
var _courant: Node3D = null

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu_mascottes")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)

	# Fond clair et lumière blanche : les conditions de la planche, pas
	# celles du désert — on juge le modèle, pas l'éclairage du jeu.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("f4f1ea")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffffff")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -34, 0)
	sun.light_energy = 1.1
	add_child(sun)

	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_charger()

func _charger() -> void:
	if _courant != null:
		_courant.queue_free()
		_courant = null
	var nom: String = NOMS[_i]
	var chemin := "res://assets/models/mascotte_%s.glb" % nom
	var sc := load(chemin) as PackedScene if ResourceLoader.exists(chemin) else null
	if sc == null:
		print("%-10s  ABSENT (%s)" % [nom, chemin])
		_suivant()
		return
	var n := sc.instantiate() as Node3D
	add_child(n)
	_courant = n

	# Même mise à l'échelle que le jeu : la hauteur est ramenée à 1,9 m.
	var boites: Array[AABB] = []
	_col(n, Transform3D.IDENTITY, boites)
	var t := boites[0]
	for i in range(1, boites.size()):
		t = t.merge(boites[i])
	var f: float = HAUTEUR_JEU / maxf(t.size.y, 0.0001)
	n.scale = Vector3.ONE * f
	n.position = Vector3(-t.get_center().x * f, -t.position.y * f,
			-t.get_center().z * f)
	_placer()

func _placer() -> void:
	var h := HAUTEUR_JEU
	var centre := Vector3(0, h * 0.5, 0)
	if _vue == 0:
		# 3/4 rapproché, légèrement au-dessus des yeux : la pose planche.
		_cam.fov = 40.0
		_cam.position = centre + Vector3(h * 1.1, h * 0.55, h * 1.8)
	else:
		# La plongée du jeu : 42° sous l'horizontale, cadrage équivalent
		# à la part d'écran qu'occupe un personnage à 14,8 m de caméra.
		_cam.fov = 58.0
		_cam.position = centre + Vector3(0, h * 2.6, h * 2.9)
	_cam.look_at(centre, Vector3.UP)

func _process(_dt: float) -> void:
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	_chauffe = 0
	if _courant == null:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dossier, NOMS[_i],
			"34" if _vue == 0 else "jeu"])
	_vue += 1
	if _vue > 1:
		_suivant()
	else:
		_placer()


func _suivant() -> void:
	_vue = 0
	_i += 1
	if _i >= NOMS.size():
		get_tree().quit()
		return
	_charger()


func _col(n: Node, xf: Transform3D, sortie: Array[AABB]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		sortie.append((xf * mi.transform) * mi.get_aabb())
	for c in n.get_children():
		_col(c, xf * (n.transform if n is Node3D else Transform3D.IDENTITY),
				sortie)
