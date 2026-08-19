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
	# LES RUINES BASSES : deux vues, une de loin pour juger la masse et la
	# couleur, une au ras pour juger la lisibilité du couvert.
	{"nom": "ruines", "pos": Vector3(-34.0, 14.0, -26.0), "cible": Vector3(-46, 2.0, -38)},
	{"nom": "ruines_pres", "pos": Vector3(-42.0, 9.0, -30.0), "cible": Vector3(-46, 1.2, -37)},
	# SOUS L'ARCHE, AU PLACEMENT EXACT DE LA CAMÉRA DE JEU. Le tablier est à
	# 8,6 m, la caméra à 10,4 m : cette vue répond en une image à la question
	# « que voit le joueur quand il franchit l'arche par-dessous ? ».
	{"nom": "sous_arche", "pos": Vector3(60.0, 10.4, 26.0), "cible": Vector3(60, 1.4, 18)},
	{"nom": "esplanade", "pos": Vector3(-46.0, 16.0, 4.0), "cible": Vector3(-56, 3.0, 14)},
	{"nom": "oasis", "pos": Vector3(-10.0, 14.0, 36.0), "cible": Vector3(-20, 3.0, 46)},
	# LES CINQ REPÈRES DE LA PLANCHE, chacun sous l'angle où sa silhouette
	# se lit. C'est en image, et seulement en image, qu'on voit si un repère
	# se distingue du sable derrière lui.
	{"nom": "pilier_solaire", "pos": Vector3(38.0, 11.0, -33.0), "cible": Vector3(23, 8.0, -43)},
	{"nom": "portail_brise", "pos": Vector3(-29.0, 9.0, -24.0), "cible": Vector3(-41, 4.0, -32)},
	{"nom": "hangar_cobalt", "pos": Vector3(13.0, 12.0, 15.0), "cible": Vector3(-1, 4.0, 3)},
	{"nom": "temple", "pos": Vector3(0.0, 11.0, 61.0), "cible": Vector3(-12, 3.5, 51)},
	{"nom": "cristaux", "pos": Vector3(20.0, 13.0, -22.0), "cible": Vector3(6, 1.5, -6)},
	{"nom": "dunes", "pos": Vector3(44.0, 13.0, -38.0), "cible": Vector3(32, 1.0, -50)},
	{"nom": "canyon", "pos": Vector3(66.0, 13.0, 38.0), "cible": Vector3(54, 1.5, 26)},
	# Gros plan sur une tour du plan d'origine : c'est la pièce Meshy la
	# plus grande, donc celle où un défaut de matière se voit le mieux.
	{"nom": "tour_meshy", "pos": Vector3(-46.0, 8.0, 28.0), "cible": Vector3(-54.5, 5.0, 32.6)},
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
