extends Node3D
class_name ArenaBuilder
## BÂTISSEUR — transcrit ArenaPlan (polylignes, polygones) en géométrie
## Godot RÉELLE : StaticBody3D + CollisionShape3D pour chaque segment de
## mur, CollisionPolygon3D pour chaque bassin. Blockout neutre : pas de
## palette définitive à ce stade (voir ÉTAPE 7 du cahier des charges,
## volontairement reportée après validation de la structure).

const EPAISSEUR_MUR := 1.0

var _mat_mur := StandardMaterial3D.new()
var _mat_sol := StandardMaterial3D.new()
var _mat_eau := StandardMaterial3D.new()
var _mat_pont := StandardMaterial3D.new()
var _mat_podium := StandardMaterial3D.new()
var _mat_spawn := StandardMaterial3D.new()

var spawn_markers: Array[Node3D] = []


func _ready() -> void:
	_mat_mur.albedo_color = Color("3a4a63")
	_mat_sol.albedo_color = Color("d8c48c")
	_mat_sol.roughness = 1.0
	_mat_eau.albedo_color = Color("4ecbc4")
	_mat_eau.roughness = 0.3
	_mat_pont.albedo_color = Color("8a6a45")
	_mat_podium.albedo_color = Color("6a7a8a")
	_mat_spawn.albedo_color = Color("e0a030")

	_construire_sol()
	_construire_podium()
	_construire_murs()
	_construire_bassins()
	_construire_ponts()
	_construire_enceinte()
	_construire_spawns()


func _construire_sol() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ArenaPlan.R_BORD * 2.2, ArenaPlan.R_BORD * 2.2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat_sol
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ArenaPlan.R_BORD * 2.2, 0.2, ArenaPlan.R_BORD * 2.2)
	col.shape = shape
	col.position.y = -0.11
	body.add_child(col)
	add_child(body)


func _construire_podium() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const N := 8
	for i in N:
		var a0 := TAU * float(i) / N
		var a1 := TAU * float(i + 1) / N
		for v in [Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * ArenaPlan.R_PODIUM,
				Vector3(cos(a1), 0, sin(a1)) * ArenaPlan.R_PODIUM]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3(0, 0.15, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat_podium
	add_child(mi)
	# PAS DE COLLISION SURÉLEVÉE : le podium reste TRAVERSABLE à plat —
	# « ne doit pas bloquer la traversée générale de l'arène ».


func _extruder_segment(a: Vector2, b: Vector2, haut: float) -> void:
	var centre := (a + b) * 0.5
	var longueur := a.distance_to(b)
	if longueur < 0.05:
		return
	var angle := (b - a).angle()
	var body := StaticBody3D.new()
	body.position = Vector3(centre.x, haut * 0.5, centre.y)
	body.rotation.y = -angle
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(longueur + EPAISSEUR_MUR, haut, EPAISSEUR_MUR)
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mi.mesh = box
	mi.material_override = _mat_mur
	body.add_child(mi)
	add_child(body)


func _construire_murs() -> void:
	for m: Dictionary in ArenaPlan.MURS:
		var pts: PackedVector2Array = m["points"]
		var haut: float = m["haut"]
		for i in pts.size() - 1:
			_extruder_segment(pts[i], pts[i + 1], haut)


func _polygone_vers_mesh(pts: PackedVector2Array, y: float, mat: Material) -> MeshInstance3D:
	var tri := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in tri:
		var p: Vector2 = pts[idx]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _construire_bassins() -> void:
	for b: Dictionary in ArenaPlan.BASSINS:
		var pts: PackedVector2Array = b["points"]
		add_child(_polygone_vers_mesh(pts, 0.02, _mat_eau))
		# COLLISION DE L'EAU — un CollisionPolygon3D extrudé, l'obstacle
		# réel : on la contourne ou on prend le pont.
		var body := StaticBody3D.new()
		var col := CollisionPolygon3D.new()
		col.polygon = pts
		col.depth = 3.0
		col.position.y = -1.5
		col.rotation.x = -PI / 2.0
		body.add_child(col)
		add_child(body)


func _construire_ponts() -> void:
	for p: Dictionary in ArenaPlan.PONTS:
		var de: Vector2 = p["de"]
		var vers: Vector2 = p["vers"]
		var large: float = p["large"]
		var centre := (de + vers) * 0.5
		var longueur := de.distance_to(vers)
		var angle := (vers - de).angle()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(longueur + 0.6, 0.2, large)
		mi.mesh = box
		mi.material_override = _mat_pont
		mi.position = Vector3(centre.x, 0.1, centre.y)
		mi.rotation.y = -angle
		add_child(mi)
		# AUCUNE COLLISION : le pont est un plancher, il ne bloque rien —
		# c'est le sol qui porte, comme partout ailleurs sur l'île.


## L'ENCEINTE — invisible, retient les joueurs à R_BORD.
func _construire_enceinte() -> void:
	const N := 32
	for i in N:
		var a0 := TAU * float(i) / N
		var a1 := TAU * float(i + 1) / N
		var p0 := Vector2(cos(a0), sin(a0)) * ArenaPlan.R_BORD
		var p1 := Vector2(cos(a1), sin(a1)) * ArenaPlan.R_BORD
		var centre := (p0 + p1) * 0.5
		var body := StaticBody3D.new()
		body.position = Vector3(centre.x, 2.0, centre.y)
		body.rotation.y = -(p1 - p0).angle()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(p0.distance_to(p1) + 0.5, 4.0, 1.0)
		col.shape = shape
		body.add_child(col)
		add_child(body)


## SPAWNS — marqueurs colorés numérotés (temporaire, validation ÉTAPE 5).
func _construire_spawns() -> void:
	for i in ArenaPlan.SPAWNS.size():
		var s: Dictionary = ArenaPlan.SPAWNS[i]
		var pos: Vector2 = s["pos"]
		var disque := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.4
		cyl.height = 0.1
		disque.mesh = cyl
		disque.material_override = _mat_spawn
		disque.position = Vector3(pos.x, 0.05, pos.y)
		add_child(disque)

		var label3d := Label3D.new()
		label3d.text = str(i + 1)
		label3d.font_size = 96
		label3d.position = Vector3(pos.x, 2.2, pos.y)
		label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label3d.modulate = Color.WHITE
		label3d.outline_size = 12
		add_child(label3d)
		spawn_markers.append(disque)
