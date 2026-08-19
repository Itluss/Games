extends Node
class_name Locomotion
## COUCHE DE LOCOMOTION — l'état du déplacement, et la pose qui en découle.
##
## ─── LE PRINCIPE : LA DISTANCE NE DÉPEND JAMAIS DE L'ANIMATION ─────────
##
## Le gameplay décide de la vitesse réelle. Cette couche ne la modifie
## JAMAIS : elle l'observe et en tire une pose. C'est la règle qui permet
## à Bruno d'avancer aussi vite que Ruby tout en ayant l'air deux fois plus
## lourd — et c'est aussi ce qui garantit qu'un réglage d'animation ne
## puisse pas déséquilibrer le jeu par accident.
##
## Le lien va donc dans UN SEUL SENS :
##
##     vitesse réelle  ──►  phase de pas  ──►  pose du corps
##
## et jamais l'inverse. Le pas est cadencé par la DISTANCE PARCOURUE, pas
## par une horloge : un personnage ralenti par un obstacle ralentit ses
## appuis tout seul, sans qu'on ait rien à écrire. C'est ce qui évite le
## défaut le plus visible d'un jeu d'action — les pieds qui patinent.
##
## ─── LES ÉTATS ─────────────────────────────────────────────────────────
##
## REPOS      immobile
## DEPART     l'élan, entre l'arrêt et la vitesse de croisière
## AVANT      déplacement dans le sens du regard
## CHASSE     déplacement latéral, buste gardé vers la cible
## ARRIERE    recul, face à la cible
## ARRET      la décélération, avec son dépassement
## DEMI_TOUR  changement de cap marqué
##
## CE QUI DISTINGUE CHASSE ET ARRIERE D'AVANT n'est pas la vitesse mais
## l'ANGLE entre le déplacement et la visée. C'est cet angle, et lui seul,
## qui décide de l'état : un personnage qui vise à gauche en courant à
## droite fait un pas chassé, quelle que soit sa vitesse.

enum Etat { REPOS, DEPART, AVANT, CHASSE, ARRIERE, ARRET, DEMI_TOUR }

## Au-delà de cet angle entre visée et déplacement, on ne court plus vers
## l'avant : on chasse. 50° — mesuré à l'œil, c'est là que la lecture
## bascule.
const ANGLE_CHASSE := deg_to_rad(50.0)
## Au-delà, on recule.
const ANGLE_ARRIERE := deg_to_rad(130.0)
## Écart de cap qui déclenche un demi-tour plutôt qu'une simple courbe.
const ANGLE_DEMI_TOUR := deg_to_rad(115.0)
## En deçà, on considère le personnage immobile. Sous ce seuil, la phase
## de pas se fige : sans cela, un personnage collé à un mur continuerait à
## marcher sur place.
const VITESSE_MORTE := 0.25

var etat: Etat = Etat.REPOS
var profil: Dictionary = ProfilDemarche.profil(&"milo")

## Vitesse nominale du personnage, en m/s. Sert de référence à la cadence :
## la fréquence des pas suit le RAPPORT vitesse/nominale, ce qui rend le
## profil indépendant de l'équilibrage.
var vitesse_nominale: float = 6.0

# --- Entrées, telles que les fournit le contrôleur -----------------------
var _entree := Vector2.ZERO
var _visee := Vector3.FORWARD
var _vitesse := Vector3.ZERO

# --- État interne --------------------------------------------------------
## Phase du cycle de pas, en tours. Un tour = deux appuis.
var _phase := 0.0
var _elan := 0.0            # 0 à l'arrêt, 1 en régime
var _depassement := 0.0     # rebond résiduel après un arrêt
var _cap := 0.0             # orientation courante du bas du corps
var _cap_vise := 0.0
var _traine := Vector3.ZERO # inertie des accessoires
var _temps_etat := 0.0


# --- API ----------------------------------------------------------------
#
# ELLE NE CONNAÎT NI CLAVIER NI JOYSTICK, et c'est volontaire. Elle reçoit
# un vecteur et une direction ; d'où ils viennent ne la regarde pas. Un
# joystick virtuel, une manette, un test automatique ou un bot branchent
# la même chose.

