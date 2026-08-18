extends RefCounted
class_name PlanMonde
## PLAN DU MONDE — secteurs, points d'intérêt, densités.
##
## CE FICHIER EST UNE DONNÉE. On peut y déplacer un secteur, déplacer un
## repère ou changer une densité sans lire une ligne de logique. C'est la
## même règle que pour l'ancien plan d'arène, et elle a déjà prouvé sa
## valeur : le niveau se discute là où il est écrit.
##
## ─── CE QUI FAIT QU'UN MONDE PARAÎT OUVERT ──────────────────────────────
##
## Ce n'est pas la taille. Un grand disque vide paraît PLUS petit qu'une
## petite carte dense, parce que rien n'y marque la distance parcourue.
## Quatre choses fabriquent la sensation, et elles sont toutes ici :
##
##   1. DES SOLS DIFFÉRENTS. Vu de dessus, le sol occupe les trois quarts
##      de l'écran. Changer sa teinte change le secteur bien plus sûrement
##      que n'importe quel prop. C'est le levier n° 1, et le moins cher.
##
##   2. DES REPÈRES HAUTS, VISIBLES DE LOIN. Sans eux, un grand terrain
##      devient désorientant au lieu d'être ouvert. Ce sont eux qui donnent
##      envie d'aller voir, et eux qui permettent de dire « retrouve-moi à
##      la tour ».
##
##   3. UN GRADIENT DE DANGER du bord vers le centre. Il donne une
##      DIRECTION à l'exploration : on sait toujours où aller pour trouver
##      mieux, et ce que cela coûtera.
##
##   4. DE L'IRRÉGULARITÉ. Des secteurs de tailles inégales, des repères
##      jamais alignés. Une carte régulière se devine ; une carte
##      irrégulière s'apprend, et c'est en l'apprenant qu'on l'habite.

## Rayon du monde. 78 m contre 34 pour l'ancienne arène : 5,3 fois la
## surface. Assez grand pour marcher une trentaine de secondes sans
## traverser, assez petit pour qu'on croise du monde en permanence — un
## monde vide n'est pas un monde ouvert, c'est un désert.
const RAYON := 78.0
## Rayon du noyau central, l'ancienne arène.
const RAYON_NOYAU := 24.0

## Densités de mobs, en mobs visés par secteur. Elles ne sont pas
## proportionnelles à la surface : c'est justement l'écart qui crée des
## zones calmes et des points chauds.
enum Densite { CALME, MOYENNE, FORTE, EXTREME }


## LES SECTEURS.
##
## CHAQUE SECTEUR DÉCLARE UNE PART DU CERCLE, PAS UN ANGLE.
##
## La première version donnait à chacun un angle et une ouverture écrits à
## la main. Mesuré : leur somme dépassait le tour complet de 13 %, le Camp
## et les Ruines se chevauchaient sur 32°, et le secteur des Ruines s'est
## retrouvé SANS AUCUN point d'apparition — avalé par son voisin, qui le
## précédait dans la liste. Le sol des deux se superposait aussi, l'un
## repeignant l'autre.
##
## Les parts, elles, sont normalisées puis cumulées : les secteurs pavent
## le cercle exactement, et il devient IMPOSSIBLE d'en oublier un ou de les
## faire se recouvrir. Les tailles restent volontairement inégales — un
## découpage régulier se devine, un découpage irrégulier s'apprend.
const SECTEURS: Array[Dictionary] = [
	{
		"id": &"ruines",
		"nom": "LES RUINES",
		"part": 0.15,
		"sol": Cfg.SOL_RUINES,
		"danger": Densite.FORTE,
		"familles": [&"ruine", &"pilier", &"caillou", &"touffe"],
		"densite_decor": 0.065,
		"note": "Le plus étroit et le plus couvert. Bon butin, mauvaises retraites.",
	},
	{
		"id": &"camp",
		"nom": "LE CAMP",
		"part": 0.23,
		"sol": Cfg.SOL_CAMP,
		"danger": Densite.CALME,
		"familles": [&"tente", &"caisse", &"cloture", &"tonneau", &"caillou"],
		"densite_decor": 0.055,
		"note": "Le plus large. Peu de mobs, beaucoup d'abris bas : on y apprend à jouer sans être puni.",
	},
	{
		"id": &"canyon",
		"nom": "LE CANYON",
		"part": 0.19,
		"sol": Cfg.SOL_CANYON,
		"danger": Densite.MOYENNE,
		"familles": [&"mesa", &"rocher", &"caillou", &"touffe"],
		"densite_decor": 0.075,
		"note": "Mesas hautes et défilés étroits. Le secteur où l'on tend une embuscade.",
	},
	{
		"id": &"bosquet",
		"nom": "LE BOSQUET",
		"part": 0.22,
		"sol": Cfg.SOL_BOSQUET,
		"danger": Densite.MOYENNE,
		"familles": [&"arbre", &"pin", &"buisson", &"touffe", &"caillou"],
		"densite_decor": 0.11,
		"note": "Couvert dense. On y voit mal et on y est mal vu — le contraire du canyon.",
	},
	{
		"id": &"fonderie",
		"nom": "LA FONDERIE",
		"part": 0.21,
		"sol": Cfg.SOL_FONDERIE,
		"danger": Densite.FORTE,
		"familles": [&"caisse", &"tonneau", &"barricade", &"caillou"],
		"densite_decor": 0.07,
		"note": "Béton et conteneurs. Le secteur le plus « habité ».",
	},
]

