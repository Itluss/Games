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

# --- FORMATIONS ROCHEUSES ------------------------------------------------
#
# LES ÎLOTS DE GAMEPLAY, et désormais des CRÊTES et non des disques.
#
# `long` est la dimension dans l'axe, `large` en travers, `angle` en degrés
# (0 = axe est-ouest). L'arène en pose une couronne extérieure dans les
# coins et le long des bords, une couronne intérieure décalée en angle, et
# deux petites crêtes près du centre pour qu'il ne soit pas une plaine.
#
# AUCUN ANGLE N'EST RÉPÉTÉ D'UNE CRÊTE À L'AUTRE. C'est ce qui empêche la
# carte de se lire comme une grille : deux crêtes parallèles font un
# couloir, deux crêtes croisées font une poche à contourner.
const FORMATIONS: Array[Dictionary] = [
	# Couronne extérieure — les coins d'abord, c'est là que la maquette met
	# ses plus grosses masses et c'est là que le carré arrondi ouvre de
	# l'espace neuf.
	{"pos": Vector2(-21.0, -22.0), "long": 8.5, "large": 3.8,
		"angle": 12.0, "hauteur": H_CRETE},
	{"pos": Vector2(2.0, -25.0), "long": 7.0, "large": 3.4,
		"angle": 0.0, "hauteur": H_CRETE},
	{"pos": Vector2(22.0, -22.0), "long": 10.0, "large": 4.4,
		"angle": -14.0, "hauteur": H_CRETE},
	{"pos": Vector2(30.0, -4.0), "long": 8.0, "large": 4.0,
		"angle": 78.0, "hauteur": H_CRETE},
	{"pos": Vector2(25.0, 18.0), "long": 9.5, "large": 4.6,
		"angle": 20.0, "hauteur": H_CRETE},
	{"pos": Vector2(5.0, 27.0), "long": 7.5, "large": 3.6,
		"angle": -6.0, "hauteur": H_CRETE},
	{"pos": Vector2(-20.0, 25.0), "long": 11.0, "large": 4.8,
		"angle": 8.0, "hauteur": H_CRETE},
	{"pos": Vector2(-30.0, 6.0), "long": 8.5, "large": 4.2,
		"angle": 96.0, "hauteur": H_CRETE},
	# Couronne intérieure — décalée en angle pour que les couloirs radiaux
	# ne s'alignent jamais avec ceux de l'extérieur.
	{"pos": Vector2(-13.0, -12.0), "long": 7.0, "large": 3.6,
		"angle": 28.0, "hauteur": H_CRETE},
	{"pos": Vector2(9.0, -14.0), "long": 6.0, "large": 3.2,
		"angle": -22.0, "hauteur": H_CRETE},
	{"pos": Vector2(16.0, 6.0), "long": 7.5, "large": 3.8,
		"angle": 62.0, "hauteur": H_CRETE},
	{"pos": Vector2(-4.0, 16.0), "long": 6.5, "large": 3.4,
		"angle": -12.0, "hauteur": H_CRETE},
	{"pos": Vector2(-16.0, 4.0), "long": 6.0, "large": 3.2,
		"angle": 74.0, "hauteur": H_CRETE},
	# Deux crêtes MOYENNES près du centre. Elles ne cachent pas un joueur
	# debout — on voit sa tête — mais elles cassent le tir tendu et donnent
	# de quoi prendre un angle. Le centre doit rester le point le plus
	# exposé de la carte, pas une plaine nue.
	{"pos": Vector2(7.5, 9.5), "long": 4.5, "large": 2.6,
		"angle": 40.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(-8.1, -6.6), "long": 4.5, "large": 2.6,
		"angle": -50.0, "hauteur": H_CRETE_M},
	# ─── HUIT CRÊTES MOYENNES DE PLUS ──────────────────────────────────
	#
	# LEURS COORDONNÉES SONT LE RÉSULTAT D'UN RELAXEUR, PAS D'UN COUP D'ŒIL.
	# Posées à la main, sept masses sur vingt-trois n'avaient plus l'anneau
	# libre exigé — quatre d'entre elles parce que leur anneau sortait de la
	# clôture, donc qu'on ne pouvait plus passer entre elles et la barrière.
	# Un petit programme les a écartées par montée de colline, en
	# n'acceptant un pas que s'il améliore vraiment l'anneau. Sa première
	# version ne bougeait rien : elle refusait tout pas qui ne tenait pas
	# dans une enceinte rétrécie, or les quatre masses coincées échouaient
	# déjà ce test là où elles étaient.
	#
	# La consigne est explicite : « privilégier davantage de formations
	# moyennes plutôt que quelques masses géantes ». Celles-ci bouchent
	# les trous relevés par la mesure — le pire était à dix mètres de tout
	# couvert de duel, dans le coin sud-ouest — sans ajouter une seule
	# masse qui mange l'écran. Hauteur moyenne : on voit la tête de
	# l'adversaire par-dessus, donc on ne le perd pas, mais le tir tendu
	# est coupé.
	{"pos": Vector2(-24.2, -28.9), "long": 5.5, "large": 3.0,
		"angle": 25.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(12.0, -30.0), "long": 5.0, "large": 2.8,
		"angle": -35.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(30.6, -19.0), "long": 5.5, "large": 3.0,
		"angle": 100.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(15.7, 30.3), "long": 5.5, "large": 3.0,
		"angle": 15.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(-30.6, -14.5), "long": 5.0, "large": 2.8,
		"angle": 70.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(-27.8, 28.1), "long": 5.5, "large": 3.0,
		"angle": 45.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(22.4, -4.8), "long": 5.0, "large": 2.8,
		"angle": 130.0, "hauteur": H_CRETE_M},
	{"pos": Vector2(-20.0, -3.9), "long": 5.0, "large": 2.8,
		"angle": 20.0, "hauteur": H_CRETE_M},
]

