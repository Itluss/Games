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

## Cellules de 2 m déjà occupées par un bloc — le semis les évite.
static var _occupe: Dictionary = {}


static func _p(m: String, c: String, g: float, x: float, z: float,
		a := 0.0, y := 0.0) -> void:
	PIECES.append({"m": m, "c": c, "g": g, "pos": Vector2(x, z),
			"a": a, "y": y})


static func _hash(i: int) -> float:
	return float(((i * 2654435761) % 1000 + 1000) % 1000) / 1000.0


## UN MUR — la brique de la planche. La référence n'est pas un semis
## d'amas : c'est un RÉSEAU D'ALLÉES, et ce sont les murs qui les
## dessinent. Un mur est une file de cubes qui SE TOUCHENT, percée de
## portes (`trous`, en indices de cubes), hérissée d'un cube d'étage de
## loin en loin — de vrais cubes empilés, comme sur l'image.
static func _mur(c: String, de: Vector2, vers: Vector2, graine: int,
		trous: Array = [], g := 1.0) -> void:
	var n := int(round(de.distance_to(vers) / 2.0))
	for i in n + 1:
		if i in trous:
			continue
		var q := de.lerp(vers, float(i) / maxf(n, 1))
		_occupe[Vector2i(int(round(q.x / 2.0)), int(round(q.y / 2.0)))] = true
		_p("bloc", c, g, q.x, q.y)
		if g >= 1.0 and _hash(graine + i * 37) > 0.8:
			_p("bloc", c, g, q.x, q.y, 0.0, 2.0)


## Un petit AMAS compact (gravats, réserve, île de couvert) — jamais la
## structure principale : la structure, ce sont les murs.
static func _tas(c: String, cx: float, cz: float, w: int, d: int,
		graine: int) -> void:
	for i in w:
		for j in d:
			var t := _hash(graine + i * 73 + j * 179)
			var x := cx + (float(i) - float(w - 1) * 0.5) * 2.0
			var z := cz + (float(j) - float(d - 1) * 0.5) * 2.0
			if t < 0.18:
				continue
			_occupe[Vector2i(int(round(x / 2.0)), int(round(z / 2.0)))] = true
			if t < 0.30:
				_p("bloc", c, 0.5, x, z)
			else:
				_p("bloc", c, 1.0, x, z)
				if t > 0.84:
					_p("bloc", c, 1.0, x, z, 0.0, 2.0)


## Le point est-il sur une ALLÉE ? Les rues du plan sont sacrées : ni
## bloc, ni semis — c'est la garantie « on circule partout » de la
## planche, et le banc la mesure.
static func _sur_allee(p: Vector2) -> bool:
	if p.length() < 13.0:
		return true
	if p.length() > 33.0:
		return false
	if absf(p.x) < 2.6 or absf(p.y) < 2.6:
		return true
	return absf(absf(p.x) - 12.0) < 2.6 or absf(absf(p.y) - 12.0) < 2.6


static func _libre_semis(x: float, z: float) -> bool:
	if _occupe.has(Vector2i(int(round(x / 2.0)), int(round(z / 2.0)))):
		return false
	var p := Vector2(x, z)
	if _sur_allee(p):
		return false
	for b: Dictionary in BASSINS:
		if p.distance_to(b["centre"]) < float(b["rayon"]) + 2.0:
			return false
	for a: Vector2 in APPARITIONS:
		if p.distance_to(a) < 3.0:
			return false
	return dans_enceinte(p, 1.5)


