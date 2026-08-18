extends Node3D
## SONDE DE CAMÉRA — outil de développement, hors jeu.
##
## POURQUOI : retour de test, « à certains endroits la caméra ne restitue
## plus rien, écran violet ». Un défaut qui ne se produit QU'À CERTAINS
## ENDROITS ne se trouve pas en regardant le code — il se trouve en allant
## voir à tous les endroits.
##
## La sonde promène une caméra réglée EXACTEMENT comme celle du jeu sur
## toute la carte, rend chaque position, et compte la part de ciel dans
## l'image. Un endroit d'où l'on ne voit que le ciel est un trou.

const PAS := 12.0
const LARGEUR := 240
const HAUTEUR := 135

var _cam: Camera3D
var _points: Array[Vector3] = []
var _index := 0
var _chauffe := 0
var _trous: Array[Vector3] = []
var _pire := 0.0
var _pire_pos := Vector3.ZERO

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	var monde := Arena.new()
	add_child(monde)

	# On échantillonne tout le disque jouable, y compris juste derrière le
	# mur : c'est près des limites qu'un trou est le plus probable.
	var r := PlanMonde.RAYON + 4.0
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if Vector2(x, z).length() <= r:
				_points.append(Vector3(x, 0.0, z))
			z += PAS
		x += PAS

	_cam = Camera3D.new()
	# LES MÊMES RÉGLAGES QUE LA CAMÉRA DU JEU. Sonder avec d'autres valeurs
	# ne prouverait rien sur le jeu.
	_cam.fov = 58.0
	# LE PLAN LOINTAIN EST LU DANS LE FICHIER, pas sur une instance neuve :
	# `ArenaCamera` ne le règle que dans son `_ready`, et une caméra jamais
	# entrée dans l'arbre porte encore la valeur par défaut de Godot,
	# 4 000 m. Ma première sonde a donc testé une caméra qui n'existe pas
	# dans le jeu, et n'a évidemment rien trouvé.
	_cam.far = float(_arg("--far", 140.0))
	add_child(_cam)
	_placer()
	print("Sonde : %d positions, plan lointain %.0f m" % [_points.size(), _cam.far])
	RenderingServer.frame_post_draw.connect(_capturer)


func _arg(nom: String, defaut: float) -> float:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for i in args.size():
		if args[i] == nom and i + 1 < args.size():
			return float(args[i + 1])
	return defaut


func _placer() -> void:
	var cible: Vector3 = _points[_index]
	# Reproduction exacte du placement d'ArenaCamera.
	_cam.global_position = cible + Vector3(0, 13.0, 10.0)
	_cam.look_at(cible, Vector3.UP)


func _capturer() -> void:
	if _index >= _points.size():
		return
	_chauffe += 1
	if _chauffe < 3:
		return
	_chauffe = 0
	var img := get_viewport().get_texture().get_image()

	# On compte les pixels de CIEL. Le ciel du jeu est un dégradé sans
	# aucune structure ; le sol, lui, porte toujours des props et des
	# ombres. On le reconnaît à sa teinte : très sombre et très bleue.
	var ciel := 0
	var total := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			total += 1
			if c.b > c.r and c.v < 0.24:
				ciel += 1
	var part := float(ciel) / maxf(1.0, float(total))
	var pos: Vector3 = _points[_index]
	if part > _pire:
		_pire = part
		_pire_pos = pos
	if part > 0.72:
		_trous.append(pos)
		print("  TROU en (%.0f, %.0f) — %.0f %% de ciel · rayon %.0f m · secteur %s"
				% [pos.x, pos.z, part * 100.0, Vector2(pos.x, pos.z).length(),
				PlanMonde.secteur_de(Vector2(pos.x, pos.z))])

	_index += 1
	if _index < _points.size():
		_placer()
		return
	print("=== SONDE TERMINÉE ===")
	print("  %d trou(s) sur %d positions" % [_trous.size(), _points.size()])
	print("  pire position : (%.0f, %.0f) à %.0f %% de ciel, rayon %.0f m"
			% [_pire_pos.x, _pire_pos.z, _pire * 100.0,
			Vector2(_pire_pos.x, _pire_pos.z).length()])
	get_tree().quit(1 if _trous.size() > 0 else 0)
