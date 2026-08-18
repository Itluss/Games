extends Control
class_name KillFeedback
## RETOUR D'ÉLIMINATION — le moment de gloire, centralisé.
##
## POURQUOI CE NŒUD EXISTE À PART. Tuer un joueur doit être SATISFAISANT, et
## la satisfaction se fabrique avec cinq choses différentes : un texte qui
## surgit, un son, un effet, une vibration, une annonce de série. Ces cinq
## canaux n'ont rien à voir entre eux et arriveront à des moments
## différents du développement. Éparpillés dans le HUD, ils auraient été
## impossibles à régler ensemble.
##
## Ici, `celebrer()` est le point d'entrée UNIQUE. Brancher le son ou la
## vibration plus tard ne demandera pas de retrouver qui appelle quoi : tout
## part d'ici.
##
## Les textes vivent dans `ConfigProgression`, pas dans ce fichier : ce sont
## des mots de game design, ils changeront souvent, et on ne doit pas ouvrir
## un fichier d'interface pour renommer « RAMPAGE ».

## Durée d'affichage. Assez pour se lire d'un coup d'œil en plein combat,
## assez court pour ne pas gêner le duel suivant.
const DUREE := 1.5

var _titre: Label
var _detail: Label
var _serie: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ANCRES POSÉES À LA MAIN, et surtout PAS via un préréglage.
	#
	# Mesuré en image, deux fois : `set_anchors_preset` ne se contente pas de
	# changer les ancres, il recalcule les décalages pour préserver le
	# rectangle courant. Appelé ici, dans `_ready`, alors que le HUD vient
	# tout juste de poser un rectangle de largeur nulle, il figeait cette
	# largeur nulle — la colonne se centrait donc sur x = 0 et toute la
	# célébration sortait par le bord gauche de l'écran.
	#
	# Poser les quatre ancres et les deux décalages horizontaux ne laisse
	# place à aucune interprétation : le contrôle fait la largeur de son
	# parent, quoi qu'il arrive. Les décalages VERTICAUX restent au HUD,
	# c'est lui qui sait à quelle hauteur placer la célébration.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	modulate.a = 0.0

	var colonne := VBoxContainer.new()
	colonne.alignment = BoxContainer.ALIGNMENT_BEGIN
	colonne.add_theme_constant_override(&"separation", 2)
	colonne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	colonne.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(colonne)

	_titre = _ligne("ÉLIMINATION", 42, UiKit.TIR_CLAIR)
	colonne.add_child(_titre)
	_detail = _ligne("+100 XP", 26, UiKit.BLANC)
	colonne.add_child(_detail)
	_serie = _ligne("", 30, UiKit.OR_CLAIR)
	colonne.add_child(_serie)


func _ligne(t: String, taille: int, couleur: Color) -> Label:
	var l := Label.new()
	l.text = t
	UiKit.texte(l, taille, couleur, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## POINT D'ENTRÉE UNIQUE. `bilan` vient du profil : { xp, serie, palier }.
##
## Les futurs canaux — son, vibration, effet d'écran — se branchent ICI, et
## nulle part ailleurs. C'est la raison d'être de cette fonction.
func celebrer(nom_victime: String, bilan: Dictionary) -> void:
	var xp := int(bilan.get("xp", 0))
	var serie := int(bilan.get("serie", 0))
	var palier: Dictionary = bilan.get("palier", {})

	_titre.text = "ÉLIMINATION"
	_titre.add_theme_color_override(&"font_color", UiKit.TIR_CLAIR)
	# Le nom de la victime est plus parlant que le seul mot « élimination » :
	# c'est ce qui transforme un compteur en anecdote.
	_detail.text = "%s   +%d XP" % [nom_victime.to_upper(), xp]

	if not palier.is_empty():
		# Le palier PREND LA VEDETTE : c'est l'évènement rare, il doit
		# écraser visuellement le kill ordinaire qui l'a déclenché.
		_titre.text = String(palier.get("texte", ""))
		_titre.add_theme_color_override(&"font_color",
				palier.get("couleur", UiKit.OR_CLAIR))
		_serie.text = "SÉRIE x%d" % serie
	elif serie > 1:
		_serie.text = "SÉRIE x%d" % serie
	else:
		_serie.text = ""

	_jouer(not palier.is_empty())
	# Vibration : uniquement sur un palier, jamais à chaque kill. Une
	# vibration à répétition devient une nuisance et se fait couper dans les
	# réglages du téléphone — on la réserve donc aux moments qui comptent.
	if not palier.is_empty() and Cfg.is_touch_platform():
		Input.vibrate_handheld(120)


func _jouer(fort: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	var depart := 1.5 if fort else 1.22
	scale = Vector2(depart, depart)
	pivot_offset = Vector2(size.x * 0.5, 0.0)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)
	_tween.tween_interval(DUREE)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
