extends RefCounted
class_name PlanMonde
## PLAN DU MONDE — un monde SANS BORD, qui s'enroule sur lui-même.
##
## ─── POURQUOI LE MONDE N'EST PLUS UN DISQUE ─────────────────────────────
##
## Le monde était un disque de 78 m entouré d'un mur invisible. Ce mur a
## coûté cher : c'est autour de lui que la caméra se retrouvait coincée
## dans la pierre, c'est lui qui rabattait le cadre sans raison, et c'est
## en s'en approchant que l'écran devenait violet. Chaque correction en
## amenait une autre, parce qu'on soignait les symptômes d'une limite qui
## n'aurait pas dû exister.
##
## Le monde s'ENROULE désormais. On part tout droit, on ne rencontre jamais
## de bord, et on revient à son point de départ. C'est ce qu'on ressent en
## faisant le tour d'une planète — sans en payer le prix.
##
## ─── POURQUOI UN TORE ET NON UNE SPHÈRE ─────────────────────────────────
##
## Une vraie sphère demanderait de refaire la gravité, le déplacement, la
## visée, la caméra et toute l'IA en coordonnées sphériques : le jeu entier.
## Un carré dont les bords se recollent — un tore — donne EXACTEMENT la
## même sensation (partir tout droit, revenir chez soi) en gardant un sol
## plat, une gravité vers le bas et un code de déplacement inchangé.
##
## La règle qui rend l'illusion parfaite : le monde est PÉRIODIQUE. Se
## téléporter d'un côté à l'autre ne change rien à l'image, puisque ce qu'on
## voit au-delà du bord est précisément ce qui se trouve de l'autre côté.
##
## ─── CE QUI FAIT QU'UN MONDE PARAÎT OUVERT ──────────────────────────────
##
## Ce n'est pas la taille. Un grand terrain vide paraît PLUS petit qu'une
## petite carte dense, parce que rien n'y marque la distance parcourue.
##
##   1. DES SOLS DIFFÉRENTS. Vu de dessus, le sol occupe les trois quarts
##      de l'écran : c'est le levier n° 1, et le moins cher.
##   2. DES REPÈRES HAUTS, VISIBLES DE LOIN. Sans eux, un monde sans bord
##      devient désorientant au lieu d'être ouvert — et sur un tore, où
##      aucun bord ne dit où l'on est, ils comptent DEUX FOIS plus.
##   3. UN DANGER INÉGAL. Il donne une direction à l'exploration. Le disque
##      la tirait du centre ; le tore n'a pas de centre, c'est donc un
##      secteur — le Creuset — qui joue ce rôle.
##   4. DE L'IRRÉGULARITÉ. Une carte régulière se devine ; une carte
##      irrégulière s'apprend, et c'est en l'apprenant qu'on l'habite.

## Côté du monde, en mètres. Le monde fait donc 144 × 144 m.
##
## VOLONTAIREMENT MODESTE POUR COMMENCER. Faire immense tout de suite,
## c'est découvrir les problèmes d'un monde qui s'enroule sur une carte où
## chaque essai coûte une minute de marche. À 144 m, le tour complet prend
## une vingtaine de secondes : on voit immédiatement si l'enroulement est
## sans couture. La surface est agrandir ensuite se fait en changeant CE
## nombre, et rien d'autre.
const COTE := 144.0
const DEMI := COTE * 0.5

## Taille des cellules de semis. Un diviseur de COTE, sans quoi le pavage
## du décor ne se recollerait pas d'un bord à l'autre.
const CELLULE := 24.0

# --- ENROULEMENT ---------------------------------------------------------
#
# TOUT le jeu doit passer par ces trois fonctions. Une seule distance
# calculée « à plat » suffit à casser l'illusion : un bot qui vous croit à
# 140 m alors que vous êtes à 4 m derrière lui ne vous verra jamais.

## Ramène une position dans le carré de référence [-DEMI, DEMI[.
static func enrouler(p: Vector2) -> Vector2:
	return Vector2(wrapf(p.x, -DEMI, DEMI), wrapf(p.y, -DEMI, DEMI))


