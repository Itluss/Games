extends Control
class_name LoaderEtoile
## LE LOADER D'ÉTOILE — une icône, un anneau, et rien d'autre.
##
## ─── POURQUOI IL REMPLACE LE BANDEAU ───────────────────────────────────
##
## L'état de l'étoile occupait un bandeau de deux lignes en haut au centre :
## nom du porteur, jauge, compteur « 18 / 30 ». C'était lisible, et c'était
## posé exactement là où l'on regarde en combat. Sur un écran de 390 pixels
## de haut, il mangeait le tiers supérieur du champ de vision.
##
## Tout ce qu'il disait tient dans un disque de la taille d'un bouton :
##
##   · L'ANNEAU dit combien de temps est tenu — c'est la seule chose qui
##     évolue en continu, et un arc se lit sans être lu, du coin de l'œil ;
##   · LE POINT dit QUI le tient — vert c'est moi, rose c'est un
##     adversaire, gris personne ;
##   · L'ÉTOILE elle-même dit s'il y a quelque chose à prendre : grise
##     quand elle traîne, dorée quand elle est portée.
##
## Le nom du porteur disparaît de l'interface, et c'est assumé : il est
## déjà écrit au-dessus de sa tête, avec une étoile dessus, et suivi sur la
## minicarte. Le répéter en haut de l'écran coûtait un tiers de la vue pour
## une information qu'on a déjà trois fois.
##
## LE CHIFFRE EXACT DISPARAÎT AUSSI. « 18 / 30 » demande d'être lu ; un
## anneau aux deux tiers se voit. En combat, on n'a pas le temps de lire.

## Épaisseur de l'anneau, en pixels.
const EPAISSEUR := 8.0
## Rayon du point d'appartenance, et son écart au bord.
const POINT := 7.0
## Durée du flash de victoire.
const FLASH := 0.7

var _ratio := 0.0
var _porteur := 0
var _t := 0.0
var _flash := 0.0
var _perte := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EtoileDirector.gagnee.connect(_sur_victoire)
	EtoileDirector.lachee.connect(_sur_perte)
	set_process(true)


func _sur_victoire(_peer_id: int, _victoires: int) -> void:
	_flash = FLASH


func _sur_perte(_position: Vector3) -> void:
	# L'ANNEAU SE VIDE D'UN COUP, sans transition. C'est la consigne de la
	# maquette, et elle a raison : une jauge qui redescend doucement
	# suggère qu'on perd du terrain progressivement, alors que la règle est
	# brutale — tout est perdu à l'instant de la mort.
	_perte = 0.35


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
	if _perte > 0.0:
		_perte = maxf(_perte - delta, 0.0)
	var r := 0.0
	if EtoileDirector.porteur_id != 0:
		r = clampf(EtoileDirector.temps / EtoileDirector.DUREE, 0.0, 1.0)
	# On ne redessine que si quelque chose bouge : au repos, l'icône est
	# figée et ne coûte rien.
	var bouge := not is_equal_approx(r, _ratio) \
			or EtoileDirector.porteur_id != _porteur \
			or _flash > 0.0 or _perte > 0.0 \
			or EtoileDirector.porteur_id == Net.local_id()
	_ratio = r
	_porteur = EtoileDirector.porteur_id
	if bouge:
		queue_redraw()


## Vert : c'est moi. Rose : un adversaire. Gris : personne.
func _teinte_appartenance() -> Color:
	if _porteur == 0:
		return Color(0.62, 0.66, 0.74)
	if _porteur == Net.local_id():
		return Color(0.42, 0.90, 0.45)
	return Color(1.0, 0.29, 0.55)


func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - EPAISSEUR * 0.5 - 2.0
	var tenu := _porteur != 0

	# PULSATION DOUCE QUAND C'EST MOI QUI LA TIENS. Elle ne sert pas à
	# décorer : c'est le seul signal qui distingue « quelqu'un la tient »
	# de « je la tiens », sans lire le point de couleur.
	var pouls := 1.0
	if tenu and _porteur == Net.local_id():
		pouls = 1.0 + sin(_t * 4.4) * 0.045

	# Le fond : un disque sombre, pour que l'anneau et l'étoile tiennent
	# au-dessus de n'importe quel décor.
	draw_circle(c, (r + EPAISSEUR * 0.5) * pouls, Color(0.05, 0.07, 0.13, 0.86))

	# La piste de l'anneau, toujours visible : sans elle, un anneau au
	# quart plein ressemble à un anneau cassé.
	draw_arc(c, r * pouls, 0.0, TAU, 40, Color(1, 1, 1, 0.13), EPAISSEUR, true)

	if tenu and _ratio > 0.001:
		# L'arc part du HAUT et tourne dans le sens des aiguilles : c'est
		# la lecture d'un compte à rebours, celle que tout le monde a déjà.
		var debut := -PI * 0.5
		var teinte := UiKit.OR_CLAIR
		# Il chauffe vers le blanc sur la fin : les cinq dernières secondes
		# se voient sans regarder un chiffre.
		if _ratio > 0.83:
			teinte = UiKit.OR_CLAIR.lerp(Color(1, 1, 0.86),
					(_ratio - 0.83) / 0.17)
		draw_arc(c, r * pouls, debut, debut + TAU * _ratio,
				maxi(int(40.0 * _ratio) + 2, 6), teinte, EPAISSEUR, true)

	# L'étoile, au centre. Grise tant que personne ne la porte.
	var or_ou_gris := UiKit.OR_CLAIR if tenu else Color(0.55, 0.58, 0.64)
	if _flash > 0.0:
		or_ou_gris = or_ou_gris.lerp(Color.WHITE, _flash / FLASH)
	_etoile(c, r * 0.60 * pouls * (1.0 + _flash * 0.28), or_ou_gris)

	# Le point d'appartenance, en haut à droite du disque.
	var p := c + Vector2(0.72, -0.72) * (r + EPAISSEUR * 0.5)
	draw_circle(p, POINT + 2.0, Color(0.04, 0.06, 0.11, 0.9))
	draw_circle(p, POINT, _teinte_appartenance())

	# Le halo de victoire : un cercle clair qui s'ouvre et s'efface.
	if _flash > 0.0:
		var k := 1.0 - _flash / FLASH
		draw_arc(c, (r + EPAISSEUR) * (1.0 + k * 0.55), 0.0, TAU, 40,
				Color(1, 0.92, 0.6, _flash / FLASH * 0.8), 4.0, true)
	# Le vidage : un cercle rouge bref, pour que la perte se voie même si
	# l'on ne regardait pas l'anneau.
	if _perte > 0.0:
		draw_arc(c, r + EPAISSEUR * 0.5, 0.0, TAU, 40,
				Color(1, 0.35, 0.4, _perte / 0.35 * 0.85), 5.0, true)


## Même contour à cinq branches que la maille 3D, l'icône de la minicarte
## et le glyphe du classement. Quatre dessins, une seule silhouette.
func _etoile(c: Vector2, r: float, teinte: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0 - PI * 0.5
		var rayon: float = r if i % 2 == 0 else r * 0.44
		pts.append(c + Vector2(cos(a), sin(a)) * rayon)
	draw_colored_polygon(pts, teinte)
	var contour := pts.duplicate()
	contour.append(pts[0])
	draw_polyline(contour, Color(0.16, 0.11, 0.03, 0.85), 2.0, true)
