extends CharacterBody3D
class_name Mob
## MOB — corps, comportement, télégraphe.
##
## AUTORITÉ : le serveur simule et décide ; les clients reçoivent des
## positions et jouent les effets. Un client ne tue jamais un mob lui-même,
## il apprend qu'il est mort.
##
## LE TÉLÉGRAPHE EST LA RÈGLE : aucune attaque ne part sans une phase
## d'anticipation VISIBLE (grossissement, halo, cercle au sol). C'est ce
## qui rend un combat lisible et juste — le joueur perd parce qu'il a mal
## réagi, jamais parce qu'il n'a pas vu venir.
##
## Les trois comportements sont volontairement DIFFÉRENTS dans ce qu'ils
## demandent au joueur :
##   • Charger  → esquiver latéralement au bon moment
##   • Shooter  → se rapprocher sous le feu, casser la ligne de vue
##   • Exploder → gérer l'espace et fuir une zone

enum State { IDLE, CHASE, TELEGRAPH, ACT, DEAD }

var data: MobData = null
var health: HealthComponent
var health_bar: HealthBar3D

var state: State = State.IDLE
var target: Node3D = null
var mob_id: int = 0

var _visual: Node3D
var _materials: Array[StandardMaterial3D] = []
var _danger_ring: MeshInstance3D = null
var _timer: float = 0.0
var _cooldown: float = 0.0
var _retarget: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _strafe: float = 1.0

func get_peer_id() -> int:
	# Les mobs n'appartiennent à personne ; renvoyer 0 évite au projectile
	# de confondre un mob avec son tireur.
	return 0

func setup(mob_data: MobData, id: int) -> void:
	data = mob_data
	mob_id = id
	name = "Mob_%d" % id

func _ready() -> void:
	add_to_group(&"mobs")
	collision_layer = Cfg.LAYER_MOB
	collision_mask = Cfg.LAYER_WORLD

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5 * data.scale
	capsule.height = 1.5 * data.scale
	shape.shape = capsule
	shape.position = Vector3(0, 0.75 * data.scale, 0)
	add_child(shape)

	_build_visual()

	health = HealthComponent.new()
	health.max_health = data.health
	add_child(health)
	health.health_changed.connect(func(c, m): health_bar.set_ratio(c / maxf(m, 0.01)))

	health_bar = HealthBar3D.new()
	health_bar.position = Vector3(0, 2.0 * data.scale, 0)
	add_child(health_bar)
	health_bar.build(0.95 * data.scale)

	_target_pos = global_position
	state = State.CHASE

