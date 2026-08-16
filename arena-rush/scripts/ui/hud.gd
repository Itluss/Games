extends CanvasLayer
class_name HUD
## INTERFACE DE JEU — minimaliste, tactile, adaptée à tous les ratios.
##
## PRINCIPE : n'afficher que ce qui change une décision. Vies restantes,
## santé, arme active, temps. Rien d'autre — chaque élément superflu vole
## de la place à un écran de téléphone et de l'attention au combat.
##
## ADAPTATION AUX ÉCRANS : tout est ancré aux COINS via des marges, jamais
## positionné en absolu. Un iPhone très allongé et un iPad presque carré
## gardent donc des commandes sous les pouces, au même écart des bords.
##
## LE BOUTON DE TIR EST UN MINI-JOYSTICK : maintenir tire (avec visée
## assistée), glisser oriente. C'est la convention du genre sur mobile, et
## elle évite d'occuper un troisième doigt.

const MARGIN := 26
const STICK_SIZE := 210
const FIRE_SIZE := 160

var player: Player = null

var _root: Control
var _move_stick: VirtualJoystick
var _fire_stick: VirtualJoystick
var _swap_button: Button
var _dash_button: Button
var _alive_label: Label
var _timer_label: Label
var _announce: Label
var _countdown: Label
var _health_fill: ColorRect
var _health_text: Label
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label

var _swap_queued: bool = false
var _dash_queued: bool = false

func _ready() -> void:
	add_to_group(&"hud")
	layer = 10
	_build()
	MatchDirector.countdown_tick.connect(_on_countdown)
	MatchDirector.alive_count_changed.connect(_on_alive_changed)
	MatchDirector.announce.connect(_on_announce)
	MatchDirector.match_ended.connect(_on_match_ended)
	MatchDirector.player_eliminated.connect(_on_player_eliminated)

func bind_player(p: Player) -> void:
	player = p
	p.health_changed.connect(_on_health_changed)
	p.inventory_changed.connect(_on_inventory_changed)
	p.died.connect(_on_local_died)
	_on_health_changed(p.health.current_health, p.health.max_health)
	_on_inventory_changed(p.slots, p.active_slot)

# --- CONSTRUCTION --------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top()
	_build_center()
	_build_bottom()
	_build_controls()
	_build_overlay()

