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
	var _chrono0 := Time.get_ticks_usec() if SondeChrono.actif else 0
	_tick_chrono(delta)
	if SondeChrono.actif:
		SondeChrono.ajouter(&"cerveau_bot", Time.get_ticks_usec() - _chrono0)


func _tick_chrono(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_retarget()

	var pos := player.global_position
	var desired := Vector3.ZERO

	if _target and is_instance_valid(_target):
		# LE PLUS COURT CHEMIN, PAS LA SOUSTRACTION. Un adversaire situé à
		# quatre mètres derrière la couture est à 140 m « à plat » : le bot
		# viserait dans la direction exactement opposée, et jugerait la
		# cible hors de portée alors qu'elle est sur lui.
		var to := PlanMonde.ecart3(pos, _target.global_position)
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
		if _wander.length_squared() < 0.01 \
				or PlanMonde.distance3(pos, _wander) < 3.0:
			_wander = _pick_wander_point()
		# LE PLUS COURT CHEMIN PASSE SOUVENT PAR LE BORD. Un bot qui vise sa
		# destination « à plat » ferait tout le tour du monde pour rejoindre
		# un point situé à quatre mètres derrière la couture — et prendrait
		# la direction exactement opposée à la bonne.
		desired = PlanMonde.ecart3(pos, _wander)
		desired.y = 0.0
		desired = desired.normalized()

	# PLUS AUCUNE LIMITE À RESPECTER EN MODE PERSISTANT. Le monde s'enroule :
	# il n'y a plus de bord contre lequel se coller, donc plus rien à
	# repousser. Seule la zone du Battle Royale contraint encore.
	if not MatchDirector.est_persistant():
		var flat := Vector2(pos.x, pos.z)
		if flat.length() > MatchDirector.zone_radius - 4.0:
			desired = Vector3(-flat.normalized().x, 0.0,
					-flat.normalized().y) * 1.5
			_wander = Vector3.ZERO

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
			var d: float = PlanMonde.distance3(pos, node.global_position)
			var weight: float = 1.0 if group == &"mobs" else 1.35
			# 34 m et non 30 : sur une carte cinq fois plus grande, un bot
			# myope ne rencontre plus personne. On reste toutefois sous la
			# portée où le joueur peut réagir — un bot qui vous repère de
			# 60 m serait perçu comme tricheur.
			if d * weight < best_d and d < 34.0:
				best_d = d * weight
				best = node
	_target = best

## OÙ VA UN BOT QUI N'A PERSONNE À COMBATTRE ?
##
## L'ancienne réponse — un point au hasard dans un disque autour du centre —
## marchait sur une arène de 34 m : tout y était à portée. Sur 156 m, elle
## produirait des bots agglutinés au milieu et cinq secteurs déserts. Le
## monde paraîtrait vide partout sauf en un point.
##
## Ils PATROUILLENT donc d'un point d'intérêt à l'autre. Trois effets, tous
## voulus : la carte semble habitée jusque dans ses coins, les repères
## deviennent des lieux de rencontre — ce qui est leur raison d'être — et
## le joueur croise du monde en chemin plutôt qu'en un seul endroit.
##
## Une chance sur quatre de viser un point quelconque : sans elle, tous les
## bots suivraient les mêmes six routes et le monde paraîtrait scripté.
func _pick_wander_point() -> Vector3:
	if randf() < 0.25 or PlanMonde.POINTS_INTERET.is_empty():
		# N'importe où dans le carré : un monde sans bord n'a ni couronne
		# ni centre à éviter.
		var q := PlanMonde.enrouler(Vector2(
				randf_range(-PlanMonde.DEMI, PlanMonde.DEMI),
				randf_range(-PlanMonde.DEMI, PlanMonde.DEMI)))
		return Vector3(q.x, 0.0, q.y)
	var poi: Dictionary = PlanMonde.POINTS_INTERET[
			randi() % PlanMonde.POINTS_INTERET.size()]
	var c := PlanMonde.position_poi(poi)
	# On vise les ABORDS du repère, pas son centre exact : sinon les bots
	# se marchent dessus en arrivant, et le lieu devient un embouteillage.
	var ecart := float(poi["rayon_actif"]) * randf_range(0.4, 1.1)
	var b := randf() * TAU
	var q := PlanMonde.enrouler(c + Vector2(cos(b) * ecart, sin(b) * ecart))
	return Vector3(q.x, 0.0, q.y)
