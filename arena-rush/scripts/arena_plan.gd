extends RefCounted
class_name ArenaPlan
## PLAN DE L'ARÈNE — données pures, indépendantes du rendu.
##
## Chaque mur est une POLYLIGNE explicite (liste de points), chaque bassin
## un POLYGONE explicite. Rien n'est généré par formule, boucle aléatoire
## ou symétrie automatique : chaque entrée existe parce qu'un couloir, un
## abri, une boucle ou une rupture de ligne de vue en a besoin — voir le
## commentaire au-dessus de chaque groupe.
##
## ─── LE REPÈRE ──────────────────────────────────────────────────────────
## X/Z, origine au centre du podium. Les angles sont en degrés, mesurés
## depuis +X, sens trigonométrique (donc +Z est à 90°). Quatre quartiers
## de 90° chacun :
##   NE  [  0°, 90°]  TRÉSORS
##   NW  [ 90°,180°]  ÉPAVE
##   SW  [180°,270°]  DOCKS
##   SE  [270°,360°]  JARDIN ROCHEUX
##
## ─── LES TROIS BOUCLES, EN RAYON ────────────────────────────────────────
##   Podium         r <  5      plateforme, aucun mur
##   Boucle centrale 5 – 13     8 m de large — cible 7-9 m
##   Quartiers      13 – 24     10 m de large — cible 7-10 m (boucle inter.)
##   Connecteur     24 – 30      6 m, ouvert, couverture légère seulement
##   Boucle périph. 30 – 40     10 m de large — cible 9-12 m
##   Lisière        40 – 46     décor de bord, hors jeu
## Le connecteur reste SANS MUR : c'est lui qui garantit qu'on peut
## toujours passer d'un quartier à la boucle périphérique sans repasser
## par le centre — la jonction entre boucle intermédiaire et périphérique.

const R_PODIUM := 5.0
const R_CENTRALE := 13.0
const R_QUARTIER := 24.0
const R_CONNECTEUR := 30.0
const R_PERIPH := 40.0
const R_BORD := 46.0

## Murs : Array de {"points": PackedVector2Array, "haut": float, "nom": String}
static var MURS: Array[Dictionary] = []
## Bassins : Array de {"points": PackedVector2Array, "nom": String}
static var BASSINS: Array[Dictionary] = []
## Ponts : Array de {"de": Vector2, "vers": Vector2, "large": float}
static var PONTS: Array[Dictionary] = []
## Abris — cachettes à double sortie, pour la validation technique :
## {"centre": Vector2, "rayon": float, "sorties": [Vector2, Vector2]}
static var ABRIS: Array[Dictionary] = []
## Dix apparitions : {"pos": Vector2, "sorties": [Vector2, Vector2], "quartier": String}
static var SPAWNS: Array[Dictionary] = []
## Îlots diagonaux du centre : {"centre": Vector2, "rayon": float}
static var ILOTS_CENTRE: Array[Dictionary] = []


static func _pt(r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a) * r, sin(a) * r)


static func _mur(nom: String, points: Array, haut := 3.0) -> void:
	var pv := PackedVector2Array()
	for p in points:
		pv.append(p if p is Vector2 else _pt(p[0], p[1]))
	MURS.append({"points": pv, "haut": haut, "nom": nom})


static func _bassin(nom: String, points: Array) -> void:
	var pv := PackedVector2Array()
	for p in points:
		pv.append(p if p is Vector2 else _pt(p[0], p[1]))
	BASSINS.append({"points": pv, "nom": nom})


## UN AMAS — silhouette générée autour d'un centre local, en rayons/angles
## croissants : la seule façon de garantir un polygone SIMPLE (jamais
## croisé) tout en dessinant une forme irrégulière à la main. C'est le
## moule commun des rochers, coques et bassins de cette passe — la
## discipline qui manquait à la précédente.
static func _amas(centre: Vector2, points_locaux: Array) -> Array:
	var pts := []
	for p in points_locaux:
		pts.append(centre + Vector2(cos(deg_to_rad(p[1])) * p[0],
				sin(deg_to_rad(p[1])) * p[0]))
	return pts


static func _static_init() -> void:
	_construire_spawns()
	_construire_centre()
	_construire_ne_tresors()
	_construire_nw_epave()
	_construire_sw_docks()
	_construire_se_jardin()


