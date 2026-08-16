extends Node
## POINT D'ENTRÉE — accueil, lancement et relance des parties.
##
## Le monde de jeu est CRÉÉ et DÉTRUIT à chaque partie plutôt que remis à
## zéro : c'est la seule façon fiable de garantir qu'aucun état résiduel
## (mob orphelin, tween en cours, projectile en vol) ne contamine la partie
## suivante. Une relance est donc toujours propre, par construction.

const AUTOSTART_SOLO := true

var world: GameWorld = null
var hud: HUD = null
var _menu: Control = null
var _debug: Node = null
var _last_mode: int = 0   # 0 = solo, 1 = hôte, 2 = client
var _last_bots: int = 3

func _ready() -> void:
	add_to_group(&"main")
	# Argument de ligne de commande : permet de lancer une seconde instance
	# directement en client, sans passer par le menu à chaque test.
	if "--join" in OS.get_cmdline_args():
		_start(2, 0)
		return
	if "--host" in OS.get_cmdline_args():
		_start(1, 0)
		return
	# Démarrage direct en solo : sert aux tests automatisés et à relancer
	# une partie sans repasser par le menu pendant le développement.
	if "--solo" in OS.get_cmdline_args():
		_start(0, 3)
		return
	_show_menu()

# --- MENU ----------------------------------------------------------------

func _show_menu() -> void:
	_clear_world()
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color("1b2436")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 16)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "ARENA RUSH"
	title.add_theme_font_size_override(&"font_size", 78)
	title.add_theme_color_override(&"font_color", Cfg.COL_LOCAL_PLAYER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Survivez. Pillez. Restez le dernier."
	sub.add_theme_font_size_override(&"font_size", 22)
	sub.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_spacer(28))
	box.add_child(_menu_button("SOLO — 3 BOTS", Cfg.COL_HEAL,
			func(): _start(0, 3)))
	box.add_child(_menu_button("HÉBERGER UNE PARTIE", Cfg.COL_BASIC,
			func(): _start(1, 0)))
	box.add_child(_menu_button("REJOINDRE (127.0.0.1)", Cfg.COL_ENERGY,
			func(): _start(2, 0)))

	var hint := Label.new()
	hint.text = "Clavier : ZQSD/WASD · Souris = viser · Clic = tirer · A = arme · Maj = esquive · F1 = debug"
	hint.add_theme_font_size_override(&"font_size", 15)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_spacer(20))
	box.add_child(hint)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _menu_button(text: String, color: Color, action: Callable) -> Control:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 68)
	b.add_theme_font_size_override(&"font_size", 26)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.22)
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = color
	b.add_theme_stylebox_override(&"normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(color.r, color.g, color.b, 0.45)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	b.pressed.connect(action)
	var center := CenterContainer.new()
	center.add_child(b)
	return center

# --- CYCLE DE PARTIE -----------------------------------------------------

func _start(mode: int, bots: int) -> void:
	_last_mode = mode
	_last_bots = bots
	match mode:
		0:
			Net.start_solo(bots)
			_build_world()
		1:
			if Net.host():
				_build_world()
		2:
			# Le client attend que le serveur lui envoie la liste des pairs
			# avant de construire quoi que ce soit : construire trop tôt
			# donnerait un monde vide et désynchronisé.
			if Net.join():
				Net.peer_list_changed.connect(_on_peers_ready,
						CONNECT_ONE_SHOT)

func _on_peers_ready() -> void:
	if world == null:
		_build_world()

func _build_world() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)

	world = GameWorld.new()
	world.name = "World"
	add_child(world)

	if OS.is_debug_build():
		_debug = preload("res://scripts/core/debug_panel.gd").new()
		_debug.name = "DebugPanel"
		add_child(_debug)

func _clear_world() -> void:
	for node in [world, hud, _debug]:
		if node and is_instance_valid(node):
			node.queue_free()
	world = null
	hud = null
	_debug = null
	Pool.clear()
	MatchDirector.reset()

## Relance avec les mêmes réglages — le bouton REJOUER de l'écran de fin.
func restart_match() -> void:
	_clear_world()
	# Une image d'attente laisse aux `queue_free()` le temps d'être traités
	# avant qu'on reconstruise des nœuds portant les mêmes noms.
	await get_tree().process_frame
	if _last_mode == 0:
		Net.start_solo(_last_bots)
	_build_world()

func back_to_lobby() -> void:
	Net.leave()
	_show_menu()
