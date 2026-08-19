extends RefCounted
class_name PlanAreneTest
## ARÈNE DE COMBAT — composition MANUELLE, 40 × 40 m.
##
## ─── POURQUOI CE FICHIER EXISTE À CÔTÉ DU MONDE ─────────────────────────
##
## Le monde ouvert est SEMÉ : une grille parcourt le carré, tire un dé par
## point et pose un prop selon la densité du secteur. C'est la bonne
## méthode pour 144 × 144 m — personne ne place vingt mille objets à la
## main — mais elle ne produit pas du level design. Elle produit une
## répartition. Un semis ne saura jamais qu'un couvert doit être
## CONTOURNABLE, qu'un passage doit avoir deux issues, ou qu'on ne met rien
## de haut au milieu d'une place.
##
## Ce plan-ci est écrit à la main, position par position, pour tester le
## COMBAT. Chaque objet y répond à une question de jeu : couper une ligne
## de tir, offrir un tour à faire, marquer une direction. Aucun n'est là
## pour faire joli.
##
## ─── LA RÈGLE QUI COMMANDE TOUT : LA CAMÉRA ─────────────────────────────
##
## La caméra est à 10,4 m au-dessus du joueur, reculée de 8 m, ouverte à
## 58°. Elle voit donc une bande d'environ 22 m de large. Trois
## conséquences, et elles décident de tout le reste :
##
##   1. UN OBJET DE PLUS DE 2 M REMPLIT L'ÉCRAN quand on passe à côté.
##      Les hauts sont donc RARES et repoussés vers les bords.
##   2. ON VOIT LE DESSUS DES CHOSES. Un couvert se lit par son emprise au
##      sol, pas par sa façade. D'où des masses larges et basses.
##   3. LA MOITIÉ DE L'ARÈNE EST HORS CHAMP. Il faut des repères hauts pour
##      savoir où l'on est — mais deux suffisent, et sur les bords.
##
## ─── LE PLAN ────────────────────────────────────────────────────────────
##
##            NORD  (z négatif)
##     ┌──────────────────────────────┐
##     │  BASTION NO   passe   BASTION NE│
##     │     ▟▙        étroite     ▟▙    │
##     │            ╲     ╱              │
##  O  │  route   ── PLACE CENTRALE ──  route │  E
##     │  ouverte      (dégagée)      ouverte │
##     │            ╱     ╲              │
##     │     ▟▙        passe       ▟▙    │
##     │  BASTION SO   étroite  BASTION SE│
##     └──────────────────────────────┘
##            SUD  (z positif)
##
## Quatre bastions en diagonale, une place au milieu, deux passes étroites
## (nord et sud) et deux routes larges (est et ouest). De n'importe quel
## bastion on atteint les deux voisins par deux chemins différents : aucun
## joueur ne peut fermer la carte en tenant un seul point.

## Côté de l'arène, en mètres.
const COTE := 40.0
const DEMI := COTE * 0.5

## Rayon de la place centrale. Rien de solide à l'intérieur au-delà des
## trois petits couverts déclarés plus bas.
const RAYON_PLACE := 7.0

## ─── OFFSET ANTI-SCINTILLEMENT ──────────────────────────────────────────
##
## LE DÉFAUT QUE CECI CORRIGE. Un prop dont la face inférieure est plate et
## posée EXACTEMENT à y = 0 est coplanaire avec le sol. Les deux surfaces
## se disputent alors le même pixel, et laquelle gagne dépend de l'erreur
## d'arrondi de la profondeur, donc de l'angle de la caméra : le prop
## clignote dès qu'on bouge. C'est invisible sur une capture fixe et
## insupportable en jeu.
##
## Douze millimètres suffisent à les départager, et sont sous le seuil du
## visible : personne ne voit un conteneur flotter d'un centimètre vu de
## dix mètres de haut.
const LEVEE := 0.012