func _label(text: String, size_px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	# Contour sombre : le texte blanc doit rester lisible au-dessus du
	# sable clair comme au-dessus d'une explosion.
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override(&"outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_top() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = MARGIN
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override(&"separation", 34)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	_alive_label = _label("4 VIVANTS", 30, Cfg.COL_LOCAL_PLAYER)
	bar.add_child(_alive_label)
	_timer_label = _label("0:00", 30, Color(1, 1, 1, 0.85))
	bar.add_child(_timer_label)

func _build_center() -> void:
	_announce = _label("", 46, Cfg.COL_SHOTGUN)
	_announce.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce.offset_top = 96
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce.modulate.a = 0.0
	_root.add_child(_announce)

	_countdown = _label("", 132, Color.WHITE)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown.modulate.a = 0.0
	_root.add_child(_countdown)

func _build_bottom() -> void:
	# Colonne centrée en bas : santé au-dessus, armes en dessous. Le centre
	# bas est la seule zone jamais couverte par les pouces.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.offset_bottom = -MARGIN
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override(&"separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)

	var health_row := CenterContainer.new()
	health_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(health_row)

	var health_box := Control.new()
	health_box.custom_minimum_size = Vector2(330, 26)
	health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_row.add_child(health_box)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_box.add_child(bg)

	_health_fill = ColorRect.new()
	_health_fill.color = Cfg.COL_HEAL
	_health_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_health_fill.offset_left = 3
	_health_fill.offset_top = 3
	_health_fill.offset_bottom = -3
	_health_fill.offset_right = 324
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_box.add_child(_health_fill)

	_health_text = _label("100", 19)
	_health_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_box.add_child(_health_text)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override(&"separation", 12)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(slots)

	for i in 2:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(158, 56)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.5)
		style.set_corner_radius_all(10)
		style.set_border_width_all(3)
		style.border_color = Color(1, 1, 1, 0.18)
		panel.add_theme_stylebox_override(&"panel", style)
		# Les emplacements sont TOUCHABLES : passer d'une arme à l'autre en
		# tapant directement son icône est plus direct qu'un bouton dédié.
		panel.gui_input.connect(_on_slot_input.bind(i))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		slots.add_child(panel)
		_slot_panels.append(panel)

		var lbl := _label("—", 20)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(lbl)
		_slot_labels.append(lbl)

func _build_controls() -> void:
	_move_stick = VirtualJoystick.new()
	_move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_stick.custom_minimum_size = Vector2(STICK_SIZE, STICK_SIZE)
	_move_stick.size = Vector2(STICK_SIZE, STICK_SIZE)
	_move_stick.offset_left = MARGIN
	_move_stick.offset_top = -(STICK_SIZE + MARGIN)
	_move_stick.offset_right = MARGIN + STICK_SIZE
	_move_stick.offset_bottom = -MARGIN
	_root.add_child(_move_stick)

	_fire_stick = VirtualJoystick.new()
	_fire_stick.radius = FIRE_SIZE * 0.42
	# Origine FIXE à droite : le bouton de tir doit rester là où le pouce
	# l'attend, contrairement au joystick de déplacement.
	_fire_stick.dynamic_origin = false
	_fire_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fire_stick.custom_minimum_size = Vector2(FIRE_SIZE, FIRE_SIZE)
	_fire_stick.size = Vector2(FIRE_SIZE, FIRE_SIZE)
	_fire_stick.offset_left = -(FIRE_SIZE + MARGIN)
	_fire_stick.offset_top = -(FIRE_SIZE + MARGIN)
	_fire_stick.offset_right = -MARGIN
	_fire_stick.offset_bottom = -MARGIN
	_root.add_child(_fire_stick)

	var fire_label := _label("TIR", 22, Color(1, 1, 1, 0.9))
	fire_label.set_anchors_preset(Control.PRESET_CENTER)
	fire_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	fire_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_fire_stick.add_child(fire_label)

	_swap_button = _round_button("ARME", Cfg.COL_ENERGY)
	_swap_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_swap_button.offset_left = -(FIRE_SIZE + MARGIN + 106)
	_swap_button.offset_top = -(MARGIN + 96)
	_swap_button.offset_right = -(FIRE_SIZE + MARGIN + 10)
	_swap_button.offset_bottom = -(MARGIN + 6)
	_swap_button.pressed.connect(func(): _swap_queued = true)
	_root.add_child(_swap_button)

	_dash_button = _round_button("ESQUIVE", Cfg.COL_BASIC)
	_dash_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash_button.offset_left = -(FIRE_SIZE + MARGIN + 20)
	_dash_button.offset_top = -(MARGIN + FIRE_SIZE + 96)
	_dash_button.offset_right = -(FIRE_SIZE + MARGIN - 76)
	_dash_button.offset_bottom = -(MARGIN + FIRE_SIZE + 6)
	_dash_button.pressed.connect(func(): _dash_queued = true)
	_root.add_child(_dash_button)

func _round_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.3)
	style.set_corner_radius_all(24)
	style.set_border_width_all(3)
	style.border_color = color
	b.add_theme_stylebox_override(&"normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(color.r, color.g, color.b, 0.55)
	b.add_theme_stylebox_override(&"pressed", hover)
	b.add_theme_stylebox_override(&"hover", hover)
	return b

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 22)
	_overlay.add_child(box)

	_overlay_title = _label("VICTOIRE", 92, Cfg.COL_HEAL)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)

	_overlay_sub = _label("", 28)
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_sub)

	var replay := _round_button("REJOUER", Cfg.COL_HEAL)
	replay.custom_minimum_size = Vector2(280, 74)
	replay.add_theme_font_size_override(&"font_size", 28)
	replay.pressed.connect(_on_replay)
	var center := CenterContainer.new()
	center.add_child(replay)
	box.add_child(center)

# --- LECTURE PAR LE CONTRÔLEUR -------------------------------------------

func move_vector() -> Vector2:
	return _move_stick.value if _move_stick else Vector2.ZERO

func aim_vector() -> Vector2:
	return _fire_stick.value if _fire_stick else Vector2.ZERO

func is_firing() -> bool:
	return _fire_stick.pressed if _fire_stick else false

## Consommation à usage unique : le contrôleur lit l'appui une seule fois,
## sinon un simple tap déclencherait un changement d'arme par image.
func consume_swap() -> bool:
	var v := _swap_queued
	_swap_queued = false
	return v

func consume_dash() -> bool:
	var v := _dash_queued
	_dash_queued = false
	return v

