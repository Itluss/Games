extends Node3D
## CONTRÔLE QUALITÉ DU KIT DE L'ÎLE — chaque asset généré, seul, sous
## deux angles : trois quarts et plongée de jeu. C'est sur CES images
## que se décide l'entrée dans la liste d'approbation de KitIle — bords
## coupés, socle envahissant, texture en bouillie ou sujet manqué se
## voient ici, jamais dans un plan large.

const LARGEUR := 1100
const HAUTEUR := 520
const CHAUFFE := 8

var _noms: Array[StringName] = []
var _i := -1
var _n := 0
var _cam: Camera3D
var _porte: Node3D
var _dossier := ""


func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://kit_ile")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=%s" % _dossier)
	var d := DirAccess.open("res://assets/models")
	for f in d.get_files():
		if f.begins_with("ile_") and f.ends_with(".glb"):
			_noms.append(StringName(f.get_basename()))
	_noms.sort()
	print("%d assets à contrôler" % _noms.size())

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("caa25a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("f2e8d8")
	e.ambient_light_energy = 0.45
	env.environment = e
	add_child(env)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-52, -38, 0)
	soleil.light_energy = 0.85
	add_child(soleil)
	var sol := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(30, 30)
	sol.mesh = p
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("e2a047")
	sol.material_override = m
	add_child(sol)
	_porte = Node3D.new()
	add_child(_porte)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_suivant()


func _suivant() -> void:
	_i += 1
	if _i >= _noms.size():
		print("=== 0 échec(s) ===")
		get_tree().quit(0)
		return
	for c in _porte.get_children():
		_porte.remove_child(c)
		c.queue_free()
	# Le modèle BRUT d'abord : on juge ce que Meshy a livré, socle
	# compris. La version corrigée (échelle, enterrage) se juge ensuite
	# dans l'arène.
	var sc := load("res://assets/models/%s.glb" % _noms[_i]) as PackedScene
	if sc == null:
		_suivant()
		return
	var inst := sc.instantiate() as Node3D
	_porte.add_child(inst)
	var boite := _mesure(inst)
	var r: float = maxf(boite.size.length() * 0.5, 0.4)
	inst.position = -boite.get_center()
	_cam.fov = 45.0
	_cam.look_at_from_position(
			Vector3(r * 1.6, r * 1.3, r * 1.6), Vector3.ZERO, Vector3.UP)
	_n = 0
	set_process(true)


func _mesure(n: Node) -> AABB:
	var b := AABB()
	var premier := true
	var file: Array[Node] = [n]
	while not file.is_empty():
		var e: Node = file.pop_back()
		var mi := e as MeshInstance3D
		if mi != null and mi.mesh != null:
			var lb := mi.mesh.get_aabb()
			if premier:
				b = lb
				premier = false
			else:
				b = b.merge(lb)
		for c in e.get_children():
			file.append(c)
	return b


func _process(_d: float) -> void:
	_n += 1
	if _n < CHAUFFE:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dossier, _noms[_i]])
	print("→ %s" % _noms[_i])
	_suivant()