## ─── LE PLAN DES RUES ──────────────────────────────────────────────────
##
## Neuf parcelles de douze mètres, séparées par des allées de cinq :
##
##        NO      N      NE            NO  ruines rouges (cour fermée)
##      ┌────┬────────┬────┐           N   fortin rouge
##      │ NO │   N    │ NE │           NE  jungle (couloirs de haies)
##      ├────┼────────┼────┤           E   village (cour de barrières)
##      │ O  │ PLACE  │ E  │           SE  canyon (double rempart)
##      ├────┼────────┼────┤           S   champs (rangées basses)
##      │ SO │   S    │ SE │           SO  oasis (bassins et pont)
##      └────┴────────┴────┘           O   laboratoire (enclos violet)
##
## Les allées passent à x = ±12 et z = ±12, plus les deux axes ; la place
## occupe le centre. Chaque parcelle ouvre sur SES DEUX RUES au moins par
## deux portes : le labyrinthe est ouvert PAR CONSTRUCTION, et les murs —
## pas le vide — dessinent les chemins, comme sur la planche.
static func _static_init() -> void:
	BASSINS.append({"centre": Vector2(-22, -21), "rayon": 5.6})
	BASSINS.append({"centre": Vector2(-13, -27), "rayon": 3.8})
	for i in 10:
		var a := TAU * float(i) / 10.0 + TAU / 20.0
		APPARITIONS.append(Vector2(
				round(cos(a) * 38.0), round(sin(a) * 38.0)))
	FOYERS_MOBS.append(Vector2(21, 30))
	FOYERS_MOBS.append(Vector2(30, -21))
	FOYERS_MOBS.append(Vector2(-30, 26))
	FOYERS_MOBS.append(Vector2(2, -34))

	# ─── LA PLACE (parcelle centrale) ──────────────────────────────────
	_p("plateforme", "pierre", 1.0, 0, 0)
	# Le petit enclos de la planche : quatre murets de pierre en moulinet
	# autour de la plateforme, quatre entrées.
	_mur("pierre", Vector2(-4, 8), Vector2(4, 8), 1, [], 0.5)
	_mur("pierre", Vector2(-4, -8), Vector2(4, -8), 2, [], 0.5)
	_mur("pierre", Vector2(8, -4), Vector2(8, 4), 3, [], 0.5)
	_mur("pierre", Vector2(-8, -4), Vector2(-8, 4), 4, [], 0.5)
	for a in [45.0, 135.0, 225.0, 315.0]:
		_p("touffe", "jaune", 1.0, cos(deg_to_rad(a)) * 10.0,
				sin(deg_to_rad(a)) * 10.0)

	# ─── NO · LES RUINES ROUGES — une cour fermée qu'on visite ─────────
	# Périmètre 18 × 12 sur la parcelle, TROIS portes (sud, est, nord),
	# une cour intérieure coupée d'un mur bas, deux tours d'angle.
	_mur("rouge", Vector2(-30, 27), Vector2(-14, 27), 11, [3])
	_mur("rouge", Vector2(-30, 15), Vector2(-14, 15), 13, [5])
	_mur("rouge", Vector2(-30, 17), Vector2(-30, 25), 17, [2])
	_mur("rouge", Vector2(-14, 17), Vector2(-14, 25), 19)
	_p("bloc", "rouge", 1.0, -30, 27, 0.0, 2.0)
	_p("bloc", "rouge", 1.0, -14, 15, 0.0, 2.0)
	_mur("rouge", Vector2(-26, 21), Vector2(-20, 21), 23, [1], 0.5)
	_p("bloc", "rouge", 0.5, -17, 24)
	_p("bloc", "rouge", 0.5, -27, 18)

	# ─── N · LE FORTIN — la seconde ruine de la planche ────────────────
	_mur("rouge", Vector2(-4, 32), Vector2(6, 32), 29, [2])
	_mur("rouge", Vector2(-4, 24), Vector2(6, 24), 31, [2, 3])
	_mur("rouge", Vector2(6, 26), Vector2(6, 30), 41)
	_p("bloc", "rouge", 1.0, 6, 32, 0.0, 2.0)
	_p("bloc", "rouge", 0.5, -4, 26)
	_tas("rouge", -8, 35, 2, 2, 43)

	# ─── NE · LA JUNGLE — des couloirs de haies, pas un bosquet ────────
	# Deux haies décalées font le S de circulation ; arbres aux angles.
	_mur("vert", Vector2(14, 18), Vector2(28, 18), 47, [2, 5])
	_mur("vert", Vector2(18, 26), Vector2(32, 26), 53, [4])
	_mur("vert", Vector2(32, 14), Vector2(32, 24), 59, [2])
	_mur("vert", Vector2(14, 30), Vector2(14, 34), 61, [], 0.5)
	_tas("vert", 22, 33, 2, 2, 67)
	for e in [[16, 21], [25, 30], [31, 17], [20, 15], [34, 29], [15, 27]]:
		_p("arbre" if int(e[0]) % 2 == 0 else "palmier", "vert", 1.0,
				e[0], e[1], float((int(e[0]) * 41) % 360))
	for e in [[18, 29], [28, 21], [23, 17], [33, 33]]:
		_p("buisson", "vert", 1.0, e[0], e[1])

	# ─── E · LE VILLAGE — une cour de ferme sur la rue ─────────────────
	_p("cabane", "bois", 1.0, 20, 5, 180.0)
	_p("cabane", "bois", 1.0, 28, -6, 90.0)
	for i in 4:
		_p("barriere", "bois", 1.0, 16.0 + float(i) * 2.7, 9.6, 0.0)
	for i in 3:
		_p("barriere", "bois", 1.0, 33.0, -1.0 + float(i) * 2.7, 90.0)
	for e in [[25, 8], [26.6, 9.2], [25.6, 10.6]]:
		_p("caisse", "bois", 1.0, e[0], e[1], float((int(e[0]) * 31) % 90))
	_p("tonneau", "bois", 1.0, 30, 8)
	_p("tonneau", "bois", 1.0, 17, -3)
	_p("bloc", "jaune", 0.5, 31, 2)
	_p("touffe", "jaune", 1.0, 23, -2)

	# ─── SE · LE CANYON — deux remparts, trois couloirs ────────────────
	# Les deux longues crêtes de la planche, portes en quinconce : on y
	# entre par l'ouest, on en sort par le nord ou l'est, jamais coincé.
	_mur("rouge", Vector2(14, -16), Vector2(32, -16), 71, [4])
	_mur("rouge", Vector2(16, -24), Vector2(34, -24), 73, [2, 7])
	_mur("rouge", Vector2(34, -14), Vector2(34, -22), 79, [3])
	_mur("rouge", Vector2(14, -32), Vector2(26, -32), 83, [2], 1.0)
	_p("bloc", "rouge", 1.0, 14, -16, 0.0, 2.0)
	_p("bloc", "rouge", 1.0, 34, -22, 0.0, 2.0)
	_p("bloc", "rouge", 1.0, 22, -24, 0.0, 2.0)
	_tas("rouge", 30, -30, 2, 2, 89)
	_p("cactus", "vert", 1.0, 18, -20)
	_p("cactus", "vert", 1.0, 29, -13)
	_p("rocher", "pierre", 1.0, 25, -28)

	# ─── S · LES CHAMPS — trois rangées basses, à ciel ouvert ──────────
	# Du couvert de genou en LIGNES, comme des cultures : casse la ligne
	# de tir, jamais la vue. C'est le quartier des duels longs.
	_mur("jaune", Vector2(-10, -16), Vector2(-4, -16), 97, [], 0.5)
	_mur("jaune", Vector2(4, -18), Vector2(10, -18), 101, [1], 0.5)
	_mur("jaune", Vector2(-10, -26), Vector2(-4, -26), 103, [1], 0.5)
	_p("bloc", "jaune", 1.0, 4, -24)
	_p("bloc", "jaune", 1.0, -10, -21)
	_p("bloc", "jaune", 1.0, 4, -24, 0.0, 2.0)
	for i in 3:
		_p("barriere", "bois", 1.0, 4.0 + float(i) * 2.7, -31.0, 0.0)
	_tas("jaune", 7, -33, 2, 2, 107)

	# ─── SO · L'OASIS — l'eau, l'île, le pont ──────────────────────────
	_p("pont", "bois", 1.0, -17.2, -24.3, 35.0)
	for e in [[-30, -15], [-29, -25], [-16, -16], [-8, -30], [-20, -32],
			[-27, -10], [-33, -20]]:
		_p("palmier", "vert", 1.0, e[0], e[1], float((int(e[1]) * 13) % 360))
	for e in [[-25, -13], [-10, -25], [-16, -33]]:
		_p("buisson", "vert", 1.0, e[0], e[1])
	_p("rocher", "pierre", 1.0, -34, -26)

	# ─── O · LE LABORATOIRE — l'enclos violet et ses machines ──────────
	_mur("violet", Vector2(-32, 6), Vector2(-18, 6), 109, [4])
	_mur("violet", Vector2(-32, -6), Vector2(-20, -6), 113, [2])
	_mur("violet", Vector2(-32, -4), Vector2(-32, 4), 127)
	_p("bloc", "violet", 1.0, -32, 6, 0.0, 2.0)
	_p("bloc", "violet", 1.0, -32, -6, 0.0, 2.0)
	_p("bloc", "violet", 1.0, -18, 6, 0.0, 2.0)
	_p("machine", "violet", 1.0, -26, 3.5)
	_p("machine", "violet", 1.0, -22, -3.5, 90.0)
	_p("bloc", "violet", 0.5, -19, -4)
	_tas("violet", -36, 12, 2, 2, 131)

	# ─── LES HAIES DE RUE — ce qui fait « allée » sur la planche ───────
	# De longues haies vertes LONGENT les rues principales, à trois
	# mètres du fil de l'allée : le regard suit un couloir vert, les
	# pieds une rue de sable. C'est LE motif signature de la référence.
	_mur("vert", Vector2(-3, -15), Vector2(-3, -27), 137, [3], 1.0)
	_mur("vert", Vector2(3, 15), Vector2(3, 25), 139, [2], 1.0)
	_mur("vert", Vector2(15, 3), Vector2(27, 3), 149, [3], 1.0)
	_mur("vert", Vector2(-15, -3), Vector2(-25, -3), 151, [2], 1.0)
	# Des rangées de pierre courtes cassent les longues perspectives des
	# rues à ±12 sans jamais les fermer.
	_mur("pierre", Vector2(-9, 15), Vector2(-5, 15), 157, [], 0.5)
	_mur("pierre", Vector2(5, -15), Vector2(9, -15), 163, [], 0.5)
	_mur("pierre", Vector2(15, 5), Vector2(15, 9), 167, [], 0.5)
	_mur("pierre", Vector2(-15, -5), Vector2(-15, -9), 173, [], 0.5)

	# ─── LA CEINTURE — le tour de l'île est un chemin, pas un désert ───
	# Petits postes et rochers entre les parcelles et la lisière, pour
	# que la boucle extérieure ait ses couverts aussi.
	_tas("pierre", 0, 37, 2, 2, 179)
	_tas("pierre", 37, 0, 2, 2, 181)
	_tas("pierre", 0, -37, 2, 2, 191)
	_tas("vert", -37, 5, 2, 2, 193)
	_p("rocher", "pierre", 1.0, 36, 14)
	_p("rocher", "pierre", 1.0, -14, 36)
	_p("rocher", "pierre", 1.0, 36, -12)
	_p("rocher", "pierre", 1.0, -36, -14)

	# ─── LE SEMIS — la vie entre les murs ──────────────────────────────
	# Touffes, buissons, arbres et cailloux, JAMAIS sur une allée : la
	# rue reste une rue. Les carrefours reçoivent leurs arbres.
	for coin in [[12, 12], [-12, 12], [12, -12], [-12, -12]]:
		var cx := float(coin[0]) * 1.28
		var cz := float(coin[1]) * 1.28
		if _libre_semis(cx, cz):
			_p("arbre", "vert", 1.0, cx, cz, float((coin[0] * 31) % 360))
	var n_sem := 0
	var essai := 0
	while n_sem < 110 and essai < 1600:
		essai += 1
		var t := _hash(essai * 7 + 5)
		var u := _hash(essai * 13 + 3)
		var a2 := t * TAU
		var r2 := 13.0 + u * 30.0
		var x := roundf(cos(a2) * r2)
		var z := roundf(sin(a2) * r2)
		if not _libre_semis(x, z):
			continue
		n_sem += 1
		var quoi := _hash(essai * 29 + 17)
		if quoi < 0.10:
			_p("arbre", "vert", 1.0, x, z, t * 360.0)
		elif quoi < 0.20:
			_p("palmier", "vert", 1.0, x, z, u * 360.0)
		elif quoi < 0.42:
			_p("buisson", "vert", 1.0, x, z, t * 360.0)
		elif quoi < 0.54:
			_p("rocher", "pierre", 1.0, x, z, u * 180.0)
		else:
			_p("touffe", "jaune", 1.0, x, z, t * 360.0)

	# ─── LA LISIÈRE ────────────────────────────────────────────────────
	for i in 30:
		var a := TAU * float(i) / 30.0 + 0.05
		var r := 41.0 + _hash(i * 7919) * 2.0
		var x := cos(a) * r
		var z := sin(a) * r
		if not dans_enceinte(Vector2(x, z), -3.0):
			continue
		match i % 3:
			0:
				_p("palmier", "vert", 1.0, x, z, float((i * 47) % 360))
				_p("buisson", "vert", 1.0, x + 1.6, z - 1.0)
			1:
				_p("arbre", "vert", 1.0, x, z)
				_p("touffe", "jaune", 1.0, x - 1.4, z + 1.2)
			_:
				_p("buisson", "vert", 1.0, x, z)