## ─── LES DIX APPARITIONS ────────────────────────────────────────────────
## À 36 m (milieu de la boucle périphérique), décalées de 18° pour ne
## jamais tomber pile sur une frontière de quartier. Chaque spawn connaît
## SES DEUX SORTIES : le long de la boucle périphérique (deux sens), et
## elles suffisent — la boucle est large et ouverte, aucun mur ne les
## enferme.
static func _construire_spawns() -> void:
	var quartier_de := func(deg: float) -> String:
		var d := fmod(deg, 360.0)
		if d < 90.0:
			return "NE"
		elif d < 180.0:
			return "NW"
		elif d < 270.0:
			return "SW"
		return "SE"
	for i in 10:
		var deg := 18.0 + float(i) * 36.0
		var pos := _pt(36.0, deg)
		var long_boucle := _pt(1.0, deg + 90.0)  # tangente, sens direct
		SPAWNS.append({
			"pos": pos,
			"sorties": [pos + long_boucle * 6.0, pos - long_boucle * 6.0],
			"quartier": quartier_de.call(deg),
		})
		# ABRI IMMÉDIAT — un petit mur en L juste en retrait du spawn,
		# côté centre : il masque la ligne de vue vers le podium sans
		# boucher la boucle périphérique elle-même.
		var recul := _pt(1.0, deg + 180.0)
		var travers := _pt(1.0, deg + 90.0)
		var c := pos + recul * 2.5
		_mur("abri_spawn_%d" % i, [
			c + travers * 2.2, c, c - recul * 2.0,
		], 2.2)


## ─── LE CENTRE ──────────────────────────────────────────────────────────
## Podium octogonal, aucun mur (juste un repère de sol — voir le
## bâtisseur). Quatre îlots DIAGONAUX (45/135/225/315°) qui cassent la
## ligne de vue en travers du podium sans jamais toucher les axes
## cardinaux, qui restent grands ouverts comme demandé.
static func _construire_centre() -> void:
	for deg in [45.0, 135.0, 225.0, 315.0]:
		ILOTS_CENTRE.append({"centre": _pt(9.0, deg), "rayon": 1.6})
		_mur("ilot_centre_%d" % int(deg), [
			_pt(9.0, deg) + Vector2(-1.4, -1.0),
			_pt(9.0, deg) + Vector2(1.4, -0.6),
			_pt(9.0, deg) + Vector2(1.0, 1.4),
			_pt(9.0, deg) + Vector2(-1.2, 1.0),
			_pt(9.0, deg) + Vector2(-1.4, -1.0),
		], 2.0)


## ─── NE · TRÉSORS ───────────────────────────────────────────────────────
## QUATRE amas SEULEMENT — pas sept petits blocs. Chacun est GRAND et net :
## deux piles rectangulaires qui encadrent l'entrée, un abri à double
## sortie au centre du quartier (le plus visité, donc le plus protégé),
## une pile finale plus large qui referme la marche. Le zigzag vient de
## leur ALTERNANCE proche/loin du centre, pas de leur nombre.
static func _construire_ne_tresors() -> void:
	# Pile A — proche du centre, referme l'entrée depuis le hub.
	var a := _pt(15.0, 18.0)
	_mur("tresor_pile_a", _amas(a, [
		[2.6, 40.0], [2.6, 140.0], [2.6, 220.0], [2.6, 320.0],
	]), 2.0)
	# Pile B — loin, en vis-à-vis de A : c'est ELLE qui force le zigzag.
	var b := _pt(22.0, 40.0)
	_mur("tresor_pile_b", _amas(b, [
		[2.3, 30.0], [2.9, 110.0], [2.3, 200.0], [2.9, 290.0],
	]), 2.2)
	# L'ABRI CENTRAL — au milieu du quartier, en U ouvert vers le hub ET
	# vers la boucle périphérique : deux sorties franches, jamais un cul-
	# de-sac, et c'est la pièce la plus grande — elle mérite d'être vue.
	var c := _pt(18.5, 62.0)
	_mur("tresor_abri", [
		c + Vector2(-2.4, 2.2), c + Vector2(-2.4, -2.2), c + Vector2(2.4, -2.2),
	], 2.6)
	ABRIS.append({"centre": c, "rayon": 2.6,
			"sorties": [c + Vector2(3.4, 2.4), c + Vector2(-3.4, 0.0)]})
	# Pile D — la plus large, referme la marche côté ÉPAVE.
	var d := _pt(16.0, 82.0)
	_mur("tresor_pile_d", _amas(d, [
		[3.2, 15.0], [2.6, 100.0], [3.0, 190.0], [2.4, 280.0],
	]), 2.4)


