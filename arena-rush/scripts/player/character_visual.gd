extends Node3D
class_name CharacterVisual
## APPARENCE D'UN PERSONNAGE — animation procédurale, zéro logique de jeu.
##
## POURQUOI CE NŒUD EXISTE : le prototype n'a pas encore de modèles animés.
## Plutôt que de bloquer le gameplay en attendant des .glb, on anime des
## primitives par le code. La frontière est nette — ce nœud ne connaît ni
## les PV, ni les dégâts, ni le réseau ; il reçoit un ÉTAT et le joue.
##
## REMPLACEMENT PAR DE VRAIS MODÈLES : garder `set_state()`, `flash()`,
## `attach_weapon()` et `get_weapon_mount()`, remplacer le contenu par un
## AnimationPlayer. Aucun appelant n'a à changer.

enum State { IDLE, RUN, ATTACK, HIT, DEATH }

var state: State = State.IDLE
var _rig: Node3D
var _parts: Dictionary = {}          # nom -> MeshInstance3D
var _base_pos: Dictionary = {}       # nom -> position de repos
var _materials: Array[StandardMaterial3D] = []
var _mount: Node3D
var _weapon_model: Node3D = null

var _time: float = 0.0
## Mouvement reçu du corps, exprimé dans son repère et normalisé.
var _vel: Vector3 = Vector3.ZERO
var _acc: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO     # x = tangage, y = roulis
var _squash: Vector3 = Vector3.ONE
var _squash_target: Vector3 = Vector3.ONE
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _dead: bool = false

func build(color: Color, accent: Color, height: float = 1.7) -> void:
	_rig = VisualKit.build_humanoid(color, accent, height)
	add_child(_rig)
	for child in _rig.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		_parts[mi.name] = mi
		_base_pos[mi.name] = mi.position
		var m: Material = mi.material_override
		if m is StandardMaterial3D:
			_materials.append(m)
	_mount = _rig.get_node_or_null("WeaponMount")

func get_weapon_mount() -> Node3D:
	return _mount

## Greffe le modèle d'arme sur la main. L'ancien est retiré : un joueur ne
## tient jamais deux armes à la fois, même une image.
func attach_weapon(model: Node3D) -> void:
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = model
	if model and _mount:
		_mount.add_child(model)

## Vitesse et accélération dans le repère du personnage, normalisées.
## `z > 0` = vers l'avant, `x > 0` = vers la droite.
func set_motion(vel: Vector3, acc: Vector3) -> void:
	_vel = vel
	_acc = acc

## Déformation ponctuelle — écrasement ou étirement — qui revient d'elle
## même. C'est l'ingrédient qui fait qu'un mouvement brutal se LIT au lieu
## d'être subi : sans déformation, une accélération instantanée n'a aucune
## expression visuelle.
func punch(target: Vector3, duration: float = 0.16) -> void:
	if _dead:
		return
	_squash_target = target
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_squash_target = Vector3.ONE.lerp(target, v), 1.0, 0.0, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func set_state(s: State) -> void:
	if _dead or state == s:
		return
	state = s
	match s:
		State.ATTACK:
			_attack_t = 0.16
			punch(Vector3(1.06, 0.96, 0.94), 0.12)
		State.HIT:
			_hit_t = 0.18
		State.DEATH:
			_dead = true
			_play_death()

## Teinte brève de tout le personnage — c'est LE signal « tu as été
## touché », lisible même quand l'écran est chargé.
func flash(color: Color = Color.WHITE, duration: float = 0.12) -> void:
	if _dead:
		return
	for m in _materials:
		m.emission_enabled = true
		m.emission = color
		var tw := create_tween()
		tw.tween_property(m, "emission_energy_multiplier", 0.0, duration) \
				.from(2.6)

func _play_death() -> void:
	# Bascule au sol + affaissement : une mort doit se LIRE d'un coup d'œil,
	# y compris à l'autre bout de l'arène.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rig, "rotation:x", -PI / 2.0, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "scale", Vector3(1.15, 0.55, 1.15), 0.32)
	tw.tween_property(self, "position:y", -0.25, 0.5)