## Chaque mob a une SILHOUETTE distincte : on doit savoir à quoi on a
## affaire avant même qu'il attaque.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var s := data.scale
	var body := VisualKit.mat(data.color)
	var dark := VisualKit.mat(data.color.darkened(0.4))
	var glow := VisualKit.mat(data.color.lightened(0.4), 1.2)

	# TROIS SILHOUETTES QUI NE SE RESSEMBLENT PAS, ET C'EST LE POINT.
	#
	# La règle qu'on s'impose : un joueur doit pouvoir nommer la famille
	# d'un mob EN VISION PÉRIPHÉRIQUE, sans le regarder et sans lire sa
	# couleur. Cela veut dire jouer sur trois axes à la fois — la masse, la
	# proportion et l'appui au sol :
	#
	#   fonceur   large, bas, posé au sol, cornu    → « ça va me rentrer dedans »
	#   tireur    étroit, HAUT, flottant, à œil     → « ça me vise de loin »
	#   kamikaze  rond, petit, hérissé, instable    → « ça va exploser »
	#
	# UNE SEULE PIÈCE PORTE LE CONTOUR SUR TÉLÉPHONE — le corps. C'est un
	# budget, pas un choix esthétique : au-delà d'un certain nombre
	# d'instances visibles, le rendu WebGL cesse purement et simplement de
	# dessiner la 3D. Voir `VisualKit.add_outline`.
	#
	# La couleur n'arrive qu'en quatrième position. C'est volontaire : elle
	# est le seul signal qui disparaisse à contre-jour ou dans une ombre.
	#
	# TOUT SE JOUE DANS LES MAILLES, PAS DANS `data.scale` : cette échelle
	# pilote aussi la capsule de collision, et l'augmenter aurait rendu le
	# fonceur plus facile à toucher. On change ce qu'on voit, pas ce qu'on
	# touche — la mécanique reste identique au pixel près.
	match data.behavior:
		"charger":
			# LARGE ET BAS. Le corps est aplati verticalement et étiré en
			# largeur : vu de dessus, il occupe presque deux fois la surface
			# d'un tireur, ce qui se lit avant toute couleur.
			var corps_fonceur := VisualKit.capsule(0.62 * s, 1.42 * s, body,
					Vector3(0, 0.60 * s, 0), Vector3(PI / 2.2, 0, 0))
			VisualKit.add_outline(corps_fonceur, 0.05, true)
			_visual.add_child(corps_fonceur)
			_visual.add_child(VisualKit.sphere(0.40 * s, dark,
					Vector3(0, 0.70 * s, -0.56 * s),
					Vector3(1.25, 0.85, 1.0)))
			# UNE ARÊTE SOMBRE SUR LE DOS. Vu de dessus — c'est-à-dire dans
			# la seule vue qu'aura le joueur — une capsule couchée n'est
			# qu'une pastille lisse : la capture le montrait comme une
			# tache rose sans avant ni arrière. Cette arête donne un axe à
			# la bête, donc une direction de charge lisible d'un coup d'œil.
			_visual.add_child(VisualKit.box(
					Vector3(0.22 * s, 0.16 * s, 1.15 * s), dark,
					Vector3(0, 1.02 * s, 0.05 * s)))
			# Cornes allongées vers l'AVANT : elles indiquent la direction de
			# la charge autant qu'elles disent l'espèce.
			# Cornes couchées vers l'avant MAIS relevées de vingt degrés :
			# à plat elles se confondaient avec le corps vu du dessus.
			_visual.add_child(VisualKit.cone(0.15 * s, 0.70 * s, glow,
					Vector3(-0.30 * s, 0.92 * s, -0.72 * s), Vector3(-1.05, 0, 0)))
			_visual.add_child(VisualKit.cone(0.15 * s, 0.70 * s, glow,
					Vector3(0.30 * s, 0.92 * s, -0.72 * s), Vector3(-1.05, 0, 0)))
			# Deux pattes trapues : elles POSENT la bête au sol. Un fonceur
			# qui flotte se confondrait avec un tireur.
			_visual.add_child(VisualKit.cylinder(0.14 * s, 0.34 * s, dark,
					Vector3(-0.30 * s, 0.17 * s, 0.10 * s)))
			_visual.add_child(VisualKit.cylinder(0.14 * s, 0.34 * s, dark,
					Vector3(0.30 * s, 0.17 * s, 0.10 * s)))
		"shooter":
			# ÉTROIT ET HAUT. Son œil culmine à 2 m alors que le fonceur
			# plafonne à 1 m : c'est un rapport du simple au double, visible
			# même quand les deux ne sont que deux taches à l'écran.
			var corps_tireur := VisualKit.sphere(0.40 * s, body,
					Vector3(0, 1.62 * s, 0), Vector3(0.9, 1.30, 0.9))
			VisualKit.add_outline(corps_tireur, 0.05, true)
			_visual.add_child(corps_tireur)
			_visual.add_child(VisualKit.sphere(0.20 * s, glow,
					Vector3(0, 1.66 * s, -0.32 * s)))
			# Collerette large sur un corps étroit : le contraste de largeur
			# entre les deux est ce qui fait lire « antenne », donc « tir ».
			_visual.add_child(VisualKit.cylinder(0.46 * s, 0.08 * s, dark,
					Vector3(0, 1.10 * s, 0)))
			_visual.add_child(VisualKit.cylinder(0.06 * s, 0.90 * s, dark,
					Vector3(0, 0.60 * s, 0)))
			# Il ne touche pas le sol : le socle flotte à vingt centimètres.
			_visual.add_child(VisualKit.sphere(0.17 * s, dark,
					Vector3(0, 0.24 * s, 0), Vector3(1.3, 0.6, 1.3)))
		_:  # exploder
			# ROND ET PETIT, hérissé sur tout son pourtour. Une boule n'a pas
			# d'orientation lisible — et c'est exactement le message : elle
			# ne charge pas, elle ne vise pas, elle arrive.
			var corps_kamikaze := VisualKit.sphere(0.52 * s, body,
					Vector3(0, 0.58 * s, 0), Vector3(1.0, 0.92, 1.0))
			VisualKit.add_outline(corps_kamikaze, 0.05, true)
			_visual.add_child(corps_kamikaze)
			for i in 8:
				var a := TAU * float(i) / 8.0
				_visual.add_child(VisualKit.cone(0.11 * s, 0.34 * s, glow,
						Vector3(cos(a) * 0.50 * s, 0.58 * s, sin(a) * 0.50 * s),
						Vector3(PI / 2.0, -a, 0)))
			_visual.add_child(VisualKit.sphere(0.20 * s, glow,
					Vector3(0, 1.06 * s, 0)))
			_visual.add_child(VisualKit.cylinder(0.17 * s, 0.12 * s, dark,
					Vector3(0, 0.09 * s, 0)))

	for child in _visual.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			_materials.append(child.material_override)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_time += delta

	if Net.is_server():
		_server_think(delta)
	else:
		# Clients : simple rattrapage de la position autoritaire.
		_target_pos = PlanMonde.replier_vers(global_position, _target_pos)
		global_position = global_position.lerp(_target_pos,
				1.0 - exp(-16.0 * delta))

	# Flottement du Shooter : il ne touche jamais le sol, ce qui le rend
	# reconnaissable de loin même immobile.
	if data.behavior == "shooter" and _visual:
		_visual.position.y = sin(_time * 2.4) * 0.14

