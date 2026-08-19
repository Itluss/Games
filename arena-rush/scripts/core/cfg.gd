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
## VOLUMES QUI CACHENT LE JOUEUR VU DE DESSUS — tabliers de pont, halles,
## plateformes. Ils n'arrêtent RIEN : ni les corps, ni les tirs. Ils
## n'existent que pour que la caméra sache qu'elle regarde à travers un toit.
const LAYER_TOIT := 32

## BORDURE D'ARÈNE — arrête les corps, laisse passer le REGARD.
##
## LE DÉFAUT QU'ELLE CORRIGE, ET IL EST GÉOMÉTRIQUE, PAS ACCIDENTEL. La
## caméra se pose huit mètres au SUD du joueur. Quand celui-ci s'approche
## du bord sud de l'arène, la caméra se retrouve donc DEHORS, et regarde à
## l'intérieur à travers le mur d'enceinte. Mesuré au balayage
## déterministe : 10 % des positions praticables rendaient le joueur
## invisible, et la quasi-totalité était collée au bord sud.
##
## Aucune hauteur de mur ne règle cela — près du bord, le rayon traverse
## l'enceinte à moins de deux mètres du sol, sous n'importe quel mur digne
## de ce nom. Le mur ne doit donc pas être sur la couche que la caméra
## interroge. Il garde toute sa fonction physique : les corps s'y arrêtent,
## puisque joueurs et mobs l'ajoutent à leur masque.
const LAYER_BORDURE := 64

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
## Ambiante = LE REBOND DU SOL, pas seulement celui du ciel.
##
## Elle était d'un bleu de ciel franc (a8d4f2), ce qui se défend sur une
## dalle de béton. Sur du sable, non : mesurée en image, une grande face de
## pierre crème à l'ombre — le flanc d'une tour, celui d'un mur — virait au
## gris-vert et sortait de la palette. La faute n'est pas à la pierre, elle
## est à la lumière qui l'atteint. Dans un désert, ce qui éclaire les
## ombres est le sable, et le sable est chaud.
##
## On garde un reste de bleu pour que les ombres ne se confondent pas avec
## les faces éclairées — c'est ce qui donne le relief. Mais le rebond
## domine, et les ombres restent DANS le monde au lieu de le contredire.
const COL_AMBIANTE_JOUR := Color("d2c4a6")
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

# --- RUINES SOLAIRES : LA PALETTE DE LA PLANCHE ---------------------------
#
# UN SEUL BIOME SUR TOUTE LA CARTE, et c'est la décision qui commande tout
# le reste. Le monde comptait six univers — cité néon, fonderie, bosquet,
# canyon, camp, ruines — qui se contredisaient d'un secteur à l'autre. La
# planche de direction artistique en impose un seul : un désert ensoleillé
# où des civilisations avancées ont laissé des ruines de pierre claire,
# de métal cobalt et d'énergie solaire.
#
# Les six secteurs ne disparaissent pas pour autant : ils deviennent SIX
# LIEUX DU MÊME MONDE. Ce qui les distingue n'est plus la matière — c'est
# le RELIEF, la DENSITÉ et le rôle qu'ils jouent dans le parcours. Une
# esplanade dallée ne se confond pas avec un champ de dunes, même bâtie
# dans la même pierre.
#
# HUIT TEINTES, PAS UNE DE PLUS. C'est le nuancier de la planche, et s'y
# tenir est ce qui donnera l'unité. Chaque fois qu'on est tenté d'en
# ajouter une neuvième, c'est qu'on cherche à distinguer par la couleur ce
# qu'il faudrait distinguer par la forme.

## SABLE DORÉ — le sol du monde, et les trois quarts de l'écran vu de haut.
const COL_SABLE := Color("f2cc86")
## Sable d'ombre, pour creuser les creux et les abords de ruine.
const COL_SABLE_OMBRE := Color("d9ab63")
## PIERRE CRÈME — toute la maçonnerie ancienne. Claire, chaude, propre.
##
## ABAISSÉE DE ead9bd À dfc59a APRÈS MESURE EN IMAGE. La valeur de la
## planche, lue au nuancier, arrivait à l'écran presque blanche : sous un
## soleil à pleine énergie, avec une saturation poussée à 1,32, une pierre
## déjà claire brûle. Les murets et les colonnes devenaient des masses
## blanches sans relief, et le sable pâle derrière elles ne les détachait
## plus. Ce n'est pas une trahison de la planche — c'est ce qu'il faut
## écrire dans le fichier pour OBTENIR la planche à l'écran.
const COL_PIERRE_CREME := Color("dfc59a")
## Sa face à l'ombre. Deux valeurs suffisent à faire lire un biseau.
const COL_PIERRE_OMBRE := Color("b8996b")
## COBALT PROFOND — le métal des anciens. C'est LUI qui dit « technologie »
## et qui empêche le désert de virer au monochrome sépia.
const COL_COBALT := Color("1e3f8f")
const COL_COBALT_CLAIR := Color("3560c4")
## TURQUOISE LUMINEUX — l'énergie. Émissif, jamais éclairant : il brille
## sur lui-même sans coûter une seule lumière dynamique au rendu mobile.
const COL_TURQUOISE := Color("2fd6e8")
## OR SOLAIRE — les liserés, les cerclages, les emblèmes. Par touches.
const COL_OR := Color("e0a63c")
## MAGENTA VIVANT — les fleurs, et rien d'autre. Le point le plus saturé de
## la carte, donc le plus rare : c'est ce qui lui garde son pouvoir.
const COL_MAGENTA := Color("e2467f")
## VERT OASIS — cactus et plantes grasses.
const COL_VERT := Color("7cb05a")
const COL_VERT_CLAIR := Color("9ecd77")
## GRIS DOUX — les cailloux et le gravier. Neutre, il repose l'œil entre
## deux accents et ne concurrence rien.
##
## RÉCHAUFFÉ. Un gris parfaitement neutre posé sur du sable doré ne se lit
## pas comme neutre : il se lit comme BLEU, et le canyon s'est retrouvé
## semé de rochers qui ressemblaient à des blocs de glace — vérifié en
## image. Un gris légèrement sableux tient le même rôle de repos sans
## quitter le désert.
const COL_GRIS := Color("b8ab93")

