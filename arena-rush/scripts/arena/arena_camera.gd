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

## Hauteur au-dessus de la cible.
## Réglée d'après des captures réelles : à 17 m de haut le personnage ne
## faisait qu'une poignée de pixels sur un écran de téléphone.
@export var height: float = 13.5
## Recul derrière la cible.
@export var distance: float = 10.0
## Vitesse de rattrapage. Assez élevée pour ne jamais « traîner », assez
## basse pour amortir les à-coups.
@export var smoothing: float = 7.5
## Décalage maximal dans la direction visée.
@export var look_ahead: float = 3.4

var target: Node3D = null

var _desired: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO

func _ready() -> void:
	# La caméra s'enregistre elle-même : les effets n'ont pas à la chercher
	# dans l'arbre à chaque impact.
	Fx.camera = self
	current = true
	fov = 58.0
	# Champ lointain court : rien au-delà de l'arène n'a besoin d'être rendu.
	far = 140.0

func set_target(node: Node3D) -> void:
	target = node
	if node:
		_snap()

func _snap() -> void:
	_desired = target.global_position
	global_position = _desired + Vector3(0, height, distance)
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

	var aim: Vector3 = target.get(&"aim_input") if target.get(&"aim_input") != null \
			else Vector3.ZERO
	if aim.length() > 0.1:
		_ahead = _ahead.lerp(aim.normalized() * look_ahead, 1.0 - exp(-4.0 * delta))
	else:
		_ahead = _ahead.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))

	_desired = focus + _ahead
	var goal := _desired + Vector3(0, height, distance)
	# Lissage exponentiel : indépendant du framerate, contrairement à un
	# lerp à facteur constant qui accélère quand les FPS montent.
	global_position = global_position.lerp(goal, 1.0 - exp(-smoothing * delta))
	look_at(_desired, Vector3.UP)

## Zoom arrière progressif quand la zone se referme : la fin de partie se
## joue dans un espace réduit, la caméra doit le montrer entièrement.
func adapt_to_zone(zone_radius: float) -> void:
	var t := clampf(zone_radius / Cfg.ARENA_RADIUS, 0.35, 1.0)
	height = lerpf(11.0, 13.5, t)
	distance = lerpf(8.0, 10.0, t)
