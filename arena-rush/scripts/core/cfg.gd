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
# LE CIEL EST PASSÉ DU CRÉPUSCULE AU PLEIN JOUR.
#
# L'ancienne ambiance était un coucher de soleil : zénith indigo, ambiante
# violette, exposition à 0,52. Sur un écran de téléphone en plein jour,
# cela donnait une image sombre et mauve où le personnage se noyait dans
# le décor — c'est exactement ce que le brief demande de corriger. Un jeu
# mobile lisible se joue sous un ciel franc : bleu net au zénith, horizon
# chaud, soleil blanc, ombres bleutées mais CLAIRES.
const COL_CIEL_HAUT := Color("2f8fdb")
const COL_CIEL_HORIZON := Color("ffd6a0")
## Soleil de milieu de matinée : blanc à peine doré. Il éclaire, il ne teinte pas.
const COL_SOLEIL_JOUR := Color("fff3dc")
## Ambiante = rebond du ciel. Bleue et CLAIRE : les ombres restent lisibles,
## on distingue encore un mob dans l'ombre d'une colonne.
const COL_AMBIANTE_JOUR := Color("a8d4f2")
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
## Roche GRISE MAIS CHAUDE. Elle était bleutée (8b8fa3) : sur un sol de
## sable orange, chaque caillou virait au bleu et le désert paraissait
## sale — vérifié en image. Un gris légèrement beige reste distinct du
## sable sans s'y opposer.
const COL_ROCHE := Color("9c8d7c")
const COL_ROCHE_CHAUDE := Color("8f6543")
const COL_PIERRE := Color("b5aa97")
const COL_BOIS := Color("8a6242")
const COL_FEUILLAGE := Color("5aa653")
const COL_TOILE := Color("d8c9a4")

# --- MATIÈRES DE LA ZONE D'ESSAI : RUINES ENSOLEILLÉES -------------------
#
# UNE RÈGLE, ET ELLE PRIME SUR LE RESTE : le décor est un FOND. Ces teintes
# sont choisies chaudes et lumineuses pour sortir le secteur de la grisaille,
# mais toutes restent MOINS saturées que celles du gameplay — un rocher ne
# doit jamais accrocher l'œil autant qu'un mob ou qu'un projectile.
#
# Les accents froids — vert, turquoise, violet — sont volontairement RARES.
# Posés partout ils annuleraient le contraste chaud du sable ; posés par
# touches, ce sont eux qui donnent l'impression de couleur.
## Pierre chaude des ruines : franchement plus contrastée que le sable.
const COL_PIERRE_CHAUDE := Color("b98a5e")
## Sommet des pierres, éclairé : c'est ce liseré clair qui détache une
## silhouette basse d'un sol de la même famille de teintes.
const COL_PIERRE_CRETE := Color("dcb283")
## Cactus et plantes grasses — la seule vraie note verte du secteur.
const COL_CACTUS := Color("4f9e5c")
const COL_CACTUS_CLAIR := Color("6fc47a")
## Fleur de cactus, minuscule et vive : un point de couleur, pas une masse.
const COL_FLEUR := Color("ff6fae")
## Cristal turquoise. Émissif, sans lumière dynamique : il brille sans rien
## coûter au rendu mobile.
const COL_CRISTAL := Color("35e0d0")

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
## LES RUINES SONT LA ZONE D'ESSAI VISUEL. Leur sol passe d'un gris-beige
## terne à un sable chaud et lumineux : vu de dessus, le sol occupe les
## trois quarts de l'écran, c'est donc lui qui décide de l'ambiance d'un
## secteur bien avant le moindre prop.
const SOL_RUINES := Color("e39a4a")
const SOL_NOYAU := Color("7c7f9c")

## Brume de lointain. Elle reste FROIDE face à un sol chaud : c'est ce
## contraste qui creuse la profondeur au lieu de l'aplatir. Mais elle est
## désormais CLAIRE — une brume sombre sur un sol clair salissait l'image
## au lieu de l'éloigner.
const COL_BRUME_JOUR := Color("b9d8ee")