## Intention de déplacement, normalisée dans le cercle unité.
## x = droite, y = avant. C'est exactement ce que rend un joystick virtuel.
func set_move_input(input: Vector2) -> void:
	_entree = input if input.length_squared() <= 1.0 else input.normalized()


## Direction de visée, dans le plan horizontal.
func set_aim_direction(direction: Vector3) -> void:
	var plat := Vector3(direction.x, 0.0, direction.z)
	if plat.length_squared() > 0.0001:
		_visee = plat.normalized()


## Vitesse réelle, telle que la physique vient de la produire. C'est la
## SEULE source de vérité de la cadence : on ne devine pas le déplacement
## depuis l'entrée, on lit ce qui s'est réellement passé.
func set_velocity(v: Vector3) -> void:
	_vitesse = Vector3(v.x, 0.0, v.z)


func vitesse_plane() -> float:
	return _vitesse.length()


# --- MISE À JOUR --------------------------------------------------------

func avancer(delta: float) -> void:
	var v := vitesse_plane()
	var bouge := v > VITESSE_MORTE
	var etat_avant := etat

	# ── L'ÉLAN ─────────────────────────────────────────────────────────
	# Il monte en `ELAN` secondes et retombe en `FREIN`. C'est lui qui
	# fabrique le départ et l'arrêt : sans lui, un personnage passerait de
	# zéro à pleine cadence en une image, ce qui se lit comme un saut.
	var cible := 1.0 if bouge else 0.0
	var duree: float = float(profil[ProfilDemarche.ELAN] if bouge
			else profil[ProfilDemarche.FREIN])
	_elan = move_toward(_elan, cible, delta / maxf(duree, 0.01))

	# ── LA PHASE DE PAS, CADENCÉE PAR LA DISTANCE ──────────────────────
	# `cadence` est un nombre de pas par seconde À VITESSE NOMINALE. On le
	# module par le rapport de vitesse réelle : à mi-vitesse, deux fois
	# moins d'appuis. C'est ce qui empêche les pieds de patiner.
	if bouge:
		var rapport := v / maxf(vitesse_nominale, 0.01)
		_phase += delta * float(profil[ProfilDemarche.CADENCE]) * rapport
		_phase = fmod(_phase, 1.0)

	# ── LE DÉPASSEMENT ─────────────────────────────────────────────────
	# Au moment précis où le personnage cesse d'avancer, on injecte une
	# impulsion qui s'amortit. C'est le petit rebond de Poppy et le
	# tassement de Bruno — la trace de ce que le corps venait de faire.
	if etat_avant != Etat.ARRET and not bouge and _elan > 0.35:
		_depassement = float(profil[ProfilDemarche.DEPASSEMENT])
	_depassement = move_toward(_depassement, 0.0, delta * 3.4)

	# ── LE CAP ─────────────────────────────────────────────────────────
	if bouge:
		_cap_vise = atan2(_vitesse.x, _vitesse.z)
	var ecart := wrapf(_cap_vise - _cap, -PI, PI)
	var pas_pivot := float(profil[ProfilDemarche.PIVOT]) * TAU * delta
	_cap += clampf(ecart, -pas_pivot, pas_pivot)
	_cap = wrapf(_cap, -PI, PI)

	# ── L'ÉTAT ─────────────────────────────────────────────────────────
	etat = _decider(bouge, absf(ecart))
	_temps_etat = 0.0 if etat != etat_avant else _temps_etat + delta


func _decider(bouge: bool, ecart: float) -> Etat:
	if not bouge:
		# On reste en ARRÊT tant que le corps n'a pas fini de se tasser :
		# c'est ce qui laisse le dépassement se voir au lieu d'être coupé
		# net par un retour au repos.
		return Etat.ARRET if (_elan > 0.05 or _depassement > 0.01) else Etat.REPOS
	if ecart > ANGLE_DEMI_TOUR:
		return Etat.DEMI_TOUR
	if _elan < 0.9 and etat in [Etat.REPOS, Etat.ARRET, Etat.DEPART]:
		return Etat.DEPART
	# L'angle entre le déplacement et la VISÉE, pas entre déplacement et
	# cap : c'est la visée qui dit où regarde le buste.
	var angle := absf(_vitesse.normalized().signed_angle_to(_visee, Vector3.UP))
	if angle > ANGLE_ARRIERE:
		return Etat.ARRIERE
	if angle > ANGLE_CHASSE:
		return Etat.CHASSE
	return Etat.AVANT


