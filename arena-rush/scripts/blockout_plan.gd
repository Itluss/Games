extends RefCounted
class_name BlockoutPlan
## ARENA 01 — THE CONVERGENCE — source de vérité des données (V2, topologie
## de circulation corrigée).
##
## Le SVG (`design/arena-01-graybox-lines-v1.svg`) n'est plus reproduit
## littéralement : la V2 (`design/arena-01-graybox-lines-v1.svg` reste la
## seule référence de FORME jamais modifiée, mais son schéma de
## circulation — rampes cardinales directes vers le Core — est
## explicitement remplacé, comme demandé). Le markdown
## (`design/arena-01-the-convergence-spec-v1.md`) reste la référence pour
## les dimensions non contredites par la V2 (rayon d'enceinte, hauteurs,
## budget de loot).
##
## ─── NOUVELLE TOPOLOGIE ──────────────────────────────────────────────────
## Spawn (secteur ouvert, 3 spawns) → 2 sorties (horaire/antihoraire) →
## un des deux HUBS diagonaux voisins (zone de confrontation) → anneau de
## rotation → une des 4 entrées du Core (décalées de ~35-45° par rapport
## aux axes de spawn, donc jamais en face d'une base). Aucune route
## directe secteur→Core. Un graphe de navigation nommé (`NAV_NOEUDS` /
## `NAV_ARETES`) encode cette topologie pour que le validateur puisse
## vérifier des distances et des chemins réels, pas juste la présence de
## murs.

const Y_SOL := 0.0
const Y_ROUTE := 3.0       ## route/plateforme surélevée standard
const Y_SNIPER := 6.0      ## plateforme haute maximale
const HAUT_COUVERTURE := 1.35  ## 1.2-1.5 m, milieu de fourchette
const HAUT_MUR := 4.0          ## 3-5 m, milieu de fourchette

const R_BORD := 95.0       ## mur extérieur — diamètre 190 m (markdown)
const R_ZONE_1 := 53.0     ## première zone (repère, pas un mur)
const R_CORE := 17.0       ## Core plaza, diamètre 34 m (markdown)
const R_ANNEAU_IN := 28.0  ## anneau de rotation, bord intérieur (V2 prompt)
const R_ANNEAU_OUT := 43.0 ## anneau de rotation, bord extérieur (V2 prompt)
const R_ANNEAU_NAV := 35.0 ## rayon des nœuds de navigation de l'anneau

## Secteurs de spawn — angle du centre de chaque groupe de 3 spawns.
const SECTEURS := ["Sanctuary", "Forge", "Barracks", "Rift"]
const SECTEUR_ANGLE := {"Sanctuary": 90.0, "Forge": 0.0, "Barracks": 270.0, "Rift": 180.0}

## Hubs diagonaux — angle du centre, et les deux secteurs qu'il relie.
## « cw »/« ccw » ci-dessous (sur SECTEUR_HUBS) est cohérent avec cette
## table : cw = l'angle du hub est INFÉRIEUR à l'angle du secteur.
const HUBS := ["NE", "SE", "SW", "NW"]
const HUB_ANGLE := {"NE": 45.0, "SE": 315.0, "SW": 225.0, "NW": 135.0}
const HUB_SECTEURS := {
	"NE": ["Sanctuary", "Forge"], "SE": ["Forge", "Barracks"],
	"SW": ["Barracks", "Rift"], "NW": ["Rift", "Sanctuary"],
}
## Pour chaque secteur, le hub atteint par la sortie horaire (cw) et
## antihoraire (ccw) — angle décroissant = cw, croissant = ccw.
const SECTEUR_HUBS := {
	"Sanctuary": {"cw": "NE", "ccw": "NW"}, "Forge": {"cw": "SE", "ccw": "NE"},
	"Barracks": {"cw": "SW", "ccw": "SE"}, "Rift": {"cw": "NW", "ccw": "SW"},
}
## Entrée du Core associée à chaque hub : décalée de +10° par rapport à
## l'angle du hub (donc à 35° pile de l'axe de spawn le plus proche —
## « environ 35 à 45° », jamais en face d'une base) — et surtout PAS au
## même angle que le hub, pour qu'aucun trajet hub→Core ne soit un rayon
## droit : il faut longer l'anneau sur ces 10° avant de trouver l'entrée.
const ENTREE_CORE_ANGLE := {"NE": 55.0, "SE": 325.0, "SW": 235.0, "NW": 145.0}

