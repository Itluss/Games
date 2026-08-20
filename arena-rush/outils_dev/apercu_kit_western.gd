extends Node3D
## APERÇU DU KIT WESTERN — mesure et rendu, avant toute intégration.
##
## On regarde CE QUE MESHY A LIVRÉ, pas ce qu'on lui a demandé : les
## dimensions réelles, le nombre de triangles, le nombre de matériaux, et
## la silhouette vue de l'angle de la caméra de jeu. Une pièce qui ne se
## lit pas de dessus ne sert à rien dans cette arène.
const LARGEUR := 520
const HAUTEUR := 520
const CHAUFFE := 6

const PIECES := [
	["west_rock_formation_a", 3.2], ["west_rock_formation_b", 3.4],
	["west_rock_small", 0.6], ["west_stonewall_straight", 1.5],
	["west_fence_straight", 1.3], ["west_sign_wood", 2.6],
	["west_haybale", 0.95], ["west_crate", 0.9],
	["west_barrel", 0.95], ["west_wagon", 2.8], ["west_cactus_a", 2.1],
]

var _cam: Camera3D
var _dossier := ""
var _chauffe := 0
var _montes: Array[Dictionary] = []
var _i := 0

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu_kit")
	DirAccess.make_dir_recursive_absolute(_dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("e8d5b0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d6cbb0")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.2
	add_child(sun)

	print("%-26s %-22s %8s %6s" % ["pièce", "dimensions (m)", "tris", "mat."])
	var x := 0.0
	for p in PIECES:
		var nom: String = p[0]
		var h: float = p[1]
		var chemin := "res://assets/models/%s.glb" % nom
		if not ResourceLoader.exists(chemin):
			print("%-26s ABSENT" % nom)
			x += 3.4
			continue
		var m := (load(chemin) as PackedScene).instantiate() as Node3D
		add_child(m)
		var b: Array[AABB] = []
		_col(m, Transform3D.IDENTITY, b)
		var t := b[0]
		for i in range(1, b.size()):
			t = t.merge(b[i])
		var f: float = h / maxf(t.size.y, 0.0001)
		m.scale = Vector3.ONE * f
		m.position = Vector3(-t.get_center().x * f, -t.position.y * f,
				-t.get_center().z * f)
		m.visible = false
		_montes.append({"n": m, "nom": nom, "h": h, "large": t.size.x * f})
		var tris := 0
		var mats := 0
		for mi in _mailles(m):
			var msh := (mi as MeshInstance3D).mesh
			mats += msh.get_surface_count()
			for s in msh.get_surface_count():
				var arr := msh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() / 3) if idx.size() > 0 \
						else ((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		var r := t.size * f
		print("%-26s %5.2f × %5.2f × %5.2f %8d %6d"
				% [nom, r.x, r.y, r.z, tris, mats])

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 30.0
	# ANGLE DE LA CAMÉRA DE JEU : 10,4 m de haut pour 8 m de recul, soit
	# 52° sous l'horizontale. Une pièce se juge sous l'angle où on la voit.
	add_child(_cam)
	_placer()


## Cadre sur la pièce courante : une botte de foin et un chariot n'ont pas
## la même taille, un cadre fixe rendrait l'une minuscule et l'autre coupée.
func _placer() -> void:
	for d in _montes:
		(d["n"] as Node3D).visible = false
	if _i >= _montes.size():
		return
	var d: Dictionary = _montes[_i]
	(d["n"] as Node3D).visible = true
	var etendue: float = maxf(float(d["large"]), float(d["h"])) * 1.35
	# Angle de la caméra de jeu : 52° sous l'horizontale.
	_cam.position = Vector3(0, etendue * 1.15, etendue * 0.90)
	_cam.look_at(Vector3(0, float(d["h"]) * 0.35, 0), Vector3.UP)

func _process(_d: float) -> void:
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	if _i >= _montes.size():
		get_tree().quit()
		return
	var d: Dictionary = _montes[_i]
	get_viewport().get_texture().get_image().save_png(
			"%s/%s.png" % [_dossier, d["nom"]])
	_i += 1
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
