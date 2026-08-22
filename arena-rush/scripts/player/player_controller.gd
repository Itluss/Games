extends Node
class_name PlayerController
## PILOTAGE HUMAIN — traduit clavier/souris et tactile en intentions.
##
## Ce nœud ne bouge rien lui-même : il REMPLIT les champs d'intention du
## joueur, que celui-ci simule ensuite. Cette séparation permet au même
## corps d'être piloté par un humain, par un bot, ou par le réseau, sans
## qu'une seule ligne de Player ne change.
##
## VISÉE ASSISTÉE : le cœur de la jouabilité tactile. Le joueur donne une
## direction grossière (ou rien du tout) et le jeu accroche la cible la
## plus menaçante dans ce cône. Sans elle, tirer au doigt sur une cible
## mobile est frustrant ; avec elle, le combat reste nerveux.

## Demi-angle du cône d'accrochage QUAND LE JOUEUR VISE — pouce glissé
## sur le bouton de tir ou souris. Il était à 55° : assez large pour
## qu'en visant un AUTRE ennemi, l'accrochage retombe sur le premier —
## le joueur ne pouvait littéralement pas changer de cible. À 16°, la
## direction du pouce désigne SA cible, et l'aimant ne fait plus que
## pardonner le tremblement ; hors de tout cône, le tir part exactement
## où le pouce pointe. Sans indice de visée, l'accrochage reste
## l'ennemi le mieux placé, sans cône — le tap n'a pas changé.
const AIM_CONE := deg_to_rad(16.0)
const AIM_RANGE_BONUS := 1.25

var player: Player = null
var _hud: Node = null

func _ready() -> void:
	set_process(false)

func attach(p: Player) -> void:
	player = p
	set_process(true)

func _process(_delta: float) -> void:
	if player == null or player.is_eliminated:
		return
	_hud = get_tree().get_first_node_in_group(&"hud")

	player.move_input = _read_move()
	player.aim_input = _compute_aim()
	player.want_fire = _read_fire()
	# Le front d'appui est LATCHÉ côté joueur : le contrôleur tourne dans
	# _process et le tir dans _physics_process, deux cadences distinctes.
	# Poser un booléen d'image serait perdu une fois sur deux.
	if _read_tap():
		player.want_tap = true

	if _read_swap():
		player.swap_weapon()
	if _read_dash():
		player.want_dash = true
	# La visée du CANON : pendant le glissement, l'aperçu au sol suit le
	# pouce ; au lever, la direction figée part avec l'ordre.
	if _hud and _hud.has_method(&"special_aim_vector"):
		var sv: Vector2 = _hud.call(&"special_aim_vector")
		player.special_apercu = Vector3(sv.x, 0.0, sv.y)
	if _read_special():
		player.want_special = true
		player.special_visee = Vector3.ZERO
		if _hud and _hud.has_method(&"consume_special_visee"):
			var fv: Vector2 = _hud.call(&"consume_special_visee")
			player.special_visee = Vector3(fv.x, 0.0, fv.y)

func _read_move() -> Vector2:
	# Le clavier et le joystick coexistent : on teste une tablette avec un
	# clavier branché sans changer de build.
	var kb := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if kb.length() > 0.05:
		return kb
	if _hud and _hud.has_method(&"move_vector"):
		return _hud.call(&"move_vector")
	return Vector2.ZERO

## Intention de tir.
##
## LE DÉFAUT QUE CETTE FONCTION CORRIGE : l'action « attack » était liée
## au CLIC GAUCHE, et Godot traduit tout appui tactile en clic souris.
## Poser le pouce sur le joystick de déplacement tirait donc une rafale.
## Le personnage semblait tirer tout seul dès qu'on le faisait avancer,
## et le bouton de tir paraissait inutile.
##
## Le tir a désormais des sources EXPLICITES, et le stick de déplacement
## n'en fait pas partie.
func _read_fire() -> bool:
	# Bouton de tir du HUD : la source principale, au doigt comme à la
	# souris.
	if _hud and _hud.has_method(&"is_firing") and _hud.call(&"is_firing"):
		return true
	# Clavier : indispensable pour tester au bureau sans viser à la souris.
	if Input.is_action_pressed(&"attack"):
		return true
	# Souris, hors tactile UNIQUEMENT, et seulement si le curseur ne
	# survole aucun élément d'interface — sans quoi on retomberait sur le
	# défaut d'origine dès qu'on clique le joystick.
	if not Cfg.is_touch_platform() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and get_viewport().gui_get_hovered_control() == null:
		return true
	return false