## Angle où commence le découpage. Le décaler fait pivoter tout le monde
## d'un bloc, sans jamais rompre le pavage.
const ANGLE_DEPART := -PI * 0.62

static var _angles_cache: Dictionary = {}

## Angles calculés de chaque secteur : { id -> { centre, ouverture } }.
static func angles() -> Dictionary:
	if not _angles_cache.is_empty():
		return _angles_cache
	var somme := 0.0
	for s: Dictionary in SECTEURS:
		somme += float(s["part"])
	var curseur := ANGLE_DEPART
	for s: Dictionary in SECTEURS:
		# NORMALISATION : même si les parts ne totalisent pas 1, le pavage
		# reste exact. Une somme fausse ne peut donc plus laisser de trou.
		var ouverture := TAU * float(s["part"]) / somme
		_angles_cache[s["id"]] = {
			"centre": curseur + ouverture * 0.5,
			"ouverture": ouverture,
		}
		curseur += ouverture
	return _angles_cache


static func angle_de(id: StringName) -> float:
	return float((angles().get(id, {"centre": 0.0}))["centre"])


static func ouverture_de(id: StringName) -> float:
	return float((angles().get(id, {"ouverture": 1.0}))["ouverture"])


## LES POINTS D'INTÉRÊT.
##
## Ils ne déclarent PLUS de position absolue : ils déclarent leur secteur,
## une distance au centre et un écart angulaire. Leur position en découle.
##
## POURQUOI : une position absolue écrite à la main peut tomber dans le
## mauvais secteur dès qu'on retouche un découpage — et c'est exactement ce
## qui venait d'arriver. Dérivée, elle suit toujours son secteur.
##
## `hauteur` est ce qui compte le plus : c'est elle qui rend le repère
## visible d'un secteur à l'autre, donc utile. Un point d'intérêt bas n'est
## pas un repère, c'est de la décoration.
const POINTS_INTERET: Array[Dictionary] = [
	{
		"id": &"tour", "nom": "TOUR DE GUET", "secteur": &"camp",
		"rayon": 52.0, "ecart": -0.18, "hauteur": 17.0, "rayon_actif": 13.0,
		"note": "LE repère du monde. La plus haute chose de la carte, visible de partout : c'est elle qui permet de se réorienter.",
	},
	{
		"id": &"pont", "nom": "LE PONT DE PIERRE", "secteur": &"canyon",
		"rayon": 55.0, "ecart": 0.12, "hauteur": 11.0, "rayon_actif": 12.0,
		"note": "Une arche que l'on franchit par-dessous. Un passage obligé fabrique des rencontres.",
	},
	{
		"id": &"temple", "nom": "LE TEMPLE ENGLOUTI", "secteur": &"bosquet",
		"rayon": 50.0, "ecart": -0.1, "hauteur": 9.5, "rayon_actif": 14.0,
		"note": "Le seul volume clair du bosquet, donc son unique repère.",
	},
	{
		"id": &"depot", "nom": "LE DÉPÔT", "secteur": &"fonderie",
		"rayon": 53.0, "ecart": 0.16, "hauteur": 12.0, "rayon_actif": 15.0,
		"note": "Halle ouverte et grue. Le meilleur butin hors noyau.",
	},
	{
		"id": &"carcasse", "nom": "LA CARCASSE", "secteur": &"ruines",
		"rayon": 49.0, "ecart": 0.0, "hauteur": 10.0, "rayon_actif": 12.0,
		"note": "Un vaisseau échoué, planté de travers. Une silhouette qu'on ne confond avec rien.",
	},
	{
		"id": &"place", "nom": "LA PLACE", "secteur": &"noyau",
		"rayon": 0.0, "ecart": 0.0, "hauteur": 14.0, "rayon_actif": RAYON_NOYAU,
		"note": "Le cœur. Densité maximale, meilleur butin, aucun endroit où se cacher longtemps.",
	},
]