## ─── VOCABULAIRE DE COUVERTS ────────────────────────────────────────────
##
## Chaque modèle Meshy est normalisé à 1,90 par son plus grand côté : les
## dimensions livrées ne disent donc rien de la taille, seulement de la
## PROPORTION. C'est elle qui décide du rôle, et c'est PropKit qui remet
## chaque pièce à la taille déclarée ici.
##
##   barriere    1,90 × 1,15 × 0,76  long et bas   → couvert linéaire bas
##   passerelle  1,90 × 1,14 × 0,72  idem          → couvert linéaire bas
##   debris      1,89 × 1,12 × 1,72  large et bas  → couvert d'angle bas
##   ventilation 1,78 × 1,32 × 1,78  carré bas     → couvert isolé bas
##   conteneur   1,11 × 1,11 × 1,90  long, mi-haut → mur de passe
##   bloc        1,90 × 1,90 × 1,47  cube mi-haut  → pivot de bastion
##   caisses     0,85 × 1,90 × 0,85  pile étroite  → couvert mi-haut étroit
##   generateur  1,01 × 1,90 × 1,02  boîte haute   → couvert mi-haut
##   kiosque     1,29 × 1,59 × 1,90  masse bâtie   → cœur de bastion
##   tour/pylone 1,00 × 1,90 × 0,95  vertical      → REPÈRE, aux bords
##   plante / debris / borne / lampadaire / panneau → décor, jamais bloquant

## HAUTEURS, ET LA RÈGLE DES 80 %.
##
## BAS   ≤ 1,20 m — on tire par-dessus, on voit le combat par-dessus.
## MI    ≤ 2,10 m — coupe la ligne de tir debout, ne cache pas l'écran.
## HAUT  > 3,00 m — deux exemplaires sur toute la carte, aux bords.
const H_BAS := 1.15
const H_MI := 2.05

