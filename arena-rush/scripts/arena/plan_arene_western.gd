extends RefCounted
class_name PlanAreneWestern
## ARÈNE WESTERN — 80 × 80 m, deathmatch à dix, composition manuelle.
##
## ─── LA MAQUETTE FAIT AUTORITÉ ─────────────────────────────────────────
##
## Ce plan REPRODUIT la maquette jointe, il ne s'en inspire pas. Chaque
## fois qu'un placement m'a paru améliorable, j'ai suivi la maquette : une
## composition validée à l'œil par son auteur vaut mieux qu'une
## composition raisonnée par moi.
##
## ─── CE QUE LA V2 CORRIGE, ET SUR QUELLE MESURE ────────────────────────
##
## La V1 était juste sur le papier et vide à l'écran. Mesuré sur les rendus
## à la caméra de jeu : 72 à 82 % de l'image était du sable nu, contre 40
## à 43 % sur les vues 3D de la maquette. Le premier instrument que j'avais
## écrit disait pourtant que tout allait bien — il comptait un tonneau de
## cinquante-cinq centimètres comme un couvert, et la médiane des distances
## tombait à 1,7 m. Il mesurait la PROXIMITÉ ; le défaut était l'EMPRISE.
##
## Quatre écarts relevés en comparant la maquette et le rendu :
##
##   1. QUATRE-VINGT-QUATRE POUR CENT de l'emprise des couverts tenait dans
##      treize grosses formations. Tout le reste — murets, barrières,
##      caisses — pesait moins de trois pour cent de l'aire jouable.
##   2. Les rochers étaient des DISQUES. La maquette montre des CRÊTES
##      allongées, de six à douze mètres, orientées chacune autrement. À
##      surface égale une crête barre bien mieux une ligne de vue, et elle
##      se contourne différemment selon le côté d'où l'on arrive.
##   3. Les couverts étaient ISOLÉS. La maquette les GROUPE : presque
##      chaque rocher a ses caisses, sa botte de foin, son bout de muret,
##      ses cactus. C'est ce groupement qui remplit l'écran.
##   4. Les petits objets faisaient quatre-vingt-dix centimètres. Sur la
##      maquette ils sont EMPILÉS par deux ou trois, donc lisibles de loin
##      et utilisables en vrai duel.
##
## ─── LA RÈGLE QUI COMMANDE LE PLACEMENT : AUCUNE IMPASSE ───────────────
##
## Le jeu demandé est une CHASSE. Je vois Ruby, je tire, elle se cache
## derrière un rocher, je contourne par la gauche, elle repart par la
## droite. Cette boucle-là est tout le plaisir, et elle exige une seule
## chose du level design : que chaque grosse masse soit CONTOURNABLE À
## 360°, avec assez de place pour courir autour.

## Côté du monde, en mètres.
const COTE := 80.0
const DEMI := COTE * 0.5

## LEVÉE ANTI-SCINTILLEMENT — douze millimètres, et ce n'est pas cosmétique.
##
## Meshy livre chaque modèle pieds à y = 0 : sa face inférieure tombe alors
## EXACTEMENT dans le plan du sol. Deux surfaces coplanaires se disputent
## le même pixel, et laquelle gagne dépend de l'arrondi de la profondeur —
## la pièce clignote dès que la caméra bouge, et jamais sur une capture
## fixe. Douze millimètres les départagent, et personne ne voit flotter
## quoi que ce soit depuis dix mètres de haut.
const LEVEE := 0.012