func _server_think(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.45
		_acquire_target()
		_strafe = 1.0 if randf() < 0.5 else -1.0

	match state:
		State.CHASE:
			_chase(delta)
		State.TELEGRAPH:
			_telegraph(delta)
		State.ACT:
			_act(delta)
		_:
			velocity = Vector3.ZERO

	if not is_on_floor() and data.behavior != "shooter":
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	# LE MOB SE REPLIE AUTOUR DU JOUEUR. Sans cela, un mob qui poursuit à
	# travers la limite continue tout droit dans le vide : il vise la bonne
	# direction — l'écart est calculé sur le tore — mais sa position, elle,
	# n'est jamais ramenée. Au bout de quelques tours il se retrouve à des
	# centaines de mètres du monde, vivant, comptant dans le plafond de
	# mobs, et n'affrontant plus personne.
	global_position = PlanMonde.replier(global_position)
	_face_movement(delta)

func _face_movement(delta: float) -> void:
	var look := PlanMonde.ecart3(global_position, target.global_position) if target \
			else Vector3(velocity.x, 0, velocity.z)
	look.y = 0.0
	if look.length() > 0.1:
		# Même demi-tour que le joueur : les silhouettes de mobs (cornes du
		# Chargeur, œil du Tireur) sont modelées vers -Z.
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z) + PI,
				1.0 - exp(-delta / 0.11))

func _acquire_target() -> void:
	var best: Node3D = null
	var best_d := data.detection_range
	for node in get_tree().get_nodes_in_group(&"players"):
		if not is_instance_valid(node) or node.get(&"is_eliminated") == true:
			continue
		var d: float = PlanMonde.distance3(global_position, node.global_position)
		if d < best_d:
			best_d = d
			best = node
	target = best

# --- COMPORTEMENTS -------------------------------------------------------

func _chase(delta: float) -> void:
	if target == null:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		return
	var to := PlanMonde.ecart3(global_position, target.global_position)
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	var wish := dir

	if data.behavior == "shooter":
		# Le Shooter cherche une DISTANCE, pas un contact : il recule si on
		# le colle et se décale en permanence.
		if dist < data.preferred_distance * 0.75:
			wish = -dir
		elif dist > data.preferred_distance * 1.2:
			wish = dir
		else:
			wish = dir.cross(Vector3.UP) * _strafe

	# Lissage vectoriel exponentiel, comme pour le joueur : un `move_toward`
	# par axe donne des trajectoires en escalier et une allure d'automate.
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.lerp(wish * data.speed, 1.0 - exp(-delta / 0.16))
	velocity.x = flat.x
	velocity.z = flat.z

	if _cooldown <= 0.0 and dist <= data.attack_range:
		_enter_telegraph()