## ─── CATÉGORIES (géométrie physique) ────────────────────────────────────
static var MURS: Array[Dictionary] = []
static var COUVERTS: Array[Dictionary] = []
## Plateformes surélevées — TOUJOURS un socle plein du sol jusqu'à son
## sommet (V2 : plus jamais de dalle suspendue praticable en dessous).
## {"rect": Rect2, "y": float, "nom": String, "acces": Array[Vector2]}
static var PLATEFORMES: Array[Dictionary] = []
static var RAMPES: Array[Dictionary] = []

static var SPAWNS: Array[Dictionary] = []  ## {"nom", "pos", "secteur"}
static var LOOT_HAUT: Array[Vector2] = []
static var LOOT_MOYEN: Array[Vector2] = []
static var LOOT_COMMUN: Array[Vector2] = []
static var SOINS: Array[Vector2] = []
static var CAPSULE_CENTRALE := Vector2.ZERO
static var SOCKETS_ZONE_FINALE: Array[Dictionary] = []

## ─── GRAPHE DE NAVIGATION (pour le validateur) ───────────────────────────
## Nœuds nommés → position monde (XZ). Arêtes non orientées avec un poids
## = distance euclidienne réelle entre les deux nœuds. Construit à partir
## de la MÊME géométrie que les murs/rampes ci-dessous (pas une copie
## indépendante qui pourrait diverger).
static var NAV_NOEUDS: Dictionary = {}       ## nom -> Vector2
static var NAV_ARETES: Array[Dictionary] = []  ## {"a", "b", "poids"}
static var NAV_ADJ: Dictionary = {}          ## nom -> Array[String] (cache pour Dijkstra)


# --- AIDES DE COMPOSITION ---------------------------------------------------

static func _pt(r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a) * r, sin(a) * r)


static func _mur(nom: String, points: Array, haut := HAUT_MUR, y := Y_SOL) -> void:
	var pv := PackedVector2Array()
	for p in points:
		pv.append(p)
	MURS.append({"points": pv, "haut": haut, "y": y, "nom": nom})


static func _rect_mur(nom: String, a: Vector2, b: Vector2, haut := HAUT_MUR) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	_mur(nom, [
		Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y),
		Vector2(lo.x, hi.y), Vector2(lo.x, lo.y),
	], haut)


static func _rect_couvert(nom: String, a: Vector2, b: Vector2) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	COUVERTS.append({"points": PackedVector2Array([
		Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y),
		Vector2(lo.x, hi.y), Vector2(lo.x, lo.y),
	]), "haut": HAUT_COUVERTURE, "y": Y_SOL, "nom": nom})


## Anneau (mur circulaire) avec des ouvertures à des angles arbitraires
## (plus seulement cardinaux — V2 décale les entrées du Core).
static func _anneau_troue(nom: String, rayon: float, demi_trou_deg: float,
		angles_ouverture: Array) -> void:
	const PAS := 48
	for i in PAS:
		var a0 := TAU * float(i) / PAS
		var a1 := TAU * float(i + 1) / PAS
		var milieu := rad_to_deg(a0 + (a1 - a0) * 0.5)
		var dans_trou := false
		for c in angles_ouverture:
			if absf(wrapf(milieu - c, -180.0, 180.0)) < demi_trou_deg:
				dans_trou = true
				break
		if dans_trou:
			continue
		var p0 := Vector2(cos(a0), sin(a0)) * rayon
		var p1 := Vector2(cos(a1), sin(a1)) * rayon
		_mur("%s_%d" % [nom, i], [p0, p1], HAUT_MUR)


