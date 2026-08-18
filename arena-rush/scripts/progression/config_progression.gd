extends RefCounted
class_name ConfigProgression
## RÉGLAGES DE PROGRESSION — toutes les valeurs, à un seul endroit.
##
## POURQUOI CE FICHIER : une valeur d'équilibrage dispersée dans le code
## est une valeur qu'on n'ose plus changer. Celles-ci vont bouger souvent —
## c'est le propre d'une économie de jeu — donc elles doivent être
## modifiables sans lire une ligne de logique.
##
## Rien ici n'est une constante « technique » : ce sont des DÉCISIONS DE
## GAME DESIGN, et elles sont écrites pour être discutées.

# --- GAINS D'EXPÉRIENCE --------------------------------------------------
#
# LE RAPPORT ENTRE CES VALEURS EST LE VRAI RÉGLAGE, pas leur valeur
# absolue. Un joueur vaut vingt mobs communs : c'est ce qui dit au joueur,
# sans un mot de tutoriel, que le PvP est le cœur du jeu et que les mobs
# ne sont qu'un moyen de s'équiper.

const XP_JOUEUR := 100
const XP_MOB_COMMUN := 5
const XP_MOB_RESISTANT := 10
const XP_MOB_ELITE := 20
## Prime versée à chaque palier de série atteint, EN PLUS de l'XP du kill.
const XP_BONUS_SERIE := 50
## XP par minute passée en jeu. Volontairement faible : le temps ne doit
## jamais être un substitut au talent, seulement une reconnaissance de la
## fidélité.
const XP_PAR_MINUTE := 12

## Catégorie de mob → gain. Le tableau est la seule autorité : ajouter une
## catégorie ne demande pas de toucher au code qui la lit.
const XP_PAR_CATEGORIE := {
	&"commun": XP_MOB_COMMUN,
	&"resistant": XP_MOB_RESISTANT,
	&"elite": XP_MOB_ELITE,
}

# --- RÉAPPARITION --------------------------------------------------------

## Attente avant de revenir. Assez longue pour qu'une mort se ressente,
## assez courte pour qu'on n'aille pas regarder son téléphone.
const DELAI_RESPAWN := 2.5
## Invulnérabilité au retour. Elle n'existe que pour empêcher le
## « spawn kill » — être abattu avant d'avoir pu bouger n'apprend rien.
const PROTECTION_RESPAWN := 2.0

# --- SÉRIES D'ÉLIMINATIONS ----------------------------------------------
#
# Les paliers sont VOLONTAIREMENT rapprochés au début : un joueur moyen
# doit voir « ON FIRE » de temps en temps, sinon le système ne récompense
# que ceux qui n'en ont pas besoin.
const PALIERS_SERIE := [
	{"seuil": 3, "texte": "ON FIRE", "couleur": Color("ffb43a")},
	{"seuil": 5, "texte": "RAMPAGE", "couleur": Color("ff6a2a")},
	{"seuil": 10, "texte": "UNSTOPPABLE", "couleur": Color("ff2e6a")},
	{"seuil": 15, "texte": "GODLIKE", "couleur": Color("b06bff")},
]

# --- NIVEAUX DE COMPTE ---------------------------------------------------

## Niveau maximal actuellement défini. Le calcul ci-dessous n'a AUCUNE
## table en dur, donc relever ce plafond ne demande rien d'autre.
const NIVEAU_MAX := 50

## XP nécessaire pour passer DU niveau donné au suivant.
##
## COURBE CHOISIE : quadratique douce plutôt qu'exponentielle. Une courbe
## exponentielle rend les hauts niveaux inatteignables pour qui joue une
## heure par semaine — or c'est exactement le joueur qu'on veut voir
## revenir. Ici, le niveau 50 demande environ cent fois le niveau 2 : long,
## mais jamais absurde.
##
## Les premiers niveaux sont écrasés volontairement : les cinq premières
## minutes doivent en donner trois ou quatre. C'est la promesse qui donne
## envie de rester.
static func xp_pour_passer_le_niveau(niveau: int) -> int:
	var n := maxi(1, niveau)
	if n <= 4:
		return 150 * n
	return int(round(120.0 * pow(float(n), 1.55)))


