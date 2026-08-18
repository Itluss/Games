extends Node
## CONFIGURATION GLOBALE — constantes partagées et réglages de qualité.
##
## Tout ce qui est « vrai partout » vit ici : couches physiques, palette,
## équilibrage de haut niveau. Aucun autre script ne doit redéfinir une
## couche de collision ou une couleur d'équipe dans son coin : une valeur
## dupliquée est une valeur qui finira par diverger.
##
## Autoload : Cfg

# --- COUCHES PHYSIQUES ---------------------------------------------------
# Masques de bits (couche 1 = 1, couche 2 = 2, couche 3 = 4, ...).
# Les projectiles n'ont volontairement PAS de couche commune avec leur
# tireur : c'est ce qui empêche de se blesser soi-même sans le moindre
# test à l'exécution.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MOB := 4
const LAYER_PROJECTILE := 8
const LAYER_PICKUP := 16

# --- ÉQUIPES -------------------------------------------------------------
enum Team { PLAYER, MOB }

# --- PALETTE -------------------------------------------------------------
# Direction artistique : cartoon premium, couleurs franches, ambiance
# chaude. Les teintes vives sont réservées au GAMEPLAY (projectiles, loot,
# télégraphes) ; le décor reste plus sourd pour ne jamais concurrencer la
# lisibilité du combat.
const COL_SAND := Color("e3b374")
const COL_SAND_DARK := Color("c08a45")
const COL_ROCK := Color("b0603a")
const COL_ROCK_DARK := Color("8a4526")
const COL_GRASS := Color("6cc24a")
const COL_SKY_TOP := Color("2f7fd6")
const COL_SKY_HORIZON := Color("ffdca8")
const COL_SUN := Color("fff2d6")

# --- PALETTE DE L'ARÈNE : CITÉ FUTURISTE NÉON ---------------------------
#
# LE PIÈGE ÉVITÉ ICI : une cité néon, on l'imagine spontanément de nuit,
# sur un asphalte noir. Ce serait un contresens pour CE jeu. Kael porte
# une veste bleu roi ; posé sur un sol bleu-noir, il disparaît. Or dans un
# jeu vu de dessus, la première exigence n'est pas la beauté, c'est de
# distinguer son personnage d'un coup d'œil.
#
# L'arène est donc au CRÉPUSCULE, pas en pleine nuit : le sol reste un
# béton pâle et froid qui détache toutes les silhouettes, et le néon vient
# du ciel, des enseignes et des liserés. On garde l'image sans perdre la
# lisibilité — et le contraste chaud/froid entre un ciel corail et un sol
# bleuté fait à lui seul la moitié du travail.
const COL_BETON := Color("8b93a8")
const COL_BETON_SOMBRE := Color("6f7793")
## Marquages au sol et joints de dalle.
const COL_MARQUAGE := Color("6e7691")
const COL_METAL := Color("2e3552")
const COL_METAL_SOMBRE := Color("242a41")
const COL_NEON_CYAN := Color("3ce9ff")
const COL_NEON_MAGENTA := Color("ff3ea5")
## Ciel de crépuscule : indigo profond au zénith, corail à l'horizon.
const COL_CIEL_HAUT := Color("221a44")
const COL_CIEL_HORIZON := Color("f57a52")
## Soleil rasant, chaud mais peu énergique — il sculpte, il n'écrase pas.
const COL_SOLEIL_VILLE := Color("ffc79e")
## Ambiante violette : elle colore les ombres au lieu de les grisailler.
const COL_AMBIANTE_VILLE := Color("6b5ca8")
# --- MATIÈRES DU MONDE OUVERT -------------------------------------------
#
# UNE COULEUR PAR MATIÈRE, PAS PAR OBJET. Un rocher du canyon et une mesa
# partagent la même roche ; ce qui distingue les secteurs, c'est le SOL et
# la densité, pas cinquante teintes de props. Trop de couleurs et la carte
# devient un patchwork où plus rien ne se lit.
#
# Toutes sont choisies DÉSATURÉES par rapport aux couleurs de gameplay :
# le décor ne doit jamais concurrencer un projectile, un butin ou un
# adversaire. C'est la règle qui tient toute la lisibilité du jeu.
const COL_ROCHE := Color("8b8fa3")
const COL_ROCHE_CHAUDE := Color("8f6543")
const COL_PIERRE := Color("c3bdae")
const COL_BOIS := Color("8a6242")
const COL_FEUILLAGE := Color("5aa653")
const COL_TOILE := Color("d8c9a4")

