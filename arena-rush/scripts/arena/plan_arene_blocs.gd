extends RefCounted
class_name PlanAreneBlocs
## L'ARÈNE AUX BLOCS — 96 × 96 m, huit quartiers, fidèle à la planche.
##
## ─── LA PLANCHE FAIT AUTORITÉ ──────────────────────────────────────────
##
## Ce plan transcrit la référence « Hunt Royale style » fournie : une île
## de sable doré, huit zones à l'identité franche, un objectif étoile au
## centre, et un labyrinthe OUVERT — partout au moins deux façons de
## contourner. Les zones sont VOLONTAIREMENT asymétriques, comme sur la
## planche : l'équité vient des dix apparitions en anneau et du centre
## unique, pas d'un miroir.
##
## ─── LA GRILLE ─────────────────────────────────────────────────────────
##
## Toutes les positions sont des multiples de 1 m, tous les angles des
## multiples de 45°. Les blocs font 2 m : un mur s'écrit comme une LIGNE
## de blocs, une ruine comme un CONTOUR troué. Les trouées font au moins
## 3 m — un joueur ne se coince jamais, une poursuite passe toujours.
##
## ─── LES HUIT QUARTIERS (numérotation de la planche) ───────────────────
##
##   1  LA PLACE DE L'ÉTOILE   centre ouvert, plateforme de pierre.
##   2  LES RUINES ROUGES      nord-ouest et nord : enceintes brisées.
##   3  LA JUNGLE              nord-est : haies vertes, arbres, palmiers.
##   4  LE VILLAGE             est : cabane au toit turquoise, enclos.
##   5  LE CANYON              sud-est : crêtes de blocs rouge-orange.
##   6  LES CHAMPS             sud : rangées jaunes, barrières, touffes.
##   7  L'OASIS                sud-ouest : deux bassins turquoise, ponts.
##   8  LE LABORATOIRE         ouest : blocs violets, cuves, accent clair.

const COTE := 96.0
const BORD := 44.0
const CONGE := 12.0
## Levée anti-scintillement, héritée de l'arène précédente : le sol est
## huit millimètres sous zéro, les pièces douze au-dessus.
const LEVEE := 0.012

## Teintes nommées du plan — la correspondance vers le kit est UNIQUE,
## dans le bâtisseur. Le plan ne connaît pas les couleurs, il connaît les
## QUARTIERS.
## Chaque entrée : {"m": module, "c": teinte, "g": gabarit,
##                  "pos": Vector2, "a": angle en degrés}
static var PIECES: Array[Dictionary] = []
## Les bassins de l'oasis : disques {centre, rayon}. L'eau est un
## OBSTACLE : on la contourne ou l'on prend le pont.
static var BASSINS: Array[Dictionary] = []
## Les dix apparitions, en anneau à 38 m.
static var APPARITIONS: Array[Vector2] = []
## Les foyers de mobs — la planche les annonce (« 10 joueurs + mobs »).
static var FOYERS_MOBS: Array[Vector2] = []


static func dans_enceinte(p: Vector2, marge := 0.0) -> bool:
	var b := BORD - marge
	var c: float = minf(CONGE, b)
	var q := Vector2(absf(p.x), absf(p.y))
	if q.x > b or q.y > b:
		return false
	var noyau := b - c
	if q.x <= noyau or q.y <= noyau:
		return true
	return (q - Vector2(noyau, noyau)).length() <= c


# --- AIDES DE COMPOSITION ------------------------------------------------

static func _p(m: String, c: String, g: float, x: float, z: float,
		a := 0.0) -> void:
	PIECES.append({"m": m, "c": c, "g": g, "pos": Vector2(x, z), "a": a})


## Une ligne de blocs, du départ à l'arrivée, au pas de 2 m, avec des
## TROUÉES : la liste `trous` donne les indices de blocs omis. C'est la
## brique du labyrinthe ouvert — chaque mur est déjà percé à l'écriture.
static func _ligne(c: String, g: float, de: Vector2, vers: Vector2,
		trous: Array = []) -> void:
	var n := int(round(de.distance_to(vers) / 2.0))
	for i in n + 1:
		if i in trous:
			continue
		var q := de.lerp(vers, float(i) / maxf(n, 1))
		_p("bloc", c, g, q.x, q.y)