## `speed_ratio` : 0 à l'arrêt, 1 à pleine course.
func update_visual(delta: float, speed_ratio: float) -> void:
	if _dead or _rig == null:
		return
	_time += delta

	if _attack_t > 0.0:
		_attack_t -= delta
		if _attack_t <= 0.0 and state == State.ATTACK:
			state = State.RUN if speed_ratio > 0.1 else State.IDLE
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0 and state == State.HIT:
			state = State.RUN if speed_ratio > 0.1 else State.IDLE
	if state == State.IDLE and speed_ratio > 0.1:
		state = State.RUN
	elif state == State.RUN and speed_ratio <= 0.1:
		state = State.IDLE

	# COURSE : les jambes balancent, le torse rebondit. La fréquence suit
	# la vitesse réelle, donc le personnage ne « patine » jamais.
	var swing := sin(_time * lerpf(4.0, 15.0, speed_ratio)) * speed_ratio
	_offset("LegL", Vector3(0, 0, swing * 0.26))
	_offset("LegR", Vector3(0, 0, -swing * 0.26))
	_offset("ArmL", Vector3(0, 0, -swing * 0.2))

	var bob := absf(sin(_time * lerpf(4.0, 15.0, speed_ratio))) * speed_ratio * 0.07
	_offset("Torso", Vector3(0, bob, 0))
	_offset("Head", Vector3(0, bob * 1.1, 0))
	_offset("Shoulders", Vector3(0, bob, 0))
	_offset("Visor", Vector3(0, bob * 1.1, 0))

	# ATTAQUE : le bras armé se détend vers l'avant. Court et sec — c'est
	# la nervosité du geste qui rend un tir satisfaisant.
	var punch := 0.0
	if _attack_t > 0.0:
		punch = sin((1.0 - _attack_t / 0.16) * PI) * 0.22
	_offset("ArmR", Vector3(0, 0, -punch - swing * -0.2))

	# COUP ENCAISSÉ : recul du buste, très bref.
	if _hit_t > 0.0:
		var k := _hit_t / 0.18
		_rig.position.z = k * 0.14
	else:
		_rig.position.z = 0.0

	# INCLINAISON — le corps penche dans le sens de la marche et s'incline
	# dans les changements de direction. C'est ce qui distingue un
	# personnage d'un objet qu'on translate : sans elle, il glisse à plat,
	# sans poids ni intention.
	#
	# La vitesse donne l'assiette générale, l'accélération la réaction
	# vive aux changements. Le lissage est exponentiel, donc identique à
	# toute cadence d'affichage.
	var target_lean := Vector2(
			clampf(_vel.z * 0.16 + _acc.z * 0.10, -0.30, 0.30),
			clampf(_vel.x * 0.20 + _acc.x * 0.14, -0.34, 0.34))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta / 0.09))
	# L'avant du gabarit est -Z, d'où les signes : un tangage positif
	# ferait basculer le buste en arrière.
	_rig.rotation.x = -_lean.x
	_rig.rotation.z = -_lean.y

	# RESPIRATION à l'arrêt : une immobilité parfaitement figée est le
	# signe le plus sûr d'un pantin.
	var breathe := 1.0 + sin(_time * 1.9) * 0.018 * (1.0 - speed_ratio)
	_squash = _squash.lerp(_squash_target, 1.0 - exp(-delta / 0.055))
	_rig.scale = Vector3(_squash.x, _squash.y * breathe, _squash.z)

func _offset(part: String, delta_pos: Vector3) -> void:
	var node: MeshInstance3D = _parts.get(part)
	if node == null:
		return
	node.position = _base_pos[part] + delta_pos

func revive() -> void:
	_dead = false
	state = State.IDLE
	position = Vector3.ZERO
	if _rig:
		_rig.rotation = Vector3.ZERO
		_rig.scale = Vector3.ONE
		_rig.position = Vector3.ZERO
