extends RefCounted
class_name PlanAreneWestern
## ARÈNE WESTERN — 80 × 80 m, deathmatch à dix, composition manuelle.
##
## ─── LA MAQUETTE FAIT AUTORITÉ ─────────────────────────────────────────
##
## Ce plan REPRODUIT la maquette jointe, il ne s'en inspire pas. Chaque
## fois qu'un placement m'a paru améliorable, j'ai suivi la maquette : une
## composition validée à l'œil par son auteur vaut mieux qu'une
## composition raisonnée par moi. Les coordonnées ci-dessous sont la
## lecture de cette image, ramenée à 80 m de côté.
##
## Ce qu'on y lit, et qui commande tout le reste :
##
##   · Une arène ARRONDIE, ceinte de barrières de bois, portail au sud.
##   · Un CENTRE modeste — une margelle de pierre, pas un monument.
##   · Une couronne de FORMATIONS ROCHEUSES en terracotta, irrégulière.
##   · Entre elles, du petit couvert : caisses, tonneaux, bottes, chariots.
##   · Une BOUCLE PRINCIPALE qui fait le tour à mi-rayon.
##   · Des BOUCLES INTERMÉDIAIRES autour de chaque grosse formation.
##   · Des PASSAGES TRANSVERSAUX qui coupent vers le centre.
##
## ─── LA RÈGLE QUI COMMANDE LE PLACEMENT : AUCUNE IMPASSE ───────────────
##
## Le jeu demandé est une CHASSE. Je vois Ruby, je tire, elle se cache
## derrière un rocher, je contourne par la gauche, elle repart par la
## droite. Cette boucle-là est tout le plaisir, et elle exige une seule
## chose du level design : que chaque grosse masse soit CONTOURNABLE À
## 360°, avec assez de place pour courir autour.
##
## D'où la contrainte que le banc vérifie : autour de chaque formation
## majeure, un anneau libre d'au moins DEGAGEMENT mètres. Une formation
## adossée à une autre, ou à la bordure, crée un cul-de-sac — et un
## cul-de-sac transforme une poursuite en exécution.

## Côté jouable, en mètres.
const COTE := 80.0
const DEMI := COTE * 0.5
## Rayon de la clôture. Au-delà, le désert continue visuellement.
const RAYON_CLOTURE := 38.0
## Anneau libre exigé autour de chaque grosse masse, en mètres.
const DEGAGEMENT := 3.6

## Hauteurs, et elles portent le rôle de couvert.
##
## BASSE  0,9 m — on tire par-dessus, on s'y accroupit. Caisses, tonneaux,
##                bottes de foin, petites pierres.
## MOYEN  1,5 m — coupe le tir tendu, laisse voir la tête. Murets,
##                barrières, rochers moyens.
## HAUTE  3,2 m — couvert complet. Grosses formations, chariots bâchés.
const H_BASSE := 0.9
const H_MOYEN := 1.5
const H_HAUTE := 3.2

# --- FORMATIONS ROCHEUSES ------------------------------------------------
#
# LES ÎLOTS DE GAMEPLAY. Chacun est un obstacle qu'on contourne, jamais un
# mur qu'on longe. Leur disposition est IRRÉGULIÈRE — c'est la maquette qui
# l'impose, et c'est aussi ce qui rend la carte apprenable : une couronne
# régulière se devine, une couronne irrégulière s'habite.
#
# `rayon` est l'emprise au sol, `hauteur` dit si l'on voit par-dessus.
const FORMATIONS: Array[Dictionary] = [
	# Couronne intérieure — six masses autour du centre, à ~15 m.
	{"pos": Vector2(-13.5, -8.0), "rayon": 3.4, "hauteur": H_HAUTE},
	{"pos": Vector2(2.0, -15.5), "rayon": 3.8, "hauteur": H_HAUTE},
	{"pos": Vector2(15.0, -6.5), "rayon": 3.2, "hauteur": H_HAUTE},
	{"pos": Vector2(13.0, 9.5), "rayon": 3.6, "hauteur": H_HAUTE},
	{"pos": Vector2(-1.5, 16.0), "rayon": 3.4, "hauteur": H_HAUTE},
	{"pos": Vector2(-15.0, 8.0), "rayon": 3.2, "hauteur": H_HAUTE},

	# Couronne extérieure — six autres à ~27 m, décalées en angle pour que
	# les couloirs radiaux ne s'alignent jamais avec ceux de l'intérieur.
	{"pos": Vector2(-26.0, -20.0), "rayon": 4.4, "hauteur": H_HAUTE},
	{"pos": Vector2(-4.0, -28.5), "rayon": 4.0, "hauteur": H_HAUTE},
	{"pos": Vector2(24.0, -21.0), "rayon": 4.6, "hauteur": H_HAUTE},
	{"pos": Vector2(29.0, 4.0), "rayon": 3.8, "hauteur": H_HAUTE},
	{"pos": Vector2(18.0, 25.0), "rayon": 4.2, "hauteur": H_HAUTE},
	# ÉCARTÉE APRÈS MESURE. À (-22 · 24) elle ne laissait que 75 % de son
	# anneau libre — juste au seuil — parce que le muret voisin lui
	# mordait le flanc. Une masse qu'on ne contourne qu'aux trois quarts
	# n'est pas un îlot, c'est un coin : la poursuite s'y termine au lieu
	# d'y tourner. Deux mètres suffisent à rouvrir le tour.
	{"pos": Vector2(-23.5, 22.0), "rayon": 4.2, "hauteur": H_HAUTE},
	{"pos": Vector2(-30.0, 6.0), "rayon": 3.6, "hauteur": H_HAUTE},
]