# Couleurs d'identité — une arme se reconnaît à sa couleur avant même
# qu'on lise son nom.
const COL_BASIC := Color("5fc4ff")
const COL_SHOTGUN := Color("ffb347")
## Magenta et non violet : le mob tireur porte désormais le violet-bleu,
## et deux signaux de sens opposés — « arme à ramasser » et « ennemi qui
## tire » — ne doivent jamais partager une teinte.
const COL_ENERGY := Color("ff5ce0")
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
	return est_mobile() or DisplayServer.is_touchscreen_available()

## LE TÉLÉPHONE N'ÉTAIT PAS RECONNU COMME UN TÉLÉPHONE.
##
## `OS.has_feature("mobile")` est FAUX dans un export web, même ouvert sur
## un iPhone : l'export web n'a que les étiquettes « web », « web_ios »,
## « web_android ». Or le jeu se joue précisément comme ça — par le
## navigateur du téléphone. Toutes les baisses de qualité prévues pour
## mobile n'ont donc jamais été appliquées à la seule plateforme qui en
## avait besoin : le jeu tournait en qualité HAUTE, ombres comprises, sur
## un écran haute densité.
##
## C'est le genre de défaut qui ne se voit sur aucune machine de
## développement, puisque le bureau est légitimement en qualité haute.
func est_mobile() -> bool:
	return force_mobile or OS.has_feature("mobile") \
			or OS.has_feature("web_ios") or OS.has_feature("web_android") \
			or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())

## Force le profil téléphone sur une machine de bureau, via `-- --mobile`.
##
## POURQUOI CE DRAPEAU EXISTE. Une sonde a longé tout le bord du monde et
## n'a rien trouvé — parce qu'elle tournait en qualité HAUTE, ombres
## comprises, alors que la joueuse est en qualité BASSE. Un instrument qui
## ne mesure pas la configuration du joueur ne mesure rien, et celui-là a
## rendu un verdict rassurant sur un jeu qui ne l'était pas.
##
## Sans ombres, une paroi n'a plus que son éclairage ambiant : elle devient
## un aplat. Le profil du téléphone n'est donc pas seulement « moins beau »,
## il change ce qui est LISIBLE — c'est exactement ce qu'il faut pouvoir
## reproduire.
var force_mobile := false

func _ready() -> void:
	# Sur mobile, on part en qualité moyenne : mieux vaut 60 FPS stables
	# qu'un premier lancement à 30 dont le joueur ne reviendra pas.
	# QUALITÉ BASSE SUR TÉLÉPHONE, ET NON MOYENNE. C'est un choix, pas un
	# réglage par défaut : la joueuse a décrit le jeu comme « injouable »
	# sur son iPhone — image qui tremble, zoom erratique, décor qui
	# disparaît. Ces trois symptômes sont ceux d'une cadence d'images
	# effondrée, et ils apparaissent « à certains endroits » parce que le
	# coût du décor varie du simple au décuple selon le secteur.
	#
	# Le cran BAS coupe les trois postes les plus chers : les ombres
	# dynamiques, les contours dilatés — qui DOUBLENT les appels de rendu
	# des personnages — et l'essentiel des particules. Rien de tout cela ne
	# touche au jeu lui-même, conformément à la règle de ce curseur.
	#
	# C'est volontairement trop prudent. Le jeu doit d'abord TOURNER ; on
	# remontera le curseur quand on saura ce que le téléphone encaisse.
	if "--mobile" in OS.get_cmdline_user_args():
		force_mobile = true
		print("[Cfg] Profil téléphone forcé.")
	if est_mobile():
		quality = Quality.LOW
	# On ne touche PAS à `scaling_3d_scale` : l'export web utilise le rendu
	# `gl_compatibility`, où la mise à l'échelle 3D de Godot n'a aucun
	# effet. La ligne aurait rassuré sans rien faire.
	Engine.max_fps = 60
