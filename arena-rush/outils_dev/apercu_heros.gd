extends Node3D
## APERÇU DU LOT HÉROS — rendu + mesures, pour juger avant d'intégrer.
##
## Deux vues par héros, et ce sont les deux qui décident :
##   3/4  — la silhouette telle qu'on la voit sur une fiche de sélection.
##   DESSUS — la seule qui compte en jeu, puisque la caméra plonge. Un
##            héros superbe de face et illisible de dessus est raté.
const LARGEUR := 900
const HAUTEUR := 900
const CHAUFFE := 6

const HEROS := [
	{"nom": "hero_brute", "h": 2.15},
	{"nom": "hero_zippy", "h": 1.72},
	{"nom": "hero_spark", "h": 1.62},
	{"nom": "hero_bolt", "h": 1.88},
]

var _cam: Camera3D
var _dossier := ""
var _i := 0
var _vue := 0
var _chauffe := 0
var _courant: Node3D = null

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu_heros")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("d9cdb4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("cfd8e8")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -34, 0)
	sun.light_energy = 1.15
	add_child(sun)

	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_charger()

func _charger() -> void:
	if _courant != null:
		_courant.queue_free()
		_courant = null
	var d: Dictionary = HEROS[_i]
	var chemin := "res://assets/models/%s.glb" % d["nom"]
	var sc := load(chemin) as PackedScene
	if sc == null:
		push_error("illisible : %s" % chemin)
		return
	var n := sc.instantiate() as Node3D
	add_child(n)
	_courant = n

	# MESURE : on ramène le modèle à la hauteur déclarée, exactement comme
	# le fera le jeu, puis on rapporte ce qu'il a vraiment livré.
	var boites: Array[AABB] = []
	_col(n, Transform3D.IDENTITY, boites)
	var t := boites[0]
	for i in range(1, boites.size()):
		t = t.merge(boites[i])
	var f: float = float(d["h"]) / maxf(t.size.y, 0.0001)
	n.scale = Vector3.ONE * f
	n.position = Vector3(-t.get_center().x * f, -t.position.y * f,
			-t.get_center().z * f)
	var reelle := t.size * f
	var tris := 0
	var surfaces := 0
	for mi in _mailles(n):
		surfaces += (mi as MeshInstance3D).mesh.get_surface_count()
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var a := (mi as MeshInstance3D).mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if idx.size() > 0:
				tris += idx.size() / 3
			else:
				tris += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("%-12s  %5.2f × %5.2f × %5.2f m   %6d tris   %d surface(s)"
			% [d["nom"], reelle.x, reelle.y, reelle.z, tris, surfaces])
	_placer()

func _placer() -> void:
	var d: Dictionary = HEROS[_i]
	var h: float = d["h"]
	var centre := Vector3(0, h * 0.5, 0)
	if _vue == 0:
		_cam.fov = 40.0
		_cam.position = centre + Vector3(h * 1.35, h * 0.55, h * 2.0)
	else:
		# DESSUS, à l'angle de la caméra de jeu : 10,4 m de haut pour 8 m
		# de recul, soit 52° sous l'horizontale.
		_cam.fov = 40.0
		_cam.position = centre + Vector3(0, h * 2.3, h * 1.8)
	_cam.look_at(centre, Vector3.UP)

func _process(_dt: float) -> void:
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	_chauffe = 0
	var d: Dictionary = HEROS[_i]
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dossier, d["nom"],
			"34" if _vue == 0 else "dessus"])
	_vue += 1
	if _vue > 1:
		_vue = 0
		_i += 1
		if _i >= HEROS.size():
			get_tree().quit()
			return
		_charger()
	else:
		_placer()

func _col(n: Node, t: Transform3D, out: Array[AABB]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(t * mi.get_aabb())
	for e in n.get_children():
		var s := t
		var e3 := e as Node3D
		if e3 != null:
			s = t * e3.transform
		_col(e, s, out)

func _mailles(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for e in n.get_children():
		_mailles(e, out)
	return out