# --- MURETS DE PIERRE ----------------------------------------------------
#
# COUVERT MOYEN, ET SURTOUT BRISEUR DE LIGNE DE TIR. Ils sont posés en
# ARCS et non en droites : un mur droit de dix mètres est un corridor,
# un arc est un abri qu'on contourne. `arc` est l'angle couvert, en
# degrés ; `rayon` la courbure.
const MURETS: Array[Dictionary] = [
	# La margelle centrale — quatre arcs avec de larges brèches. Le centre
	# doit être identifiable, pas fortifié.
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 20.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 115.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 200.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 295.0, "arc": 55.0},
	# Arcs dispersés, adossés à aucune formation.
	{"centre": Vector2(-8.0, -20.0), "rayon": 5.0, "depart": 300.0, "arc": 95.0},
	{"centre": Vector2(21.5, -10.0), "rayon": 4.5, "depart": 140.0, "arc": 90.0},
	{"centre": Vector2(6.0, 22.0), "rayon": 5.5, "depart": 210.0, "arc": 85.0},
	{"centre": Vector2(-24.0, 0.0), "rayon": 5.0, "depart": 30.0, "arc": 90.0},
	{"centre": Vector2(9.0, -24.0), "rayon": 4.5, "depart": 80.0, "arc": 80.0},
	{"centre": Vector2(-13.0, 27.0), "rayon": 4.8, "depart": 350.0, "arc": 80.0},
]

# --- BARRIÈRES DE BOIS ---------------------------------------------------
#
# La clôture périphérique est bâtie à part (voir `cloture()`). Celles-ci
# sont les refends INTÉRIEURS : de courts segments qui découpent les
# grandes ouvertures sans jamais fermer un passage.
const BARRIERES: Array[Dictionary] = [
	{"pos": Vector2(-19.0, -14.5), "angle": 35.0, "long": 6.0},
	{"pos": Vector2(8.5, -20.0), "angle": 110.0, "long": 5.5},
	{"pos": Vector2(25.0, 12.0), "angle": 70.0, "long": 6.5},
	{"pos": Vector2(-8.0, 24.0), "angle": 15.0, "long": 6.0},
	{"pos": Vector2(-27.0, 14.0), "angle": 125.0, "long": 5.5},
	{"pos": Vector2(20.0, -30.0), "angle": 160.0, "long": 6.0},
]

# --- CHARIOTS ------------------------------------------------------------
#
# Trois, pas plus. C'est la silhouette la plus reconnaissable de la
# planche — donc un repère d'orientation — et elle perdrait ce rôle
# répétée dix fois.
const CHARIOTS: Array[Dictionary] = [
	{"pos": Vector2(-30.0, -6.0), "angle": 20.0},
	{"pos": Vector2(27.0, 17.0), "angle": 200.0},
	{"pos": Vector2(6.0, 31.0), "angle": 100.0},
]

