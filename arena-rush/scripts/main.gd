extends Node3D
## SCÈNE PRINCIPALE — assemble arène, joueur, caméra, diagnostic.
## Démarre en caméra de gameplay (ÉTAPE 6) ; touche M bascule la vue
## cartographique. Le diagnostic reste affiché tant que la structure
## n'est pas validée (ÉTAPE de validation explicite).

func _ready() -> void:
	_environnement()

	var arene := ArenaBuilder.new()
	arene.name = "Arena"
	add_child(arene)

	var diag := Diagnostic.new()
	diag.name = "Diagnostic"
	add_child(diag)

	var joueur := ArenaPlayer.new()
	joueur.name = "Milo"
	var spawn: Dictionary = ArenaPlan.SPAWNS[0]
	var pos: Vector2 = spawn["pos"]
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


func _environnement() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6fb3e0")
	sm.sky_horizon_color = Color("cfe6ee")
	sm.ground_bottom_color = Color("8a7a5c")
	sm.ground_horizon_color = Color("cfe6ee")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment = env
	add_child(world)

	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-55, -35, 0)
	soleil.light_energy = 1.0
	soleil.shadow_enabled = true
	add_child(soleil)
