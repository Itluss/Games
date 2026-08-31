extends Node3D
## Vue de dessus du graybox — validation de structure, sans décor.
## Usage : godot --rendering-driver opengl3 --path arena-rush
##         res://scenes/blockout_vue.tscn -- --sortie=C:/chemin/capture.png

func _ready() -> void:
	var arene := BlockoutBuilder.new()
	add_child(arene)

	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-90, 0, 0)
	soleil.light_energy = 1.2
	add_child(soleil)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101010")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.9
	world.environment = env
	add_child(world)

	await get_tree().process_frame
	await get_tree().physics_frame

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = BlockoutPlan.R_BORD * 2.15
	cam.position = Vector3(0, 60, 0.001)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.far = 120.0
	cam.near = 1.0
	add_child(cam)
	cam.current = true

	for i in 6:
		await get_tree().process_frame

	var chemin := "C:/Users/camille/Games/arena-rush/_out/vue_blockout.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			chemin = a.substr("--sortie=".length())
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(chemin)
	print("CAPTURE %s -> %s" % ["OK" if err == OK else "ÉCHEC(%d)" % err, chemin])
	get_tree().quit()