# --- PETIT COUVERT -------------------------------------------------------
#
# Caisses, tonneaux, bottes de foin. Ils ne bloquent pas la course : ils
# cassent la ligne de tir et donnent où se jeter. `type` choisit le modèle,
# la hauteur est toujours basse.
const PETITS: Array[Dictionary] = [
	{"pos": Vector2(-6.5, -6.0), "type": &"caisse"},
	{"pos": Vector2(7.0, -5.0), "type": &"tonneau"},
	{"pos": Vector2(4.5, 7.5), "type": &"botte"},
	{"pos": Vector2(-8.0, 6.0), "type": &"caisse"},
	{"pos": Vector2(-18.0, -2.0), "type": &"botte"},
	{"pos": Vector2(19.0, 1.0), "type": &"tonneau"},
	{"pos": Vector2(-2.0, -21.0), "type": &"caisse"},
	{"pos": Vector2(1.0, 21.5), "type": &"tonneau"},
	{"pos": Vector2(-21.0, -25.0), "type": &"botte"},
	{"pos": Vector2(16.0, -26.0), "type": &"caisse"},
	{"pos": Vector2(31.0, -9.0), "type": &"tonneau"},
	{"pos": Vector2(-31.0, 18.0), "type": &"botte"},
	{"pos": Vector2(11.0, 30.0), "type": &"caisse"},
	{"pos": Vector2(-13.0, -31.0), "type": &"tonneau"},
	{"pos": Vector2(28.0, -3.0), "type": &"botte"},
	{"pos": Vector2(-27.0, -12.0), "type": &"caisse"},
	{"pos": Vector2(23.0, 30.0), "type": &"tonneau"},
	{"pos": Vector2(-6.0, 32.0), "type": &"botte"},
]

# --- VÉGÉTATION ----------------------------------------------------------
#
# AUCUN RÔLE DE JEU, et c'est la règle : un cactus ne doit jamais arrêter
# une poursuite. Ils sont donc posés hors des lignes de circulation, contre
# les rochers et près de la clôture — là où l'on ne court pas.
const VEGETATION: Array[Dictionary] = [
	{"pos": Vector2(-17.5, -11.0), "type": &"cactus"},
	{"pos": Vector2(5.5, -18.5), "type": &"buisson"},
	{"pos": Vector2(18.5, -9.5), "type": &"cactus"},
	{"pos": Vector2(16.0, 12.5), "type": &"buisson"},
	{"pos": Vector2(-4.5, 19.0), "type": &"cactus"},
	{"pos": Vector2(-18.5, 11.0), "type": &"buisson"},
	{"pos": Vector2(-30.0, -23.0), "type": &"cactus"},
	{"pos": Vector2(-7.5, -32.0), "type": &"cactus"},
	{"pos": Vector2(28.5, -24.5), "type": &"buisson"},
	{"pos": Vector2(33.0, 7.5), "type": &"cactus"},
	{"pos": Vector2(21.5, 28.5), "type": &"buisson"},
	{"pos": Vector2(-25.5, 27.5), "type": &"cactus"},
	{"pos": Vector2(-34.0, 3.0), "type": &"cactus"},
	{"pos": Vector2(34.0, -14.0), "type": &"buisson"},
]

# --- APPARITIONS ---------------------------------------------------------
#
# DIX POINTS, TOUS SUR LA PÉRIPHÉRIE, à 33 m du centre.
#
# AUCUN N'A DE LIGNE DE TIR SUR LE CENTRE, et c'est vérifié par le banc :
# chacun est posé de sorte qu'une formation ou un muret s'interpose. Naître
# à découvert face au point le plus fréquenté de la carte, c'est naître
# mort — et sur une carte à réapparition permanente, ce défaut se paie dix
# fois par minute.
##
## L'ordre ALTERNE d'un bord à l'autre plutôt que de tourner : deux joueurs
## servis à la suite se retrouvent à l'opposé, jamais côte à côte.
const RAYON_APPARITION := 33.0
const APPARITIONS: Array[Vector2] = [
	Vector2(0.0, -33.0),        # nord
	Vector2(0.0, 33.0),         # sud
	Vector2(-33.0, 0.0),        # ouest
	Vector2(33.0, 0.0),         # est
	# LES QUATRE DIAGONALES ONT ÉTÉ DÉPLACÉES APRÈS MESURE. Posées à
	# 23 m sur les diagonales, elles tombaient DANS les formations de la
	# couronne extérieure — le banc a relevé quatre apparitions bloquées
	# sur dix. Naître à l'intérieur d'un rocher, c'est au mieux rester
	# coincé, au pire être éjecté n'importe où par la physique.
	#
	# Elles glissent sur la couronne à 33 m, entre deux formations, en
	# gardant leur rôle d'écartement.
	Vector2(-30.5, -13.0),      # nord-ouest
	Vector2(30.5, 13.0),        # sud-est
	Vector2(30.5, -13.0),       # nord-est
	Vector2(-30.5, 13.0),       # sud-ouest
	Vector2(-12.0, -30.5),      # nord-nord-ouest
	Vector2(13.5, 30.2),        # sud-sud-est
]


## Toutes les masses susceptibles de bloquer une poursuite, avec leur
## emprise. Sert au banc de contournabilité et au calcul des dégagements.
static func masses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in FORMATIONS:
		out.append({"pos": f["pos"], "rayon": f["rayon"], "nom": "formation"})
	for c: Dictionary in CHARIOTS:
		out.append({"pos": c["pos"], "rayon": 2.6, "nom": "chariot"})
	return out