## ─── NW · ÉPAVE ─────────────────────────────────────────────────────────
## Deux coques LONGUES et franches (huit points chacune, une vraie
## courbe, pas un coude à trois points) qui coupent la vue en travers du
## quartier. Le passage entre elles est unique et large ; la cachette
## traversante loge dans le creux naturel qu'elles dessinent.
static func _construire_nw_epave() -> void:
	var coque1 := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		coque1.append(_pt(lerpf(13.5, 16.5, sin(t * PI)), lerpf(96.0, 132.0, t)))
	_mur("epave_coque_1", coque1, 3.6)

	var coque2 := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		coque2.append(_pt(lerpf(23.0, 20.0, sin(t * PI)), lerpf(138.0, 174.0, t)))
	_mur("epave_coque_2", coque2, 3.6)

	# LA CACHETTE TRAVERSANTE — dans le creux entre les deux coques,
	# ouverte des deux côtés du passage.
	var c := _pt(18.5, 136.0)
	_mur("epave_cachette", [
		c + Vector2(-2.0, -1.6), c + Vector2(0.0, -2.6), c + Vector2(2.0, -1.6),
	], 2.6)
	ABRIS.append({"centre": c, "rayon": 2.4,
			"sorties": [c + Vector2(-2.8, 1.2), c + Vector2(2.8, 1.2)]})


## ─── SW · DOCKS ─────────────────────────────────────────────────────────
## Trois bassins bâtis en AMAS (silhouette irrégulière garantie simple,
## jamais une ellipse) nettement séparés — 6 m de terre au moins entre
## deux plans d'eau. Un pont par bassin, posé à sa lisière la plus
## étroite : un raccourci qui économise le tour, jamais l'unique voie,
## puisque la terre continue tout autour de chaque bassin.
static func _construire_sw_docks() -> void:
	var b1 := _pt(16.0, 200.0)
	_bassin("dock_bassin_1", _amas(b1, [
		[3.2, 20.0], [3.6, 100.0], [3.0, 170.0], [3.8, 230.0], [3.2, 300.0],
	]))
	PONTS.append({"de": b1 + _pt(4.4, 80.0), "vers": b1 + _pt(4.4, 100.0) + Vector2(1.6, 0.6),
			"large": 2.2})

	var b2 := _pt(20.0, 233.0)
	_bassin("dock_bassin_2", _amas(b2, [
		[3.6, 10.0], [4.0, 90.0], [3.4, 160.0], [3.8, 250.0], [3.0, 320.0],
	]))
	PONTS.append({"de": b2 + Vector2(-4.4, -1.0), "vers": b2 + Vector2(4.4, 1.0),
			"large": 2.2})

	var b3 := _pt(14.5, 262.0)
	_bassin("dock_bassin_3", _amas(b3, [
		[3.0, 30.0], [3.4, 110.0], [2.8, 190.0], [3.2, 280.0],
	]))
	PONTS.append({"de": b3 + Vector2(-3.6, 2.0), "vers": b3 + Vector2(3.6, -2.0),
			"large": 2.2})

	# Deux murets de quai, en retrait — un repère vertical dans un
	# quartier autrement tout en creux, jamais sur le tour à pied.
	_mur("dock_muret_1", [_pt(24.5, 210.0), _pt(24.5, 217.0)], 1.6)
	_mur("dock_muret_2", [_pt(23.0, 255.0), _pt(20.5, 260.0)], 1.6)


## ─── SE · JARDIN ROCHEUX ────────────────────────────────────────────────
## Trois amas rocheux, GRANDS et irréguliers (silhouette en amas, pas en
## polygone régulier), reliés par deux courts murets qui dessinent le S —
## sans jamais souder les amas entre eux, un raccourci étroit passe à
## chaque jonction. Deux cachettes traversantes, une par bout du S.
static func _construire_se_jardin() -> void:
	var r1 := _pt(17.0, 284.0)
	_mur("roc_amas_1", _amas(r1, [
		[3.4, 10.0], [3.0, 90.0], [3.8, 160.0], [3.2, 230.0], [2.8, 300.0],
	]), 2.8)
	var r2 := _pt(23.0, 314.0)
	_mur("roc_amas_2", _amas(r2, [
		[3.0, 20.0], [3.6, 100.0], [3.2, 180.0], [3.8, 250.0], [2.6, 320.0],
	]), 3.0)
	var r3 := _pt(16.5, 344.0)
	_mur("roc_amas_3", _amas(r3, [
		[3.2, 0.0], [2.8, 80.0], [3.6, 160.0], [3.0, 240.0], [2.6, 310.0],
	]), 2.8)
	# Les deux murets qui dessinent le S — courts, jamais soudés aux amas.
	_mur("roc_muret_12", [r1 + Vector2(3.6, 1.0), r2 + Vector2(-3.2, -1.4)], 1.6)
	_mur("roc_muret_23", [r2 + Vector2(-2.0, 3.2), r3 + Vector2(3.0, -1.6)], 1.6)
	# Deux cachettes traversantes, aux deux bouts du S.
	ABRIS.append({"centre": r1, "rayon": 3.0,
			"sorties": [r1 + _pt(4.2, 200.0), r1 + _pt(4.2, 340.0)]})
	ABRIS.append({"centre": r3, "rayon": 3.0,
			"sorties": [r3 + _pt(4.2, 20.0), r3 + _pt(4.2, 160.0)]})