# --- L'ENCEINTE ----------------------------------------------------------
#
# UN CARRÉ AUX ANGLES ARRONDIS, PAS UN DISQUE.
#
# C'était la différence de forme la plus visible entre la maquette et la
# V1. Elle n'est pas décorative : un disque n'a pas de coins, donc pas de
# ces poches d'angle où la maquette pose ses plus grosses crêtes et où une
# poursuite change de rythme. Le portail est au sud, comme le START.
#
# Attention à ce que ce changement coûte : la surface jouable passe de
# 4 500 à 5 500 m². Vingt pour cent d'aire en plus, c'est vingt pour cent
# de couverts en plus à poser, sinon la carte se vide au lieu de se
# remplir. Les coins sont donc peuplés en premier.
const BORD := 36.0
const CONGE := 13.0
## Marge où l'on ne pose rien : le joueur ne doit jamais coller la clôture.
const MARGE_BORD := 1.6
## Anneau libre exigé autour de chaque grosse masse, en mètres.
const DEGAGEMENT := 3.6

## Hauteurs, et elles portent le rôle de couvert.
##
## BASSE  0,9 m — on tire par-dessus, on s'y accroupit.
## MOYEN  1,5 m — coupe le tir tendu, laisse voir la tête. Murs, barrières.
## PILE   2,1 m — un empilement de caisses : couvert complet mais étroit.
## CRETE  2,9 m — couvert complet. C'est trente centimètres de MOINS que la
##                V1 : la consigne dit que les grosses masses mangeaient
##                l'écran, et la hauteur y est pour autant que l'emprise.
const H_BASSE := 0.9
const H_MOYEN := 1.5
const H_PILE := 2.1
const H_CRETE := 2.9
## Crête moyenne — barre le tir tendu sans effacer complètement l'autre.
const H_CRETE_M := 1.9

# --- LA COMPOSITION ------------------------------------------------------
#
# ─── POURQUOI TOUT CE QUI SUIT EST ENGENDRÉ, ET NON ÉCRIT ──────────────
#
# La version précédente listait chaque pièce à la main, avec sa position au
# décimètre et son angle à un degré près. Vue de dessus, elle donnait un
# SEMIS : même densité partout, même taille partout, aucun repère, aucune
# voie. On ne pouvait désigner aucun endroit de la carte, parce qu'aucun
# endroit n'existait. Le retour a été franc et juste : « les éléments ont
# été posés n'importe comment ».
#
# Trois règles la remplacent, et ce sont celles des arènes du genre :
#
#   1. UNE GRILLE. Toutes les positions sont des multiples d'un mètre, tous
#      les angles des multiples de quarante-cinq degrés. Ce n'est pas de la
#      rigidité : c'est ce qui fait qu'une carte se lit comme construite au
#      lieu de semée. Les angles quelconques d'avant — 12°, -14°, 78° — ne
#      donnaient pas de la variété, ils donnaient du désordre.
#
#   2. UNE SYMÉTRIE DE 180°. Chaque pièce posée dans une moitié reparaît,
#      pivotée d'un demi-tour, dans l'autre. C'est la garantie d'équité
#      d'un affrontement à réapparition permanente : aucun quartier n'est
#      mieux servi qu'un autre, et personne ne peut apprendre « le bon
#      coin ».
#
#   3. UNE SEULE MOITIÉ EST ÉCRITE. L'autre est CALCULÉE — voir `_miroir`.
#      La symétrie cesse d'être une promesse qu'on tient à la main pour
#      devenir une propriété du code, donc quelque chose qu'un banc peut
#      vérifier. C'est aussi ce qui rend la carte modifiable : déplacer une
#      pièce en déplace deux, et l'équilibre ne se perd jamais en route.
#
# ─── LES LIEUX, ET LEURS NOMS ──────────────────────────────────────────
#
#   LA PLACE      le centre, dégagé sur six mètres autour de la margelle,
#                 avec quatre murs en moulinet. C'est le point le plus
#                 exposé de la carte et il doit le rester : l'étoile y
#                 tombe souvent, et la tenir doit coûter cher.
#   LES BASTIONS  quatre crêtes en diagonale, les plus grosses masses de la
#                 carte. Ce sont les REPÈRES : où qu'on soit, on en voit
#                 un, et l'on sait de quel quartier on parle.
#   LES QUATRE PORTES  aux quatre points cardinaux, la couronne extérieure
#                 s'ouvre. Ce sont les entrées de la boucle, et les seuls
#                 endroits d'où l'on voit le centre de loin.
#   LA BOUCLE     l'anneau courable entre les crêtes du bord et la
#                 clôture. On en fait le tour sans jamais buter.
#   LES CORRALS   deux enclos de barrières opposés. Le seul couvert qui
#                 arrête le corps sans cacher l'adversaire.

