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
## NEUF BOTS ET NON TROIS.
##
## Le nombre était écrit en dur à trois endroits — ici, au démarrage
## automatique et sur le bouton du menu. Relever le plafond du gestionnaire
## de réseau n'aurait donc rien changé : le jeu aurait continué à en lancer
## trois. Une valeur dupliquée est une valeur qui finit par diverger, alors
## elle est désormais unique et les trois endroits la lisent.
const BOTS_SOLO := 9
var _last_bots: int = BOTS_SOLO

## Arguments de lancement, des DEUX côtés du séparateur `--`.
##
## POURQUOI CETTE FONCTION EXISTE : Godot répartit les arguments entre
## deux listes. Ce qui suit `--` va dans `get_cmdline_user_args()`, le
## reste dans `get_cmdline_args()`. On ne lisait que la seconde, si bien
## qu'un lancement de la forme
##
##     godot --path arena-rush --quit-after 900 -- --solo
##
## affichait le MENU au lieu de démarrer une partie, sans la moindre
## erreur. Une validation automatisée finissait donc au vert sans avoir
## rien joué. Ce faux succès a masqué un vrai bug pendant plusieurs
## vérifications — il est toujours plus dangereux qu'un échec.
func _arguments() -> PackedStringArray:
	var tout := OS.get_cmdline_args()
	tout.append_array(OS.get_cmdline_user_args())
	return tout


func _ready() -> void:
	add_to_group(&"main")
	var args := _arguments()
	# Argument de ligne de commande : permet de lancer une seconde instance
	# directement en client, sans passer par le menu à chaque test.
	if "--join" in args:
		_start(2, 0)
		return
	if "--host" in args:
		_start(1, 0)
		return
	# Démarrage direct en solo : sert aux tests automatisés et à relancer
	# une partie sans repasser par le menu pendant le développement.
	if "--solo" in args:
		_start(0, BOTS_SOLO)
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
	# LE MENU DÉCRIVAIT UN AUTRE JEU. « Restez le dernier » était la promesse
	# du Battle Royale ; l'arène est persistante depuis, on y revient toujours
	# et personne n'y gagne. Une accroche fausse est le premier mensonge que
	# le joueur lit, et il la lit avant même d'avoir joué.
	sub.text = "Un monde sans bord. Pillez, affrontez, recommencez."
	sub.add_theme_font_size_override(&"font_size", 22)
	sub.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_spacer(28))
	box.add_child(_menu_button("SOLO — %d BOTS" % BOTS_SOLO, Cfg.COL_HEAL,
			func(): _start(0, BOTS_SOLO)))
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