# --- ANCIENS NOMS, CONSERVÉS LE TEMPS DE LA TRANSITION --------------------
#
# Le décor et les mobs les citent encore. Ils pointent désormais vers la
# palette solaire : le monde change de peau sans qu'une seule ligne de
# gameplay ne bouge.
const COL_PIERRE_CHAUDE := COL_PIERRE_CREME
const COL_PIERRE_CRETE := Color("f6ead4")
const COL_CACTUS := COL_VERT
const COL_CACTUS_CLAIR := COL_VERT_CLAIR
const COL_FLEUR := COL_MAGENTA
const COL_CRISTAL := COL_TURQUOISE
const COL_ROCHE := COL_GRIS
const COL_ROCHE_CHAUDE := COL_SABLE_OMBRE
const COL_PIERRE := COL_PIERRE_CREME

# --- SOLS DES SIX LIEUX --------------------------------------------------
#
# TOUS DÉRIVÉS DU SABLE, et c'est voulu : on ne change pas de monde en
# traversant, on change d'endroit. L'écart entre le plus clair et le plus
# sombre tient en une valeur et demie — assez pour qu'on sente le passage,
# trop peu pour qu'on croie avoir changé de planète.
#
# ─── TOUS ASSOMBRIS D'UN CRAN APRÈS MESURE ──────────────────────────────
#
# LE DÉFAUT. Les valeurs de la planche, lues au nuancier, donnaient un
# sable très clair. À l'écran, sous un soleil à pleine énergie et une
# saturation poussée à 1,32, ce sable arrivait au HAUT de la plage de
# tonalité — et tout ce qui était posé dessus y arrivait aussi. Sol et
# props se retrouvaient à la même valeur : vérifié en image, un muret de
# 1,1 m disparaissait dans le sable à la distance de la caméra de jeu.
#
# Ce qui a été essayé d'abord, et qui n'a rien donné : inverser les
# valeurs de la pierre, corps sombre et crête claire. Le principe était
# bon et il est resté, mais il ne pouvait pas suffire — quand le SOL est
# saturé, aucun réglage du prop ne recrée le contraste, parce que ce n'est
# pas le prop qui manque de place, c'est le fond qui n'en laisse plus.
#
# Le sol descend donc d'un cran. Il reste doré, il reste chaud, il reste
# la planche — mais il redevient un FOND, c'est-à-dire ce sur quoi les
# choses se détachent.
## L'ESPLANADE — dalles de pierre claire autour du pilier central.
const SOL_ESPLANADE := Color("d3b784")
## LES RUINES — sable mêlé de gravats, le plus couvert.
const SOL_RUINES := Color("d9a95d")
## LES DUNES — sable pur, ouvert, rapide.
const SOL_DUNES := Color("e2b968")
## LE CANYON — sable d'ombre entre les parois.
const SOL_CANYON := Color("bd8748")
## L'OASIS — le sable verdit à peine. C'est la seule note fraîche du sol.
const SOL_OASIS := Color("b3ad57")
## LE CHAMP DE CRISTAUX — sable pâli par la lumière qui en sort.
const SOL_CRISTAUX := Color("d8bd85")

# --- ANCIENS SOLS, REDIRIGÉS ---------------------------------------------
const SOL_CAMP := SOL_DUNES
const SOL_BOSQUET := SOL_OASIS
const SOL_FONDERIE := SOL_CRISTAUX
const SOL_NOYAU := SOL_ESPLANADE

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
## ARÈNE DE COMBAT PLUTÔT QUE MONDE OUVERT, via `-- --arene-test`.
##
## POURQUOI UN DRAPEAU ET NON UNE SCÈNE À PART. Une arène de test ne vaut
## que si elle est jouée par le VRAI jeu — mêmes bots, mêmes mobs, même
## caméra, même HUD, même réseau. Une scène parallèle qui recrée tout cela
## dériverait dès la première semaine, et l'on testerait un jeu qui n'est
## pas celui qu'on publie.
##
## Le drapeau ne change donc qu'une chose : ce que l'arène BÂTIT. Tout le
## reste du jeu ignore jusqu'à son existence.
var arene_test := false

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
	if "--arene-test" in OS.get_cmdline_user_args():
		arene_test = true
		print("[Cfg] Arène de combat 40 × 40 m (composition manuelle).")
	if est_mobile():
		quality = Quality.LOW
	# On ne touche PAS à `scaling_3d_scale` : l'export web utilise le rendu
	# `gl_compatibility`, où la mise à l'échelle 3D de Godot n'a aucun
	# effet. La ligne aurait rassuré sans rien faire.
	Engine.max_fps = 60
