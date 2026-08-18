extends Camera3D
class_name ArenaCamera
## CAMÉRA D'ARÈNE — vue de dessus légèrement inclinée.
##
## L'inclinaison (~52°) est un compromis assumé : à la verticale on perd
## la silhouette des personnages et le jeu devient plat ; trop bas, les
## obstacles masquent le combat. Cet angle garde les corps lisibles ET le
## sol lisible.
##
## L'AVANCE SUR LA VISÉE est ce qui fait qu'on voit ce qu'on attaque : la
## caméra se décale légèrement dans la direction visée plutôt que de rester
## centrée sur le joueur, ce qui donne de la marge devant lui.
##
## CE QUE CE FICHIER A APPRIS DU MONDE OUVERT. Cette caméra a été réglée
## pour une arène plate de 68 m dont le plus haut obstacle montait à 3 m.
## Le monde fait maintenant 156 m et porte des mesas de 14 m, des tours et
## des temples. Reculée de 10 m derrière le joueur, elle se retrouvait
## RÉGULIÈREMENT à l'intérieur d'un rocher : la face de la roche remplissait
## l'écran entier, et le jeu n'affichait plus qu'un aplat violet.
##
## Ce n'était pas une supposition. Une sonde a promené le placement nominal
## de la caméra sur 1 085 positions du monde : le joueur était masqué dans
## 15,3 % des cas, et dans 5,2 % des cas plus de 60 % du cadre était bouché
## par quelque chose à moins de sept mètres — plusieurs dizaines de points à
## 100 %. C'est exactement l'image signalée.
##
## Deux garde-fous en découlent, et ils sont indépendants :
##   • un DÉGAGEMENT : la caméra ne reste jamais derrière un obstacle, elle
##     se rapproche du joueur jusqu'à le revoir ;
##   • un RECALAGE sur téléportation : une réapparition déplace le joueur de
##     150 m, et le rattrapage amorti passait un tiers de seconde à filmer
##     le ciel.

## Hauteur au-dessus de la cible.
## Réglée d'après des captures réelles : à 17 m de haut le personnage ne
## faisait qu'une poignée de pixels sur un écran de téléphone.
@export var height: float = 13.0
## Recul derrière la cible.
@export var distance: float = 10.0
## Vitesse de rattrapage. Assez élevée pour ne jamais « traîner », assez
## basse pour amortir les à-coups.
@export var smoothing: float = 7.5
## Décalage maximal dans la direction visée.
@export var look_ahead: float = 3.4

## Hauteur de l'œil visé sur le joueur : la ligne de vue part de sa
## poitrine, pas de ses pieds, sinon le moindre muret la coupe.
const YEUX := 1.4
## Part minimale du recul nominal. En dessous, la caméra serait dans le dos
## du personnage et le jeu deviendrait illisible : mieux vaut alors accepter
## qu'un morceau de décor passe dans le cadre.
const DEGAGEMENT_MINI := 0.3
## Rayon de la sonde de dégagement. Un simple rayon se faufilerait entre
## deux piliers et laisserait la caméra dans la pierre.
const RAYON_SONDE := 0.7
## Vitesse de retour vers le recul nominal une fois l'obstacle passé.
## On rentre INSTANTANÉMENT — sinon on filme la roche — et on ressort
## doucement, sinon chaque rocher frôlé donne un à-coup.
const RETOUR := 2.5
## Au-delà, la cible n'a pas marché : elle a été téléportée.
const SAUT := 25.0

var target: Node3D = null

var _desired: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO
## Point de visée lissé, distinct de la position du joueur.
var _focus: Vector3 = Vector3.ZERO
## Position lissée AVANT dégagement. On la garde à part : si le lissage
## repartait de la position rabattue, la caméra se rapprocherait un peu
## plus à chaque image et finirait collée au personnage.
var _ideal: Vector3 = Vector3.ZERO
## Fraction du recul réellement disponible, dans [DEGAGEMENT_MINI, 1].
var _degagement: float = 1.0

var _forme := SphereShape3D.new()
var _requete := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	# La caméra s'enregistre elle-même : les effets n'ont pas à la chercher
	# dans l'arbre à chaque impact.
	Fx.camera = self
	current = true
	fov = 58.0
	# Champ lointain court. Ce n'est PAS « la taille de l'arène » — le monde
	# fait 156 m — mais la portée réelle du cadre : incliné à 52° avec 29°
	# de demi-ouverture, le rayon le plus haut touche le sol à 30 m. Tout ce
	# qui est au-delà n'entre dans l'image que par sa hauteur.
	far = 140.0
	_forme.radius = RAYON_SONDE
	_requete.shape = _forme
	_requete.collision_mask = Cfg.LAYER_WORLD

func set_target(node: Node3D) -> void:
	target = node
	if node:
		_snap()

