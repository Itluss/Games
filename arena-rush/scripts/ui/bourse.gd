extends Control
class_name Bourse
## LA BOURSE — le compteur de prime du joueur local, près du pouce droit.
##
## Elle répond à une seule question, celle qui gouverne tout le système :
## « qu'est-ce que je risque en ce moment ? ». Une pièce d'or dessinée,
## le montant en gros, le multiplicateur quand il dépasse ×1 — et un
## liseré de couronne quand on est le roi. Chaque pièce gagnée fait
## SAUTER le disque : le gain se sent avant d'être lu.
##
## Elle occupe la place de l'ancien loader d'étoile : là où le regard
## passe déjà, entre la visée et le décor.

## Durée du sursaut de gain.
const SURSAUT := 0.35

var _prime := 0
var _mult := 1
var _roi := false
var _sursaut := 0.0
var _police: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_police = UiKit.police()


func poser(prime: int, mult: int, roi: bool) -> void:
	if prime > _prime:
		_sursaut = SURSAUT
	if prime != _prime or mult != _mult or roi != _roi:
		_prime = prime
		_mult = mult
		_roi = roi
		queue_redraw()


func _process(delta: float) -> void:
	if _sursaut > 0.0:
		_sursaut = maxf(0.0, _sursaut - delta)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	# Le sursaut : le disque gonfle puis retombe, en dixième de seconde.
	var pr := _sursaut / SURSAUT
	var gonfle := 1.0 + 0.16 * sin(pr * PI)
	r *= gonfle
	# Le socle sombre, comme les boutons voisins.
	draw_circle(c, r + 3.0, Color(0.05, 0.07, 0.14, 0.55))
	# La pièce : disque d'or, bord sombre, éclat.
	draw_circle(c, r, Color("c8901e"))
	draw_circle(c, r - 3.0, UiKit.OR_CLAIR if _sursaut <= 0.0
			else Color("ffe27a"))
	draw_arc(c, r - 6.5, PI * 1.05, PI * 1.55, 12, Color(1, 1, 1, 0.55), 2.5)
	# Le liseré du roi.
	if _roi:
		draw_arc(c, r + 5.0, 0.0, TAU, 40, Color("ffd94a"), 3.0)
	# Le montant, en gros — c'est LE chiffre du jeu.
	var texte := str(_prime)
	var taille := 26 if _prime < 100 else 21
	var l := _police.get_string_size(texte, HORIZONTAL_ALIGNMENT_CENTER,
			-1, taille)
	draw_string_outline(_police, c + Vector2(-l.x * 0.5, l.y * 0.30),
			texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 4,
			Color(0.24, 0.14, 0.02))
	draw_string(_police, c + Vector2(-l.x * 0.5, l.y * 0.30), texte,
			HORIZONTAL_ALIGNMENT_LEFT, -1, taille, Color.WHITE)
	# Le multiplicateur, sous la pièce, seulement quand il travaille.
	if _mult > 1:
		var m := "×%d" % _mult
		var lm := _police.get_string_size(m, HORIZONTAL_ALIGNMENT_CENTER,
				-1, 13)
		var pos := Vector2(c.x - lm.x * 0.5, size.y - 2.0)
		draw_string_outline(_police, pos, m, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 13, 3, Color(0.24, 0.14, 0.02))
		draw_string(_police, pos, m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color("ffe27a"))