# --- COUVERTS DE GAMEPLAY ------------------------------------------------
#
# `pos` est en mètres, origine au centre de l'arène, z négatif vers le
# nord. `taille` est le volume DEMANDÉ : PropKit y fait tenir le modèle.
#
# LES QUATRE BASTIONS SONT DES « L », PAS DES TAS. Un tas d'objets se
# contourne par l'extérieur et ne sert à rien ; un L a un intérieur, donc
# un dedans et un dehors, donc un tour à faire et un angle à surprendre.
# C'est la forme la plus rentable en level design : deux segments, quatre
# façons de l'aborder.
const COUVERTS: Array[Dictionary] = [

	# ═══ BASTION NORD-OUEST ═══ (-11, -11) — le L ouvre vers la place.
	{"modele": &"deco_kiosque", "pos": Vector2(-12.6, -12.6), "rot": 0.78,
		"taille": Vector3(3.0, H_MI, 4.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(-8.6, -13.4), "rot": 0.10,
		"taille": Vector3(1.9, H_MI, 3.6)},
	{"modele": &"deco_bloc", "pos": Vector2(-13.6, -8.4), "rot": 0.42,
		"taille": Vector3(2.1, H_MI, 1.7)},
	{"modele": &"deco_barriere", "pos": Vector2(-9.4, -9.0), "rot": 2.36,
		"taille": Vector3(3.2, H_BAS, 0.9)},
	{"modele": &"deco_debris", "pos": Vector2(-15.4, -10.8), "rot": 1.05,
		"taille": Vector3(2.2, H_BAS, 2.0)},

	# ═══ BASTION NORD-EST ═══ (11, -11) — L miroir, décalé pour ne pas
	# faire symétrie parfaite : une carte trop régulière se devine.
	{"modele": &"deco_kiosque", "pos": Vector2(12.2, -12.0), "rot": -0.86,
		"taille": Vector3(3.0, H_MI, 4.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(8.2, -13.6), "rot": -0.16,
		"taille": Vector3(1.9, H_MI, 3.6)},
	{"modele": &"deco_generateur", "pos": Vector2(13.8, -8.0), "rot": 0.0,
		"taille": Vector3(1.5, H_MI, 1.5)},
	{"modele": &"deco_barriere", "pos": Vector2(9.0, -8.6), "rot": 0.84,
		"taille": Vector3(3.2, H_BAS, 0.9)},
	{"modele": &"deco_passerelle", "pos": Vector2(15.0, -11.4), "rot": 1.62,
		"taille": Vector3(3.0, H_BAS, 0.9)},

	# ═══ BASTION SUD-OUEST ═══ (-11, 11)
	{"modele": &"deco_kiosque", "pos": Vector2(-12.0, 12.4), "rot": 2.30,
		"taille": Vector3(3.0, H_MI, 4.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(-8.4, 13.2), "rot": -0.12,
		"taille": Vector3(1.9, H_MI, 3.6)},
	{"modele": &"deco_caisses", "pos": Vector2(-13.8, 8.4), "rot": 0.35,
		"taille": Vector3(1.3, H_MI, 1.3)},
	{"modele": &"deco_barriere", "pos": Vector2(-9.2, 8.8), "rot": -0.80,
		"taille": Vector3(3.2, H_BAS, 0.9)},
	{"modele": &"deco_debris", "pos": Vector2(-15.2, 11.0), "rot": 2.10,
		"taille": Vector3(2.2, H_BAS, 2.0)},

	# ═══ BASTION SUD-EST ═══ (11, 11)
	# DÉCALÉ APRÈS MESURE — LA RÈGLE DU SUD DÉGAGÉ.
	#
	# La caméra est toujours posée huit mètres au SUD du joueur : tout ce
	# qui se trouve juste au sud d'un endroit où l'on se tient passe entre
	# elle et lui. Ce kiosque était à (12,6 · 12,0), pile au sud de la
	# poche à (14 · 11), et le banc y a relevé le joueur masqué.
	{"modele": &"deco_kiosque", "pos": Vector2(11.4, 13.2), "rot": -2.36,
		"taille": Vector3(3.0, H_MI, 4.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(8.6, 13.4), "rot": 0.14,
		"taille": Vector3(1.9, H_MI, 3.6)},
	{"modele": &"deco_bloc", "pos": Vector2(13.4, 8.2), "rot": -0.48,
		"taille": Vector3(2.1, H_MI, 1.7)},
	{"modele": &"deco_barriere", "pos": Vector2(9.4, 9.2), "rot": 2.30,
		"taille": Vector3(3.2, H_BAS, 0.9)},
	{"modele": &"deco_passerelle", "pos": Vector2(15.2, 11.2), "rot": 1.50,
		"taille": Vector3(3.0, H_BAS, 0.9)},

	# ═══ LES DEUX PASSES ÉTROITES ═══ nord et sud, ~3,6 m de large.
	#
	# ELLES SONT COURTES — six mètres, pas quinze. Un couloir long est un
	# piège à campeur : celui qui le tient tue tout ce qui s'y engage et
	# personne ne peut le déloger. Six mètres se traversent en deux
	# secondes, et les deux bouts sont visibles depuis le milieu.
	{"modele": &"deco_conteneur", "pos": Vector2(-1.9, -15.0), "rot": 0.0,
		"taille": Vector3(1.7, H_MI, 5.0)},
	{"modele": &"deco_conteneur", "pos": Vector2(1.9, -15.0), "rot": 0.0,
		"taille": Vector3(1.7, H_MI, 5.0)},
	{"modele": &"deco_conteneur", "pos": Vector2(-1.9, 15.0), "rot": 0.0,
		"taille": Vector3(1.7, H_MI, 5.0)},
	{"modele": &"deco_conteneur", "pos": Vector2(1.9, 15.0), "rot": 0.0,
		"taille": Vector3(1.7, H_MI, 5.0)},
	# Un couvert bas à chaque sortie de passe : on débouche à couvert, pas
	# à découvert. Sortir d'un goulet dans un champ de tir découragerait de
	# s'en servir, et la passe deviendrait un décor.
	{"modele": &"deco_debris", "pos": Vector2(0.0, -11.4), "rot": 0.5,
		"taille": Vector3(2.4, H_BAS, 2.2)},
	{"modele": &"deco_debris", "pos": Vector2(0.0, 11.4), "rot": -0.7,
		"taille": Vector3(2.4, H_BAS, 2.2)},

	# ═══ LES DEUX ROUTES LARGES ═══ est et ouest, 8 m de dégagement.
	#
	# Leur intérêt de jeu est l'INVERSE de celui des passes : on y va vite
	# et on s'y expose. Elles ne portent donc que du couvert BAS, décalé de
	# l'axe, pour qu'on puisse s'y jeter sans que la route cesse d'être une
	# route.
	{"modele": &"deco_ventilation", "pos": Vector2(-16.4, -2.6), "rot": 0.3,
		"taille": Vector3(2.2, H_BAS, 2.2)},
	{"modele": &"deco_barriere", "pos": Vector2(-15.6, 2.8), "rot": 0.05,
		"taille": Vector3(3.4, H_BAS, 0.9)},
	{"modele": &"deco_ventilation", "pos": Vector2(16.4, 2.6), "rot": -0.3,
		"taille": Vector3(2.2, H_BAS, 2.2)},
	{"modele": &"deco_barriere", "pos": Vector2(15.6, -2.8), "rot": 0.05,
		"taille": Vector3(3.4, H_BAS, 0.9)},

	# ═══ LA PLACE CENTRALE ═══
	#
	# TROIS COUVERTS BAS, EN MOULINET, ET RIEN D'AUTRE.
	#
	# Ils sont décalés du centre exact : le point (0,0) reste libre. C'est
	# volontaire — c'est là que les trajectoires se croisent, et un obstacle
	# posé pile au milieu transformerait chaque passage en contournement
	# obligatoire. Disposés en moulinet, ils offrent un couvert quel que
	# soit l'angle d'où l'on est pris à partie, sans jamais fermer la vue :
	# à 1,15 m, on voit le combat par-dessus.
	{"modele": &"deco_debris", "pos": Vector2(-3.4, -2.2), "rot": 0.9,
		"taille": Vector3(2.6, H_BAS, 2.4)},
	{"modele": &"deco_debris", "pos": Vector2(3.6, -1.6), "rot": -1.9,
		"taille": Vector3(2.4, H_BAS, 2.2)},
	{"modele": &"deco_passerelle", "pos": Vector2(0.4, 3.6), "rot": 0.18,
		"taille": Vector3(3.6, H_BAS, 1.0)},
]

# --- REPÈRES -------------------------------------------------------------
#
# DEUX, PAS SIX. Un repère ne vaut que par sa rareté : s'il y en a partout,
# aucun ne dit plus où l'on est. Ils sont posés HORS des zones de combat,
# au-delà des bastions, pour qu'on les regarde sans jamais se battre
# dessous — c'est ce qui les empêche de remplir l'écran au mauvais moment.
const REPERES: Array[Dictionary] = [
	{"modele": &"deco_tour", "pos": Vector2(-17.4, -17.4), "rot": 0.55,
		"taille": Vector3(2.6, 6.4, 2.6)},
	{"modele": &"deco_pylone", "pos": Vector2(17.4, 17.4), "rot": -0.35,
		"taille": Vector3(1.7, 7.0, 1.7)},
]

# --- DÉCOR PUR -----------------------------------------------------------
#
# DIX PIÈCES, PAS UNE DE PLUS, et toutes hors des lignes de circulation.
# Elles n'ont aucun rôle de jeu : elles disent seulement que l'endroit est
# habité. La règle est simple — si l'on peut se cogner dedans en courant
# d'un bastion à l'autre, c'est qu'elle est mal placée.
const DECOR: Array[Dictionary] = [
	{"modele": &"deco_plante", "pos": Vector2(-6.2, -17.2), "rot": 0.4,
		"taille": Vector3(1.7, 1.4, 1.6)},
	{"modele": &"deco_plante", "pos": Vector2(6.6, 17.0), "rot": 2.1,
		"taille": Vector3(1.7, 1.4, 1.6)},
	{"modele": &"deco_plante", "pos": Vector2(-17.6, 6.0), "rot": 1.2,
		"taille": Vector3(1.6, 1.3, 1.5)},
	{"modele": &"deco_borne", "pos": Vector2(-6.0, -6.0), "rot": 0.0,
		"taille": Vector3(0.7, 1.6, 0.7)},
	{"modele": &"deco_borne", "pos": Vector2(6.0, 6.0), "rot": 0.0,
		"taille": Vector3(0.7, 1.6, 0.7)},
	{"modele": &"deco_lampadaire", "pos": Vector2(-6.4, 6.2), "rot": 0.0,
		"taille": Vector3(0.9, 2.6, 0.9)},
	{"modele": &"deco_lampadaire", "pos": Vector2(6.4, -6.2), "rot": 0.0,
		"taille": Vector3(0.9, 2.6, 0.9)},
	{"modele": &"deco_panneau", "pos": Vector2(-18.2, -6.4), "rot": 1.57,
		"taille": Vector3(1.2, 2.4, 0.5)},
	{"modele": &"deco_panneau", "pos": Vector2(18.2, 6.4), "rot": 1.57,
		"taille": Vector3(1.2, 2.4, 0.5)},
	{"modele": &"deco_debris", "pos": Vector2(17.8, -16.0), "rot": 0.8,
		"taille": Vector3(1.8, 0.9, 1.6)},
]

# --- APPARITIONS DES JOUEURS --------------------------------------------
#
# ONZE POINTS pour dix bots et un joueur, répartis sur la couronne
# extérieure. Aucun n'est dans un bastion : naître au milieu d'un groupe de
# couverts, c'est naître dans le champ de tir de celui qui le tient.
#
# AUCUN N'EST EN VIS-À-VIS DIRECT D'UN AUTRE. La couronne est parcourue
# dans un ordre qui SAUTE : les indices 0 et 1 se retrouvent à un tiers de
# tour l'un de l'autre, pas côte à côte. Comme GameWorld distribue les
# indices dans l'ordre d'arrivée, deux joueurs consécutifs n'apparaissent
# jamais nez à nez.
const APPARITIONS: Array[Vector3] = [
	# DÉCALÉES DE L'AXE DES PASSES — DÉFAUT MESURÉ, PAS SUPPOSÉ.
	#
	# Les apparitions nord et sud étaient à x = 0, c'est-à-dire exactement
	# dans l'alignement des deux goulets. Or la caméra se pose huit mètres
	# au sud du joueur : à l'apparition nord, elle regardait le joueur À
	# TRAVERS les conteneurs de la passe. Le banc a relevé le joueur masqué
	# à ce point précis, et c'est aussi ce que le cahier des charges
	# interdit — ne pas apparaître derrière un gros élément.
	#
	# Trois mètres de décalage suffisent : on sort de l'axe du goulet tout
	# en gardant l'apparition sur son bord de carte.
	Vector3(-3.6, 0.2, -17.6),     # nord, hors de l'axe de la passe
	Vector3(12.4, 0.2, 12.4),      # sud-est
	Vector3(-17.6, 0.2, 0.0),      # ouest
	Vector3(12.4, 0.2, -12.4),     # nord-est
	Vector3(3.6, 0.2, 17.6),       # sud, hors de l'axe de la passe
	Vector3(-12.4, 0.2, -12.4),    # nord-ouest
	Vector3(17.6, 0.2, 0.0),       # est
	Vector3(-12.4, 0.2, 12.4),     # sud-ouest
	Vector3(-6.4, 0.2, -17.8),     # nord-nord-ouest
	Vector3(6.4, 0.2, 17.8),       # sud-sud-est
	Vector3(17.8, 0.2, -6.4),      # est-nord-est
]

# --- FOYERS DE MOBS ------------------------------------------------------
#
# CINQ GROUPES, DIX MOBS. Deux par groupe, sauf un trio.
#
# AUCUN AU CENTRE, et c'est la décision de conception la plus importante de
# cette liste. Des mobs sur la place se feraient ramasser par le premier
# arrivé, et la place deviendrait le seul endroit à visiter. Répartis en
# couronne intermédiaire, ils obligent à SORTIR pour progresser — donc à
# croiser d'autres joueurs en chemin, ce qui est tout l'intérêt d'un test
# de combat.
#
# Chaque foyer est à plus de 5 m du point d'apparition le plus proche :
# on ne naît jamais au contact.
const FOYERS_MOBS: Array[Dictionary] = [
	{"centre": Vector2(-9.5, -3.0), "nombre": 2},   # flanc ouest
	{"centre": Vector2(9.5, 3.0), "nombre": 2},     # flanc est
	{"centre": Vector2(-3.0, 9.6), "nombre": 2},    # flanc sud
	{"centre": Vector2(3.0, -9.6), "nombre": 2},    # flanc nord
	# AU BORD DE LA PLACE, et c'est une correction mesurée. Ce groupe était
	# dans l'angle nord-est, le point le plus isolé de la carte. Le banc a
	# relevé moins de 2 % du temps de jeu passé sur la place : une zone
	# morte en plein milieu, là où la composition promettait le grand
	# combat lisible. Les bots vont où sont les mobs — rien ne les appelait
	# au centre, ils n'y allaient pas.
	{"centre": Vector2(2.4, -3.6), "nombre": 2},    # bord de la place
]

## Écart entre deux mobs d'un même groupe. Assez pour qu'on les distingue,
## assez peu pour qu'ils se lisent comme un groupe.
const ECART_GROUPE := 1.8


## Les dix positions de mobs, dérivées des foyers.
static func positions_mobs() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f: Dictionary in FOYERS_MOBS:
		var c: Vector2 = f["centre"]
		var n: int = f["nombre"]
		for i in n:
			# Disposés sur un petit arc, jamais empilés : deux mobs à la
			# même position se chevauchent et clignotent l'un dans l'autre.
			var a := TAU * float(i) / float(maxi(n, 1)) + 0.6
			var p := c + Vector2(cos(a), sin(a)) * ECART_GROUPE
			out.append(Vector3(p.x, 0.2, p.y))
	return out


# --- LA COULEUR EST LE SYSTÈME DE LECTURE, PAS UNE DÉCORATION ------------
#
# LE DÉFAUT MESURÉ. Premier jet : toutes les pièces posées dans la même
# pierre crème, sur un sable clair. Vue de la caméra de jeu, l'arène
# sortait en APLAT BEIGE — quarante-cinq objets qu'on ne distinguait ni du
# sol ni les uns des autres. La composition était pourtant la même que
# celle-ci : ce n'est pas le plan qui manquait, c'est la couleur.
#
# La règle vient de la référence de lisibilité : on doit savoir CE QU'UNE
# MASSE FAIT avant de l'avoir regardée. Trois familles, trois traitements,
# et l'œil apprend la convention en une partie :
#
#   BAS      pierre d'ombre  — masse sombre et large : « on tire par-dessus »
#   MI-HAUT  cobalt          — la seule couleur froide : « ça coupe la vue »
#   REPÈRE   pierre claire   — haut et pâle, se détache sur le ciel
#   DÉCOR    gris / vert     — désaturé, recule, ne réclame aucune attention
#
# Le cobalt est réservé aux couverts qui BLOQUENT. C'est ce qui permet de
# décider d'un coup d'œil, en pleine course, si l'on peut tirer par-dessus
# un obstacle ou s'il faut le contourner — la question la plus fréquente
# du jeu, et celle qu'on n'a pas le temps de se poser.
## Brun profond des couverts bas.
##
## ASSOMBRI APRÈS MESURE. La pierre d'ombre de la palette (b8996b) posée
## sur le sable de l'arène donnait deux valeurs quasi identiques : les
## couverts bas — qui sont la MAJORITÉ de la carte — disparaissaient dans
## le sol, vérifié en image. Un couvert qu'on ne voit pas n'est pas un
## couvert. Assombri d'un quart, il redevient une masse, sans quitter la
## famille chaude du désert.
const COL_COUVERT_BAS := Color("8f7241")

static func teinte_couvert(hauteur: float) -> Color:
	return Cfg.COL_COBALT if hauteur > (H_BAS + H_MI) * 0.5 \
			else COL_COUVERT_BAS


static func teinte_decor(modele: StringName) -> Color:
	return Cfg.COL_VERT if modele == &"deco_plante" else Cfg.COL_GRIS


## Toutes les pièces posées, chacune avec la teinte de son rôle.
static func toutes_les_pieces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in COUVERTS:
		var d := c.duplicate()
		d["teinte"] = teinte_couvert((c["taille"] as Vector3).y)
		out.append(d)
	for r: Dictionary in REPERES:
		var d := r.duplicate()
		d["teinte"] = Cfg.COL_PIERRE_CREME
		out.append(d)
	for e: Dictionary in DECOR:
		var d := e.duplicate()
		d["teinte"] = teinte_decor(e["modele"])
		out.append(d)
	return out
