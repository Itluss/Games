extends RefCounted
class_name PlanArene
## PLAN DE L'ARÈNE — « Secteur 9 », un carrefour de cité au crépuscule.
##
## CE FICHIER EST UNE DONNÉE, PAS DU CODE. Chaque pièce est une ligne
## lisible : où elle est, comment elle est tournée, quel volume elle occupe,
## quel modèle l'habille. On peut donc discuter du niveau sans lire une
## seule ligne de logique, et le déplacer sans rien casser.
##
## ─── CE QUE LE PLAN DOIT GARANTIR ───────────────────────────────────────
##
## L'ancien plan était trois couronnes parfaitement symétriques. C'était
## honnête et parfaitement inutile à retenir : toutes les directions se
## valaient, donc aucune ne se mémorisait. Une carte qu'on apprend est une
## carte ASYMÉTRIQUE — on retient « le pylône », « la ruelle des
## conteneurs », « l'immeuble à l'enseigne ».
##
## L'asymétrie ne dispense d'aucune garantie. Celles-ci sont vérifiées par
## le test de l'arène, pas seulement espérées :
##
##   1. AUCUNE LIGNE DE TIR D'UN POINT D'APPARITION À UN AUTRE. Les quatre
##      apparitions sont sur les diagonales ; les quatre immeubles sont donc
##      posés sur les axes, exactement en travers des cordes qui relient
##      deux apparitions voisines, et le pylône central coupe les deux
##      diagonales. Personne ne peut viser un adversaire avant qu'il ait
##      bougé.
##   2. UN ABRI À MOINS DE QUATRE MÈTRES DE CHAQUE APPARITION. Commencer à
##      découvert, c'est mourir d'une décision qu'on n'a pas prise.
##   3. AUCUN CUL-DE-SAC. Les masses sont séparées par des rues : on peut
##      toujours contourner, jamais se faire enfermer.
##   4. LE CENTRE EST DISPUTÉ, PAS CONFORTABLE. Il a des abris, mais il est
##      vu de partout — on y va pour le butin, on n'y campe pas.
##
## ─── LES TROIS RÔLES ────────────────────────────────────────────────────
##
##   STRUCTURE  — coupe une ligne de vue entière et sert de repère.
##   ABRI       — la hauteur de combat. C'est là que le jeu se joue.
##   GARNITURE  — donne vie et échelle. Aucune collision : rien de ce qui
##                est purement décoratif ne doit pouvoir bloquer un joueur.

## Rayon auquel apparaissent les joueurs. Le plan en dépend directement :
## les immeubles sont calés sur les cordes entre apparitions voisines.
const RAYON_APPARITION := 26.0

## Volume déclaré de chaque pièce, en MÈTRES. C'est lui qui fait autorité :
## le modèle Meshy est ramené à l'intérieur, jamais l'inverse (voir
## PropKit). Kael mesure 1,90 m — un abri de 1,2 m couvre un joueur
## accroupi, un abri de 2,2 m le couvre debout.

# --- STRUCTURES ----------------------------------------------------------
# Les quatre immeubles sont sur les axes, les apparitions sur les
# diagonales : chacun barre donc la corde entre deux apparitions voisines.
# Les décalages (1.5, -1.2, -1.0, 1.8) sont VOLONTAIRES — parfaitement
# alignés, ils auraient reconstitué la symétrie qu'on cherche à fuir.
const STRUCTURES: Array[Dictionary] = [
	{"modele": &"deco_pylone", "pos": Vector2(0.0, 0.0), "rot": 0.0,
		"taille": Vector3(2.6, 6.4, 2.6),
		"note": "LE PYLÔNE. Repère visible de toute l'arène, et seul objet qui coupe les deux diagonales d'apparition."},

	{"modele": &"deco_tour", "pos": Vector2(1.5, 18.6), "rot": 0.18,
		"taille": Vector3(7.0, 5.2, 5.0), "note": "Immeuble NORD — barre la corde entre les apparitions est et ouest du haut."},
	{"modele": &"deco_tour", "pos": Vector2(18.9, -1.2), "rot": 1.66,
		"taille": Vector3(5.5, 5.6, 7.5), "note": "Immeuble EST."},
	{"modele": &"deco_tour", "pos": Vector2(-1.0, -19.2), "rot": 3.05,
		"taille": Vector3(6.5, 4.8, 5.0), "note": "Immeuble SUD."},
	{"modele": &"deco_tour", "pos": Vector2(-18.7, 1.8), "rot": 4.85,
		"taille": Vector3(5.0, 5.4, 6.8), "note": "Immeuble OUEST."},

	{"modele": &"deco_panneau", "pos": Vector2(7.8, 16.2), "rot": 0.52,
		"taille": Vector3(4.6, 4.4, 1.0), "note": "Enseigne du quartier nord-est — repère fort et écran de fumée visuel."},
	{"modele": &"deco_panneau", "pos": Vector2(-15.8, 8.8), "rot": 2.24,
		"taille": Vector3(4.6, 4.4, 1.0), "note": "Enseigne du quartier ouest."},
	{"modele": &"deco_passerelle", "pos": Vector2(14.2, 6.8), "rot": 0.92,
		"taille": Vector3(6.2, 3.2, 2.6), "note": "Passerelle est — casse la rue est en deux sans la fermer."},
	{"modele": &"deco_pylone", "pos": Vector2(-13.8, -13.2), "rot": 0.0,
		"taille": Vector3(2.2, 5.6, 2.2), "note": "Second pylône, sud-ouest : donne au quart le plus vide un repère à lui."},
]