# --- FORMATIONS ROCHEUSES ------------------------------------------------
#
# `long` est la dimension dans l'axe, `large` en travers, `angle` en degrés
# (0 = axe est-ouest).
#
# LES BASTIONS SONT DEUX FOIS PLUS GROS QUE LE RESTE, et c'est délibéré.
# Une carte où tout a la même taille n'a pas de repère : l'œil n'accroche
# nulle part et l'on se perd dans son propre terrain. Il faut une masse
# dominante par quartier.
const _FORMATIONS_MOITIE: Array[Dictionary] = [
	# LES BASTIONS — les quatre repères, en diagonale.
	{"pos": Vector2(16.0, 16.0), "long": 11.0, "large": 4.6,
		"angle": 45.0, "hauteur": H_CRETE},
	{"pos": Vector2(16.0, -16.0), "long": 11.0, "large": 4.6,
		"angle": 135.0, "hauteur": H_CRETE},
	# LES ÉPAULES DE LA BOUCLE — elles hérissent le bord SAUF aux quatre
	# points cardinaux, qui restent ouverts : ce sont les portes.
	{"pos": Vector2(30.0, 20.0), "long": 9.0, "large": 3.6,
		"angle": 90.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(20.0, 30.0), "long": 9.0, "large": 3.6,
		"angle": 0.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(30.0, -20.0), "long": 9.0, "large": 3.6,
		"angle": 90.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(-20.0, 30.0), "long": 9.0, "large": 3.6,
		"angle": 0.0, "hauteur": H_CRETE_M},
	# DEUX CRÊTES D'APPROCHE — elles cassent la vue depuis les portes vers
	# la place, sans jamais la fermer.
	{"pos": Vector2(9.0, 24.0), "long": 7.0, "large": 3.2,
		"angle": 45.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(24.0, -9.0), "long": 7.0, "large": 3.2,
		"angle": 45.0, "hauteur": H_CRETE_M},
	# LES POCHES DIAGONALES EXTÉRIEURES. Ajoutées après mesure : sans
	# elles, dix-huit pour cent des poses de caméra ne montraient pas deux
	# couverts de duel, là où la règle en veut deux à quatre. Les grands
	# vides étaient précisément ces quatre triangles entre un bastion et la
	# clôture.
	# ORIENTÉES LE LONG DE LA DIAGONALE, PAS EN TRAVERS. Posées à 135° —
	# donc perpendiculaires à la diagonale — elles barraient la poche : le
	# banc a mesuré un anneau libre à 65 % là où il en faut 75, coincées
	# qu'elles étaient entre le bastion et les deux crêtes d'épaule. Dans
	# l'axe, elles laissent passer des deux côtés et gardent leur rôle de
	# couvert.
	{"pos": Vector2(25.0, 25.0), "long": 6.0, "large": 3.0,
		"angle": 45.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(25.0, -25.0), "long": 6.0, "large": 3.0,
		"angle": 135.0, "hauteur": H_CRETE_M},
]

