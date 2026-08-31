extends Node3D
## SCÈNE JOUABLE DU GRAYBOX — structure et circulation seulement, aucun
## décor. M bascule la vue cartographique.

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	world.environment = env
	add_child(world)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-55, -35, 0)
	soleil.shadow_enabled = true
	add_child(soleil)

	var arene := BlockoutBuilder.new()
	arene.name = "Arena"
	add_child(arene)

	var joueur := ArenaPlayer.new()
	joueur.name = "Milo"
	# Joueur de test placé nommément à Spawn_S01 (pas par index positionnel :
	# c'est ce que la spec Arena 01 demande explicitement à vérifier).
	var pos := Vector2.ZERO
	for s: Dictionary in BlockoutPlan.SPAWNS:
		if s["nom"] == "S01":
			pos = s["pos"]
			break
	joueur.position = Vector3(pos.x, 1.0, pos.y)
	add_child(joueur)

	var cam := ArenaCam.new()
	cam.name = "Camera"
	add_child(cam)
	cam.target = joueur
	cam.current = true
	joueur.camera_path = joueur.get_path_to(cam)
	cam._snap()

	var ui := CanvasLayer.new()
	var lbl := Label.new()
	lbl.text = "ZQSD/WASD : déplacer   M : vue cartographique"
	lbl.position = Vector2(16, 12)
	lbl.add_theme_font_size_override(&"font_size", 16)
	ui.add_child(lbl)
	add_child(ui)