## Appui NEUF sur la gâchette, toutes sources confondues.
func _read_tap() -> bool:
	var neuf := Input.is_action_just_pressed(&"attack")
	if _hud and _hud.has_method(&"consume_tap") and _hud.call(&"consume_tap"):
		neuf = true
	return neuf


func _read_swap() -> bool:
	if Input.is_action_just_pressed(&"swap_weapon"):
		return true
	if _hud and _hud.has_method(&"consume_swap"):
		return _hud.call(&"consume_swap")
	return false

func _read_special() -> bool:
	if InputMap.has_action(&"special") \
			and Input.is_action_just_pressed(&"special"):
		return true
	if _hud and _hud.has_method(&"consume_special"):
		return _hud.call(&"consume_special")
	return false


func _read_dash() -> bool:
	if Input.is_action_just_pressed(&"dash"):
		return true
	if _hud and _hud.has_method(&"consume_dash"):
		return _hud.call(&"consume_dash")
	return false

## Cible prioritaire : la plus proche pondérée par l'écart angulaire.
## Un ennemi droit devant est préféré à un ennemi légèrement plus proche
## mais sur le côté — c'est ce que le joueur attend intuitivement.
func _compute_aim() -> Vector3:
	var hint := _aim_hint()
	var origin := player.global_position
	var range_m := 14.0
	if player.weapon and player.weapon.data:
		range_m = player.weapon.data.range * AIM_RANGE_BONUS

	var best: Node3D = null
	var best_score := INF
	for group in [&"mobs", &"players"]:
		for node in get_tree().get_nodes_in_group(group):
			if node == player or not is_instance_valid(node):
				continue
			if node.get(&"is_eliminated") == true:
				continue
			var hc = node.get(&"health")
			if hc != null and hc.is_dead:
				continue
			# LE PLUS COURT CHEMIN. Une cible située juste au-delà de la
			# limite du monde est à deux mètres ; mesurée « à plat » elle
			# est à cent quarante, donc jamais retenue — et la visée
			# automatique cesserait de fonctionner sur toute une bande de
			# la carte sans que rien ne le signale.
			var to: Vector3 = PlanMonde.ecart3(origin, node.global_position)
			to.y = 0.0
			var dist := to.length()
			if dist > range_m or dist < 0.01:
				continue
			var dir := to / dist
			var angle := 0.0
			if hint.length() > 0.1:
				angle = absf(hint.normalized().angle_to(dir))
				if angle > AIM_CONE:
					continue
			var score := dist * (1.0 + angle * 1.4)
			if score < best_score:
				best_score = score
				best = node

	# La cible verrouillée est publiée pour que le joueur puisse
	# l'AFFICHER : une visée automatique invisible donne l'impression que
	# le personnage pivote tout seul sans raison.
	player.locked_target = best

	if best != null:
		var aim: Vector3 = PlanMonde.ecart3(origin, best.global_position)
		aim.y = 0.0
		return aim.normalized()
	if hint.length() > 0.1:
		return hint.normalized()
	# Aucune cible, aucune intention : on ne force AUCUNE direction. Le
	# joueur s'orientera alors selon son déplacement, ce qui est la seule
	# règle lisible. Renvoyer l'orientation courante la figeait.
	return Vector3.ZERO

## Direction souhaitée par le joueur, avant accrochage.
func _aim_hint() -> Vector3:
	if _hud and _hud.has_method(&"aim_vector"):
		var v: Vector2 = _hud.call(&"aim_vector")
		if v.length() > 0.15:
			return Vector3(v.x, 0.0, v.y)
	# Souris : on projette le curseur sur le plan du sol.
	if not Cfg.is_touch_platform():
		var cam := Fx.camera
		if cam:
			var mouse := cam.get_viewport().get_mouse_position()
			var from := cam.project_ray_origin(mouse)
			var dir := cam.project_ray_normal(mouse)
			if absf(dir.y) > 0.001:
				var t := (player.global_position.y + 1.0 - from.y) / dir.y
				if t > 0.0:
					var point := from + dir * t
					var to := point - player.global_position
					to.y = 0.0
					if to.length() > 0.4:
						return to
	# AUCUN indice de visée issu du déplacement.
	#
	# On renvoyait ici la direction du joystick gauche, ce qui revenait à
	# viser avec le pouce qui dirige : le cône d'accrochage suivait la
	# marche, si bien qu'un ennemi sur le côté restait ignoré tant qu'on
	# ne se tournait pas vers lui.
	#
	# Sans indice, l'accrochage retient simplement l'ennemi le plus
	# proche, où qu'il soit. C'est la règle du genre, et c'est ce qui
	# permet au stick gauche de ne servir qu'à DIRIGER. Faute de cible,
	# le tir part droit devant, dans l'axe du personnage.
	return Vector3.ZERO