# --- MURS DE PIERRE BAS --------------------------------------------------
#
# COUVERT MOYEN, ET SURTOUT BRISEUR DE LIGNE DE TIR. Droits et courts,
# posés en travers des ouvertures. Un mur droit de six à sept mètres ne
# fait pas un corridor tant qu'on peut passer des deux côtés.
const _MURS_MOITIE: Array[Dictionary] = [
	# LE MOULINET DE LA PLACE. Quatre murs décalés en rotation : on est
	# toujours couvert d'un côté et exposé de l'autre, et changer de côté
	# demande de bouger. C'est ce qui fait qu'on ne campe pas au centre.
	{"pos": Vector2(7.0, 2.0), "angle": 0.0, "long": 7.0},
	{"pos": Vector2(2.0, -7.0), "angle": 90.0, "long": 7.0},
	# LES PORTES DES VOIES — un mur en travers de chaque voie cardinale, à
	# mi-chemin. On voit le centre depuis la porte, mais pas en ligne
	# droite : il faut s'engager.
	{"pos": Vector2(5.0, -17.0), "angle": 90.0, "long": 6.0},
	{"pos": Vector2(17.0, 5.0), "angle": 0.0, "long": 6.0},
	# LA COURONNE MÉDIANE — entre la place et les bastions, c'était une
	# plaine. Trois murs en biais y cassent la vue sans créer de couloir :
	# posés à quarante-cinq degrés, ils ne sont parallèles ni aux voies
	# cardinales ni aux diagonales, donc ils ne prolongent aucune ligne.
	{"pos": Vector2(-12.0, 9.0), "angle": 45.0, "long": 6.0},
	{"pos": Vector2(9.0, 12.0), "angle": 135.0, "long": 6.0},
	# À 135° ET NON À 45°. Posé à 45°, ce mur était COLINÉAIRE au bastion
	# voisin : il le prolongeait au lieu de le flanquer, et les deux
	# ensemble formaient une barrière que le banc a mesurée contournable à
	# 67 % seulement, pour un seuil de 75. Perpendiculaire, il couvre la
	# même approche sans fermer le tour.
	{"pos": Vector2(-20.0, -10.0), "angle": 135.0, "long": 6.0},
	# LES JOUES DES PORTES. Les quatre ouvertures cardinales restent
	# franches, mais bordées : sans ces murets, on tirait d'une porte
	# jusqu'à la place sans rien pour se couvrir en chemin, et la porte
	# devenait un poste de tir au lieu d'une entrée.
	{"pos": Vector2(6.0, -27.0), "angle": 90.0, "long": 5.0},
	{"pos": Vector2(-6.0, -27.0), "angle": 90.0, "long": 5.0},
	{"pos": Vector2(27.0, 6.0), "angle": 0.0, "long": 5.0},
	{"pos": Vector2(27.0, -6.0), "angle": 0.0, "long": 5.0},
]

# --- MARGELLE DU CENTRE --------------------------------------------------
#
# Quatre arcs avec de larges brèches. Le centre doit être IDENTIFIABLE,
# pas fortifié : c'est le point le plus exposé de la carte, et il doit le
# rester. Les brèches sont ce qui permet d'y entrer, d'en sortir et d'en
# faire le tour sans jamais s'y trouver enfermé.
const ARCS_CENTRE: Array[Dictionary] = [
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 20.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 115.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 200.0, "arc": 55.0},
	{"centre": Vector2(0, 0), "rayon": 5.5, "depart": 295.0, "arc": 55.0},
]

# --- EMPILEMENTS ---------------------------------------------------------
#
# Les POCHES : du couvert plein, haut, en dehors des voies. C'est là qu'on
# se replie, et c'est ce qui donne à chaque quartier de quoi se battre
# ailleurs qu'au centre.
const _PILES_MOITIE: Array[Dictionary] = [
	{"pos": Vector2(23.0, 6.0), "type": &"caisse", "etages": 3, "angle": 0.0},
	{"pos": Vector2(6.0, 23.0), "type": &"botte", "etages": 2, "angle": 90.0},
	{"pos": Vector2(23.0, -6.0), "type": &"botte", "etages": 2, "angle": 0.0},
	{"pos": Vector2(-6.0, 23.0), "type": &"caisse", "etages": 3, "angle": 90.0},
	# Les deux qui flanquent la voie est-ouest, juste avant la place.
	{"pos": Vector2(11.0, 0.0), "type": &"caisse", "etages": 2, "angle": 0.0},
	{"pos": Vector2(15.0, -20.0), "type": &"botte", "etages": 2, "angle": 45.0},
	{"pos": Vector2(-20.0, -15.0), "type": &"caisse", "etages": 3, "angle": 0.0},
	{"pos": Vector2(0.0, 11.0), "type": &"botte", "etages": 2, "angle": 90.0},
	{"pos": Vector2(-27.0, 20.0), "type": &"caisse", "etages": 2, "angle": 45.0},
	{"pos": Vector2(-3.0, -15.0), "type": &"botte", "etages": 2, "angle": 0.0},
]