func _on_slot_input(event: InputEvent, index: int) -> void:
	var tapped: bool = false
	if event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if tapped and player and player.active_slot != index:
		_swap_queued = true

# --- MISES À JOUR --------------------------------------------------------

func _process(_delta: float) -> void:
	if MatchDirector.phase in [MatchDirector.Phase.WARMUP,
			MatchDirector.Phase.ESCALATION, MatchDirector.Phase.CLOSING]:
		var t := int(MatchDirector.elapsed)
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	if player and _dash_button:
		# Le bouton s'estompe pendant la recharge : l'état de la capacité
		# se lit sans jauge supplémentaire.
		_dash_button.modulate.a = lerpf(0.4, 1.0, player.dash_ready_ratio())

func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := clampf(current / maxf(maximum, 0.01), 0.0, 1.0)
	_health_text.text = str(int(ceil(current)))
	var tw := create_tween()
	tw.tween_property(_health_fill, "offset_right", -3 + 327 * ratio, 0.12)
	_health_fill.color = Cfg.COL_HEAL.lerp(Cfg.COL_DANGER, (1.0 - ratio) ** 1.5)

func _on_inventory_changed(slots: Array, active: int) -> void:
	for i in _slot_panels.size():
		var id: StringName = slots[i] if i < slots.size() else &""
		var data := Registry.weapon(id)
		var style := _slot_panels[i].get_theme_stylebox(&"panel") as StyleBoxFlat
		if data == null:
			_slot_labels[i].text = "—"
			style.border_color = Color(1, 1, 1, 0.18)
			style.bg_color = Color(0, 0, 0, 0.5)
			continue
		var ammo := ""
		if i == active and player and player.weapon:
			ammo = "  " + player.weapon.ammo_text()
		_slot_labels[i].text = data.display_name + ammo
		# L'arme ACTIVE est bordée de sa couleur et remplie : impossible de
		# se tromper d'un coup d'œil, même en plein combat.
		if i == active:
			style.border_color = data.color
			style.bg_color = Color(data.color.r, data.color.g, data.color.b, 0.3)
			var tw := create_tween()
			tw.tween_property(_slot_panels[i], "scale", Vector2(1.08, 1.08), 0.07)
			tw.tween_property(_slot_panels[i], "scale", Vector2.ONE, 0.1)
		else:
			style.border_color = Color(data.color.r, data.color.g, data.color.b, 0.4)
			style.bg_color = Color(0, 0, 0, 0.5)

func _on_alive_changed(count: int) -> void:
	_alive_label.text = "%d VIVANT%s" % [count, "S" if count > 1 else ""]

func _on_countdown(value: int) -> void:
	_countdown.text = str(value) if value > 0 else "GO"
	_countdown.modulate.a = 1.0
	_countdown.scale = Vector2(1.6, 1.6)
	_countdown.pivot_offset = _countdown.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown, "modulate:a", 0.0, 0.8).set_delay(0.2)

func _on_announce(text: String, color: Color) -> void:
	_announce.text = text
	_announce.add_theme_color_override(&"font_color", color)
	_announce.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_announce, "modulate:a", 0.0, 0.5)

func _on_player_eliminated(peer_id: int, name_text: String) -> void:
	if player and peer_id == player.peer_id:
		return
	_on_announce("%s ÉLIMINÉ" % name_text.to_upper(), Cfg.COL_ENEMY_PLAYER)

func _on_local_died() -> void:
	# On n'affiche pas encore « rejouer » : la partie continue pour les
	# autres, et le joueur éliminé regarde la fin.
	_overlay_title.text = "ÉLIMINÉ"
	_overlay_title.add_theme_color_override(&"font_color", Cfg.COL_DANGER)
	_overlay_sub.text = "En attente de la fin de la partie…"
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.5)

func _on_match_ended(winner_id: int, winner_name: String) -> void:
	var won := player != null and winner_id == player.peer_id
	_overlay_title.text = "VICTOIRE" if won else "ÉLIMINÉ"
	_overlay_title.add_theme_color_override(&"font_color",
			Cfg.COL_HEAL if won else Cfg.COL_DANGER)
	_overlay_sub.text = "Dernier survivant de l'arène." if won \
			else "Vainqueur : %s" % winner_name
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.5)

func _on_replay() -> void:
	var main := get_tree().get_first_node_in_group(&"main")
	if main and main.has_method(&"restart_match"):
		main.call(&"restart_match")