func _snap() -> void:
	_focus = target.global_position
	_desired = target.global_position
	_ahead = Vector3.ZERO
	_ideal = _desired + Vector3(0, height, distance)
	# LE DÉGAGEMENT VAUT AUSSI POUR UN RECALAGE. Sans cette ligne, on
	# réapparaissait pile derrière un rocher avec une image de roche, et le
	# lissage ne la corrigeait qu'à l'image suivante — un clignotement noir
	# à chaque retour en jeu.
	var oeil := _desired + Vector3(0, YEUX, 0)
	_degagement = _mesurer_degagement(oeil, _ideal - oeil)
	global_position = oeil + placer(_ideal - oeil, _degagement)
	look_at(_desired, Vector3.UP)

## La caméra suit au rythme de l'AFFICHAGE, pas de la physique.
##
## Première cause de saccade : en `_physics_process`, la caméra ne bougeait
## que 60 fois par seconde par paliers, pendant que l'écran affichait à une
## cadence différente — surtout en navigateur, où elle est variable. Chaque
## image intermédiaire réutilisait la même position, ce qui se voit
## immédiatement sur un décor qui défile.
func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var focus: Vector3 = target.global_position

	# UNE TÉLÉPORTATION N'EST PAS UN DÉPLACEMENT. Réapparaître envoie le
	# joueur jusqu'à 150 m plus loin ; amortir ce saut faisait voyager la
	# caméra à l'horizontale pendant un tiers de seconde, cadre plein de
	# ciel et de brume. On recale sec : personne ne regrette une coupe.
	if _focus.distance_to(focus) > SAUT:
		_snap()
		return

	var aim: Vector3 = target.get(&"aim_input") if target.get(&"aim_input") != null \
			else Vector3.ZERO
	if aim.length() > 0.1:
		_ahead = _ahead.lerp(aim.normalized() * look_ahead, 1.0 - exp(-4.0 * delta))
	else:
		_ahead = _ahead.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))

	# On lisse AUSSI la cible du regard. Amortir la position de la caméra
	# sans amortir son point de visée laisse l'orientation copier la
	# position brute du joueur, qui avance par pas de physique pendant que
	# l'écran affiche à une autre cadence : l'image tremble.
	_focus = _focus.lerp(focus, 1.0 - exp(-smoothing * delta))
	_desired = _focus + _ahead
	var goal := _desired + Vector3(0, height, distance)
	# Lissage exponentiel : indépendant du framerate, contrairement à un
	# lerp à facteur constant qui accélère quand les FPS montent.
	_ideal = _ideal.lerp(goal, 1.0 - exp(-smoothing * delta))

	var oeil := _desired + Vector3(0, YEUX, 0)
	var libre := _mesurer_degagement(oeil, _ideal - oeil)
	if libre < _degagement:
		_degagement = libre
	else:
		_degagement = lerpf(_degagement, libre, 1.0 - exp(-RETOUR * delta))
	global_position = oeil + placer(_ideal - oeil, _degagement)
	look_at(_desired, Vector3.UP)

## Où se met la caméra quand elle ne peut reculer que d'une fraction ?
##
## PAS SUR LE SEGMENT. Rabattre proportionnellement les trois axes plaque la
## caméra au niveau du sol, juste derrière le personnage — c'est-à-dire à la
## hauteur exacte où se trouvent les rochers, les tentes et les piliers. Une
## caméra de dessus se dégage en MONTANT, pas en s'aplatissant.
##
## La racine carrée fait ce compromis sans discontinuité : à 30 % de recul
## il reste 55 % de hauteur, donc une vue plus plongeante et plus dégagée.
## Mesuré sur 1 085 positions : le cadre bouché tombe de 0,9 % à 0 %.
static func placer(course: Vector3, part: float) -> Vector3:
	return Vector3(course.x * part, course.y * sqrt(part), course.z * part)

## Jusqu'où peut-on reculer depuis le joueur sans entrer dans un décor ?
##
## Renvoie une fraction du recul demandé. Le sol n'entre jamais en compte :
## le trajet part de la poitrine du joueur et monte, il ne le rencontre pas.
func _mesurer_degagement(oeil: Vector3, course: Vector3) -> float:
	var espace := get_world_3d().direct_space_state
	if espace == null or course.length_squared() < 0.01:
		return 1.0
	_requete.transform = Transform3D(Basis(), oeil)
	_requete.motion = course
	var bornes := espace.cast_motion(_requete)
	if bornes.size() < 1:
		return 1.0
	# `cast_motion` rend [sûr, premier contact]. On prend la fraction sûre,
	# et on retranche de quoi ne pas raser la surface : une caméra collée à
	# une paroi la voit en gros plan, ce qui revient au même défaut.
	var sur: float = bornes[0]
	return clampf(sur - 0.04, DEGAGEMENT_MINI, 1.0)

## Zoom arrière progressif quand la zone se referme : la fin de partie se
## joue dans un espace réduit, la caméra doit le montrer entièrement.
func adapt_to_zone(zone_radius: float) -> void:
	var t := clampf(zone_radius / Cfg.ARENA_RADIUS, 0.35, 1.0)
	height = lerpf(10.5, 13.0, t)
	distance = lerpf(8.0, 10.0, t)