# --- BARRIÈRES DE BOIS ---------------------------------------------------
#
# LES CORRALS. Trois segments par enclos, ouverts d'un côté : ils arrêtent
# le corps mais laissent VOIR au travers — le seul couvert de la carte
# qu'on peut tenir sans perdre l'adversaire de vue.
const _BARRIERES_MOITIE: Array[Dictionary] = [
	{"pos": Vector2(-25.0, -9.0), "angle": 0.0, "long": 7.0},
	{"pos": Vector2(-28.0, -5.0), "angle": 90.0, "long": 6.0},
	{"pos": Vector2(-21.0, -5.0), "angle": 90.0, "long": 6.0},
]

# --- CHARIOTS ------------------------------------------------------------
#
# Deux, pas plus. C'est la silhouette la plus reconnaissable du décor —
# donc un repère d'orientation — et elle perdrait ce rôle répétée dix fois.
# Un par voie nord-sud, à l'entrée de la place.
const _CHARIOTS_MOITIE: Array[Dictionary] = [
	{"pos": Vector2(0.0, -21.0), "angle": 0.0},
]

# --- PETIT COUVERT -------------------------------------------------------
#
# Tonneaux et caisses isolés. Ils ne bloquent pas la course : ils cassent
# la ligne de tir et donnent où se jeter. Ils ne comptent PAS comme couvert
# de duel — la mesure les sépare exprès.
#
# ILS SE POSENT CONTRE QUELQUE CHOSE, jamais au milieu du vide. Un tonneau
# seul en pleine plaine est le signe même de l'objet posé au hasard ; le
# même tonneau au pied d'un mur raconte qu'on l'y a rangé.
const _PETITS_MOITIE: Array[Dictionary] = [
	{"pos": Vector2(9.0, 4.0), "type": &"tonneau"},
	{"pos": Vector2(4.0, -9.0), "type": &"caisse"},
	{"pos": Vector2(20.0, 6.0), "type": &"tonneau"},
	{"pos": Vector2(6.0, 20.0), "type": &"botte"},
	{"pos": Vector2(3.0, -18.0), "type": &"caisse"},
	{"pos": Vector2(18.0, 3.0), "type": &"tonneau"},
	{"pos": Vector2(-23.0, -11.0), "type": &"botte"},
	# ÉCARTÉE DU BASTION : à (13 · 13) la caisse tombait sur la pointe de
	# la crête diagonale et bouchait le seul côté par lequel on en faisait
	# le tour.
	{"pos": Vector2(12.0, 4.0), "type": &"caisse"},
]

