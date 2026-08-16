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

	match data.behavior:
		"charger":
			# Trapu, large, cornu : lit « ça va foncer sur moi ».
			_visual.add_child(VisualKit.capsule(0.52 * s, 1.15 * s, body,
					Vector3(0, 0.7 * s, 0), Vector3(PI / 2.2, 0, 0)))
			_visual.add_child(VisualKit.sphere(0.34 * s, dark,
					Vector3(0, 0.82 * s, -0.5 * s)))
			_visual.add_child(VisualKit.cone(0.11 * s, 0.42 * s, glow,
					Vector3(-0.22 * s, 0.95 * s, -0.62 * s), Vector3(-1.3, 0, 0)))
			_visual.add_child(VisualKit.cone(0.11 * s, 0.42 * s, glow,
					Vector3(0.22 * s, 0.95 * s, -0.62 * s), Vector3(-1.3, 0, 0)))
		"shooter":
			# Flottant, œil unique, fin : lit « il tire de loin ».
			_visual.add_child(VisualKit.sphere(0.46 * s, body,
					Vector3(0, 1.15 * s, 0), Vector3(1.0, 1.15, 1.0)))
			_visual.add_child(VisualKit.sphere(0.19 * s, glow,
					Vector3(0, 1.18 * s, -0.36 * s)))
			_visual.add_child(VisualKit.cylinder(0.38 * s, 0.1 * s, dark,
					Vector3(0, 0.66 * s, 0)))
			_visual.add_child(VisualKit.cylinder(0.07 * s, 0.5 * s, dark,
					Vector3(0, 0.3 * s, 0)))
		_:  # exploder
			# Rond, hérissé, instable : lit « ne me laisse pas t'approcher ».
			_visual.add_child(VisualKit.sphere(0.58 * s, body,
					Vector3(0, 0.72 * s, 0)))
			for i in 6:
				var a := TAU * float(i) / 6.0
				_visual.add_child(VisualKit.cone(0.1 * s, 0.34 * s, glow,
						Vector3(cos(a) * 0.55 * s, 0.72 * s, sin(a) * 0.55 * s),
						Vector3(PI / 2.0, -a, 0)))
			_visual.add_child(VisualKit.sphere(0.2 * s, glow,
					Vector3(0, 1.22 * s, 0)))

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
	_face_movement(delta)

func _face_movement(delta: float) -> void:
	var look := target.global_position - global_position if target \
			else Vector3(velocity.x, 0, velocity.z)
	look.y = 0.0
	if look.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), 9.0 * delta)

func _acquire_target() -> void:
	var best: Node3D = null
	var best_d := data.detection_range
	for node in get_tree().get_nodes_in_group(&"players"):
		if not is_instance_valid(node) or node.get(&"is_eliminated") == true:
			continue
		var d: float = global_position.distance_to(node.global_position)
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
	var to := target.global_position - global_position
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

	var speed := data.speed
	velocity.x = move_toward(velocity.x, wish.x * speed, 34.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 34.0 * delta)

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
			var to := (target.global_position - global_position) if target \
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
		Fx.shake(0.14)
		_end_action()
		return

	if target and global_position.distance_to(target.global_position) < 1.6:
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
	var to := target.global_position + Vector3(0, 1.0, 0) - origin
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
				var d: float = body.global_position.distance_to(global_position)
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
