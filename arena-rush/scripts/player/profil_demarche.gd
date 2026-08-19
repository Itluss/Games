extends RefCounted
class_name ProfilDemarche
## LES SIX DÉMARCHES — ce qui rend un personnage reconnaissable de loin.
##
## ─── LE PROBLÈME, ET POURQUOI IL NE SE RÈGLE PAS AVEC DES CLIPS ─────────
##
## L'exigence est qu'un joueur reconnaisse Milo, Poppy, Bruno, Nox, Ruby ou
## Gus SANS voir leur nom, à vitesse de jeu identique, depuis une caméra
## posée à dix mètres au-dessus d'eux. À cette distance, on ne voit ni un
## visage ni le détail d'une main : on voit une SILHOUETTE QUI OSCILLE.
##
## Une bibliothèque d'animations — celle de Meshy comprise — livre une
## course générique, la même pour les six. Rejouer le même clip plus vite
## ne fabrique pas une personnalité : cela fabrique le même personnage
## pressé. Ce qui distingue une démarche tient dans six grandeurs, et
## aucune n'est contenue dans un fichier d'animation :
##
##   CADENCE          combien de pas par seconde
##   REBOND           de combien le corps monte et descend à chaque pas
##   PENCHÉ           de combien le buste devance les pieds
##   BALANCEMENT      l'oscillation gauche/droite du haut du corps
##   AFFAISSEMENT     de combien le bassin cède sous le poids à l'appui
##   TRAÎNE           l'inertie des accessoires — chapeau, cheveux, manteau
##
## Ce fichier ne contient QUE des nombres et leur justification. Il ne
## joue rien, il ne dessine rien : il décrit six façons de se déplacer, et
## la couche de locomotion s'en sert pour poser le corps à chaque image.
##
## ─── POURQUOI DES NOMBRES ET NON DES ANIMATIONS ────────────────────────
##
## Trois raisons, et la troisième est la plus importante.
##
## 1. Six personnages × huit états — repos, départ, avant, pas chassé
##    gauche, pas chassé droit, arrière, arrêt, demi-tour — font
##    quarante-huit clips à produire, à nommer, à raccorder et à
##    maintenir. Un profil en fait six lignes.
## 2. Les modèles sont pour l'instant des maillages STATIQUES, sans os. Un
##    profil les anime quand même ; un clip ne le peut pas.
## 3. Le jour où les squelettes arrivent, ces mêmes nombres pilotent la
##    VITESSE des clips et les couches additives. Le profil ne devient pas
##    caduc : il devient le réglage du mélange. Rien de ce qui est écrit
##    ici n'est à jeter.
##
## ─── LA RÈGLE D'ÉQUILIBRAGE ────────────────────────────────────────────
##
## Aucun de ces nombres ne touche à la vitesse RÉELLE du personnage. Bruno
## avance aussi vite que Ruby — il le fait en moins de pas, plus longs. La
## distinction est entièrement visuelle, l'équilibrage reste au gameplay.

## Cadence de référence, en pas par seconde à vitesse nominale.
##
## C'est le nombre le plus discriminant des six : l'œil compte les appuis
## avant même d'avoir identifié la silhouette. Gus fait plus du double des
## pas de Bruno pour parcourir la même distance.
const CADENCE := "cadence"
## Amplitude verticale du corps, en mètres, crête à crête.
const REBOND := "rebond"
## Inclinaison du buste vers l'avant en marche, en radians.
const PENCHE := "penche"
## Roulis gauche/droite du haut du corps, en radians.
const BALANCEMENT := "balancement"
## Descente du bassin à l'appui, en mètres. C'est ce qui donne le POIDS.
const AFFAISSEMENT := "affaissement"
## Vivacité du rattrapage des accessoires. Bas = traîne longtemps.
const TRAINE := "traine"
## Vivacité de l'orientation du corps vers sa direction, en tours/seconde.
const PIVOT := "pivot"
## Durée du démarrage et de l'arrêt, en secondes. Un lourd met du temps.
const ELAN := "elan"
const FREIN := "frein"
## Rebond parasite à l'arrêt : le corps dépasse puis revient.
const DEPASSEMENT := "depassement"
## Écartement latéral des appuis, en mètres. Une base large lit « stable ».
const BASE := "base"


