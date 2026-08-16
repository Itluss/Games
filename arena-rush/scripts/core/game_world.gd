extends Node3D
class_name GameWorld
## MONDE DE JEU — orchestre l'arène, les entités et la partie.
##
## POURQUOI TOUTES LES APPARITIONS PASSENT PAR ICI : un RPC ne trouve sa
## cible que si le nœud existe au MÊME chemin sur tous les pairs. En
## centralisant la création, on garantit que « Mob_7 » désigne le même mob
## partout. Laisser chaque système créer ses nœuds dans son coin est le
## moyen le plus sûr de casser un jeu réseau de façon indébogable.
##
## Le serveur décide, diffuse, et exécute la même fonction que les clients.

const MOB_SYNC_HZ := 20.0

var arena: Arena
var entities: Node3D
var spawner: MobSpawner
var camera: ArenaCamera
var local_player: Player = null
var controller: PlayerController

var _next_mob_id: int = 1
var _next_loot_id: int = 1
var _sync_accum: float = 0.0
var _spawn_index: Dictionary = {}   # peer_id -> index de point d'apparition

func _ready() -> void:
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)

	camera = ArenaCamera.new()
	camera.name = "Camera"
	add_child(camera)

	spawner = MobSpawner.new()
	spawner.name = "MobSpawner"
	spawner.world = self
	add_child(spawner)

	controller = PlayerController.new()
	controller.name = "Controller"
	add_child(controller)

	MatchDirector.zone_updated.connect(_on_zone_updated)
	MatchDirector.match_ended.connect(_on_match_ended)

	_start()

func _start() -> void:
	# Le serveur distribue les corps ; les clients attendent l'ordre. En
	# solo, `is_server()` est vrai, donc le même chemin est emprunté.
	if Net.is_server():
		var index := 0
		for id in Net.all_ids():
			_spawn_index[id] = index
			var info: Dictionary = Net.peers[id]
			Net.broadcast(self, &"net_spawn_player",
					[id, info.get("name", "Joueur"), info.get("bot", false), index])
			index += 1
	MatchDirector.begin(arena)

# --- JOUEURS -------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func net_spawn_player(id: int, name_text: String, bot: bool, index: int) -> void:
	if entities.has_node("Player_%d" % id):
		return
	var p := Player.new()
	p.setup(id, name_text, bot)
	entities.add_child(p)
	p.global_position = arena.player_spawn(index)

	if bot:
		# Le cerveau ne vit que sur le serveur : les clients ne simulent
		# pas les bots, ils reçoivent leurs positions comme celles d'un
		# joueur humain distant.
		if Net.is_server():
			var brain := BotBrain.new()
			brain.name = "Brain"
			p.add_child(brain)
			brain.attach(p)
	elif id == Net.local_id():
		local_player = p
		camera.set_target(p)
		controller.attach(p)
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"bind_player"):
			hud.call(&"bind_player", p)

	MatchDirector.register_player(id, p)

# --- MOBS ----------------------------------------------------------------

## SERVEUR UNIQUEMENT — appelé par le spawner.
func server_spawn_mob(type_id: StringName) -> void:
	if not Net.is_server():
		return
	var players := get_tree().get_nodes_in_group(&"players")
	var pos := arena.mob_spawn(players)
	var id := _next_mob_id
	_next_mob_id += 1
	Net.broadcast(self, &"net_spawn_mob", [id, type_id, pos])

@rpc("authority", "call_local", "reliable")
func net_spawn_mob(id: int, type_id: StringName, pos: Vector3) -> void:
	var data := Registry.mob(type_id)
	if data == null or entities.has_node("Mob_%d" % id):
		return
	var m := Mob.new()
	m.setup(data, id)
	entities.add_child(m)
	m.global_position = pos
	m.mob_died.connect(_on_mob_died)

	# Apparition visible : sans elle, les mobs « poppent » et le joueur a
	# l'impression d'être pris en traître.
	Fx.impact(pos + Vector3(0, 0.4, 0), data.color, 0.9)
	var visual := m.get_node_or_null("Node3D")
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.24).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

func _on_mob_died(mob: Mob, killer_id: int) -> void:
	if not Net.is_server():
		return
	var data := mob.data
	if data.loot_weapon_id == &"" or randf() > data.loot_chance:
		return
	# La qualité du butin suit la pression : en fin de partie, les armes
	# lâchées sont celles qui permettent de gagner un duel.
	var weapon_id := data.loot_weapon_id
	if MatchDirector.pressure > 0.55 and randf() < 0.35:
		var upgraded := Registry.weapon_for_pressure(MatchDirector.pressure)
		if upgraded != &"":
			weapon_id = upgraded
	server_drop_loot(weapon_id, mob.global_position)

# --- LOOT ----------------------------------------------------------------

