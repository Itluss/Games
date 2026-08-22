extends PanelContainer
class_name Classement
## LE CLASSEMENT — quatre lignes, quatre colonnes, rien d'autre.
##
## COLONNES : rang, nom, kills, et la PRIME. Rien de plus : chaque
## information ajoutée coûterait une seconde de lecture en plein combat.
##
## LE TRI SUIT LA PRIME. C'est elle, l'enjeu du jeu : le classement est
## la course aux couronnes en direct — le premier du tableau EST le roi
## qui porte la couronne dans l'arène, et le lien entre les deux se fait
## d'un regard. Les kills départagent, l'identifiant stabilise.

## Nombre de lignes affichées. Quatre comme la maquette : au-delà, le
## panneau mange le coin de l'écran et plus personne ne le lit.
const LIGNES := 4
## Cadence de rafraîchissement. Le classement bouge à chaque élimination,
## soit quelques fois par minute — le relire soixante fois par seconde
## serait absurde.
const PERIODE := 0.4

var joueur_local: Node3D = null

var _grille: GridContainer
var _cases: Array[Label] = []
var _prochain := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel",
			UiKit.panneau(18, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 3))
	var marge := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right"]:
		marge.add_theme_constant_override(cote, 12)
	for cote in [&"margin_top", &"margin_bottom"]:
		marge.add_theme_constant_override(cote, 8)
	marge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marge.add_child(col)

	var titre := _texte("CLASSEMENT", 19, UiKit.BLANC)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(titre)

	_grille = GridContainer.new()
	_grille.columns = 4
	_grille.add_theme_constant_override(&"h_separation", 10)
	_grille.add_theme_constant_override(&"v_separation", 3)
	_grille.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_grille)

	# En-tête : les deux colonnes de chiffres sont annoncées, le rang et le
	# nom se passent d'étiquette.
	_grille.add_child(_texte("", 15))
	_grille.add_child(_texte("", 15))
	var t_kills := _texte("KILLS", 14, Color(0.75, 0.81, 0.92))
	t_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grille.add_child(t_kills)
	# LA PIÈCE EST DESSINÉE, PAS ÉCRITE — voir `UiKit.PieceGlyphe`.
	var boite := Control.new()
	boite.custom_minimum_size = Vector2(28, 18)
	boite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grille.add_child(boite)
	var t_piece := UiKit.PieceGlyphe.new()
	t_piece.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	t_piece.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	t_piece.grow_vertical = Control.GROW_DIRECTION_BOTH
	t_piece.offset_left = -17
	t_piece.offset_top = -8
	t_piece.offset_bottom = 8
	boite.add_child(t_piece)

	for i in LIGNES:
		var rang := _texte("", 17, Color(0.62, 0.70, 0.85))
		_grille.add_child(rang)
		var nom := _texte("", 18, UiKit.BLANC)
		nom.custom_minimum_size = Vector2(96, 0)
		_grille.add_child(nom)
		var kills := _texte("", 18, UiKit.BLANC)
		kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kills.custom_minimum_size = Vector2(34, 0)
		_grille.add_child(kills)
		var pieces := _texte("", 18, UiKit.OR_CLAIR)
		pieces.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pieces.custom_minimum_size = Vector2(28, 0)
		_grille.add_child(pieces)
		_cases.append_array([rang, nom, kills, pieces])

	set_process(true)


func _texte(t: String, taille: int, couleur: Color = UiKit.BLANC) -> Label:
	var l := Label.new()
	l.text = t
	UiKit.texte(l, taille, couleur)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_prochain -= delta
	if _prochain > 0.0:
		return
	_prochain = PERIODE
	rafraichir()


func rafraichir() -> void:
	var liste: Array = []
	for n in get_tree().get_nodes_in_group(&"players"):
		var j := n as Player
		if j == null or not is_instance_valid(j):
			continue
		liste.append(j)
	# Tri par PRIME, puis par kills, puis par identifiant. LE DERNIER
	# CRITÈRE N'EST PAS DE LA COQUETTERIE : sans lui, deux joueurs à
	# égalité permutent d'une image à l'autre au gré de l'ordre du
	# groupe, et le tableau se met à clignoter.
	liste.sort_custom(func(a: Player, b: Player) -> bool:
		if a.prime != b.prime:
			return a.prime > b.prime
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.peer_id < b.peer_id)

	# ─── LE JOUEUR LOCAL EST TOUJOURS VISIBLE ─────────────────────────
	#
	# C'ÉTAIT UN VRAI DÉFAUT, ET IL NE SE VOYAIT QU'EN JOUANT. En début de
	# partie tout le monde est à zéro kill : le départage se fait alors sur
	# l'identifiant, et les bots portent des identifiants négatifs. Le
	# tableau affichait donc quatre bots et jamais le joueur — vérifié en
	# capture dans le navigateur. Un classement où l'on ne se trouve pas ne
	# sert à rien.
	#
	# On garde le tri intact et l'on remplace la DERNIÈRE ligne visible par
	# la sienne, en conservant son vrai rang : il voit les meilleurs, puis
	# où il en est.
	var rangs: Array[int] = []
	for i in mini(LIGNES, liste.size()):
		rangs.append(i)
	var moi := -1
	for i in liste.size():
		if liste[i] == joueur_local:
			moi = i
			break
	if moi >= 0 and not rangs.has(moi) and not rangs.is_empty():
		rangs[rangs.size() - 1] = moi

	for i in LIGNES:
		var base := i * 4
		if i >= rangs.size():
			for k in 4:
				_cases[base + k].text = ""
			continue
		var rang: int = rangs[i]
		var j: Player = liste[rang]
		_cases[base].text = str(rang + 1)
		_cases[base + 1].text = j.display_name.to_upper()
		# LE NOM PORTE LA COULEUR DU HÉROS, comme au-dessus de sa tête.
		# C'est ce qui permet de faire le lien entre la ligne du tableau et
		# la silhouette qu'on a en face sans lire le nom.
		_cases[base + 1].add_theme_color_override(&"font_color",
				Cfg.couleur_identite(j.heros()))
		_cases[base + 2].text = str(j.kills)
		_cases[base + 3].text = str(j.prime)