func _enter_telegraph() -> void:
	state = State.TELEGRAPH
	_timer = data.telegraph_time
	if data.behavior == "exploder":
		_show_danger_ring(data.explosion_radius)
	Net.broadcast(self, &"net_telegraph", [])

@rpc("authority", "call_local", "reliable")
func net_telegraph() -> void:
	# Grossissement + pulsation lumineuse : deux signaux redondants, pour
	# rester lisible même quand l'écran est chargé de particules.
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.28, 0.82, 1.28), 0.12)
		tw.tween_property(_visual, "scale", Vector3.ONE, data.telegraph_time)
	for m in _materials:
		m.emission_enabled = true
		m.emission = data.color.lightened(0.5)
		var tw2 := create_tween().set_loops(3)
		tw2.tween_property(m, "emission_energy_multiplier", 2.4,
				data.telegraph_time / 6.0)
		tw2.tween_property(m, "emission_energy_multiplier", 0.2,
				data.telegraph_time / 6.0)

func _telegraph(delta: float) -> void:
	# Immobilisation pendant l'anticipation : le joueur a une fenêtre nette
	# pour réagir, ce qui rend chaque attaque évitable.
	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)
	_timer -= delta
	if _timer > 0.0:
		return
	state = State.ACT
	match data.behavior:
		"charger":
			_timer = data.charge_duration
			var to := PlanMonde.ecart3(global_position, target.global_position) if target \
					else Vector3.FORWARD
			to.y = 0.0
			_charge_dir = to.normalized()
		"shooter":
			_fire_shot()
			_end_action()
		"exploder":
			_explode()

func _act(delta: float) -> void:
	if data.behavior != "charger":
		return
	velocity.x = _charge_dir.x * data.charge_speed
	velocity.z = _charge_dir.z * data.charge_speed
	_timer -= delta

	# Un obstacle stoppe net la charge : les rochers de l'arène deviennent
	# des outils défensifs plutôt que du décor.
	if get_slide_collision_count() > 0:
		Fx.impact(global_position + Vector3(0, 0.8, 0), data.color, 1.2)
		# Atténuée : un Chargeur percutant un rocher à l'autre bout de
		# l'arène n'a aucune raison de secouer l'écran du joueur.
		Fx.shake_at(global_position, 0.14)
		_end_action()
		return

	if target and PlanMonde.distance3(global_position, target.global_position) < 1.6:
		if target.has_method(&"server_take_damage"):
			target.call(&"server_take_damage", data.damage,
					global_position, 0, Cfg.Team.MOB)
		Fx.impact(target.global_position + Vector3(0, 1.0, 0), data.color, 1.4)
		_end_action()
		return

	if _timer <= 0.0:
		_end_action()

func _end_action() -> void:
	state = State.CHASE
	_cooldown = data.attack_cooldown

func _fire_shot() -> void:
	if target == null:
		return
	var origin := global_position + Vector3(0, 1.15 * data.scale, 0)
	var to := PlanMonde.ecart3(origin, target.global_position + Vector3(0, 1.0, 0))
	to.y = 0.0
	Net.broadcast(self, &"net_shoot", [origin, to.normalized()])

@rpc("authority", "call_local", "reliable")
func net_shoot(origin: Vector3, dir: Vector3) -> void:
	# Le tir de mob emprunte le même projectile que les armes, avec une
	# WeaponData construite à la volée : un seul code de projectile à
	# maintenir, donc un seul endroit où corriger un bug.
	var shot := WeaponData.new()
	shot.id = &"mob_shot"
	shot.damage = data.damage
	shot.range = data.attack_range * 1.3
	shot.projectile_speed = data.projectile_speed
	shot.projectile_radius = 0.22
	shot.color = data.color.lightened(0.25)
	shot.trail_length = 1.6
	var p := Pool.acquire(Weapon.PROJECTILE_SCENE, get_tree().current_scene)
	if p:
		(p as Projectile).setup(shot, origin, dir, Cfg.Team.MOB, 0, Net.is_server())
	Fx.muzzle_flash(get_tree().current_scene, origin, shot.color, 0.8)