static func enrouler3(p: Vector3) -> Vector3:
	return Vector3(wrapf(p.x, -DEMI, DEMI), p.y, wrapf(p.z, -DEMI, DEMI))


## Le plus court chemin de `a` vers `b`, en tenant compte de l'enroulement.
##
## C'est LA fonction du fichier. Sur un tore, deux points ne sont jamais
## séparés de plus d'un demi-côté sur chaque axe : le trajet qui traverse
## le bord est souvent le plus court, et c'est celui-là qui compte.
static func ecart(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(wrapf(b.x - a.x, -DEMI, DEMI), wrapf(b.y - a.y, -DEMI, DEMI))


static func ecart3(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(wrapf(b.x - a.x, -DEMI, DEMI), b.y - a.y,
			wrapf(b.z - a.z, -DEMI, DEMI))


static func distance(a: Vector2, b: Vector2) -> float:
	return ecart(a, b).length()


static func distance3(a: Vector3, b: Vector3) -> float:
	return ecart3(a, b).length()


## Distance maximale possible entre deux points du monde : la diagonale du
## demi-carré. Sert de borne supérieure sûre à toute recherche de minimum.
static func distance_max() -> float:
	return Vector2(DEMI, DEMI).length()


## Densités de mobs, en mobs visés par secteur. Elles ne sont pas
## proportionnelles à la surface : c'est justement l'écart qui crée des
## zones calmes et des points chauds.
enum Densite { CALME, MOYENNE, FORTE, EXTREME }


## LES SECTEURS.
##
## CHAQUE SECTEUR DÉCLARE UN CENTRE, PAS UNE FORME. Un point appartient au
## secteur dont le centre est le plus proche — en distance enroulée.
##
## POURQUOI CE DÉCOUPAGE-LÀ. Le disque découpait le tour en parts d'angle,
## ce qui n'a plus aucun sens sans centre. Découper à la main en rectangles
## aurait ramené le défaut déjà payé une fois : des morceaux qui se
## chevauchent, des interstices sans propriétaire, un secteur avalé par son
## voisin. Un découpage par centres ne PEUT pas laisser de trou ni de
## recouvrement — chaque point du monde a exactement un centre le plus
## proche — et il se recolle tout seul d'un bord à l'autre puisque la
## distance employée est celle du tore.
##
## `poids` règle la taille sans toucher aux positions : plus il est petit,
## plus le secteur est resserré. C'est ce qui permet de garder le Creuset
## exigu, donc disputé, sans le coincer dans un coin.
const SECTEURS: Array[Dictionary] = [
	{
		"id": &"creuset",
		"nom": "LE CREUSET",
		"centre": Vector2(-56.0, 14.0),
		"poids": 0.62,
		"sol": Cfg.SOL_NOYAU,
		"danger": Densite.EXTREME,
		"familles": [&"pilier", &"ruine", &"caillou"],
		# DENSITÉ BASSE, ET C'EST VOULU. Le Creuset porte DÉJÀ tout le plan
		# de l'ancienne arène — ses structures, ses abris, sa garniture. Y
		# semer en plus au tarif d'un secteur ordinaire empilait deux décors
		# au même endroit : mesuré, le joueur y devenait invisible depuis la
		# caméra une fois sur sept. On ne meuble pas deux fois la même pièce.
		"densite_decor": 0.025,
		"note": "Le point chaud du monde. Densité maximale, meilleur butin, aucun endroit où se cacher longtemps. Il remplace le noyau du disque : sur un tore, le danger ne peut plus venir du centre, il vient d'un LIEU.",
	},
	{
		"id": &"ruines",
		"nom": "LES RUINES",
		"centre": Vector2(-46.0, -38.0),
		"poids": 0.85,
		"sol": Cfg.SOL_RUINES,
		"danger": Densite.FORTE,
		"familles": [&"ruine", &"pilier", &"caillou", &"touffe"],
		"densite_decor": 0.065,
		"note": "Étroit et couvert. Bon butin, mauvaises retraites.",
	},
	{
		"id": &"camp",
		"nom": "LE CAMP",
		"centre": Vector2(32.0, -50.0),
		"poids": 1.25,
		"sol": Cfg.SOL_CAMP,
		"danger": Densite.CALME,
		"familles": [&"tente", &"caisse", &"cloture", &"tonneau", &"caillou"],
		"densite_decor": 0.055,
		"note": "Le plus large. Peu de mobs, beaucoup d'abris bas : on y apprend à jouer sans être puni.",
	},
	{
		"id": &"canyon",
		"nom": "LE CANYON",
		"centre": Vector2(54.0, 26.0),
		"poids": 1.05,
		"sol": Cfg.SOL_CANYON,
		"danger": Densite.MOYENNE,
		"familles": [&"mesa", &"rocher", &"caillou", &"touffe"],
		"densite_decor": 0.075,
		"note": "Mesas hautes et défilés étroits. Le secteur où l'on tend une embuscade.",
	},
	{
		"id": &"bosquet",
		"nom": "LE BOSQUET",
		"centre": Vector2(-20.0, 46.0),
		"poids": 1.1,
		"sol": Cfg.SOL_BOSQUET,
		"danger": Densite.MOYENNE,
		"familles": [&"arbre", &"pin", &"buisson", &"touffe", &"caillou"],
		"densite_decor": 0.11,
		"note": "Couvert dense. On y voit mal et on y est mal vu — le contraire du canyon.",
	},
	{
		"id": &"fonderie",
		"nom": "LA FONDERIE",
		"centre": Vector2(6.0, -6.0),
		"poids": 1.0,
		"sol": Cfg.SOL_FONDERIE,
		"danger": Densite.FORTE,
		"familles": [&"caisse", &"tonneau", &"barricade", &"caillou"],
		"densite_decor": 0.07,
		"note": "Béton et conteneurs. Le secteur le plus « habité ».",
	},
]


## Le secteur qui contient une position.
##
## L'ONDULATION N'EST PAS UN ORNEMENT. Un découpage par centres donne des
## frontières parfaitement droites, qui se lisent au sol comme les coutures
## d'un patron de couture. On perturbe donc le point testé par deux sinus de
## périodes différentes : les limites deviennent sinueuses sans qu'aucune ne
## puisse se croiser ou laisser de trou — la règle « le centre le plus
## proche gagne » reste intacte, on la teste juste ailleurs.
##
## Les périodes DIVISENT le côté du monde : sans cela l'ondulation ne se
## recollerait pas d'un bord à l'autre, et la couture qu'on cherche à
## masquer réapparaîtrait, une seule fois, à l'endroit le plus visible.
static func secteur_de(p: Vector2) -> StringName:
	var q := p + Vector2(
			sin(p.y * TAU / 48.0) * 4.5 + sin(p.y * TAU / 144.0) * 3.0,
			sin(p.x * TAU / 36.0) * 4.0 + sin(p.x * TAU / 144.0) * 3.5)
	var meilleur: StringName = SECTEURS[0]["id"]
	var meilleure := INF
	for s: Dictionary in SECTEURS:
		var d := distance(q, s["centre"]) / float(s["poids"])
		if d < meilleure:
			meilleure = d
			meilleur = s["id"]
	return meilleur


static func secteur(id: StringName) -> Dictionary:
	for s: Dictionary in SECTEURS:
		if s["id"] == id:
			return s
	return {}


## LES POINTS D'INTÉRÊT.
##
## Ils déclarent un DÉPORT depuis le centre de leur secteur, pas une
## position absolue : déplacer un secteur emmène son repère avec lui, et
## aucun ne peut se retrouver chez le voisin après une retouche.
##
## `hauteur` est ce qui compte le plus. Sur un monde qui s'enroule, aucun
## bord ne dit où l'on se trouve : les silhouettes hautes sont la SEULE
## façon de se repérer, et c'est à elles qu'on doit de pouvoir dire
## « retrouve-moi à la tour ».
const POINTS_INTERET: Array[Dictionary] = [
	{
		"id": &"tour", "nom": "TOUR DE GUET", "secteur": &"camp",
		"deport": Vector2(-9.0, 7.0), "hauteur": 17.0, "rayon_actif": 13.0,
		"note": "LE repère du monde. La plus haute chose de la carte, visible de partout : c'est elle qui permet de se réorienter.",
	},
	{
		"id": &"pont", "nom": "LE PONT DE PIERRE", "secteur": &"canyon",
		"deport": Vector2(6.0, -8.0), "hauteur": 11.0, "rayon_actif": 12.0,
		"note": "Une arche que l'on franchit par-dessous. Un passage obligé fabrique des rencontres.",
	},
	{
		"id": &"temple", "nom": "LE TEMPLE ENGLOUTI", "secteur": &"bosquet",
		"deport": Vector2(8.0, 5.0), "hauteur": 9.5, "rayon_actif": 14.0,
		"note": "Le seul volume clair du bosquet, donc son unique repère.",
	},
	{
		"id": &"depot", "nom": "LE DÉPÔT", "secteur": &"fonderie",
		"deport": Vector2(-7.0, 9.0), "hauteur": 12.0, "rayon_actif": 15.0,
		"note": "Halle ouverte et grue. Le meilleur butin hors Creuset.",
	},
	{
		"id": &"carcasse", "nom": "LA CARCASSE", "secteur": &"ruines",
		"deport": Vector2(5.0, 6.0), "hauteur": 10.0, "rayon_actif": 12.0,
		"note": "Un vaisseau échoué, planté de travers. Une silhouette qu'on ne confond avec rien.",
	},
	{
		"id": &"place", "nom": "LA PLACE", "secteur": &"creuset",
		"deport": Vector2(0.0, 0.0), "hauteur": 14.0, "rayon_actif": 16.0,
		"note": "Le cœur du Creuset. C'est là qu'on va quand on veut se battre.",
	},
]


## Position au sol d'un point d'intérêt, dérivée de son secteur.
static func position_poi(poi: Dictionary) -> Vector2:
	return enrouler(Vector2(secteur(poi["secteur"])["centre"]) + Vector2(poi["deport"]))


static func point_interet(id: StringName) -> Dictionary:
	for p: Dictionary in POINTS_INTERET:
		if p["id"] == id:
			return p
	return {}


## Écart minimal entre deux points d'apparition, en mètres.
const ECART_APPARITIONS := 16.0


## Cible de mobs vivants par niveau de danger.
static func mobs_vises(danger: int) -> int:
	match danger:
		Densite.CALME: return 3
		Densite.MOYENNE: return 6
		Densite.FORTE: return 9
		_: return 12


## POINTS D'APPARITION DES JOUEURS.
##
## Deux par secteur, jamais dans le Creuset : réapparaître au point le plus
## disputé du monde transformerait chaque mort en série de morts.
##
## TIRAGE AVEC REJET, et la distance employée est celle du TORE. Avec une
## distance à plat, deux points séparés par la couture se croiraient à
## l'opposé du monde alors qu'ils sont voisins — et deux joueurs
## reviendraient au même endroit.
static func apparitions_joueurs() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	# Graine FIXE : la carte doit être la même pour tout le monde et d'une
	# partie à l'autre. Un monde qu'on ne peut pas apprendre ne s'habite pas.
	rng.seed = 20260818
	for s: Dictionary in SECTEURS:
		if s["id"] == &"creuset":
			continue
		for k in 2:
			var choisi := Vector3.ZERO
			for essai in 40:
				var c: Vector2 = s["centre"]
				var p := enrouler(c + Vector2(rng.randf_range(-18.0, 18.0),
						rng.randf_range(-18.0, 18.0)))
				choisi = Vector3(p.x, 0.2, p.y)
				# On exige AUSSI que le point soit resté dans son secteur :
				# un tirage large près d'une frontière peut déborder chez le
				# voisin, et l'on se retrouverait avec quatre apparitions
				# dans le même secteur et zéro dans un autre.
				if secteur_de(p) != s["id"]:
					continue
				var trop_pres := false
				for q: Vector3 in points:
					if distance(Vector2(q.x, q.z), p) < ECART_APPARITIONS:
						trop_pres = true
						break
				if not trop_pres:
					break
			points.append(choisi)
	return points