# --- MURS DE PIERRE BAS --------------------------------------------------
#
# COUVERT MOYEN, ET SURTOUT BRISEUR DE LIGNE DE TIR. La maquette les montre
# DROITS et courts, posés en travers des ouvertures — pas en arcs. Un mur
# droit de six à huit mètres ne fait pas un corridor tant qu'on peut passer
# des deux côtés ; c'est la longueur qui crée le corridor, pas la forme.
const MURS: Array[Dictionary] = [
	{"pos": Vector2(-9.5, 2.0), "angle": 100.0, "long": 7.0},
	{"pos": Vector2(8.0, -2.0), "angle": 80.0, "long": 6.0},
	{"pos": Vector2(-24.0, 0.0), "angle": 5.0, "long": 8.0},
	{"pos": Vector2(12.5, 13.5), "angle": 55.0, "long": 7.0},
	{"pos": Vector2(-2.0, 9.5), "angle": 0.0, "long": 6.0},
	{"pos": Vector2(-14.5, -18.0), "angle": 40.0, "long": 6.5},
	{"pos": Vector2(18.5, -8.0), "angle": 120.0, "long": 6.0},
	{"pos": Vector2(-8.5, 30.0), "angle": 10.0, "long": 7.0},
	{"pos": Vector2(28.0, -14.0), "angle": 60.0, "long": 6.0},
	{"pos": Vector2(-28.5, -9.0), "angle": 85.0, "long": 6.5},
	{"pos": Vector2(17.0, 28.5), "angle": 165.0, "long": 6.5},
	{"pos": Vector2(-1.0, -19.0), "angle": 95.0, "long": 5.5},
	{"pos": Vector2(-19.5, 30.5), "angle": 70.0, "long": 6.0},
	{"pos": Vector2(9.5, -25.5), "angle": 25.0, "long": 6.0},
	{"pos": Vector2(31.5, 9.0), "angle": 110.0, "long": 6.0},
	{"pos": Vector2(-33.0, 24.0), "angle": 30.0, "long": 5.5},
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
# LE COUVERT QUI MANQUAIT. Une caisse seule fait quatre-vingt-dix
# centimètres : on la voit à peine et on ne s'y bat pas. Empilées par deux
# ou trois, les mêmes caisses font deux mètres, se voient de loin sur un
# téléphone, et donnent un vrai duel — c'est exactement ce que montre la
# maquette, et c'est le niveau de couvert qui manquait entre le tonneau et
# la falaise.
#
# `etages` dit la hauteur, `type` le modèle. Chaque pile est posée PRÈS
# d'une crête ou d'un mur : la maquette ne pose presque jamais un couvert
# tout seul au milieu du sable.
const PILES: Array[Dictionary] = [
		# ÉCARTÉE APRÈS MESURE : à (-16,5 · -8) elle tombait pile sur l'anneau
	# de dégagement de la crête voisine, qui n'était plus contournable
	# qu'aux trois quarts — juste au seuil.
	{"pos": Vector2(-16.1, -6.7), "type": &"caisse", "etages": 3, "angle": 15.0},
	{"pos": Vector2(4.5, -8.5), "type": &"botte", "etages": 2, "angle": 40.0},
	{"pos": Vector2(19.5, -12.0), "type": &"caisse", "etages": 3, "angle": -25.0},
	{"pos": Vector2(26.5, 2.0), "type": &"botte", "etages": 2, "angle": 70.0},
	{"pos": Vector2(13.0, 20.0), "type": &"caisse", "etages": 3, "angle": 10.0},
	{"pos": Vector2(-2.0, 22.0), "type": &"botte", "etages": 2, "angle": -35.0},
	{"pos": Vector2(-24.5, 15.0), "type": &"caisse", "etages": 3, "angle": 55.0},
	{"pos": Vector2(-11.0, -25.5), "type": &"botte", "etages": 2, "angle": 20.0},
	{"pos": Vector2(10.5, 3.5), "type": &"caisse", "etages": 2, "angle": -60.0},
	{"pos": Vector2(-6.5, -16.0), "type": &"caisse", "etages": 2, "angle": 85.0},
	{"pos": Vector2(30.8, 24.2), "type": &"botte", "etages": 2, "angle": 30.0},
	{"pos": Vector2(-29.0, -19.6), "type": &"caisse", "etages": 2, "angle": -15.0},
	{"pos": Vector2(21.5, -30.0), "type": &"botte", "etages": 2, "angle": 60.0},
	{"pos": Vector2(-20.6, 30.6), "type": &"caisse", "etages": 2, "angle": -40.0},
	{"pos": Vector2(-4.5, -11.5), "type": &"botte", "etages": 2, "angle": 25.0},
	{"pos": Vector2(17.9, 14.0), "type": &"caisse", "etages": 3, "angle": -20.0},
	{"pos": Vector2(-15.2, 19.3), "type": &"botte", "etages": 2, "angle": 65.0},
	{"pos": Vector2(6.1, -18.1), "type": &"caisse", "etages": 2, "angle": 45.0},
	{"pos": Vector2(-31.6, 20.1), "type": &"botte", "etages": 2, "angle": -10.0},
	{"pos": Vector2(26.1, -27.6), "type": &"caisse", "etages": 3, "angle": 35.0},
]

# --- BARRIÈRES DE BOIS ---------------------------------------------------
#
# La clôture périphérique est bâtie à part. Celles-ci sont les refends
# INTÉRIEURS : de courts segments qui découpent les grandes ouvertures sans
# jamais fermer un passage. Elles arrêtent le corps mais laissent VOIR au
# travers — le seul couvert de la carte qu'on peut tenir sans perdre
# l'adversaire de vue.
const BARRIERES: Array[Dictionary] = [
	{"pos": Vector2(-19.0, -15.5), "angle": 35.0, "long": 6.0},
	{"pos": Vector2(8.5, -20.0), "angle": 110.0, "long": 5.5},
	{"pos": Vector2(25.5, 11.0), "angle": 70.0, "long": 6.5},
	{"pos": Vector2(-8.0, 24.5), "angle": 15.0, "long": 6.0},
	{"pos": Vector2(-27.5, 21.0), "angle": 125.0, "long": 5.5},
	{"pos": Vector2(20.0, -31.0), "angle": 160.0, "long": 6.0},
	{"pos": Vector2(-3.5, 4.0), "angle": 130.0, "long": 5.0},
	{"pos": Vector2(14.5, -4.0), "angle": 20.0, "long": 5.5},
	{"pos": Vector2(-21.5, 8.5), "angle": 150.0, "long": 5.5},
	{"pos": Vector2(3.0, 15.5), "angle": 75.0, "long": 5.0},
	{"pos": Vector2(-31.0, -25.0), "angle": 45.0, "long": 6.0},
	{"pos": Vector2(31.5, 30.0), "angle": 135.0, "long": 6.0},
]

# --- CHARIOTS ------------------------------------------------------------
#
# Trois, pas plus. C'est la silhouette la plus reconnaissable de la
# planche — donc un repère d'orientation — et elle perdrait ce rôle
# répétée dix fois.
const CHARIOTS: Array[Dictionary] = [
	{"pos": Vector2(-27.5, -6.0), "angle": 20.0},
	{"pos": Vector2(2.5, 18.5), "angle": 100.0},
	{"pos": Vector2(27.0, 27.5), "angle": 200.0},
]

# --- PETIT COUVERT -------------------------------------------------------
#
# Tonneaux et caisses isolés. Ils ne bloquent pas la course : ils cassent
# la ligne de tir et donnent où se jeter. Ils ne comptent PAS comme couvert
# de duel — la mesure les sépare exprès, parce que les confondre est
# exactement ce qui avait fait croire la V1 dense.
const PETITS: Array[Dictionary] = [
	{"pos": Vector2(-6.5, -3.0), "type": &"caisse"},
	{"pos": Vector2(5.0, -5.0), "type": &"tonneau"},
	{"pos": Vector2(2.5, 6.5), "type": &"botte"},
	{"pos": Vector2(-7.5, 7.0), "type": &"caisse"},
	{"pos": Vector2(-19.0, -1.5), "type": &"botte"},
	{"pos": Vector2(20.5, 1.5), "type": &"tonneau"},
	{"pos": Vector2(-3.0, -22.0), "type": &"caisse"},
	{"pos": Vector2(-0.5, 25.5), "type": &"tonneau"},
	{"pos": Vector2(-23.0, -26.0), "type": &"botte"},
	{"pos": Vector2(15.0, -26.5), "type": &"caisse"},
	{"pos": Vector2(32.0, -10.0), "type": &"tonneau"},
	# ÉCARTÉE APRÈS MESURE : l'empilement voisin, déplacé par le relaxeur,
	# est venu se poser dessus.
	{"pos": Vector2(-33.5, 16.5), "type": &"botte"},
	{"pos": Vector2(9.0, 31.0), "type": &"caisse"},
	{"pos": Vector2(-14.0, -31.5), "type": &"tonneau"},
	{"pos": Vector2(29.5, -25.0), "type": &"botte"},
	{"pos": Vector2(-26.5, -13.0), "type": &"caisse"},
	{"pos": Vector2(23.5, 32.0), "type": &"tonneau"},
	{"pos": Vector2(-6.5, 33.0), "type": &"botte"},
	{"pos": Vector2(18.0, 15.5), "type": &"tonneau"},
	{"pos": Vector2(-17.5, 19.0), "type": &"caisse"},
]

# --- VÉGÉTATION ----------------------------------------------------------
#
# AUCUN RÔLE DE JEU, et c'est la règle : un cactus ne doit jamais arrêter
# une poursuite. Mais la maquette en met PARTOUT, en touffes, et assez
# hauts pour se lire — c'est une bonne part de ce qui remplit son écran.
#
# On en pose donc trois fois plus qu'en V1, en touffes contre les crêtes et
# le long de la clôture, JAMAIS dans les lignes de circulation. La consigne
# est claire : « davantage de gameplay, pas davantage de bruit visuel » —
# aussi la végétation ne bouche jamais un passage, elle habille les flancs.
const VEGETATION: Array[Dictionary] = [
	{"pos": Vector2(-25.0, -19.0), "type": &"cactus"},
	{"pos": Vector2(-16.5, -25.0), "type": &"cactus"},
	{"pos": Vector2(6.5, -21.0), "type": &"buisson"},
	{"pos": Vector2(-1.0, -29.5), "type": &"cactus"},
	{"pos": Vector2(17.0, -18.5), "type": &"cactus"},
	{"pos": Vector2(27.5, -26.0), "type": &"buisson"},
	{"pos": Vector2(33.5, -6.0), "type": &"cactus"},
	{"pos": Vector2(26.0, -1.5), "type": &"cactus"},
	{"pos": Vector2(30.0, 12.0), "type": &"buisson"},
	{"pos": Vector2(20.5, 22.5), "type": &"cactus"},
	{"pos": Vector2(29.5, 31.5), "type": &"cactus"},
	{"pos": Vector2(10.0, 24.5), "type": &"buisson"},
	{"pos": Vector2(0.5, 31.5), "type": &"cactus"},
	{"pos": Vector2(-13.5, 27.5), "type": &"cactus"},
	{"pos": Vector2(-24.0, 29.5), "type": &"buisson"},
	{"pos": Vector2(-31.5, 12.5), "type": &"cactus"},
	{"pos": Vector2(-33.5, 1.0), "type": &"cactus"},
	{"pos": Vector2(-26.0, 6.5), "type": &"buisson"},
	{"pos": Vector2(-18.5, 9.5), "type": &"cactus"},
	{"pos": Vector2(-11.5, -16.5), "type": &"cactus"},
	{"pos": Vector2(12.5, -10.5), "type": &"buisson"},
	{"pos": Vector2(19.0, 9.5), "type": &"cactus"},
	{"pos": Vector2(-6.5, 18.5), "type": &"cactus"},
	{"pos": Vector2(8.5, 13.0), "type": &"buisson"},
	{"pos": Vector2(-13.0, -3.0), "type": &"cactus"},
	{"pos": Vector2(14.0, 1.0), "type": &"buisson"},
	{"pos": Vector2(-4.5, -12.5), "type": &"cactus"},
	# ÉCARTÉ APRÈS MESURE : le relaxeur a fait glisser la crête moyenne
	# voisine jusque sur lui, et le cactus poussait dans le rocher.
	{"pos": Vector2(25.0, -9.0), "type": &"cactus"},
	{"pos": Vector2(-21.0, 18.5), "type": &"buisson"},
	{"pos": Vector2(5.5, 20.0), "type": &"cactus"},
	{"pos": Vector2(-29.0, -13.5), "type": &"cactus"},
	{"pos": Vector2(24.5, -16.0), "type": &"buisson"},
	{"pos": Vector2(-9.5, -30.0), "type": &"cactus"},
	{"pos": Vector2(4.0, -33.0), "type": &"cactus"},
	{"pos": Vector2(19.5, -33.0), "type": &"buisson"},
	{"pos": Vector2(33.0, -30.0), "type": &"cactus"},
	{"pos": Vector2(34.5, 16.0), "type": &"cactus"},
	{"pos": Vector2(25.0, 33.0), "type": &"buisson"},
	{"pos": Vector2(9.5, 34.0), "type": &"cactus"},
	{"pos": Vector2(-6.0, 30.0), "type": &"cactus"},
	{"pos": Vector2(-24.0, 33.5), "type": &"buisson"},
	{"pos": Vector2(-34.0, 26.0), "type": &"cactus"},
	{"pos": Vector2(-34.5, -20.0), "type": &"cactus"},
	{"pos": Vector2(-21.0, -33.0), "type": &"buisson"},
	{"pos": Vector2(2.5, 3.0), "type": &"cactus"},
	{"pos": Vector2(-3.5, -3.5), "type": &"buisson"},
	{"pos": Vector2(16.5, -16.5), "type": &"cactus"},
	{"pos": Vector2(-25.0, 4.5), "type": &"cactus"},
]

# --- APPARITIONS ---------------------------------------------------------
#
# DIX POINTS, TOUS SUR LA PÉRIPHÉRIE.
#
# AUCUN N'A DE LIGNE DE TIR SUR LE CENTRE, et c'est vérifié par le banc :
# chacun est posé de sorte qu'une crête ou un mur s'interpose. Naître à
# découvert face au point le plus fréquenté de la carte, c'est naître mort
# — et sur une carte à réapparition permanente, ce défaut se paie dix fois
# par minute.
#
# L'ordre ALTERNE d'un bord à l'autre plutôt que de tourner : deux joueurs
# servis à la suite se retrouvent à l'opposé, jamais côte à côte.
const APPARITIONS: Array[Vector2] = [
	Vector2(-5.0, -32.5),
	Vector2(6.0, 32.5),
	Vector2(-32.5, -3.0),
	Vector2(32.5, 4.0),
	Vector2(-28.0, -27.0),
	# DÉPLACÉE APRÈS MESURE : à (29 · 26) elle naissait à quatre-vingts
	# centimètres du chariot, donc coincée contre lui.
	Vector2(32.5, 22.0),
	# DÉPLACÉE APRÈS MESURE : la pile voisine, écartée par le relaxeur,
	# est venue se poser à soixante centimètres.
	Vector2(29.0, -30.0),
	# DÉPLACÉE APRÈS MESURE : le relaxeur a fait glisser la crête moyenne du
	# coin sud-ouest jusqu'à (-27,8 · 28,1), pile sur elle. Une apparition
	# ne se défend pas contre un déplacement de décor : c'est à elle de
	# céder la place.
	Vector2(-34.0, 13.0),
	Vector2(15.0, -32.5),
	# DÉPLACÉE APRÈS MESURE : elle n'était qu'à 11,7 m de sa voisine du
	# coin sud-ouest, sous le seuil de douze mètres.
	Vector2(-13.0, 32.5),
]


## L'ENCEINTE EST-ELLE FRANCHIE ?
##
## Carré aux angles arrondis : on replie le point dans le premier quadrant,
## puis on ne teste l'arrondi que dans le coin. `marge` rétrécit l'enceinte
## — c'est ainsi qu'on demande « à l'intérieur, mais pas collé au bord ».
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
