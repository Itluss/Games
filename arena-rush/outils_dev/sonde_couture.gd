extends Node
## SONDE DE COUTURE — outil de développement, hors jeu.
##
## LA SEULE QUESTION QUI COMPTE POUR UN MONDE QUI S'ENROULE : la limite se
## voit-elle ? Tout le reste — secteurs, apparitions, collisions — est
## vérifiable par le calcul. Celle-ci ne l'est pas : elle se juge en image.
##
## LE PRINCIPE. On place le joueur à cinq centimètres d'un bord, on
## photographie. On le replace à cinq centimètres du bord OPPOSÉ, on
## rephotographie. Sur un tore, ces deux positions sont VOISINES : dix
## centimètres les séparent. Les deux images doivent donc être quasiment
## identiques.
##
## Si elles diffèrent, la couture est visible et le monde n'est pas
## réellement sans bord — quelle que soit la beauté du reste. Si elles se
## ressemblent, franchir la limite ne se remarque pas, et c'est exactement
## ce qu'on cherchait.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_couture.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 480
const HAUTEUR := 270
## Nombre de traversées testées, réparties le long des deux coutures.
const PAIRES := 12
## Trames laissées au monde pour se replacer avant chaque photo. Les
## cellules se repositionnent dans `_process`, la caméra aussi : une seule
## trame photographierait un monde à moitié déplacé.
const REPOS := 4
## Écart moyen par canal au-delà duquel la couture se voit.
const TOLERANCE := 0.045

var _joueur: Node3D
var _cam: Camera3D
var _paire := 0
var _cote := 0
var _attente := 0
var _avant: Image = null
var _ecarts: Array[float] = []
var _prete := false

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id():
			_joueur = n
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	_cam = get_viewport().get_camera_3d()
	_figer()
	_placer()
	_prete = true
	RenderingServer.frame_post_draw.connect(_analyser)


## FIGE TOUT CE QUI N'EST PAS LE MONDE.
##
## LE PREMIER JET MESURAIT LE MAUVAIS ÉCART. Les deux photos d'une même
## traversée sont prises à cinq trames d'intervalle : entre les deux, les
## mobs marchent, les bots tirent, les particules vivent. L'écart mesuré
## valait 0,023 en moyenne — du mouvement, pas de la couture.
##
## On ne peut pas soustraire ce bruit, il faut l'éteindre. Ce qui reste
## alors dans l'image est le décor seul, et le décor est censé être
## rigoureusement identique de part et d'autre de la limite.
func _figer() -> void:
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") != Net.local_id():
			n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	var monde := get_tree().get_first_node_in_group(&"game_world")
	if monde:
		monde.set_process(false)
	MatchDirector.set_process(false)
	MatchDirector.set_physics_process(false)


## Immobilise le personnage : son animation avancerait, elle aussi.
func _immobiliser() -> void:
	_joueur.set(&"move_input", Vector2.ZERO)
	_joueur.set(&"want_fire", false)
	_joueur.set(&"velocity", Vector3.ZERO)
	var visuel = _joueur.get(&"visual")
	if visuel and visuel.has_method(&"set_motion"):
		visuel.set_motion(Vector3.ZERO, Vector3.ZERO)


## Les deux positions d'une traversée : juste avant et juste après la
## limite. La moitié des paires traverse en X, l'autre en Z.
func _positions(i: int) -> Array:
	var t := -PlanMonde.DEMI + PlanMonde.COTE * (float(i % (PAIRES / 2)) + 0.5) \
			/ float(PAIRES / 2)
	if i < PAIRES / 2:
		return [Vector3(PlanMonde.DEMI - 0.05, 0.0, t),
				Vector3(-PlanMonde.DEMI + 0.05, 0.0, t)]
	return [Vector3(t, 0.0, PlanMonde.DEMI - 0.05),
			Vector3(t, 0.0, -PlanMonde.DEMI + 0.05)]


func _placer() -> void:
	_immobiliser()
	_joueur.global_position = _positions(_paire)[_cote]
	if _cam and _cam.has_method(&"_snap"):
		_cam.call(&"_snap")
	_attente = REPOS


func _analyser() -> void:
	if not _prete:
		return
	if _attente > 0:
		_immobiliser()
		_attente -= 1
		return
	var img := get_viewport().get_texture().get_image()
	if _cote == 0:
		_avant = img
		_cote = 1
		_placer()
		return
	var e := _difference(_avant, img)
	_ecarts.append(e)
	if e > TOLERANCE:
		print("      ! traversée %d : écart %.4f en %s"
				% [_paire, e, str(_positions(_paire)[0])])
	_paire += 1
	_cote = 0
	if _paire >= PAIRES:
		_conclure()
		return
	_placer()


## Écart moyen par canal entre deux images, sur un pixel sur quatre.
func _difference(a: Image, b: Image) -> float:
	var somme := 0.0
	var n := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			somme += (absf(ca.r - cb.r) + absf(ca.g - cb.g)
					+ absf(ca.b - cb.b)) / 3.0
			n += 1
	return somme / maxf(1.0, float(n))


func _conclure() -> void:
	_prete = false
	var pire := 0.0
	var total := 0.0
	for e in _ecarts:
		pire = maxf(pire, e)
		total += e
	var mauvaises := 0
	for e in _ecarts:
		if e > TOLERANCE:
			mauvaises += 1
	print("=== SONDE DE COUTURE (%d traversées) ===" % _ecarts.size())
	print("  écart moyen : %.4f · pire : %.4f · tolérance : %.4f"
			% [total / maxf(1.0, float(_ecarts.size())), pire, TOLERANCE])
	print("  traversées visibles : %d" % mauvaises)
	print("=== %d échec(s) sur 1 vérification ===" % (1 if mauvaises > 0 else 0))
	get_tree().quit(1 if mauvaises > 0 else 0)