# --- LA POSE ------------------------------------------------------------
#
# Ce que la couche RESTITUE : un décalage et une rotation à appliquer au
# visuel. Elle ne touche jamais au corps physique — le personnage se
# déplace exactement où le gameplay l'a mis, seule son APPARENCE bouge.
# C'est ce qui rend l'ensemble inoffensif pour la collision et le réseau.

## Décalage vertical du corps, en mètres.
func hauteur() -> float:
	var p := _phase * TAU
	# DEUX APPUIS PAR CYCLE : le corps monte à chaque pas, pas à chaque
	# foulée — d'où le facteur deux sur la phase du rebond.
	var rebond := -absf(sin(p)) * float(profil[ProfilDemarche.REBOND])
	# L'affaissement du bassin arrive à l'APPUI, décalé d'un quart de
	# cycle par rapport au sommet du rebond. C'est ce décalage qui fait
	# lire le poids : le corps tombe sur la jambe avant de repartir.
	var tasse := -maxf(0.0, sin(p - PI * 0.5)) \
			* float(profil[ProfilDemarche.AFFAISSEMENT])
	var lit := (rebond + tasse) * _elan
	# Le dépassement pousse vers le bas puis relâche : un vrai corps se
	# tasse quand il s'arrête, il ne se fige pas.
	return lit - _depassement * float(profil[ProfilDemarche.REBOND]) * 1.6


## Inclinaison du buste : penché vers l'avant, roulis latéral.
func inclinaison() -> Vector3:
	var p := _phase * TAU
	var penche := float(profil[ProfilDemarche.PENCHE]) * _elan
	# Le roulis suit le CYCLE COMPLET, pas les appuis : le corps bascule
	# d'un côté puis de l'autre, une fois par foulée.
	var roulis := sin(p) * float(profil[ProfilDemarche.BALANCEMENT]) * _elan
	# En marche arrière on se redresse : personne ne recule penché en
	# avant, et c'est un repère de lecture immédiat pour le joueur d'en
	# face.
	if etat == Etat.ARRIERE:
		penche = -penche * 0.6
	return Vector3(penche, 0.0, roulis)


## Écartement latéral des appuis. Fait osciller le corps autour de son axe
## de marche : une base large se lit « stable », une base étroite « vive ».
func derive_laterale() -> float:
	return sin(_phase * TAU) * float(profil[ProfilDemarche.BASE]) * 0.35 * _elan


## Orientation du bas du corps.
func cap() -> float:
	return _cap


## SÉPARATION HAUT / BAS DU CORPS.
##
## Le bas suit le déplacement, le haut reste tourné vers la cible. C'est ce
## qui permet de courir vers la droite en tirant vers la gauche sans que le
## personnage ne se torde. La valeur est BORNÉE : au-delà, un buste vrillé
## à cent-quatre-vingts degrés sur son bassin devient une difformité, et
## mieux vaut alors laisser le bas suivre.
const VRILLE_MAXI := deg_to_rad(62.0)

func vrille_buste() -> float:
	var vise := atan2(_visee.x, _visee.z)
	return clampf(wrapf(vise - _cap, -PI, PI), -VRILLE_MAXI, VRILLE_MAXI)


## TRAÎNE DES ACCESSOIRES — chapeau, cheveux, manteau, moustache.
##
## Un ressort amorti nourri par l'ACCÉLÉRATION du corps, pas par sa
## vitesse : une masse pendue ne réagit pas au fait qu'on avance, elle
## réagit au fait qu'on CHANGE de vitesse. C'est pourquoi le chapeau de
## Milo ne bouge qu'au démarrage, à l'arrêt et dans les virages —
## exactement ce que demande sa fiche.
func traine(delta: float, acceleration: Vector3) -> Vector3:
	var vivacite := float(profil[ProfilDemarche.TRAINE])
	_traine = _traine.lerp(-acceleration * 0.045, clampf(delta * vivacite, 0.0, 1.0))
	return _traine


func nom_etat() -> String:
	return ["REPOS", "DEPART", "AVANT", "CHASSE", "ARRIERE", "ARRET",
			"DEMI_TOUR"][etat]
