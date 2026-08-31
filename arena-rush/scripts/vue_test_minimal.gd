extends Node3D

func _ready() -> void:
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0, 0, -5)
	add_child(box)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 0)
	add_child(cam)
	cam.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	print("box global pos: ", box.global_position)
	print("box visible: ", box.visible, " mesh: ", box.mesh)
	print("cam current: ", cam.current, " global: ", cam.global_position)
	print("children of root: ", get_tree().root.get_child_count())
	for c in get_tree().root.get_children():
		print("  root child: ", c.name, " ", c.get_class())

	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Users/camille/Games/arena-rush/_out/vue_min.png")
	print("fait")
	get_tree().quit()