# --- ABRIS DE COMBAT -----------------------------------------------------
# Le cœur du jeu. Répartis dans les rues entre les immeubles, jamais
# alignés, avec des hauteurs mélangées pour que « se mettre à couvert »
# demande de choisir : derrière la barrière on tire vite, derrière le
# conteneur on est mieux caché.
const ABRIS: Array[Dictionary] = [
	# LA PLACE — abris serrés autour du pylône. On peut y survivre, pas s'y
	# installer : tout ce qui arrive des quatre rues vous voit.
	{"modele": &"deco_barriere", "pos": Vector2(3.8, -2.2), "rot": 0.90,
		"taille": Vector3(4.4, 1.2, 0.9)},
	{"modele": &"deco_bloc", "pos": Vector2(-3.2, 3.6), "rot": 2.40,
		"taille": Vector3(2.2, 1.6, 2.2)},
	{"modele": &"deco_generateur", "pos": Vector2(-1.4, -4.6), "rot": 0.0,
		"taille": Vector3(1.7, 1.8, 1.7)},

	# LES RUES — la couronne où se déroule l'essentiel des combats.
	{"modele": &"deco_conteneur", "pos": Vector2(9.2, 7.4), "rot": 0.35,
		"taille": Vector3(5.2, 2.2, 2.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(-8.0, -9.5), "rot": 1.15,
		"taille": Vector3(5.2, 2.2, 2.2)},
	{"modele": &"deco_barriere", "pos": Vector2(-9.8, 5.2), "rot": 2.05,
		"taille": Vector3(4.4, 1.2, 0.9)},
	{"modele": &"deco_barriere", "pos": Vector2(6.0, -10.5), "rot": 0.55,
		"taille": Vector3(4.4, 1.2, 0.9)},
	{"modele": &"deco_kiosque", "pos": Vector2(12.0, -5.5), "rot": 2.50,
		"taille": Vector3(2.6, 2.4, 2.6)},
	{"modele": &"deco_kiosque", "pos": Vector2(-5.5, 12.5), "rot": 0.80,
		"taille": Vector3(2.6, 2.4, 2.6)},
	{"modele": &"deco_ventilation", "pos": Vector2(3.5, 9.2), "rot": 1.40,
		"taille": Vector3(2.4, 1.5, 1.8)},
	{"modele": &"deco_ventilation", "pos": Vector2(-11.8, -1.5), "rot": 0.30,
		"taille": Vector3(2.4, 1.5, 1.8)},
	{"modele": &"deco_generateur", "pos": Vector2(10.8, 12.2), "rot": 0.0,
		"taille": Vector3(1.7, 1.8, 1.7)},
	{"modele": &"deco_generateur", "pos": Vector2(-12.6, 10.5), "rot": 0.0,
		"taille": Vector3(1.7, 1.8, 1.7)},
	{"modele": &"deco_bloc", "pos": Vector2(-3.0, -12.2), "rot": 0.95,
		"taille": Vector3(2.2, 1.6, 2.2)},
	{"modele": &"deco_bloc", "pos": Vector2(13.6, 2.5), "rot": 2.20,
		"taille": Vector3(2.2, 1.6, 2.2)},
	{"modele": &"deco_caisses", "pos": Vector2(7.4, -2.5), "rot": 0.60,
		"taille": Vector3(1.7, 1.1, 1.7)},
	{"modele": &"deco_caisses", "pos": Vector2(-6.5, 2.0), "rot": 1.80,
		"taille": Vector3(1.7, 1.1, 1.7)},

	# LES APPARITIONS — un abri à portée immédiate de chaque départ.
	# Garantie n° 2 : personne ne commence à découvert.
	{"modele": &"deco_conteneur", "pos": Vector2(15.6, 17.4), "rot": 0.75,
		"taille": Vector3(5.2, 2.2, 2.2)},
	{"modele": &"deco_conteneur", "pos": Vector2(-17.4, 15.6), "rot": 2.35,
		"taille": Vector3(5.2, 2.2, 2.2)},
	{"modele": &"deco_barriere", "pos": Vector2(-15.6, -17.4), "rot": 3.90,
		"taille": Vector3(4.4, 1.2, 0.9)},
	{"modele": &"deco_barriere", "pos": Vector2(17.4, -15.6), "rot": 5.50,
		"taille": Vector3(4.4, 1.2, 0.9)},
]

# --- GARNITURE -----------------------------------------------------------
# AUCUNE COLLISION. Un lampadaire qui arrête une balle ou bloque une
# course serait un mensonge : le joueur juge ce qui l'abrite à sa MASSE,
# et un poteau n'a pas l'air d'un abri.
const GARNITURE: Array[Dictionary] = [
	{"modele": &"deco_lampadaire", "pos": Vector2(6.5, 5.0), "rot": 3.60,
		"taille": Vector3(1.6, 4.2, 2.6)},
	{"modele": &"deco_lampadaire", "pos": Vector2(-6.0, -6.5), "rot": 0.45,
		"taille": Vector3(1.6, 4.2, 2.6)},
	{"modele": &"deco_lampadaire", "pos": Vector2(-7.5, 8.5), "rot": 2.10,
		"taille": Vector3(1.6, 4.2, 2.6)},
	{"modele": &"deco_lampadaire", "pos": Vector2(9.0, -8.0), "rot": 5.00,
		"taille": Vector3(1.6, 4.2, 2.6)},
	{"modele": &"deco_lampadaire", "pos": Vector2(15.5, 10.5), "rot": 1.20,
		"taille": Vector3(1.6, 4.2, 2.6)},
	{"modele": &"deco_lampadaire", "pos": Vector2(-15.0, -7.0), "rot": 4.20,
		"taille": Vector3(1.6, 4.2, 2.6)},

	{"modele": &"deco_plante", "pos": Vector2(2.2, 5.6), "rot": 0.30,
		"taille": Vector3(1.8, 1.2, 1.8)},
	{"modele": &"deco_plante", "pos": Vector2(-4.6, -7.8), "rot": 1.90,
		"taille": Vector3(1.8, 1.2, 1.8)},
	{"modele": &"deco_plante", "pos": Vector2(11.5, 9.0), "rot": 2.60,
		"taille": Vector3(1.8, 1.2, 1.8)},
	{"modele": &"deco_plante", "pos": Vector2(-10.5, 13.5), "rot": 0.70,
		"taille": Vector3(1.8, 1.2, 1.8)},

	{"modele": &"deco_borne", "pos": Vector2(5.2, 1.2), "rot": 1.10,
		"taille": Vector3(0.7, 1.1, 0.7)},
	{"modele": &"deco_borne", "pos": Vector2(-2.4, -8.4), "rot": 3.30,
		"taille": Vector3(0.7, 1.1, 0.7)},
	{"modele": &"deco_borne", "pos": Vector2(-9.0, 0.8), "rot": 0.20,
		"taille": Vector3(0.7, 1.1, 0.7)},

	{"modele": &"deco_debris", "pos": Vector2(8.4, -13.5), "rot": 1.50,
		"taille": Vector3(2.4, 0.6, 2.4)},
	{"modele": &"deco_debris", "pos": Vector2(-13.0, 4.2), "rot": 4.60,
		"taille": Vector3(2.4, 0.6, 2.4)},
	{"modele": &"deco_debris", "pos": Vector2(0.8, 14.5), "rot": 2.90,
		"taille": Vector3(2.4, 0.6, 2.4)},
]


## Toutes les pièces qui OCCUPENT l'espace, c'est-à-dire tout ce qui a une
## collision. Sert au montage, mais aussi au calcul des apparitions de mobs
## et au test de l'arène — il ne doit exister qu'UNE définition de « ce qui
## bloque », sans quoi le test finirait par vérifier autre chose que le jeu.
static func pieces_solides() -> Array[Dictionary]:
	var total: Array[Dictionary] = []
	total.append_array(STRUCTURES)
	total.append_array(ABRIS)
	return total


## Les quatre points d'apparition des joueurs, sur les diagonales.
static func apparitions_joueurs() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		points.append(Vector3(cos(a) * RAYON_APPARITION, 0.2,
				sin(a) * RAYON_APPARITION))
	return points


## Une position est-elle libre ? Test de boîte élargie du RAYON demandé.
##
## On raisonne en boîte alignée sur la pièce (donc en tenant compte de sa
## rotation) et non en simple distance au centre : un conteneur de 5,2 m de
## long n'a rien d'un disque, et l'approximer par un disque interdirait de
## faire apparaître quoi que ce soit dans toute la rue autour de lui.
static func est_libre(p: Vector2, rayon: float) -> bool:
	for piece in pieces_solides():
		var centre: Vector2 = piece["pos"]
		var taille: Vector3 = piece["taille"]
		var rot: float = piece["rot"]
		# Dans le repère de la pièce, la boîte redevient alignée aux axes.
		#
		# LE SIGNE COMPTE. Une rotation de +rot autour de Y envoie l'axe X
		# local sur (cos rot, -sin rot) dans le plan (x, z) — soit, en
		# vocabulaire de Vector2, une rotation de MOINS rot. Passer du monde
		# au repère de la pièce demande donc +rot. Avec le signe inverse, un
		# conteneur de 5,2 m sur 2,2 m serait testé en travers, et des mobs
		# apparaîtraient dedans.
		var local := (p - centre).rotated(rot)
		var demi := Vector2(taille.x * 0.5 + rayon, taille.z * 0.5 + rayon)
		if absf(local.x) < demi.x and absf(local.y) < demi.y:
			return false
	return true