## XP cumulée nécessaire pour ATTEINDRE un niveau donné.
static func xp_cumulee_pour_niveau(niveau: int) -> int:
	var total := 0
	for n in range(1, maxi(1, niveau)):
		total += xp_pour_passer_le_niveau(n)
	return total


## Niveau correspondant à une XP totale, et le reliquat dans ce niveau.
## Retourne { "niveau", "xp_dans_niveau", "xp_du_niveau" }.
static func niveau_pour_xp(xp_totale: int) -> Dictionary:
	var niveau := 1
	var reste := maxi(0, xp_totale)
	while niveau < NIVEAU_MAX:
		var palier := xp_pour_passer_le_niveau(niveau)
		if reste < palier:
			return {"niveau": niveau, "xp_dans_niveau": reste,
					"xp_du_niveau": palier}
		reste -= palier
		niveau += 1
	# Au plafond, la barre est pleine : afficher une barre qui progresse
	# encore alors que plus rien ne monte serait un mensonge.
	var dernier := xp_pour_passer_le_niveau(NIVEAU_MAX)
	return {"niveau": NIVEAU_MAX, "xp_dans_niveau": dernier,
			"xp_du_niveau": dernier}


# --- MAÎTRISES -----------------------------------------------------------
#
# Personnages et armes partagent la même courbe, PLUS PLATE que celle du
# compte : une maîtrise doit se voir monter en une session de jeu, sinon
# elle ne récompense rien de perceptible.
const MAITRISE_MAX := 30

static func xp_pour_passer_la_maitrise(niveau: int) -> int:
	return 60 + 40 * maxi(1, niveau)

static func niveau_de_maitrise(xp: int) -> int:
	var niveau := 1
	var reste := maxi(0, xp)
	while niveau < MAITRISE_MAX:
		var palier := xp_pour_passer_la_maitrise(niveau)
		if reste < palier:
			break
		reste -= palier
		niveau += 1
	return niveau


# --- PRESTIGE ------------------------------------------------------------
#
# Des PLACEHOLDERS assumés. Ils existent pour que la chaîne complète —
# calcul, stockage, affichage — soit branchée et vérifiable ; leur contenu
# définitif est une décision de direction artistique, pas de code.
#
# Le titre se déduit du niveau de compte pour l'instant. Il devra plus tard
# s'ÉQUIPER librement parmi ceux débloqués : c'est pour cela que le profil
# stocke un titre équipé plutôt que de le recalculer à l'affichage.
const TITRES := [
	{"niveau": 1, "titre": "ROOKIE", "couleur": Color("9fb4d8")},
	{"niveau": 5, "titre": "HUNTER", "couleur": Color("6ec0ff")},
	{"niveau": 12, "titre": "VETERAN", "couleur": Color("7ff06a")},
	{"niveau": 25, "titre": "PREDATOR", "couleur": Color("ffb43a")},
	{"niveau": 40, "titre": "LEGEND", "couleur": Color("ff2e6a")},
]

static func titre_pour_niveau(niveau: int) -> Dictionary:
	var trouve: Dictionary = TITRES[0]
	for t: Dictionary in TITRES:
		if niveau >= int(t["niveau"]):
			trouve = t
	return trouve


# --- MATCHMAKING ---------------------------------------------------------
#
# AUCUNE INFRASTRUCTURE ICI, et c'est délibéré. On se contente de calculer
# le panier auquel un joueur appartiendrait. Le jour où un vrai serveur
# d'appariement existera, il lira cette valeur au lieu de la réinventer —
# et les profils déjà sauvegardés le porteront déjà.
const PANIERS := [
	{"seuil": 0, "nom": &"rookie"},
	{"seuil": 8, "nom": &"regular"},
	{"seuil": 22, "nom": &"veteran"},
]

## Le panier suit le NIVEAU DE COMPTE, faute de mieux pour un prototype.
## À terme il devra suivre un classement de performance — un joueur peut
## avoir cent heures et rester mauvais, et l'inverse est encore plus vrai.
static func panier_pour_niveau(niveau: int) -> StringName:
	var trouve: StringName = &"rookie"
	for p: Dictionary in PANIERS:
		if niveau >= int(p["seuil"]):
			trouve = p["nom"]
	return trouve
