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

const SPEED := 5.6
## Constantes de TEMPS (secondes pour atteindre ~63 % de la cible), et
## non des taux par image. Un lissage en `facteur * delta` change de
## comportement avec la cadence d'affichage — donc le jeu ne réagit pas
## pareil à 30 et à 120 FPS, ce qui se ressent immédiatement en navigateur
## où la cadence varie. La forme exponentielle `1 - exp(-dt/tau)` est,
## elle, rigoureusement identique à toute cadence.
const ACCEL_TAU := 0.11
const BRAKE_TAU := 0.15
const TURN_TAU := 0.065
const DASH_SPEED := 15.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.5
const NET_SEND_HZ := 20.0
## Hauteur d'affichage du personnage, distincte de sa boîte de collision.
const VISUAL_HEIGHT := 2.5
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

## Cible actuellement accrochée par la visée assistée, publiée par le
## contrôleur. Sert uniquement à l'affichage de l'indicateur.
var locked_target: Node3D = null
var _aim_line: MeshInstance3D = null
var _lock_ring: MeshInstance3D = null

var _facing: float = 0.0
var _dash_time: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _net_accum: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _zone_accum: float = 0.0
## Accélération instantanée, transmise au visuel pour l'inclinaison.
var _accel: Vector3 = Vector3.ZERO

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
	capsule.radius = 0.48
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	# Couleur d'équipe : se distinguer d'un coup d'œil des autres joueurs
	# est une information de survie, pas une coquetterie.
	var is_me := (not is_bot) and peer_id == Net.local_id()
	var body_col := Cfg.COL_LOCAL_PLAYER if is_me else Cfg.COL_ENEMY_PLAYER
	# Accent orange pour Kael, éclairci pour les adversaires : la couleur
	# secondaire porte l'identité autant que la principale.
	var accent := Cfg.COL_KAEL_ACCENT if is_me else body_col.lightened(0.35)
	visual = CharacterVisual.new()
	add_child(visual)
	# Personnage volontairement SURDIMENSIONNÉ par rapport à une taille
	# réaliste. La caméra est en plongée et vise le téléphone : à 1,70 m
	# Kael n'occupait qu'une poignée de pixels et se lisait comme une
	# tache sombre. Les jeux d'arène en vue de dessus exagèrent tous
	# l'échelle du personnage pour cette raison.
	visual.build(body_col, accent, VISUAL_HEIGHT)

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

	# ANNEAU D'ÉQUIPE. Tous les joueurs partagent le même modèle : sans
	# repère au sol, on ne distingue plus un allié d'un adversaire, ce qui
	# est une information de survie. C'est la solution des jeux d'arène,
	# et elle a l'avantage de ne pas dénaturer le personnage — le teinter
	# salirait ses couleurs d'origine.
	var anneau := MeshInstance3D.new()
	var couronne := TorusMesh.new()
	couronne.inner_radius = 0.52
	couronne.outer_radius = 0.68
	couronne.rings = 24
	couronne.ring_segments = 6
	anneau.mesh = couronne
	anneau.material_override = VisualKit.glow_mat(body_col.lerp(Color.BLACK, 0.15), 0.9)
	anneau.position = Vector3(0, 0.05, 0)
	anneau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(anneau)

	health_bar = HealthBar3D.new()
	health_bar.position = Vector3(0, 2.9, 0)
	add_child(health_bar)
	health_bar.build(1.1)
	# La barre du joueur local est superflue (le HUD la porte déjà) et
	# encombrerait le centre de l'écran.
	health_bar.visible = not is_me

	# INDICATEURS DE VISÉE — joueur local seulement. Une visée assistée
	# qu'on ne voit pas donne l'impression que le personnage décide seul.
	if is_me:
		_build_aim_visuals()

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
	# L'inclinaison est calculée dans le repère du personnage : pencher
	# « vers l'avant » n'a de sens que relativement à son orientation.
	var local_v := Vector3(velocity.x, 0, velocity.z).rotated(Vector3.UP, -_facing)
	var local_a := _accel.rotated(Vector3.UP, -_facing)
	visual.set_motion(local_v / maxf(SPEED, 0.01), local_a / 40.0)
	visual.update_visual(delta, speed_ratio)
	_update_aim_visuals()

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
		# Étirement dans l'axe de l'esquive : sans déformation, une
		# accélération brutale ne se lit pas, elle se subit.
		visual.punch(Vector3(0.78, 0.9, 1.35), 0.18)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var before := flat
	if _dash_time > 0.0:
		_dash_time -= delta
		flat = _dash_dir * DASH_SPEED
	else:
		# Approche VECTORIELLE : on lisse le vecteur vitesse entier, pas
		# X et Z séparément. Traiter les axes isolément donnait une
		# accélération différente en diagonale et des trajectoires en
		# escalier — la sensation « mécanique ».
		var target := wish * SPEED
		var tau := ACCEL_TAU if wish.length() > 0.05 else BRAKE_TAU
		flat = flat.lerp(target, 1.0 - exp(-delta / tau))
	velocity.x = flat.x
	velocity.z = flat.z
	# L'accélération réelle nourrit l'inclinaison du corps : c'est elle qui
	# donne du POIDS au personnage.
	_accel = (flat - before) / maxf(delta, 0.001)

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# ORIENTATION — une seule règle, et elle doit être devinable :
	#   on regarde où l'on MARCHE, sauf quand on TIRE.
	#
	# Auparavant le personnage s'orientait en permanence vers la cible
	# auto-visée, donc il pivotait seul, sans cause visible pour le joueur.
	# Ne verrouiller la visée que pendant le tir permet toujours de
	# reculer en tirant — le mouvement clé du genre — sans rendre les
	# déplacements hors combat illisibles.
	var face := Vector3(velocity.x, 0, velocity.z)
	if want_fire and aim_input.length() > 0.1:
		face = aim_input
	if face.length() > 0.1:
		_facing = lerp_angle(_facing, atan2(face.x, face.z),
				1.0 - exp(-delta / TURN_TAU))
	# `_facing` est l'angle de TIR, mesuré depuis +Z. Or dans Godot l'avant
	# d'un nœud est son axe -Z local : c'est vers -Z que regardent le
	# modèle, le canon de l'arme, le chevron et le télémètre. Sans ce
	# demi-tour, tout l'attirail visuel pointe à l'exact opposé du tir.
	rotation.y = _facing + PI
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
	rotation.y = _facing + PI
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