static func _static_init() -> void:
	# ─── 1 · LA PLACE DE L'ÉTOILE ──────────────────────────────────────
	_p("plateforme", "pierre", 1.0, 0, 0)
	# Quatre demi-blocs de pierre en moulinet, à neuf mètres : le seul
	# couvert du centre. On s'y abrite un instant, jamais durablement.
	_p("bloc", "pierre", 0.5, 9, 3)
	_p("bloc", "pierre", 0.5, -9, -3)
	_p("bloc", "pierre", 0.5, 3, -9)
	_p("bloc", "pierre", 0.5, -3, 9)
	for a in [30.0, 120.0, 210.0, 300.0]:
		var r := 7.0
		_p("touffe", "jaune", 1.0, cos(deg_to_rad(a)) * r,
				sin(deg_to_rad(a)) * r)

	# ─── 2 · LES RUINES ROUGES (nord-ouest, et un poste au nord) ───────
	# Une enceinte brisée 16 × 12 : trois trouées, une tour d'angle, des
	# gravats. On y entre de trois côtés, on s'y perd de vue en deux pas.
	_ligne("rouge", 1.0, Vector2(-34, 33), Vector2(-18, 33), [3, 4])
	_ligne("rouge", 1.0, Vector2(-34, 21), Vector2(-18, 21), [6])
	_ligne("rouge", 1.0, Vector2(-34, 23), Vector2(-34, 31), [2])
	_ligne("rouge", 1.0, Vector2(-18, 23), Vector2(-18, 31), [1])
	_p("bloc", "rouge", 2.0, -34, 33)          # la tour d'angle
	_ligne("rouge", 0.5, Vector2(-28, 27), Vector2(-24, 27))
	_p("bloc", "rouge", 0.5, -21, 24)          # gravats
	_p("bloc", "rouge", 0.5, -31, 22)
	_p("rocher", "pierre", 1.0, -16, 27)
	# Le poste du nord : un carré 8 × 8 percé, une tour.
	_ligne("rouge", 1.0, Vector2(-4, 36), Vector2(4, 36), [2])
	_ligne("rouge", 1.0, Vector2(-4, 30), Vector2(4, 30), [1])
	_ligne("rouge", 1.0, Vector2(-4, 32), Vector2(-4, 34))
	_p("bloc", "rouge", 2.0, 4, 36)
	_p("bloc", "rouge", 0.5, 4, 32)

	# ─── 3 · LA JUNGLE (nord-est) ──────────────────────────────────────
	# Deux haies décalées : un S de circulation, jamais un couloir fermé.
	_ligne("vert", 1.0, Vector2(14, 24), Vector2(30, 24), [2, 3, 6])
	_ligne("vert", 1.0, Vector2(20, 32), Vector2(36, 32), [4])
	_ligne("vert", 1.0, Vector2(36, 18), Vector2(36, 28), [2])
	_ligne("vert", 0.5, Vector2(16, 30), Vector2(16, 34))
	for e in [[13, 35], [19, 27], [27, 35], [33, 21], [24, 19], [35, 13]]:
		_p("arbre", "vert", 1.0, e[0], e[1])
	for e in [[16, 21], [30, 28], [37, 31], [21, 36], [29, 18]]:
		_p("palmier", "vert", 1.0, e[0], e[1], float((int(e[0]) * 7) % 360))
	for e in [[15, 26], [23, 30], [31, 23], [34, 27], [18, 33]]:
		_p("buisson", "vert", 1.0, e[0], e[1])

	# ─── 4 · LE VILLAGE (est) ──────────────────────────────────────────
	_p("cabane", "bois", 1.0, 35, 6, 90.0)     # porte vers l'ouest
	_p("cabane", "bois", 1.0, 30, -6, 0.0)
	for e in [[29, 11], [31, 12.5], [29.6, 14]]:
		_p("caisse", "bois", 1.0, e[0], e[1], float((int(e[0]) * 31) % 90))
	_p("tonneau", "bois", 1.0, 33, 12)
	_p("tonneau", "bois", 1.0, 26, -2)
	for i in 3:
		_p("barriere", "bois", 1.0, 26.0, 3.0 + float(i) * 2.7, 90.0)
	_p("barriere", "bois", 1.0, 28, 9.4, 0.0)
	_p("bloc", "jaune", 0.5, 38, 12)
	_p("touffe", "jaune", 1.0, 27, 7)
	_p("touffe", "jaune", 1.0, 37, -2)

	# ─── 5 · LE CANYON (sud-est) ───────────────────────────────────────
	# Deux crêtes doubles en quinconce : trois couloirs, six sorties.
	_ligne("rouge", 2.0, Vector2(18, -18), Vector2(30, -18), [2])
	_ligne("rouge", 2.0, Vector2(24, -26), Vector2(36, -26), [3])
	_ligne("rouge", 1.0, Vector2(14, -30), Vector2(24, -30), [1])
	_ligne("rouge", 1.0, Vector2(36, -14), Vector2(36, -20))
	_p("bloc", "rouge", 2.0, 14, -22)          # le pilier isolé
	_p("bloc", "rouge", 0.5, 20, -24)
	_p("bloc", "rouge", 0.5, 32, -30)
	_p("cactus", "vert", 1.0, 17, -26)
	_p("cactus", "vert", 1.0, 34, -21)
	_p("rocher", "pierre", 1.0, 27, -33)

	# ─── 6 · LES CHAMPS (sud) ──────────────────────────────────────────
	# Des rangées basses : du couvert de genou, qui casse les lignes de
	# tir sans jamais boucher la vue — la zone la plus « ouverte » après
	# la place.
	_ligne("jaune", 0.5, Vector2(-10, -26), Vector2(-2, -26), [2])
	_ligne("jaune", 0.5, Vector2(-8, -32), Vector2(0, -32), [1])
	_ligne("jaune", 0.5, Vector2(4, -29), Vector2(8, -29))
	_p("bloc", "jaune", 1.0, -12, -30)
	_p("bloc", "jaune", 1.0, 2, -35)
	for i in 3:
		_p("barriere", "bois", 1.0, -3.0 + float(i) * 2.7, -22.0, 0.0)
	for e in [[-6, -29], [1, -25], [-11, -23], [6, -33], [-1, -35]]:
		_p("touffe", "jaune", 1.0, e[0], e[1])
	_p("buisson", "vert", 1.0, -9, -35)
	_p("buisson", "vert", 1.0, 8, -25)

	# ─── 7 · L'OASIS (sud-ouest) ───────────────────────────────────────
	# Deux bassins, un détroit, UN pont sur le détroit : l'eau se
	# contourne par le nord ou le sud, ou se franchit au centre — trois
	# routes, comme partout.
	BASSINS.append({"centre": Vector2(-28, -19), "rayon": 5.8})
	BASSINS.append({"centre": Vector2(-17, -27), "rayon": 4.2})
	_p("pont", "bois", 1.0, -22.6, -22.8, 40.0)
	for e in [[-35, -15], [-33, -24], [-22, -14], [-12, -30], [-25, -31]]:
		_p("palmier", "vert", 1.0, e[0], e[1], float((int(e[1]) * 13) % 360))
	for e in [[-31, -13], [-14, -23], [-20, -33]]:
		_p("buisson", "vert", 1.0, e[0], e[1])
	_p("rocher", "pierre", 1.0, -36, -20)
	_p("touffe", "jaune", 1.0, -18, -18)

	# ─── 8 · LE LABORATOIRE (ouest) ────────────────────────────────────
	# Un U violet ouvert vers l'est, deux tours, deux machines : la seule
	# zone « construite » aux angles durs — sa couleur la nomme de loin.
	_ligne("violet", 1.0, Vector2(-38, 12), Vector2(-28, 12), [2])
	_ligne("violet", 1.0, Vector2(-38, 0), Vector2(-30, 0), [1])
	_ligne("violet", 1.0, Vector2(-38, 2), Vector2(-38, 10))
	_p("bloc", "violet", 2.0, -38, 12)
	_p("bloc", "violet", 2.0, -28, 0)
	_p("machine", "violet", 1.0, -33, 7)
	_p("machine", "violet", 1.0, -31, 3, 90.0)
	_p("bloc", "violet", 0.5, -26, 8)
	_p("rocher", "pierre", 1.0, -25, 14)

	# ─── LA LISIÈRE — l'île se termine en végétation, pas en mur ───────
	# Palmiers et arbres serrés SUR le pourtour, dans la frange d'herbe
	# peinte par le sol. Ils habillent la limite ; la collision, elle,
	# est un anneau invisible posé par le bâtisseur.
	var rng_l := 977
	for i in 26:
		var a := TAU * float(i) / 26.0 + 0.07
		var r := 41.5 + float((i * 7919 + rng_l) % 100) / 100.0 * 1.6
		var x := cos(a) * r
		var z := sin(a) * r
		if not dans_enceinte(Vector2(x, z), -3.0):
			continue
		match i % 3:
			0: _p("palmier", "vert", 1.0, x, z, float((i * 47) % 360))
			1: _p("arbre", "vert", 1.0, x, z)
			_: _p("buisson", "vert", 1.0, x, z)

	# ─── APPARITIONS ───────────────────────────────────────────────────
	# Dix, en anneau à 38 m, décalées d'un dix-huitième de tour pour ne
	# tomber ni dans l'eau ni dans un mur — vérifié par le banc.
	for i in 10:
		var a := TAU * float(i) / 10.0 + TAU / 20.0
		APPARITIONS.append(Vector2(
				round(cos(a) * 38.0), round(sin(a) * 38.0)))

	# ─── FOYERS DE MOBS ────────────────────────────────────────────────
	# Un par quartier périphérique calme : jungle, canyon, ruines,
	# champs. Jamais au centre — l'étoile appartient aux joueurs.
	FOYERS_MOBS.append(Vector2(26, 28))
	FOYERS_MOBS.append(Vector2(28, -22))
	FOYERS_MOBS.append(Vector2(-26, 27))
	FOYERS_MOBS.append(Vector2(-2, -29))
