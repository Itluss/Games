extends Node3D
## BANC DE RENDU DU CYCLE DE COURSE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER EXISTE : jusqu'ici je réglais l'animation en ne
## regardant que des captures du jeu en cours de partie — une image fixe,
## prise à un instant quelconque de la foulée. C'est structurellement le
## mauvais outil : une animation se juge en MOUVEMENT, et sur un cycle
## complet. Trois passes de réglage à l'aveugle en ont fait la preuve.
##
## Ce banc rend le cycle image par image, à phase imposée, sous deux angles
## et sans aucun bruit de fond : pas de sol, pas de mobs, pas de caméra qui
## bouge. Ce qui change d'une image à l'autre est donc UNIQUEMENT le corps.
##
## Usage :
##   godot --headless --path arena-rush res://outils_dev/rendu_cycle.tscn \
##         --rendering-driver opengl3
## (sous xvfb-run, le rendu logiciel Mesa suffit)
##
## Les images sortent dans user://cycle/ — le script affiche le chemin réel.

## Nombre d'images pour UN cycle complet (deux foulées).
const IMAGES := 24
## Scénarios rendus, avec la durée RÉELLE de chaque clip. Le tir en
## course a son propre clip, et c'est justement celui qui portait le
## déplacement racine : il doit être vérifié à part.
const SCENARIOS := [
	{"prefixe": "course", "vise": false, "duree": 0.50, "regime": 1.0},
	{"prefixe": "course_tir", "vise": true, "duree": 0.70, "regime": 1.0},
	# À L'ARRÊT, gâchette pressée : c'est le cas qui n'avait aucune
	# animation. On rend les deux candidats pour les départager.
	# TIR DEBOUT : pas de clip forcé — c'est la machine à états qui doit
	# produire le mélange (jambes au repos, buste en position de tir).
	{"prefixe": "tir_debout", "vise": true, "duree": 4.03, "regime": 0.0},
	{"prefixe": "repos", "vise": false, "duree": 4.03, "regime": 0.0},
]
const LARGEUR := 320
const HAUTEUR := 480

var _visuel: CharacterVisual
var _cam: Camera3D
var _dossier := ""
var _index := 0
var _vues := []
var _vue := 0
var _regime := 1.0
var _prefixe := "course"


func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://cycle")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)

	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	get_viewport().transparent_bg = false

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.16, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.72)
	env.ambient_light_energy = 1.0
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)

	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-38, -46, 0)
	soleil.light_energy = 1.5
	add_child(soleil)

	_cam = Camera3D.new()
	_cam.fov = 32.0
	add_child(_cam)

	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Color(0.30, 0.55, 0.95), Color(1.0, 0.75, 0.25), 1.7)
	# UNE VRAIE ARME dans la main : sa taille et sa tenue font partie de ce
	# qu'il faut juger. Un chiffre d'échelle ne dit pas si l'arme paraît
	# proportionnée.
	_visuel.attach_weapon(VisualKit.build_weapon("rifle", Color(1.0, 0.75, 0.25)))

	# PROFIL d'abord : c'est l'angle où une foulée se lit vraiment. Le
	# trois-quarts arrière ensuite, qui est l'angle du jeu.
	_vues = [
		{"nom": "profil", "pos": Vector3(3.4, 1.05, 0.0), "cible": Vector3(0, 0.85, 0)},
		{"nom": "jeu", "pos": Vector3(1.9, 2.5, 2.6), "cible": Vector3(0, 0.85, 0)},
	]
	_placer_camera()

	# On part d'une phase nulle et d'un régime établi : pas de montée en
	# vitesse à filmer, on veut le cycle stabilisé.
	_visuel.set_motion(Vector3(0, 0, -5.6), Vector3.ZERO)
	_appliquer_scenario()
	RenderingServer.frame_post_draw.connect(_capturer)


var _scenario := 0

func _appliquer_scenario() -> void:
	var s: Dictionary = SCENARIOS[_scenario]
	_prefixe = s["prefixe"]
	_regime = s.get("regime", 1.0)
	_visuel.set_aiming(s["vise"])
	# Certains scénarios visent un clip précis, que la machine à états ne
	# choisirait pas encore : on la court-circuite pour pouvoir REGARDER
	# le clip avant de décider comment le brancher.
	if s.has("clip"):
		_visuel.forcer_clip(s["clip"])
	# Une trame pour que le fondu vers le bon clip soit consommé avant la
	# première capture : sinon la planche s'ouvrirait sur une transition.
	for i in 12:
		_visuel.update_visual(1.0 / 60.0, _regime)


func _placer_camera() -> void:
	_cam.position = _vues[_vue]["pos"]
	_cam.look_at(_vues[_vue]["cible"])


func _process(delta: float) -> void:
	# `quit()` ne prend effet qu'en fin de trame : ce rappel tourne encore
	# une fois après le dernier scénario.
	if _scenario >= SCENARIOS.size():
		return
	# Pas de temps IMPOSÉ, indépendant de la cadence réelle du rendu : une
	# image = une fraction exacte du cycle, sinon les images ne seraient pas
	# régulièrement réparties et la planche mentirait.
	# Le clip de course dure 0,50 s et tourne à `speed_scale`. On répartit
	# donc exactement une période sur IMAGES captures, sinon la planche
	# montrerait un échantillonnage irrégulier et mentirait sur le cycle.
	var duree: float = SCENARIOS[_scenario]["duree"]
	var cadence := 1.0
	if SCENARIOS[_scenario].get("regime", 1.0) > 0.0:
		cadence = lerpf(CharacterVisual.CADENCE_MIN,
				CharacterVisual.CADENCE_MAX, _regime)
	var pas := duree / (cadence * float(IMAGES))
	_visuel.update_visual(pas, _regime)


func _capturer() -> void:
	# `quit()` ne prend effet qu'à la fin de la trame : le signal de fin de
	# rendu se déclenche encore une fois après. Sans cette garde, on lit une
	# vue qui n'existe plus.
	if _scenario >= SCENARIOS.size() or _vue >= _vues.size():
		return
	var img := get_viewport().get_texture().get_image()
	var nom := "%s/%s_%s_%02d.png" % [_dossier, _prefixe, _vues[_vue]["nom"], _index]
	img.save_png(nom)
	_index += 1
	if _index < IMAGES:
		return
	_index = 0
	_vue += 1
	if _vue < _vues.size():
		_placer_camera()
		return
	_vue = 0
	_placer_camera()
	_scenario += 1
	if _scenario < SCENARIOS.size():
		_appliquer_scenario()
		return
	get_tree().quit()