# --- GRAPHE DE NAVIGATION : aides ------------------------------------------

static func _noeud(nom: String, pos: Vector2) -> void:
	NAV_NOEUDS[nom] = pos


static func _arete(a: String, b: String) -> void:
	var poids: float = NAV_NOEUDS[a].distance_to(NAV_NOEUDS[b])
	NAV_ARETES.append({"a": a, "b": b, "poids": poids})
	if not NAV_ADJ.has(a):
		NAV_ADJ[a] = []
	if not NAV_ADJ.has(b):
		NAV_ADJ[b] = []
	NAV_ADJ[a].append(b)
	NAV_ADJ[b].append(a)


## Dijkstra — plus court chemin entre deux nœuds nommés. Retourne
## {"distance": float, "chemin": Array[String]} (distance == INF si
## injoignable).
static func chemin_le_plus_court(depart: String, arrivee: String) -> Dictionary:
	var dist := {}
	var prec := {}
	var visite := {}
	for n in NAV_NOEUDS:
		dist[n] = INF
	dist[depart] = 0.0
	while true:
		var courant := ""
		var meilleur := INF
		for n in dist:
			if not visite.get(n, false) and dist[n] < meilleur:
				meilleur = dist[n]
				courant = n
		if courant == "":
			break
		if courant == arrivee:
			break
		visite[courant] = true
		for voisin in NAV_ADJ.get(courant, []):
			if visite.get(voisin, false):
				continue
			var poids: float = NAV_NOEUDS[courant].distance_to(NAV_NOEUDS[voisin])
			var alt: float = dist[courant] + poids
			if alt < dist.get(voisin, INF):
				dist[voisin] = alt
				prec[voisin] = courant
	if dist.get(arrivee, INF) == INF:
		return {"distance": INF, "chemin": []}
	var chemin: Array[String] = [arrivee]
	var n: String = arrivee
	while prec.has(n):
		n = prec[n]
		chemin.push_front(n)
	return {"distance": dist[arrivee], "chemin": chemin}


# --- CONSTRUCTION ------------------------------------------------------------

static func _construire_tout() -> bool:
	_construire_enceinte()
	_construire_core()
	_construire_spawns()
	_construire_secteurs_ouverts()
	_construire_hubs()
	_construire_graphe_navigation()
	_construire_ecrans_spawn()
	_construire_loot_et_soins()
	return true

static var _construit := _construire_tout()


## ─── ENCEINTE ────────────────────────────────────────────────────────────
static func _construire_enceinte() -> void:
	const PAS := 64
	for i in PAS:
		var a0 := TAU * float(i) / PAS
		var a1 := TAU * float(i + 1) / PAS
		_mur("enceinte_%d" % i, [
			Vector2(cos(a0), sin(a0)) * R_BORD,
			Vector2(cos(a1), sin(a1)) * R_BORD,
		], 5.0)


## ─── CORE ────────────────────────────────────────────────────────────────
## Mur troué aux 4 entrées décalées (ENTREE_CORE_ANGLE) — jamais aux
## cardinaux, donc jamais en face d'un secteur de spawn. Pas de mur
## d'anneau séparé : V2 veut un anneau de rotation OUVERT (juste du sol),
## pas un corridor muré des deux côtés.
static func _construire_core() -> void:
	var angles: Array = ENTREE_CORE_ANGLE.values()
	_anneau_troue("core_mur", R_CORE, rad_to_deg(atan(6.0 / R_CORE)), angles)
	CAPSULE_CENTRALE = Vector2.ZERO


