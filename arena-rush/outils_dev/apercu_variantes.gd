extends Node3D
## PLANCHE DE COMPARAISON — un décor, trois états, même lumière.
##
## Les taches noires apparues au premier allègement pouvaient venir de deux
## endroits : du dépouillement du matériau (on retire les cartes de
## normales et de rugosité) ou de la décimation (la soudure des sommets
## moyenne les normales et écrase les pièces fines). Tant qu'on change les
## deux à la fois, on ne peut rien conclure.
##
## Chaque ligne montre donc : A l'original texturé, B la couleur cuite
## dans les sommets SANS décimer, C cuit ET décimé au budget proposé. Le
## premier essai a déjà tranché sur la barrière — B est indiscernable de
## A, C s'effondre — mais la réponse dépend du décor, et c'est justement
## ce qu'on veut voir modèle par modèle avant de choisir.
##
## Les trois fichiers de chaque ligne ne sont PAS versionnés : ils se
## régénèrent à partir des sources par
##     python3 outils/alleger_decors.py --planche
## puis un passage d'éditeur pour l'import.

const LARGEUR := 1320
const HAUTEUR := 420
const CHAUFFE := 6

var _noms: Array = []
var _i := -1
var _chauffe := 0
var _cam: Camera3D
var _porte: Node3D
var _dossier := ""


func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://variantes")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=%s" % _dossier)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("cfc0a2")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9c6dd")
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-46, -38, 0)
	soleil.light_energy = 1.15
	add_child(soleil)

	_porte = Node3D.new()
	add_child(_porte)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true

	var d := DirAccess.open("res://outils_dev/variantes")
	for f in d.get_files():
		if f.ends_with("__A.glb"):
			_noms.append(f.replace("__A.glb", ""))
	_noms.sort()
	_suivant()


func _suivant() -> void:
	_i += 1
	if _i >= _noms.size():
		print("=== 0 échec(s) ===")
		get_tree().quit(0)
		return
	# `queue_free` est DIFFÉRÉ : les nœuds de la ligne précédente sont
	# encore enfants pendant cette image. Les compter dans le placement
	# décalait chaque décor d'un cran vers la droite, hors du cadre — vu
	# sur la première planche, où seul le premier modèle était visible.
	for c in _porte.get_children():
		_porte.remove_child(c)
		c.queue_free()
	var nom: String = _noms[_i]
	var rayon := 0.5
	var poses: Array[Node3D] = []
	for lettre in ["A", "B", "C"]:
		var chemin := "res://outils_dev/variantes/%s__%s.glb" % [nom, lettre]
		var scene: PackedScene = load(chemin)
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate()
		_porte.add_child(inst)
		rayon = maxf(rayon, _rayon(inst))
		poses.append(inst)
	# L'écart et le recul suivent la taille du décor : une caisse et un
	# chariot ne se jugent pas au même cadrage.
	var ecart := rayon * 2.4
	for k in poses.size():
		poses[k].position = Vector3((float(k) - 1.0) * ecart, 0.0, 0.0)
	_cam.position = Vector3(0.0, rayon * 1.15, rayon * 4.6)
	_cam.look_at_from_position(_cam.position, Vector3(0, rayon * 0.45, 0), Vector3.UP)
	_chauffe = 0
	set_process(true)


func _rayon(n: Node) -> float:
	var r := 0.0
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var a := mi.mesh.get_aabb()
		r = maxf(r, maxf(a.size.x, maxf(a.size.y, a.size.z)) * 0.5)
	for c in n.get_children():
		r = maxf(r, _rayon(c))
	return maxf(r, 0.3)


func _process(_d: float) -> void:
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dossier, _noms[_i]])
	print("→ %s" % _noms[_i])
	_suivant()
