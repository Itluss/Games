extends Node3D
class_name Diagnostic
## VUE DE VALIDATION — dessine au sol les trois boucles, les connexions,
## les entrées/sorties des cachettes et les zones interdites. Activée par
## défaut dans la scène de validation (`scenes/validation.tscn`) ; dans
## le jeu normal, elle resterait éteinte (non câblée ici — hors
## périmètre tant que la structure n'est pas validée).

func _ready() -> void:
	_anneau(ArenaPlan.R_PODIUM, ArenaPlan.R_CENTRALE, Color(0.3, 0.9, 0.4, 0.35), "boucle centrale")
	_anneau(ArenaPlan.R_CENTRALE, ArenaPlan.R_QUARTIER, Color(0.95, 0.7, 0.2, 0.30), "boucle intermédiaire (quartiers)")
	_anneau(ArenaPlan.R_QUARTIER, ArenaPlan.R_CONNECTEUR, Color(0.6, 0.6, 0.9, 0.20), "connecteur")
	_anneau(ArenaPlan.R_CONNECTEUR, ArenaPlan.R_PERIPH, Color(0.3, 0.6, 0.95, 0.35), "boucle périphérique")

	for a: Dictionary in ArenaPlan.ABRIS:
		_marqueur(a["centre"], Color(1.0, 0.2, 0.2), 0.6)
		for s: Vector2 in a["sorties"]:
			_marqueur(s, Color(1.0, 0.6, 0.2), 0.35)
			_ligne(a["centre"], s, Color(1.0, 0.6, 0.2, 0.6))

	for i: Dictionary in ArenaPlan.ILOTS_CENTRE:
		_marqueur(i["centre"], Color(0.7, 0.2, 0.9), 0.5)


func _anneau(r0: float, r1: float, c: Color, etiquette: String) -> void:
	const N := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in N:
		var a0 := TAU * float(i) / N
		var a1 := TAU * float(i + 1) / N
		var p00 := Vector3(cos(a0) * r0, 0.06, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0.06, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0.06, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0.06, sin(a1) * r1)
		for v in [p00, p01, p11, p00, p11, p10]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

	var lbl := Label3D.new()
	lbl.text = etiquette
	lbl.font_size = 48
	lbl.position = Vector3(0, 0.3, -(r0 + r1) * 0.5)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color.WHITE
	lbl.outline_size = 10
	add_child(lbl)


func _marqueur(p: Vector2, c: Color, rayon: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = rayon
	cyl.bottom_radius = rayon
	cyl.height = 0.15
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(p.x, 0.2, p.y)
	add_child(mi)


func _ligne(a: Vector2, b: Vector2, c: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(c)
	st.add_vertex(Vector3(a.x, 0.25, a.y))
	st.set_color(c)
	st.add_vertex(Vector3(b.x, 0.25, b.y))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