## ─── SPAWNS (inchangés dans leurs positions — déjà valides : 12, ≥18 m) ──
static func _construire_spawns() -> void:
	var donnees := [
		["S01", Vector2(-26.0, 84.0), "Sanctuary"], ["S02", Vector2(0.0, 86.0), "Sanctuary"],
		["S03", Vector2(26.0, 84.0), "Sanctuary"],
		["S04", Vector2(84.0, 26.0), "Forge"], ["S05", Vector2(86.0, 0.0), "Forge"],
		["S06", Vector2(84.0, -26.0), "Forge"],
		["S07", Vector2(26.0, -84.0), "Barracks"], ["S08", Vector2(0.0, -86.0), "Barracks"],
		["S09", Vector2(-26.0, -84.0), "Barracks"],
		["S10", Vector2(-84.0, -26.0), "Rift"], ["S11", Vector2(-86.0, 0.0), "Rift"],
		["S12", Vector2(-84.0, 26.0), "Rift"],
	]
	for d in donnees:
		SPAWNS.append({"nom": d[0], "pos": d[1], "secteur": d[2]})


## ─── SECTEURS OUVERTS ────────────────────────────────────────────────────
## Fini les grands murs qui enferment chaque faction (V2, règle 1) : juste
## quelques petites couvertures près des spawns, et UN gros bloqueur droit
## dans l'axe cardinal pour empêcher la course directe vers le Core — la
## seule route ouverte passe par les deux sorties (±25°) vers les hubs.
static func _construire_secteurs_ouverts() -> void:
	for secteur in SECTEURS:
		var ang: float = SECTEUR_ANGLE[secteur]
		# Bloqueur central : un mur épais de 20° de large à r=64-70, pile
		# dans l'axe du secteur.
		var large := 10.0
		for r in [64.0, 70.0]:
			_mur("%s_bloc_central_%d" % [secteur, int(r)],
					[_pt(r, ang - large), _pt(r, ang + large)], HAUT_MUR)
		_mur("%s_bloc_central_flanc_a" % secteur, [_pt(64.0, ang - large), _pt(70.0, ang - large)], HAUT_MUR)
		_mur("%s_bloc_central_flanc_b" % secteur, [_pt(64.0, ang + large), _pt(70.0, ang + large)], HAUT_MUR)

		# Deux petites couvertures près du trio de spawns (pas d'enceinte),
		# décalées pour ne jamais boucher les deux sorties.
		for signe in [-1.0, 1.0]:
			var centre := _pt(76.0, ang + signe * 12.0)
			var trav := Vector2(-sin(deg_to_rad(ang)), cos(deg_to_rad(ang)))
			_rect_couvert("%s_couvert_spawn_%s" % [secteur, "a" if signe < 0 else "b"],
					centre - trav * 2.0, centre + trav * 2.0 + trav.orthogonal() * 3.0)