## SERVEUR UNIQUEMENT. `dropped_by` marque le joueur qui vient d'abandonner
## cette arme, pour qu'il ne puisse pas la reprendre instantanément.
func server_drop_loot(weapon_id: StringName, pos: Vector3,
		dropped_by: int = 0) -> void:
	if not Net.is_server() or weapon_id == &"":
		return
	var id := _next_loot_id
	_next_loot_id += 1
	Net.broadcast(self, &"net_spawn_loot", [id, weapon_id, pos, dropped_by])

@rpc("authority", "call_local", "reliable")
func net_spawn_loot(id: int, weapon_id: StringName, pos: Vector3,
		dropped_by: int) -> void:
	if entities.has_node("Loot_%d" % id):
		return
	var l := LootPickup.new()
	l.setup(weapon_id, id, dropped_by)
	entities.add_child(l)
	l.global_position = pos + Vector3(0, 0.1, 0)
	# On lie le butin lui-même au signal : chercher « le loot le plus
	# proche portant la même arme » était une approximation qui pouvait
	# désigner le mauvais objet quand deux butins identiques se touchaient.
	l.picked_up.connect(_on_loot_picked.bind(l))

func _on_loot_picked(peer_id: int, weapon_id: StringName,
		loot: LootPickup) -> void:
	if not Net.is_server():
		return
	var player := entities.get_node_or_null("Player_%d" % peer_id) as Player
	if player == null:
		return
	var dropped := player.server_pickup(weapon_id)
	Net.broadcast(self, &"net_collect_loot", [loot.loot_id, peer_id])
	# L'arme remplacée retombe au sol : rien ne disparaît sans raison, et
	# le joueur peut revenir la chercher. Elle est écartée hors du rayon de
	# ramassage (1,5 m) pour ne pas être happée dans la foulée.
	if dropped != &"":
		var away := Vector3(randf_range(-1.0, 1.0), 0.0,
				randf_range(-1.0, 1.0)).normalized() * 2.6
		server_drop_loot(dropped, player.global_position + away, peer_id)

@rpc("authority", "call_local", "reliable")
func net_collect_loot(loot_id: int, peer_id: int) -> void:
	var l := entities.get_node_or_null("Loot_%d" % loot_id) as LootPickup
	var p := entities.get_node_or_null("Player_%d" % peer_id) as Player
	if l and p:
		l.play_collect(p.global_position)

# --- RÉPLICATION DES MOBS ------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Net.is_networked() or not Net.is_server():
		return
	_sync_accum += delta
	if _sync_accum < 1.0 / MOB_SYNC_HZ:
		return
	_sync_accum = 0.0
	# Un SEUL message pour tous les mobs plutôt qu'un RPC par entité :
	# vingt petits paquets par tick saturent la boucle réseau bien avant
	# de saturer la bande passante.
	var payload: Array = []
	for node in get_tree().get_nodes_in_group(&"mobs"):
		var m := node as Mob
		if m == null or m.state == Mob.State.DEAD:
			continue
		payload.append([m.mob_id, m.global_position, m.rotation.y])
	if not payload.is_empty():
		net_mob_states.rpc(payload)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_mob_states(payload: Array) -> void:
	for entry in payload:
		var m := entities.get_node_or_null("Mob_%d" % entry[0]) as Mob
		if m:
			m.net_position(entry[1], entry[2])

# --- ZONE ET FIN ---------------------------------------------------------

func _on_zone_updated(radius: float, next_radius: float, closing: bool) -> void:
	arena.update_zone(radius, closing)
	camera.adapt_to_zone(radius)

func _on_match_ended(winner_id: int, winner_name: String) -> void:
	# On fige les mobs : l'écran de victoire ne doit pas être parasité par
	# un combat qui continue derrière.
	for node in get_tree().get_nodes_in_group(&"mobs"):
		node.set_physics_process(false)

## Relance complète — la scène est recréée, donc aucun état résiduel.
func restart() -> void:
	MatchDirector.reset()
	Pool.clear()
	get_tree().reload_current_scene()

# --- OUTILS DE DÉVELOPPEMENT --------------------------------------------

func debug_spawn_mob(type_id: StringName) -> void:
	server_spawn_mob(type_id)

func debug_give_weapon(weapon_id: StringName) -> void:
	if local_player:
		local_player.server_pickup(weapon_id)

func debug_hurt_local(amount: float) -> void:
	if local_player:
		local_player.server_take_damage(amount, local_player.global_position,
				0, Cfg.Team.MOB)

func debug_kill_mobs() -> void:
	for node in get_tree().get_nodes_in_group(&"mobs"):
		var m := node as Mob
		if m:
			m.server_take_damage(99999.0, m.global_position, 0, Cfg.Team.PLAYER)