func _explode() -> void:
	Net.broadcast(self, &"net_explode", [global_position])
	if Net.is_server():
		var space := get_world_3d().direct_space_state
		var params := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = data.explosion_radius
		params.shape = sphere
		params.transform = Transform3D(Basis(), global_position)
		params.collision_mask = Cfg.LAYER_PLAYER
		for hit in space.intersect_shape(params, 8):
			var body = hit.get("collider")
			if body and body.has_method(&"server_take_damage"):
				var d: float = PlanMonde.distance3(body.global_position, global_position)
				var falloff := clampf(1.0 - d / data.explosion_radius, 0.3, 1.0)
				body.call(&"server_take_damage", data.damage * falloff,
						global_position, 0, Cfg.Team.MOB)
		# L'Exploder se sacrifie : c'est ce qui rend son approche menaçante.
		server_take_damage(9999.0, global_position, 0, Cfg.Team.MOB)

@rpc("authority", "call_local", "reliable")
func net_explode(at: Vector3) -> void:
	Fx.explosion(at, data.explosion_radius, data.color)
	_hide_danger_ring()

## Cercle au sol : dit EXACTEMENT où il ne faut pas être. Sans lui, une
## explosion de zone est une punition arbitraire.
func _show_danger_ring(radius: float) -> void:
	_hide_danger_ring()
	_danger_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.04
	cyl.radial_segments = 28
	_danger_ring.mesh = cyl
	var m := VisualKit.glow_mat(Cfg.COL_DANGER, 1.6)
	m.albedo_color.a = 0.34
	_danger_ring.material_override = m
	_danger_ring.position = Vector3(0, 0.03, 0)
	_danger_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_danger_ring)
	# Le cercle grandit jusqu'à son rayon réel pendant l'anticipation : la
	# montée elle-même sert de compte à rebours.
	_danger_ring.scale = Vector3(0.15, 1.0, 0.15)
	var tw := create_tween()
	tw.tween_property(_danger_ring, "scale", Vector3.ONE, data.telegraph_time)

func _hide_danger_ring() -> void:
	if _danger_ring and is_instance_valid(_danger_ring):
		_danger_ring.queue_free()
	_danger_ring = null

# --- DÉGÂTS ET MORT ------------------------------------------------------

## SERVEUR UNIQUEMENT.
func server_take_damage(amount: float, from: Vector3, killer_id: int,
		from_team: int) -> void:
	if not Net.is_server() or state == State.DEAD:
		return
	# Les mobs ne se blessent pas entre eux : sinon un Exploder nettoierait
	# la vague à lui seul et le joueur n'aurait rien à faire.
	if from_team == Cfg.Team.MOB and killer_id == 0 and amount < 9000.0:
		return
	if not health.apply_damage(amount, from, killer_id):
		return
	Net.broadcast(self, &"net_hurt", [health.current_health])
	if health.is_dead:
		Net.broadcast(self, &"net_death", [global_position, killer_id])

@rpc("authority", "call_local", "unreliable_ordered")
func net_hurt(value: float) -> void:
	if not Net.is_server():
		health.set_replicated_health(value)
	Fx.hit(global_position + Vector3(0, 1.0 * data.scale, 0), data.color, 0.9)
	# Le mob « encaisse » visiblement : écrasement bref + flash blanc.
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.2, 0.84, 1.2), 0.045)
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.09)
	for m in _materials:
		m.emission_enabled = true
		m.emission = Color.WHITE
		var tw2 := create_tween()
		tw2.tween_property(m, "emission_energy_multiplier", 0.0, 0.14).from(2.2)

@rpc("authority", "call_local", "reliable")
func net_death(at: Vector3, killer_id: int) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	health.is_dead = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	health_bar.visible = false
	_hide_danger_ring()
	Fx.death(at, data.color)

	# Réaction physique puis disparition : la séquence complète (impact →
	# détente → dissolution → loot) est ce qui rend un kill satisfaisant.
	if _visual:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_visual, "scale", Vector3(1.5, 0.25, 1.5), 0.18) \
				.set_trans(Tween.TRANS_BACK)
		tw.tween_property(_visual, "position:y", -0.5, 0.28)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()

	if Net.is_server():
		mob_died.emit(self, killer_id)

signal mob_died(mob: Mob, killer_id: int)

## Réplication de position, émise par le serveur.
@rpc("authority", "call_remote", "unreliable_ordered")
func net_position(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	rotation.y = yaw