# --- SOLS DES SECTEURS ---------------------------------------------------
#
# C'est ICI que se joue le « je suis dans le canyon ». Vu de dessus, le sol
# occupe les trois quarts de l'écran : changer sa teinte change le secteur
# bien plus sûrement que n'importe quel prop.
#
# ASSOMBRIES APRÈS MESURE EN IMAGE. Les premières valeurs étaient choisies
# « à la couleur » — un beau sable, une belle terre. Mais l'éclairage du jeu
# a été réglé pour le béton gris moyen du noyau : posé sur du sable clair,
# le même soleil sature et le secteur vire au blanc rosé. Ce sont les
# valeurs RENDUES qui comptent, jamais celles du nuancier.
const SOL_CAMP := Color("a2915f")
const SOL_CANYON := Color("8e5c3a")
const SOL_BOSQUET := Color("55743f")
const SOL_FONDERIE := Color("767d92")
const SOL_RUINES := Color("867f6d")
const SOL_NOYAU := Color("7c7f9c")

## Brume de rue. VOLONTAIREMENT VIOLETTE et non corail : teintée de la
## couleur chaude de l'horizon, elle repeignait tout le sol en rose et
## l'arène entière virait monochrome — vérifié en image. Le violet pousse
## les lointains vers le FROID, ce qui creuse la profondeur au lieu de
## l'aplatir, et laisse le chaud au ciel seul, là où il est beau.
const COL_BRUME_VILLE := Color("4a4078")

# Couleurs d'identité — une arme se reconnaît à sa couleur avant même
# qu'on lise son nom.
const COL_BASIC := Color("5fc4ff")
const COL_SHOTGUN := Color("ffb347")
const COL_ENERGY := Color("b06bff")
const COL_GRENADE := Color("6bff9e")

const COL_MOB_CHARGER := Color("ff6b5a")
const COL_MOB_SHOOTER := Color("5ad2ff")
const COL_MOB_EXPLODER := Color("ffd75a")

const COL_DANGER := Color("ff3b30")
const COL_HEAL := Color("4cd964")
const COL_LOCAL_PLAYER := Color("2a6fd6")
const COL_ENEMY_PLAYER := Color("ff5a8a")
## Accent orange de Kael — doublure, semelles, bouche du blaster.
const COL_KAEL_ACCENT := Color("f2822a")

# --- ARÈNE ---------------------------------------------------------------
const ARENA_RADIUS := 34.0

# --- QUALITÉ -------------------------------------------------------------
## Un seul curseur, lu par les systèmes coûteux (particules, ombres,
## décalcomanies). Baisser la qualité ne doit JAMAIS changer le gameplay,
## uniquement son habillage.
enum Quality { LOW, MEDIUM, HIGH }
var quality: Quality = Quality.HIGH

## Multiplicateur appliqué aux quantités de particules.
func fx_scale() -> float:
	match quality:
		Quality.LOW:
			return 0.35
		Quality.MEDIUM:
			return 0.7
		_:
			return 1.0

## Les ombres dynamiques sont le premier poste à sacrifier sur mobile.
func shadows_enabled() -> bool:
	return quality != Quality.LOW

## Détecte une plateforme tactile pour adapter l'interface sans deviner.
func is_touch_platform() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _ready() -> void:
	# Sur mobile, on part en qualité moyenne : mieux vaut 60 FPS stables
	# qu'un premier lancement à 30 dont le joueur ne reviendra pas.
	if OS.has_feature("mobile"):
		quality = Quality.MEDIUM
	Engine.max_fps = 60