## ─── HUBS DIAGONAUX ──────────────────────────────────────────────────────
## Chaque hub : une boucle locale (2 petits blocs en L décalés, jamais un
## mur continu), une plateforme haute (socle plein, 2 accès), et 2 sorties
## vers l'anneau. Loot/soins gérés dans `_construire_loot_et_soins()`.
static func _construire_hubs() -> void:
	for hub in HUBS:
		var ang: float = HUB_ANGLE[hub]
		var centre := _pt(59.4, ang)  # (±42, ±42)

		# ATTENTION : les 4 directions « occupées » vues DEPUIS LE CENTRE
		# DU HUB ne sont PAS ang et ang∓8° (ça, c'est leur angle depuis
		# l'ORIGINE du monde). Le hub est lui-même décalé du centre, donc
		# la direction hub→sortie_secteur et hub→sortie_anneau dépend de
		# la géométrie réelle, pas de l'angle polaire du hub. Calculées
		# une fois en testant (capsule bloquée à deux reprises sur des
		# blocs mal placés) : pour NE (ang=45°), hub→Sanctuary ≈ 94°,
		# hub→Forge ≈ 356°, hub→anneau_a ≈ 262°, hub→anneau_b ≈ 208°.
		# Les 3 seules zones dégagées (≥20° de marge) sont centrées sur
		# ang, ang+106° et ang-96° — pour n'importe quel hub (la
		# géométrie est la même à une rotation près puisque tous les hubs
		# sont construits de façon identique).

		# Plateforme haute — socle PLEIN (sol à Y_SNIPER), dans la zone
		# dégagée ang+106°, PAS sur l'axe ang lui-même. À l'essai, un
		# socle centré à seulement 4 m du centre du hub (le long de ang)
		# débordait jusqu'à 0,5 m du POINT DE NAVIGATION `hub_X_centre`
		# (42,42 pour NE) — la capsule ne pouvait alors plus jamais
		# s'approcher à moins d'1 m de ce nœud, cible pourtant utilisée
		# par CHAQUE trajet spawn→Core traversant ce hub (repéré en
		# testant : tous les bots restaient bloqués pile à 6-7 m du
		# centre, jamais ailleurs). Rayon 9 (bord le plus proche à 5,5 m
		# du centre) laisse une vraie marge.
		var dir_socle := ang + 106.0
		var trav2 := _pt(1.0, dir_socle + 90.0)
		var socle_centre := centre + _pt(9.0, dir_socle)
		var socle_taille := Vector2(7.0, 7.0)
		PLATEFORMES.append({
			"rect": Rect2(socle_centre - socle_taille * 0.5, socle_taille),
			"y": Y_SNIPER, "nom": "%s_sniper" % hub,
			"acces": [socle_centre + trav2 * 11.0, socle_centre - trav2 * 11.0],
		})
		RAMPES.append({"bas": socle_centre + trav2 * 11.0, "haut": socle_centre + trav2 * 3.5,
				"y_bas": Y_SOL, "y_haut": Y_SNIPER, "large": 3.0})
		RAMPES.append({"bas": socle_centre - trav2 * 11.0, "haut": socle_centre - trav2 * 3.5,
				"y_bas": Y_SOL, "y_haut": Y_SNIPER, "large": 3.0})

		# 2 blocs en L, dans les 2 zones dégagées restantes (ang et
		# ang-96° — ang+106° est maintenant prise par le socle) — pas
		# d'enceinte, ≥2 chemins de contournement.
		for i in 2:
			var a: float = ang + [0.0, -96.0][i]
			var p := centre + _pt(10.0, a)
			var d1 := _pt(2.5, a + 90.0)
			_mur("%s_couvert_%d_a" % [hub, i], [p, p + d1], HAUT_MUR)
			_mur("%s_couvert_%d_b" % [hub, i], [p, p - _pt(2.5, a)], HAUT_MUR)


