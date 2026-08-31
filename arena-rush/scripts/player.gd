extends CharacterBody3D
class_name ArenaPlayer
## MILO — CharacterBody3D, capsule de collision, déplacement RELATIF À LA
## CAMÉRA (haut = vers le haut de l'écran, peu importe l'orientation du
## monde).

## RÉGLÉE SUR LE RYTHME DE LA SPEC ARENA 01 — pas un choix de sensation.
## « spawn périphérique → Core en 30-35 s » (≈69 m) et « traversée
## complète en 60-70 s » (190 m de diamètre) exigent tous deux environ
## 3 m/s ; l'ancienne valeur (7,5) aurait traversé la nouvelle arène en
## 25 s, hors barème. Note dans le compte rendu : ce changement est
## global au contrôleur, donc partagé avec `scenes/main.tscn` (l'arène
## en couronne, 60 m — plus lente à y traverser, mais sans exigence de
## rythme documentée pour elle).
const VITESSE := 3.0
const ACCEL := 8.0

@export var camera_path: NodePath
var _camera: Camera3D


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	var hero: Node3D = load("res://assets/models/hero_milo.glb").instantiate()
	hero.scale = Vector3.ONE * 1.1
	add_child(hero)

	if camera_path != NodePath():
		_camera = get_node(camera_path)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	input = input.normalized() if input.length() > 1.0 else input

	# RELATIF À LA CAMÉRA — le "haut" du clavier avance vers le haut de
	# l'écran, quelle que soit l'orientation de la caméra isométrique.
	var dir := Vector3.ZERO
	if _camera:
		var fwd := -_camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := _camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		dir = right * input.x - fwd * input.y
	else:
		dir = Vector3(input.x, 0, input.y)

	var cible := dir * VITESSE
	velocity.x = move_toward(velocity.x, cible.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, cible.z, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0

	# GLISSEMENT LE LONG DES OBSTACLES — `move_and_slide` le fait déjà
	# nativement (jusqu'à 4 rebonds par défaut) : rien à ajouter.
	move_and_slide()

	if dir.length() > 0.1:
		var vise := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, vise, 10.0 * delta)
