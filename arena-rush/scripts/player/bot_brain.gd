extends Node
class_name BotBrain
## ADVERSAIRE ARTIFICIEL — pilote un Player comme le ferait un humain.
##
## POURQUOI CE N'EST PAS UN LUXE : un battle royale sans adversaires n'est
## pas testable. Les bots permettent de jouer et d'évaluer la boucle
## complète — loot, pression, zone, victoire — dès la première exécution,
## sans deuxième appareil.
##
## Ils écrivent dans les MÊMES champs d'intention qu'un joueur humain :
## aucune logique de jeu ne sait qu'elle sert un bot, donc rien ne peut
## diverger entre les deux.

const THINK_INTERVAL := 0.25
## En dessous de cette distance, le bot cherche à reculer : sans cela il
## colle sa cible et le combat devient illisible.
const COMFORT_MIN := 6.0
const COMFORT_MAX := 13.0

var player: Player = null

var _think: float = 0.0
var _target: Node3D = null
var _wander: Vector3 = Vector3.ZERO
var _strafe: float = 1.0

func attach(p: Player) -> void:
	player = p

func _physics_process(delta: float) -> void:
	if player == null or player.is_eliminated or not Net.is_server():
		return
	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_retarget()

	var pos := player.global_position
	var desired := Vector3.ZERO

	if _target and is_instance_valid(_target):
		var to: Vector3 = _target.global_position - pos
		to.y = 0.0
		var dist := to.length()
		var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
		player.aim_input = dir
		# Tir uniquement à portée utile : un bot qui tire dans le vide
		# gaspille ses munitions et n'exerce aucune pression.
		var eff_range := player.weapon.data.range if player.weapon.data else 12.0
		player.want_fire = dist <= eff_range * 0.92

		if dist < COMFORT_MIN:
			desired = -dir
		elif dist > COMFORT_MAX:
			desired = dir
		# Déplacement latéral permanent : une cible immobile est triviale
		# à toucher, et un bot statique n'apprend rien au joueur.
		desired += dir.cross(Vector3.UP) * _strafe * 0.85
	else:
		player.want_fire = false
		if _wander.length() < 0.1 or pos.distance_to(_wander) < 3.0:
			_wander = _pick_wander_point()
		desired = (_wander - pos)
		desired.y = 0.0
		desired = desired.normalized()

	# La zone prime sur tout : un bot qui meurt hors zone ne joue pas.
	var safe := MatchDirector.zone_radius - 4.0
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > safe:
		desired = Vector3(-flat.normalized().x, 0.0, -flat.normalized().y) * 1.5

	player.move_input = Vector2(desired.x, desired.z).limit_length(1.0)

func _retarget() -> void:
	_strafe = 1.0 if randf() < 0.5 else -1.0
	var pos := player.global_position
	var best: Node3D = null
	var best_d := INF
	# Les mobs proches passent avant les joueurs lointains : c'est aussi
	# ainsi qu'un humain joue, et cela fait looter les bots.
	for group in [&"mobs", &"players"]:
		for node in get_tree().get_nodes_in_group(group):
			if node == player or not is_instance_valid(node):
				continue
			if node.get(&"is_eliminated") == true:
				continue
			var hc = node.get(&"health")
			if hc != null and hc.is_dead:
				continue
			var d: float = pos.distance_to(node.global_position)
			var weight: float = 1.0 if group == &"mobs" else 1.35
			if d * weight < best_d and d < 30.0:
				best_d = d * weight
				best = node
	_target = best

func _pick_wander_point() -> Vector3:
	var r: float = maxf(4.0, MatchDirector.zone_radius - 6.0)
	var a := randf() * TAU
	return Vector3(cos(a) * r * randf(), 0.0, sin(a) * r * randf())