## ─── GRAPHE DE NAVIGATION ────────────────────────────────────────────────
## spawn → sortie(cw/ccw) → hub → anneau → entrée Core. Construit à partir
## des mêmes angles que la géométrie physique ci-dessus.
static func _construire_graphe_navigation() -> void:
	# 1) Tous les NŒUDS d'abord — `_arete()` a besoin des deux extrémités
	# déjà enregistrées dans NAV_NOEUDS pour calculer sa distance ; les
	# construire dans le même passage que les arêtes cassait dès que
	# l'ordre du code ne correspondait pas à l'ordre topologique (trouvé
	# en testant : « Invalid access to property... on a base object of
	# type Dictionary » sur les nœuds de hub référencés avant création).
	for s: Dictionary in SPAWNS:
		_noeud("spawn_%s" % s["nom"], s["pos"])
	# Rayon proche de celui des spawns (80, contre ~84-86) et décalage
	# large (30°) : la sortie doit rester une manœuvre surtout TANGENTIELLE
	# (parallèle à l'enceinte), pour que le virage vers le hub — qui lui
	# coupe franchement vers le centre — soit un vrai changement de
	# direction pour CHAQUE spawn du secteur, pas seulement les deux
	# spawns excentrés. Avec une sortie trop proche du hub (r=66, ±25°),
	# le spawn central du trio (sur l'axe cardinal) avait un trajet
	# spawn→sortie quasi colinéaire à sortie→hub : un seul virage
	# significatif au lieu de deux (trouvé en testant, pas en le
	# devinant).
	for secteur in SECTEURS:
		var ang: float = SECTEUR_ANGLE[secteur]
		_noeud("sortie_%s_cw" % secteur, _pt(80.0, ang - 30.0))
		_noeud("sortie_%s_ccw" % secteur, _pt(80.0, ang + 30.0))
	for hub in HUBS:
		var ha: float = HUB_ANGLE[hub]
		_noeud("hub_%s_centre" % hub, _pt(59.4, ha))
		_noeud("hub_%s_anneau_a" % hub, _pt(41.0, ha - 8.0))
		_noeud("hub_%s_anneau_b" % hub, _pt(41.0, ha + 8.0))
	for hub in HUBS:
		var ea: float = ENTREE_CORE_ANGLE[hub]
		_noeud("anneau_entree_%s" % hub, _pt(R_ANNEAU_NAV, ea))
		_noeud("entree_core_%s" % hub, _pt(R_CORE, ea))
	_noeud("core_centre", Vector2.ZERO)

	# 2) Puis les ARÊTES.
	for secteur in SECTEURS:
		var cw_hub: String = SECTEUR_HUBS[secteur]["cw"]
		var ccw_hub: String = SECTEUR_HUBS[secteur]["ccw"]
		for s: Dictionary in SPAWNS:
			if s["secteur"] == secteur:
				_arete("spawn_%s" % s["nom"], "sortie_%s_cw" % secteur)
				_arete("spawn_%s" % s["nom"], "sortie_%s_ccw" % secteur)
		_arete("sortie_%s_cw" % secteur, "hub_%s_centre" % cw_hub)
		_arete("sortie_%s_ccw" % secteur, "hub_%s_centre" % ccw_hub)
	for hub in HUBS:
		_arete("hub_%s_centre" % hub, "hub_%s_anneau_a" % hub)
		_arete("hub_%s_centre" % hub, "hub_%s_anneau_b" % hub)
	for hub in HUBS:
		_arete("anneau_entree_%s" % hub, "entree_core_%s" % hub)
		_arete("entree_core_%s" % hub, "core_centre")

	# Boucle de l'anneau : tous les nœuds d'anneau (sorties de hub +
	# accès d'entrée) triés par angle et reliés consécutivement, plus des
	# nœuds de remplissage si un intervalle dépasse 40° — garantit un
	# anneau réellement continu, pas des îlots disjoints.
	var angles_speciaux: Array = []
	for hub in HUBS:
		var ha: float = HUB_ANGLE[hub]
		angles_speciaux.append(["hub_%s_anneau_a" % hub, wrapf(ha - 8.0, 0.0, 360.0)])
		angles_speciaux.append(["hub_%s_anneau_b" % hub, wrapf(ha + 8.0, 0.0, 360.0)])
		angles_speciaux.append(["anneau_entree_%s" % hub, wrapf(ENTREE_CORE_ANGLE[hub], 0.0, 360.0)])
	angles_speciaux.sort_custom(func(a, b): return a[1] < b[1])

	var complets: Array = angles_speciaux.duplicate()
	var n_ins := 0
	for i in angles_speciaux.size():
		var a0: float = angles_speciaux[i][1]
		var a1: float = angles_speciaux[(i + 1) % angles_speciaux.size()][1]
		var ecart := wrapf(a1 - a0, 0.0, 360.0)
		if ecart > 40.0:
			var mil := wrapf(a0 + ecart * 0.5, 0.0, 360.0)
			var nom := "anneau_rempli_%d" % n_ins
			n_ins += 1
			_noeud(nom, _pt(R_ANNEAU_NAV, mil))
			complets.append([nom, mil])
	complets.sort_custom(func(a, b): return a[1] < b[1])
	for i in complets.size():
		_arete(complets[i][0], complets[(i + 1) % complets.size()][0])