# --- VÉGÉTATION ----------------------------------------------------------
#
# AUCUN RÔLE DE JEU, et c'est la règle : un cactus ne doit jamais arrêter
# une poursuite. Elle habille les flancs des crêtes et la clôture, JAMAIS
# les lignes de circulation.
#
# ELLE EST SYMÉTRIQUE ELLE AUSSI, alors qu'elle n'a aucune conséquence sur
# l'équité. C'est un choix de LECTURE : une carte dont le décor est
# symétrique et le gameplay symétrique se lit comme un lieu construit ;
# mélanger les deux redonne l'impression de semis qu'on vient de retirer.
const _VEGETATION_MOITIE: Array[Dictionary] = [
	{"pos": Vector2(33.0, 8.0), "type": &"cactus"},
	{"pos": Vector2(8.0, 33.0), "type": &"cactus"},
	{"pos": Vector2(33.0, -8.0), "type": &"cactus"},
	{"pos": Vector2(-8.0, 33.0), "type": &"cactus"},
	{"pos": Vector2(27.0, 27.0), "type": &"cactus"},
	{"pos": Vector2(27.0, -27.0), "type": &"cactus"},
	{"pos": Vector2(21.0, 13.0), "type": &"buisson"},
	{"pos": Vector2(13.0, 21.0), "type": &"buisson"},
	{"pos": Vector2(21.0, -13.0), "type": &"buisson"},
	{"pos": Vector2(-13.0, 21.0), "type": &"buisson"},
	{"pos": Vector2(30.0, 2.0), "type": &"buisson"},
	{"pos": Vector2(2.0, 30.0), "type": &"buisson"},
	{"pos": Vector2(12.0, 8.0), "type": &"buisson"},
	{"pos": Vector2(8.0, -12.0), "type": &"buisson"},
]

# --- APPARITIONS ---------------------------------------------------------
#
# DIX POINTS, TOUS SUR LA PÉRIPHÉRIE, et symétriques deux à deux comme le
# reste : quatre aux portes cardinales, quatre dans les poches diagonales,
# deux sur les flancs nord et sud.
#
# AUCUN N'A DE LIGNE DE TIR SUR LE CENTRE : les crêtes d'approche et les
# murs de porte s'interposent. Naître à découvert face au point le plus
# fréquenté de la carte, c'est naître mort — et sur une carte à
# réapparition permanente, ce défaut se paie dix fois par minute.
const _APPARITIONS_MOITIE: Array[Vector2] = [
	# CINQ POINTS RÉGULIÈREMENT ESPACÉS SUR L'ANNEAU, à trente mètres du
	# centre et trente-six degrés l'un de l'autre. Leurs cinq jumeaux par
	# demi-tour complètent le tour.
	#
	# LA RÉGULARITÉ EST LE RÉGLAGE, pas une coquetterie. Posés à la main,
	# deux d'entre eux se retrouvaient à dix mètres : deux joueurs servis
	# coup sur coup se voyaient avant d'avoir fait trois pas. Sur un cercle
	# de trente mètres, dix points également répartis sont à dix-huit
	# mètres les uns des autres — le problème disparaît par construction.
	#
	# Les angles choisis — 18°, 54°, 90°, 126°, 162° — évitent les
	# diagonales, où sont les bastions, et gardent le point cardinal nord
	# libre : c'est la porte.
	Vector2(29.0, 9.0),
	Vector2(18.0, 24.0),
	Vector2(0.0, 30.0),
	Vector2(-18.0, 24.0),
	Vector2(-29.0, 9.0),
]

# --- LE MIROIR -----------------------------------------------------------

## Les tableaux complets, engendrés une fois au chargement de la classe.
static var FORMATIONS: Array[Dictionary] = []
static var MURS: Array[Dictionary] = []
static var PILES: Array[Dictionary] = []
static var BARRIERES: Array[Dictionary] = []
static var CHARIOTS: Array[Dictionary] = []
static var PETITS: Array[Dictionary] = []
static var VEGETATION: Array[Dictionary] = []
static var APPARITIONS: Array[Vector2] = []


