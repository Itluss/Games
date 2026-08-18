extends Node3D
## APERÇU DE L'ARÈNE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER EXISTE : régler une ambiance sans la regarder, c'est
## exactement l'erreur qui a coûté trois passes à l'animation du personnage.
## Une exposition, une densité de brume ou un seuil de halo ne se jugent pas
## sur leur valeur numérique — seulement sur l'image qu'ils produisent.
##
## Trois vues, choisies pour ce qu'elles apprennent :
##   • JEU      — l'angle réel de la caméra de combat. Le seul qui compte
##                vraiment pour la lisibilité.
##   • PLONGÉE  — le plan de l'arène vu de haut : sert à juger la
##                répartition des masses et des rues.
##   • RASANTE  — presque au sol : c'est là que le ciel, la brume et les
##                néons se lisent, et là que les erreurs d'ambiance sautent
##                aux yeux.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_arene.tscn \
##       --rendering-driver opengl3

const LARGEUR := 960
const HAUTEUR := 540
## On laisse passer quelques trames avant la première capture : le halo et
## les ombres ont besoin d'une image pour s'établir, et la première serait
## trompeuse.
const CHAUFFE := 6

var _cam: Camera3D
var _dossier := ""
var _vue := 0
var _chauffe := 0

## Les vues suivent le MONDE CARRÉ. La plongée doit contenir ses 144 m de
## côté ; les autres se posent dans un secteur, là où le joueur vit. La
## dernière regarde droit vers la limite du monde — celle qui n'existe pas :
## c'est la vue où une couture se verrait, si elle se voyait.
var _vues := [
	{"nom": "jeu", "pos": Vector3(14.0, 15.0, 20.0), "cible": Vector3(0, 1.0, 0)},
	{"nom": "plongee", "pos": Vector3(1.0, 200.0, 1.2), "cible": Vector3(0, 0, 0)},
	# LES RUINES sont la zone d'essai visuel : deux vues, une de loin pour
	# juger la masse et la couleur, une au ras pour juger la lisibilité.
	{"nom": "ruines", "pos": Vector3(-34.0, 14.0, -26.0), "cible": Vector3(-46, 2.0, -38)},
	{"nom": "ruines_pres", "pos": Vector3(-42.0, 9.0, -30.0), "cible": Vector3(-46, 1.2, -37)},
	{"nom": "creuset", "pos": Vector3(-46.0, 16.0, 4.0), "cible": Vector3(-56, 3.0, 14)},
	{"nom": "bosquet", "pos": Vector3(-10.0, 14.0, 36.0), "cible": Vector3(-20, 3.0, 46)},
]

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)

	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)

	# UN PERSONNAGE DANS L'IMAGE, et ce n'est pas de la coquetterie : toute
	# la palette a été choisie pour que Kael reste lisible dessus. Une
	# capture d'arène vide ne permettrait pas de vérifier la seule chose
	# qu'il fallait vérifier.
	var kael := CharacterVisual.new()
	add_child(kael)
	kael.build(Cfg.COL_LOCAL_PLAYER, Cfg.COL_KAEL_ACCENT, 1.9)
	kael.position = Vector3(4.5, 0, 8.0)
	kael.set_motion(Vector3(0, 0, -4.0), Vector3.ZERO)

	_cam = Camera3D.new()
	_cam.fov = 46.0
	add_child(_cam)
	_placer()
	RenderingServer.frame_post_draw.connect(_capturer)


func _placer() -> void:
	_cam.position = _vues[_vue]["pos"]
	_cam.look_at(_vues[_vue]["cible"])


func _capturer() -> void:
	# `quit()` ne prend effet qu'en fin de trame : ce signal se déclenche
	# encore une fois après. Sans cette garde, on lirait une vue détruite.
	if _vue >= _vues.size():
		return
	_chauffe += 1
	if _chauffe < CHAUFFE:
		return
	_chauffe = 0
	var img := get_viewport().get_texture().get_image()
	var nom := "%s/arene_%s.png" % [_dossier, _vues[_vue]["nom"]]
	img.save_png(nom)
	print("→ ", nom)
	_vue += 1
	if _vue < _vues.size():
		_placer()
		return
	get_tree().quit()