# --- INDICATEURS DE VISÉE ------------------------------------------------
#
# Trois repères, parce que « je ne sais pas dans quel sens je suis ni où je
# tire » est un défaut de LISIBILITÉ, pas de contrôle :
#
#   • un CHEVRON au sol, toujours visible, qui dit où le corps fait face ;
#   • un TÉLÉMÈTRE dans l'axe de tir, ARRÊTÉ par le premier obstacle, donc
#     qui montre aussi que les murs bloquent réellement les balles ;
#   • un ANNEAU sous la cible accrochée par la visée assistée.

## Longueur maximale du télémètre, faute d'arme équipée.
const AIM_FALLBACK_RANGE := 14.0

func _build_aim_visuals() -> void:
	# CHEVRON d'orientation, aux pieds. Toujours affiché : c'est lui qui
	# répond en permanence à « dans quel sens suis-je ? ».
	var chevron := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.34
	cone.height = 0.5
	cone.radial_segments = 3
	chevron.mesh = cone
	chevron.material_override = VisualKit.glow_mat(Cfg.COL_LOCAL_PLAYER, 1.8)
	# Couché à plat, pointe vers l'avant (-Z).
	chevron.rotation = Vector3(-PI / 2.0, 0, 0)
	chevron.position = Vector3(0, 0.06, -0.72)
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chevron)

	# TÉLÉMÈTRE. Maille de longueur 1 sur Z, étirée par `scale.z` selon la
	# distance réellement libre devant le joueur.
	_aim_line = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.1, 0.02, 1.0)
	_aim_line.mesh = beam
	var lm := VisualKit.glow_mat(Cfg.COL_LOCAL_PLAYER, 1.4)
	lm.albedo_color.a = 0.3
	_aim_line.material_override = lm
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_line)

	# ANNEAU de cible.
	_lock_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.62
	ring.outer_radius = 0.82
	ring.rings = 20
	ring.ring_segments = 6
	_lock_ring.mesh = ring
	_lock_ring.material_override = VisualKit.glow_mat(Cfg.COL_SHOTGUN, 2.4)
	_lock_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# `top_level` : l'anneau vit dans le monde, il n'hérite ni de la
	# position ni de la rotation du joueur.
	_lock_ring.top_level = true
	_lock_ring.visible = false
	add_child(_lock_ring)

func _update_aim_visuals() -> void:
	if _aim_line == null:
		return
	if is_eliminated:
		_aim_line.visible = false
		_lock_ring.visible = false
		return

	var col := Cfg.COL_LOCAL_PLAYER
	var reach := AIM_FALLBACK_RANGE
	if weapon and weapon.data:
		col = weapon.data.color
		reach = weapon.data.range

	# Le télémètre s'arrête au premier OBSTACLE — pas sur les créatures, on
	# veut voir la portée utile, pas la première cible. C'est ce qui rend
	# visible le fait qu'un mur coupe la ligne de tir.
	var from := global_position + Vector3(0, 0.9, 0)
	var dir := Vector3(sin(_facing), 0.0, cos(_facing))
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	q.collision_mask = Cfg.LAYER_WORLD
	var hit := space.intersect_ray(q)
	var length: float = reach
	if hit:
		length = maxf(0.6, from.distance_to(hit.position))

	_aim_line.scale = Vector3(1.0, 1.0, length)
	_aim_line.position = Vector3(0, 0.06, -length * 0.5)
	var m := _aim_line.material_override as StandardMaterial3D
	if m:
		# Discret au repos, franc pendant le tir : présent sans encombrer.
		m.albedo_color = Color(col.r, col.g, col.b, 0.5 if want_fire else 0.18)
		m.emission = col
		m.emission_energy_multiplier = 2.2 if want_fire else 0.7

	var show_lock := locked_target != null and is_instance_valid(locked_target)
	_lock_ring.visible = show_lock
	if show_lock:
		_lock_ring.global_position = locked_target.global_position \
				+ Vector3(0, 0.08, 0)