## ─── ÉCRANS ANTI-LIGNE-DE-VUE ENTRE SPAWNS ──────────────────────────────
## Toujours nécessaire en V2 : les 3 spawns d'un même secteur ouvert
## restent proches et alignés, donc sans écran ils se verraient tous.
static func _construire_ecrans_spawn() -> void:
	for base in [0, 3, 6, 9]:
		for i in [0, 1]:
			_ecran_entre(SPAWNS[base + i]["pos"], SPAWNS[base + i + 1]["pos"],
					"ecran_spawn_%d_%d" % [base, i])
	for paire in [[2, 3], [5, 6], [8, 9], [11, 0]]:
		_ecran_entre(SPAWNS[paire[0]]["pos"], SPAWNS[paire[1]]["pos"],
				"ecran_spawn_coin_%d" % paire[0])


static func _ecran_entre(a: Vector2, b: Vector2, nom: String) -> void:
	var milieu := (a + b) * 0.5
	var travers := (b - a).orthogonal().normalized()
	_mur(nom, [milieu - travers * 3.0, milieu + travers * 3.0], HAUT_MUR)


## ─── LOOT ET SOINS ───────────────────────────────────────────────────────
## V2 : loot haut dans les hubs (jamais près des spawns) + 2 positions
## contestées de l'anneau ; loot moyen davantage sur les sorties que dans
## les bases ; soins dans/près des hubs (un par hub, ce qui EST « entre
## chaque paire de secteurs voisins », cohérent avec le markdown v1).
static func _construire_loot_et_soins() -> void:
	# HAUT (6) : 4 dans les hubs (près du socle sniper) + 2 sur l'anneau,
	# à des entrées de Core opposées.
	for hub in HUBS:
		LOOT_HAUT.append(_pt(59.4, HUB_ANGLE[hub]) + _pt(4.0, HUB_ANGLE[hub]))
	for hub in ["NE", "SW"]:
		LOOT_HAUT.append(_pt(R_ANNEAU_NAV, ENTREE_CORE_ANGLE[hub]))

	# MOYEN (12) : 2 par sortie de secteur (8) + 1 par hub (4) — jamais
	# dans les bases elles-mêmes.
	for secteur in SECTEURS:
		var ang: float = SECTEUR_ANGLE[secteur]
		LOOT_MOYEN.append(_pt(70.0, ang - 25.0))
		LOOT_MOYEN.append(_pt(70.0, ang + 25.0))
	for hub in HUBS:
		LOOT_MOYEN.append(_pt(59.4, HUB_ANGLE[hub]) - _pt(6.0, HUB_ANGLE[hub]))

	# COMMUN (16) : concentré près des routes de spawn/sorties — un
	# anneau à r=80, aligné sur les 8 directions de sortie (2 par secteur).
	for secteur in SECTEURS:
		var ang: float = SECTEUR_ANGLE[secteur]
		LOOT_COMMUN.append(_pt(80.0, ang - 15.0))
		LOOT_COMMUN.append(_pt(80.0, ang + 15.0))
		LOOT_COMMUN.append(_pt(80.0, ang - 30.0))
		LOOT_COMMUN.append(_pt(80.0, ang + 30.0))

	# SOINS (4) : un par hub, pour encourager les rotations entre équipes.
	for hub in HUBS:
		SOINS.append(_pt(59.4, HUB_ANGLE[hub]) - _pt(9.0, HUB_ANGLE[hub]))

	# SOCKETS DE ZONE FINALE (6) : le Core, un par hub, jamais uniquement
	# le Core (cohérent avec le markdown v1, toujours valable).
	SOCKETS_ZONE_FINALE.append({"pos": Vector2.ZERO, "nom": "core"})
	for hub in HUBS:
		SOCKETS_ZONE_FINALE.append({"pos": _pt(59.4, HUB_ANGLE[hub]), "nom": hub})