## Position au sol d'un point d'intérêt, dérivée de son secteur.
static func position_poi(poi: Dictionary) -> Vector2:
	var r := float(poi["rayon"])
	if r <= 0.0:
		return Vector2.ZERO
	var a := angle_de(poi["secteur"]) \
			+ float(poi["ecart"]) * ouverture_de(poi["secteur"])
	return Vector2(cos(a) * r, sin(a) * r)


## Écart minimal entre deux points d'apparition, en mètres.
const ECART_APPARITIONS := 16.0


## Cible de mobs vivants par niveau de danger.
static func mobs_vises(danger: int) -> int:
	match danger:
		Densite.CALME: return 3
		Densite.MOYENNE: return 6
		Densite.FORTE: return 9
		_: return 12


## Le secteur qui contient une position. Retourne `&"noyau"` au centre.
##
## On teste le RAYON avant l'angle : au centre, l'angle n'a plus de sens
## géométrique — à un mètre du milieu, un pas suffit à changer de secteur,
## et le sol clignoterait.
static func secteur_de(p: Vector2) -> StringName:
	if p.length() <= RAYON_NOYAU:
		return &"noyau"
	# Les secteurs PAVENT le cercle : le plus proche en angle est forcément
	# celui qui contient le point. Plus besoin de repli sur un « interstice »
	# — il n'y en a plus.
	var a := atan2(p.y, p.x)
	var meilleur: StringName = SECTEURS[0]["id"]
	var meilleur_ecart := INF
	for s: Dictionary in SECTEURS:
		var ecart: float = absf(wrapf(a - angle_de(s["id"]), -PI, PI))
		if ecart < meilleur_ecart:
			meilleur_ecart = ecart
			meilleur = s["id"]
	return meilleur


static func secteur(id: StringName) -> Dictionary:
	for s: Dictionary in SECTEURS:
		if s["id"] == id:
			return s
	return {}


static func point_interet(id: StringName) -> Dictionary:
	for p: Dictionary in POINTS_INTERET:
		if p["id"] == id:
			return p
	return {}


## POINTS D'APPARITION DES JOUEURS.
##
## Répartis sur TOUT le monde, et jamais au cœur : réapparaître dans le
## secteur le plus dangereux transformerait chaque mort en série de morts.
## Deux points par secteur plus quelques intermédiaires, à des rayons
## inégaux — alignés sur un cercle parfait, ils se devineraient.
static func apparitions_joueurs() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	# Graine FIXE : la carte doit être la même pour tout le monde et d'une
	# partie à l'autre. Un monde qu'on ne peut pas apprendre ne s'habite pas.
	rng.seed = 20260818
	for s: Dictionary in SECTEURS:
		for k in 2:
			# TIRAGE AVEC REJET. Mesuré sur la première version : les deux
			# apparitions les plus proches n'étaient qu'à 6,4 m l'une de
			# l'autre — assez pour que deux joueurs reviennent au même
			# endroit, ce qui annule tout l'intérêt de les répartir.
			#
			# Vingt essais suffisent très largement sur un monde de 78 m de
			# rayon ; le repli sur le dernier tirage garantit qu'on rend
			# toujours le bon nombre de points, même si la contrainte
			# devenait un jour trop serrée.
			var choisi := Vector3.ZERO
			for essai in 20:
				var a: float = angle_de(s["id"]) \
						+ rng.randf_range(-0.38, 0.38) * ouverture_de(s["id"])
				var r := rng.randf_range(RAYON * 0.55, RAYON * 0.86)
				choisi = Vector3(cos(a) * r, 0.2, sin(a) * r)
				var trop_pres := false
				for p: Vector3 in points:
					if p.distance_to(choisi) < ECART_APPARITIONS:
						trop_pres = true
						break
				if not trop_pres:
					break
			points.append(choisi)
	return points
