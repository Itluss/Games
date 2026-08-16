extends CharacterBody3D
class_name Player
## JOUEUR — corps, inventaire, réplication.
##
## RÉPARTITION DE L'AUTORITÉ (voir MultiplayerManager) :
##   • le pair PROPRIÉTAIRE simule son déplacement et diffuse sa position ;
##   • le SERVEUR décide des dégâts, de la mort, du loot et de la victoire.
##
## VISÉE ASSISTÉE : au doigt, viser précisément est impossible. Le joueur
## indique une DIRECTION et le jeu accroche la cible la plus pertinente
## dans ce cône. Sans cette assistance, le jeu serait injouable sur
## téléphone ; avec elle, il reste nerveux et lisible.

signal inventory_changed(slots: Array, active: int)
signal health_changed(current: float, maximum: float)
signal died()

const SPEED := 7.2
const ACCELERATION := 70.0
const FRICTION := 58.0
const TURN_SPEED := 16.0
const DASH_SPEED := 20.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.5
const NET_SEND_HZ := 20.0
## Dégâts par seconde hors de la zone sûre.
const ZONE_DPS := 11.0

var peer_id: int = 1
var is_bot: bool = false
var display_name: String = "Joueur"

## Intentions, remplies par le contrôleur (humain) ou le cerveau (bot).
var move_input: Vector2 = Vector2.ZERO
var aim_input: Vector3 = Vector3.FORWARD
var want_fire: bool = false
var want_dash: bool = false

var health: HealthComponent
var visual: CharacterVisual
var weapon: Weapon
var health_bar: HealthBar3D

## Inventaire : deux emplacements, remplis d'identifiants d'armes.
var slots: Array[StringName] = [&"", &""]
var active_slot: int = 0

var is_eliminated: bool = false

var _facing: float = 0.0
var _dash_time: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _net_accum: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _zone_accum: float = 0.0

func get_peer_id() -> int:
	return peer_id

## Vrai si CE pair pilote ce corps. Les bots sont pilotés par le serveur.
func is_local_authority() -> bool:
	if is_bot:
		return Net.is_server()
	return peer_id == Net.local_id()

func setup(id: int, name_text: String, bot: bool) -> void:
	peer_id = id
	display_name = name_text
	is_bot = bot
	name = "Player_%d" % id

func _ready() -> void:
	add_to_group(&"players")
	collision_layer = Cfg.LAYER_PLAYER
	collision_mask = Cfg.LAYER_WORLD

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)

	# Couleur d'équipe : se distinguer d'un coup d'œil des autres joueurs
	# est une information de survie, pas une coquetterie.
	var is_me := (not is_bot) and peer_id == Net.local_id()
	var body_col := Cfg.COL_LOCAL_PLAYER if is_me else Cfg.COL_ENEMY_PLAYER
	visual = CharacterVisual.new()
	add_child(visual)
	visual.build(body_col, body_col.lightened(0.35))

	weapon = Weapon.new()
	var mount := visual.get_weapon_mount()
	if mount:
		mount.add_child(weapon)
	else:
		add_child(weapon)

	health = HealthComponent.new()
	health.max_health = 100.0
	add_child(health)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)

	health_bar = HealthBar3D.new()
	health_bar.position = Vector3(0, 2.15, 0)
	add_child(health_bar)
	health_bar.build(1.1)
	# La barre du joueur local est superflue (le HUD la porte déjà) et
	# encombrerait le centre de l'écran.
	health_bar.visible = not is_me

	_target_pos = global_position
	equip_weapon_id(Registry.starting_weapon().id if Registry.starting_weapon() else &"basic_blaster", 0)

func _physics_process(delta: float) -> void:
	if is_eliminated:
		return
	if is_local_authority():
		_simulate(delta)
		_replicate(delta)
	else:
		_interpolate(delta)

	if Net.is_server():
		_tick_zone_damage(delta)

	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED,
			0.0, 1.0)
	visual.update_visual(delta, speed_ratio)

# --- SIMULATION ----------------------------------------------------------

