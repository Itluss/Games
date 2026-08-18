extends CanvasLayer
## OUTILS DE DÉVELOPPEMENT — F1 pour afficher.
##
## Uniquement en build de développement (`OS.is_debug_build()`), donc rien
## de tout ceci n'existe dans une build exportée pour les stores.
##
## Ces raccourcis existent parce que tester « que se passe-t-il face à
## trois Exploders avec un lance-grenades » ne doit pas demander de jouer
## quatre minutes pour y arriver.

var _panel: PanelContainer
var _fps: Label
var _visible: bool = false

func _ready() -> void:
	layer = 20
	_build()
	_panel.visible = false

func _build() -> void:
	_fps = Label.new()
	_fps.add_theme_font_size_override(&"font_size", 18)
	_fps.add_theme_color_override(&"font_color", Color(0.5, 1, 0.6))
	_fps.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_fps.add_theme_constant_override(&"outline_size", 5)
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -170
	_fps.offset_top = 8
	_fps.offset_right = -12
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# MASQUÉ PAR DÉFAUT DEPUIS QUE LE HUD AFFICHE LA CADENCE. Deux compteurs
	# d'images superposés dans le même coin, dont l'un flotte sans cadre par
	# dessus l'autre, ne donnent pas deux fois l'information : ils donnent
	# l'impression d'un débogage oublié en production. Il revient avec le
	# reste du panneau, qui est sa place.
	_fps.visible = false
	add_child(_fps)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 12
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.78)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 5)
	_panel.add_child(box)

	box.add_child(_title("DEBUG (F1)"))
	box.add_child(_btn("Spawn Charger", func(): _world().debug_spawn_mob(&"charger")))
	box.add_child(_btn("Spawn Shooter", func(): _world().debug_spawn_mob(&"shooter")))
	box.add_child(_btn("Spawn Exploder", func(): _world().debug_spawn_mob(&"exploder")))
	box.add_child(_btn("Tuer tous les mobs", func(): _world().debug_kill_mobs()))
	box.add_child(_title("Armes"))
	for id in [&"shotgun", &"energy_blaster", &"grenade_launcher", &"basic_blaster"]:
		var data := Registry.weapon(id)
		if data:
			box.add_child(_btn("Donner " + data.display_name,
					func(): _world().debug_give_weapon(id)))
	box.add_child(_title("Divers"))
	box.add_child(_btn("−25 PV", func(): _world().debug_hurt_local(25.0)))
	box.add_child(_btn("Qualité ↓", _cycle_quality))
	box.add_child(_btn("Retour au menu", func():
		var m := get_tree().get_first_node_in_group(&"main")
		if m:
			m.call(&"back_to_lobby")))

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 14)
	l.add_theme_color_override(&"font_color", Color(1, 0.8, 0.4))
	return l

func _btn(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", 14)
	b.custom_minimum_size = Vector2(196, 28)
	b.pressed.connect(func():
		if _world() != null:
			action.call())
	return b

func _world() -> GameWorld:
	var main := get_tree().get_first_node_in_group(&"main")
	return main.get(&"world") if main else null

func _cycle_quality() -> void:
	Cfg.quality = ((Cfg.quality + 1) % 3) as Cfg.Quality
	print("Qualité : ", Cfg.Quality.keys()[Cfg.quality])

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"debug_panel"):
		_visible = not _visible
		_panel.visible = _visible
		_fps.visible = _visible
	_fps.text = "%d FPS · %d mobs" % [
		Engine.get_frames_per_second(),
		get_tree().get_nodes_in_group(&"mobs").size()]