## LES SIX PROFILS.
##
## Les valeurs sont pensées PAR RAPPORT LES UNES AUX AUTRES. Prises une à
## une elles ne veulent rien dire ; c'est l'écart entre Bruno et Gus qui
## fait qu'on les distingue. Toute retouche doit donc se juger en
## comparant les six côte à côte, jamais un seul dans son coin.
const PROFILS := {

	# ── MILO — le pistolero ────────────────────────────────────────────
	# « précis, sûr de lui, équilibré ». Tout est au MILIEU : c'est lui
	# l'étalon, et c'est ce qui donne leur sens aux écarts des autres. Sa
	# marque à lui n'est pas une exagération, c'est une ABSENCE — presque
	# pas de rebond, un buste qui ne bouge pas. Un homme qui ne se presse
	# jamais. Seul le chapeau garde de l'inertie, et c'est la seule chose
	# qui bouge quand il démarre ou s'arrête.
	&"milo": {
		CADENCE: 1.85, REBOND: 0.035, PENCHE: 0.05, BALANCEMENT: 0.030,
		AFFAISSEMENT: 0.018, TRAINE: 7.0, PIVOT: 7.5,
		ELAN: 0.18, FREIN: 0.16, DEPASSEMENT: 0.10, BASE: 0.13,
	},

	# ── POPPY — la ferrailleuse ────────────────────────────────────────
	# « nerveuse, enthousiaste, explosive ». Petits pas très fréquents et
	# beaucoup de vertical : elle rebondit. Le penché est le plus fort des
	# six, non par agressivité mais parce qu'elle est TIRÉE par le poids de
	# son canon — l'impression de courir derrière son propre équipement.
	# Le dépassement à l'arrêt est le plus marqué : elle s'arrête, rebondit
	# une fois, puis se stabilise.
	&"poppy": {
		CADENCE: 2.75, REBOND: 0.075, PENCHE: 0.16, BALANCEMENT: 0.055,
		AFFAISSEMENT: 0.012, TRAINE: 5.0, PIVOT: 9.0,
		ELAN: 0.10, FREIN: 0.12, DEPASSEMENT: 0.40, BASE: 0.10,
	},

	# ── BRUNO — la masse ───────────────────────────────────────────────
	# « poids, puissance, masse ». Cadence la plus BASSE des six, et de
	# loin : à vitesse égale, il parcourt la même distance en deux fois
	# moins d'appuis, donc en foulées deux fois plus longues. C'est le
	# cœur de sa lecture.
	#
	# L'AFFAISSEMENT EST SA SIGNATURE. Le bassin cède de quatre centimètres
	# à chaque appui — quatre fois plus que Poppy. C'est ce qui fait qu'on
	# SENT le sol sous lui au lieu de le voir glisser dessus.
	#
	# Pivot lent et élan long : il ne change pas de cap, il négocie son
	# virage. Base large : les pieds loin l'un de l'autre, jamais alignés.
	# RÉGLÉ APRÈS MESURE, ET C'EST LE BANC QUI L'A EXIGÉ. Premier jet,
	# Bruno et Ruby ne se séparaient que sur UN axe — leur cadence. Tout
	# le reste était à moins d'un quart d'écart : même amplitude
	# verticale, presque même roulis. Un colosse et une voltigeuse
	# indiscernables dès qu'ils ralentissent, c'est-à-dire exactement le
	# défaut que ce lot doit éviter.
	#
	# Bruno prend donc PLUS de vertical (par l'affaissement, pas par le
	# rebond : il ne saute pas, il s'enfonce) et MOINS de roulis. Ruby
	# fait l'inverse. Deux nervosités, deux axes — c'est la seule façon
	# qu'ils restent lisibles côte à côte.
	&"bruno": {
		CADENCE: 1.15, REBOND: 0.055, PENCHE: 0.09, BALANCEMENT: 0.062,
		AFFAISSEMENT: 0.058, TRAINE: 3.0, PIVOT: 3.2,
		ELAN: 0.34, FREIN: 0.32, DEPASSEMENT: 0.30, BASE: 0.20,
	},

	# ── NOX — le duelliste ─────────────────────────────────────────────
	# « prédateur, agile, silencieux ». Le REBOND LE PLUS FAIBLE des six :
	# il glisse, il ne marche pas. Tête stable, buste penché, centre de
	# gravité bas — d'où un affaissement quasi nul, puisqu'il est déjà
	# fléchi en permanence.
	#
	# Le pivot est le plus rapide des six : ses changements de direction
	# sont secs, ce sont les jambes qui travaillent, pas le torse.
	&"nox": {
		CADENCE: 1.70, REBOND: 0.018, PENCHE: 0.19, BALANCEMENT: 0.022,
		AFFAISSEMENT: 0.008, TRAINE: 6.0, PIVOT: 11.0,
		ELAN: 0.12, FREIN: 0.14, DEPASSEMENT: 0.08, BASE: 0.11,
	},

	# ── RUBY — la voltigeuse ───────────────────────────────────────────
	# « vive, mobile, imprévisible ». Le BALANCEMENT LE PLUS FORT des six :
	# elle roule des épaules, le corps oscille latéralement. C'est ce qui
	# la sépare de Poppy, qui rebondit verticalement là où Ruby ondule
	# horizontalement — deux nervosités, deux axes.
	#
	# La traîne est la plus lente de toutes : sa chevelure continue son
	# mouvement bien après qu'elle se soit arrêtée. Sur une silhouette vue
	# de dessus, c'est ce nuage magenta qui bouge en retard qui la
	# désigne.
	# Rebond ABAISSÉ et roulis RELEVÉ après mesure — voir la note de
	# Bruno. Ruby ondule là où il s'enfonce ; sans cet écart, les deux se
	# confondaient sur trois signatures sur quatre.
	&"ruby": {
		CADENCE: 2.35, REBOND: 0.034, PENCHE: 0.10, BALANCEMENT: 0.128,
		AFFAISSEMENT: 0.010, TRAINE: 2.4, PIVOT: 8.5,
		ELAN: 0.11, FREIN: 0.13, DEPASSEMENT: 0.34, BASE: 0.12,
	},

	# ── GUS — le vétéran ───────────────────────────────────────────────
	# « expérimenté, légèrement comique mais crédible ». LA CADENCE LA PLUS
	# HAUTE et la foulée la plus courte : il trottine. Le contraste est
	# tout le personnage — les jambes s'agitent, le buste reste digne.
	#
	# D'où un balancement modéré malgré la cadence : s'il oscillait autant
	# qu'il pédale, il deviendrait burlesque, et le cahier des charges dit
	# « crédible ». Le comique vient de l'ÉCART entre le bas et le haut,
	# pas de l'exagération des deux.
	#
	# Base large pour un si petit personnage : c'est ce qui l'empêche de
	# lire comme un enfant.
	&"gus": {
		CADENCE: 3.10, REBOND: 0.030, PENCHE: 0.04, BALANCEMENT: 0.048,
		AFFAISSEMENT: 0.010, TRAINE: 4.5, PIVOT: 6.0,
		ELAN: 0.14, FREIN: 0.15, DEPASSEMENT: 0.16, BASE: 0.16,
	},
}


## Profil de secours — celui de Milo, l'étalon.
##
## POURQUOI PAS DES ZÉROS. Un personnage inconnu doit marcher correctement,
## pas glisser sans bouger : une valeur neutre est un défaut visible, un
## profil médian ne l'est pas.
static func profil(id: StringName) -> Dictionary:
	return PROFILS.get(id, PROFILS[&"milo"])


## Le profil existe-t-il vraiment ? Sert aux bancs, qui doivent distinguer
## « personnage sans profil » de « personnage au profil neutre ».
static func connu(id: StringName) -> bool:
	return PROFILS.has(id)


## L'identifiant de démarche déduit du nom de modèle : « hero_milo » →
## « milo ». Une seule règle, appliquée partout, plutôt qu'une table de
## correspondance de plus à tenir à jour.
static func id_depuis_modele(modele: String) -> StringName:
	return StringName(modele.trim_prefix("hero_").trim_suffix(".glb"))