## POURQUOI UN DEMI-TOUR ET NON UN MIROIR D'AXE. Une symétrie d'axe rend
## deux moitiés qui se font FACE : les deux camps voient la même chose au
## même endroit, et la carte prend un « haut » et un « bas ». Le demi-tour,
## lui, rend une carte qui a la même allure quel que soit le côté d'où on
## l'aborde — c'est ce qu'il faut pour un affrontement sans camps.
static func _static_init() -> void:
	for e in _FORMATIONS_MOITIE:
		FORMATIONS.append(e)
		FORMATIONS.append(_tourner(e))
	for e in _MURS_MOITIE:
		MURS.append(e)
		MURS.append(_tourner(e))
	for e in _PILES_MOITIE:
		PILES.append(e)
		PILES.append(_tourner(e))
	for e in _BARRIERES_MOITIE:
		BARRIERES.append(e)
		BARRIERES.append(_tourner(e))
	for e in _CHARIOTS_MOITIE:
		CHARIOTS.append(e)
		CHARIOTS.append(_tourner(e))
	for e in _PETITS_MOITIE:
		PETITS.append(e)
		PETITS.append(_tourner(e))
	for e in _VEGETATION_MOITIE:
		VEGETATION.append(e)
		VEGETATION.append(_tourner(e))
	for p: Vector2 in _APPARITIONS_MOITIE:
		APPARITIONS.append(p)
		APPARITIONS.append(-p)


## Un demi-tour autour du centre : la position s'inverse, et l'angle prend
## cent quatre-vingts degrés. Sur une pièce symétrique par rapport à son
## propre axe — un mur, une crête — l'angle pourrait rester tel quel ; on
## l'ajoute quand même, parce que les pièces qui ne le sont pas (le
## chariot, dont l'avant et l'arrière diffèrent) doivent tourner pour de
## bon, et qu'une règle unique vaut mieux qu'une exception à retenir.
static func _tourner(e: Dictionary) -> Dictionary:
	var d := e.duplicate()
	d["pos"] = -(e["pos"] as Vector2)
	if e.has("angle"):
		d["angle"] = fmod(float(e["angle"]) + 180.0, 360.0)
	return d


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


## Le contour de l'enceinte, en `n` points, pour bâtir la clôture.
static func contour(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var noyau := BORD - CONGE
	for i in n:
		var a := TAU * float(i) / float(n)
		# On tire un rayon depuis le centre et on cherche où il sort. La
		# forme est convexe, donc une recherche par dichotomie converge
		# vite et sans cas particulier aux jonctions droite/arrondi.
		var d := Vector2(cos(a), sin(a))
		var bas := 0.0
		var haut := BORD * 1.5
		for pas in 24:
			var m := (bas + haut) * 0.5
			if dans_enceinte(d * m):
				bas = m
			else:
				haut = m
		out.append(d * bas)
	return out


## Toutes les masses susceptibles de bloquer une poursuite, avec leur
## emprise. Sert au banc de contournabilité et au calcul des dégagements.
##
## Les crêtes sont rendues par leur DEMI-LONGUEUR, leur DEMI-LARGEUR et
## leur axe : un rayon unique mentirait dans les deux sens à la fois, trop
## grand en travers et trop petit dans l'axe.
static func masses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in FORMATIONS:
		out.append({"pos": f["pos"], "demi": Vector2(
				float(f["long"]) * 0.5, float(f["large"]) * 0.5),
				"angle": deg_to_rad(float(f["angle"])), "nom": "crête"})
	for c: Dictionary in CHARIOTS:
		out.append({"pos": c["pos"], "demi": Vector2(2.3, 1.3),
				"angle": deg_to_rad(float(c["angle"])), "nom": "chariot"})
	return out


## Rayon d'encombrement d'une masse — la plus grande distance de son centre
## à son bord. Utile là où seule une borne grossière est demandée.
static func rayon_masse(m: Dictionary) -> float:
	return (m["demi"] as Vector2).length()


## Distance du point `p` au bord de la masse `m`, zéro s'il est dedans.
static func ecart_masse(p: Vector2, m: Dictionary) -> float:
	var d: Vector2 = p - (m["pos"] as Vector2)
	var a: float = m["angle"]
	var loc := Vector2(d.x * cos(a) + d.y * sin(a),
			-d.x * sin(a) + d.y * cos(a))
	var demi: Vector2 = m["demi"]
	var dehors := Vector2(maxf(absf(loc.x) - demi.x, 0.0),
			maxf(absf(loc.y) - demi.y, 0.0))
	return dehors.length()