func _simulate(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd -= delta

	var wish := Vector3(move_input.x, 0.0, move_input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	if want_dash and _dash_cd <= 0.0:
		want_dash = false
		_dash_cd = DASH_COOLDOWN
		_dash_time = DASH_TIME
		# Une esquive sans direction part vers l'avant : jamais sur place,
		# ce qui rendrait le bouton inutile sous pression.
		_dash_dir = wish if wish.length() > 0.1 \
				else Vector3(sin(_facing), 0, cos(_facing))
		Fx.shake(0.06)

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		var target := wish * SPEED
		var rate := ACCELERATION if wish.length() > 0.05 else FRICTION
		velocity.x = move_toward(velocity.x, target.x, rate * delta)
		velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# Orientation : on regarde là où on TIRE, pas là où on marche — c'est
	# ce qui permet de reculer en tirant, mouvement clé du genre.
	var face := aim_input if aim_input.length() > 0.1 \
			else Vector3(velocity.x, 0, velocity.z)
	if face.length() > 0.1:
		_facing = lerp_angle(_facing, atan2(face.x, face.z), TURN_SPEED * delta)
	rotation.y = _facing
	visual.rotation.y = 0.0

	if want_fire:
		_try_fire()

func _try_fire() -> void:
	if weapon.data == null or not weapon.can_fire():
		return
	var dir := Vector3(sin(_facing), 0, cos(_facing))
	if aim_input.length() > 0.1:
		dir = aim_input.normalized()
	# Le client DEMANDE, le serveur DISPOSE. Le tir part visuellement tout
	# de suite chez le tireur (réactivité), mais aucun dégât n'est appliqué
	# tant que le serveur n'a pas rediffusé l'ordre.
	weapon.shake_local()
	Net.to_server(self, &"server_request_fire", [dir])

@rpc("any_peer", "call_local", "reliable")
func server_request_fire(dir: Vector3) -> void:
	if not Net.is_server() or is_eliminated:
		return
	# Le serveur revalide la cadence : un client modifié qui spammerait la
	# demande n'obtient rien de plus qu'un joueur honnête.
	if not weapon.consume():
		return
	var origin := weapon.muzzle_position()
	Net.broadcast(self, &"net_fire", [origin, dir.normalized()])

@rpc("authority", "call_local", "reliable")
func net_fire(origin: Vector3, dir: Vector3) -> void:
	if weapon.data == null:
		return
	visual.set_state(CharacterVisual.State.ATTACK)
	weapon.fire(origin, dir, Cfg.Team.PLAYER, peer_id, Net.is_server())

# --- ZONE ----------------------------------------------------------------

func _tick_zone_damage(delta: float) -> void:
	if not MatchDirector.is_outside_zone(global_position):
		_zone_accum = 0.0
		return
	_zone_accum += delta
	# Application par paliers d'une demi-seconde : des dégâts continus
	# déclencheraient un flash à chaque image et rendraient l'écran illisible.
	if _zone_accum >= 0.5:
		_zone_accum -= 0.5
		server_take_damage(ZONE_DPS * 0.5, global_position, 0, Cfg.Team.MOB)

# --- DÉGÂTS (SERVEUR) ----------------------------------------------------

## SERVEUR UNIQUEMENT. Unique porte d'entrée des dégâts sur ce joueur.
func server_take_damage(amount: float, from: Vector3, killer_id: int,
		from_team: int) -> void:
	if not Net.is_server() or is_eliminated or health.is_dead:
		return
	# Pas de tir ami entre joueurs sur soi-même ; le PvP entre joueurs
	# distincts reste évidemment actif.
	if from_team == Cfg.Team.PLAYER and killer_id == peer_id:
		return
	if not health.apply_damage(amount, from, killer_id):
		return
	Net.broadcast(self, &"net_health", [health.current_health, from])
	if health.is_dead:
		Net.broadcast(self, &"net_die", [killer_id])
		MatchDirector.eliminate(peer_id)

@rpc("authority", "call_local", "unreliable_ordered")
func net_health(value: float, from: Vector3) -> void:
	if not Net.is_server():
		health.set_replicated_health(value)
	visual.set_state(CharacterVisual.State.HIT)
	visual.flash(Cfg.COL_DANGER)
	Fx.hit(global_position + Vector3(0, 1.0, 0), Cfg.COL_DANGER, 1.0)
	if peer_id == Net.local_id() and not is_bot:
		Fx.shake(0.16)

@rpc("authority", "call_local", "reliable")
func net_die(killer_id: int) -> void:
	if is_eliminated:
		return
	is_eliminated = true
	health.is_dead = true
	visual.set_state(CharacterVisual.State.DEATH)
	Fx.death(global_position, Cfg.COL_ENEMY_PLAYER)
	health_bar.visible = false
	# Le corps reste au sol comme trace de l'affrontement, mais ne bloque
	# plus personne.
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	died.emit()

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.set_ratio(current / maxf(maximum, 0.01))
	health_changed.emit(current, maximum)

func _on_died(killer_id: int) -> void:
	pass  # la mort est diffusée par server_take_damage, pas ici

# --- RÉPLICATION ---------------------------------------------------------

func _replicate(delta: float) -> void:
	if not Net.is_networked():
		return
	_net_accum += delta
	if _net_accum < 1.0 / NET_SEND_HZ:
		return
	_net_accum = 0.0
	net_state.rpc(global_position, _facing)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(pos: Vector3, yaw: float) -> void:
	# Le serveur borne la position reçue : un client ne peut pas se
	# téléporter hors de l'arène, même en trichant sur son propre corps.
	if Net.is_server():
		var flat := Vector2(pos.x, pos.z)
		if flat.length() > Cfg.ARENA_RADIUS + 6.0:
			flat = flat.normalized() * (Cfg.ARENA_RADIUS + 6.0)
			pos = Vector3(flat.x, pos.y, flat.y)
	_target_pos = pos
	_target_yaw = yaw

func _interpolate(delta: float) -> void:
	# Lissage exponentiel : masque la latence sans jamais faire glisser un
	# corps loin derrière sa position réelle.
	var k := 1.0 - exp(-18.0 * delta)
	global_position = global_position.lerp(_target_pos, k)
	_facing = lerp_angle(_facing, _target_yaw, k)
	rotation.y = _facing
	velocity = (_target_pos - global_position) / maxf(delta, 0.001)

# --- INVENTAIRE ----------------------------------------------------------

func equip_weapon_id(id: StringName, slot: int) -> void:
	var data := Registry.weapon(id)
	if data == null:
		return
	slots[slot] = id
	active_slot = slot
	weapon.equip(data)
	visual.attach_weapon(weapon.take_model())
	inventory_changed.emit(slots, active_slot)

## Ramassage. Retourne l'identifiant de l'arme ÉJECTÉE (vide si aucune) :
## l'inventaire étant plein, l'échange doit rendre l'ancienne au sol plutôt
## que de la faire disparaître.
func server_pickup(id: StringName) -> StringName:
	if Registry.weapon(id) == null:
		return &""
	var free_slot := slots.find(&"")
	if free_slot != -1:
		Net.broadcast(self, &"net_set_slot", [free_slot, id, true])
		return &""
	# Inventaire plein : on remplace l'arme ACTIVE. Le joueur choisit donc
	# ce qu'il abandonne, simplement en sélectionnant son slot avant de
	# marcher sur le loot.
	var dropped := slots[active_slot]
	Net.broadcast(self, &"net_set_slot", [active_slot, id, true])
	return dropped

@rpc("authority", "call_local", "reliable")
func net_set_slot(slot: int, id: StringName, make_active: bool) -> void:
	slots[slot] = id
	if make_active:
		equip_weapon_id(id, slot)
	else:
		inventory_changed.emit(slots, active_slot)
	var data := Registry.weapon(id)
	if data:
		Fx.pickup(global_position + Vector3(0, 1.0, 0), data.color)

func swap_weapon() -> void:
	var other := 1 - active_slot
	if slots[other] == &"":
		return
	equip_weapon_id(slots[other], other)

func dash_ready_ratio() -> float:
	return 1.0 - clampf(_dash_cd / DASH_COOLDOWN, 0.0, 1.0)
