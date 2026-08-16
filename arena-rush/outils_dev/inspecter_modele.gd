extends Node3D
## Où est réellement l'arme par rapport aux mains — outil de dev.

var _visuel: CharacterVisual

func _ready() -> void:
	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Color.WHITE, Color.WHITE, 1.7)
	_visuel.attach_weapon(VisualKit.build_weapon("rifle", Color.ORANGE))
	_visuel.forcer_clip("garde")
	for i in 40:
		_visuel.update_visual(1.0 / 60.0, 0.0)
		await get_tree().process_frame

	var sq := _chercher(_visuel, "Skeleton3D") as Skeleton3D
	var m := sq.global_transform
	for os_nom in ["RightHand", "LeftHand", "Hips", "Head"]:
		var i := sq.find_bone(os_nom)
		print("%-10s monde = %s" % [os_nom, m * sq.get_bone_global_pose(i).origin])
	var mount := _visuel.get_weapon_mount()
	print("ACCROCHE   monde = ", mount.global_position)
	var maille := _chercher(mount, "MeshInstance3D") as Node3D
	if maille:
		print("MAILLE arme monde = ", maille.global_position)
	print("ÉCART accroche↔RightHand = %.4f m"
			% mount.global_position.distance_to(
				m * sq.get_bone_global_pose(sq.find_bone("RightHand")).origin))
	get_tree().quit()

func _chercher(n: Node, c: String) -> Node:
	if n.is_class(c):
		return n
	for e in n.get_children():
		var r := _chercher(e, c)
		if r:
			return r
	return null
