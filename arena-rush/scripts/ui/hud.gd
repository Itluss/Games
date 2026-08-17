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
## RÉPARTITION DES POUCES : le gauche DIRIGE, le droit TIRE. Le joystick
## de gauche ne sert qu'au déplacement, et le tir est un bouton que l'on
## maintient. La visée est automatique et accroche l'ennemi le plus
## proche — viser au doigt une cible mobile n'amuse personne.

const MARGIN := 26
const STICK_SIZE := 210
const FIRE_SIZE := 168
const ESQUIVE_SIZE := 104
const ARME_SIZE := 92

var player: Player = null

var _root: Control
var _move_stick: VirtualJoystick
var _fire_button: UiKit.BoutonRond
## Gâchette maintenue. Un booléen et non un compteur d'appuis : les armes
## automatiques se tiennent, elles ne se tapotent pas.
var _fire_held: bool = false
## Appui NEUF, à usage unique. Distinct de la gâchette maintenue : c'est
## lui qui autorise le tir accéléré au tapotement.
var _fire_tapped: bool = false
## Index du DOIGT qui tient le bouton de tir, -1 si aucun.
##
## POURQUOI UNE VOIE TACTILE SÉPARÉE : Godot fusionne le tactile en une
## souris unique, et un Button n'écoute que celle-ci. Or le joystick de
## déplacement, lui, suit son propre doigt. Dès qu'un doigt tenait le
## joystick — c'est-à-dire dès qu'on COURAIT — la souris émulée lui était
## acquise, et le second doigt n'atteignait jamais le bouton de tir.
## Appuyer sur TIR en courant ne faisait donc rien du tout.
##
## Le bouton suit désormais son propre doigt, par index, exactement comme
## le joystick. La voie souris subsiste pour le bureau.
var _doigt_tir: int = -1
var _swap_button: UiKit.BoutonRond
var _dash_button: UiKit.BoutonRond
var _alive_label: Label
var _timer_label: Label
var _announce: UiKit.Banniere
var _countdown: Label
var _health_bar: UiKit.BarreVie
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_ammo: Array[Label] = []
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label

var _swap_queued: bool = false
var _dash_queued: bool = false
var _help: Control = null

## Suivi du doigt posé sur le bouton de tir.
##
## On filtre par le RECTANGLE du bouton : un doigt posé ailleurs — sur le
## joystick, sur l'arène — ne déclenche rien. C'est ce qui évite de
## retomber dans le défaut où toucher l'écran tirait.
func _input(event: InputEvent) -> void:
	if _fire_button == null or not is_instance_valid(_fire_button):
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _doigt_tir < 0 and _fire_button.get_global_rect().has_point(t.position):
				_doigt_tir = t.index
				_fire_tapped = true
				_marquer_tir(true)
		elif t.index == _doigt_tir:
			_doigt_tir = -1
			_marquer_tir(false)
	elif event is InputEventScreenDrag and _doigt_tir >= 0:
		# Le doigt a glissé HORS du bouton : on relâche, sinon la gâchette
		# resterait tenue alors que le doigt est parti ailleurs.
		var d := event as InputEventScreenDrag
		if d.index == _doigt_tir \
				and not _fire_button.get_global_rect().has_point(d.position):
			_doigt_tir = -1
			_marquer_tir(false)


## Retour visuel de l'appui. Le style « pressé » d'un Button ne s'affiche
## que sur la voie souris : au doigt, sans cela, rien ne bougerait à
## l'écran et le bouton paraîtrait mort même quand il tire.
func _marquer_tir(actif: bool) -> void:
	if _fire_button == null or not is_instance_valid(_fire_button):
		return
	# Le bouton se redessine lui-même enfoncé : plus de bricolage d'échelle
	# ni de teinte depuis l'extérieur. Le DESSIN de l'état appartient au
	# bouton, la CONNAISSANCE du doigt au HUD.
	_fire_button.enfonce_doigt = actif
	_fire_button.queue_redraw()


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
	_build_help()

## Tout le texte de l'interface passe par ici, et donc par UiKit : grasse,
## penchée, cerclée de sombre. Un seul label réglé à la main suffirait à
## faire jurer l'ensemble.
func _label(text: String, size_px: int, color: Color = UiKit.BLANC) -> Label:
	var l := Label.new()
	l.text = text
	UiKit.texte(l, size_px, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## BARRE DU HAUT — deux segments accolés en une seule capsule.
##
## Les deux informations n'ont pas le même statut : le nombre de survivants
## est un ENJEU, le chronomètre un simple repère. Le premier est donc sur
## fond bleu saturé, le second sur fond d'encre. Les mettre au même niveau
## reviendrait à dire qu'ils comptent autant.
func _build_top() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_top = MARGIN
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.add_theme_constant_override(&"separation", 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	var gauche := PanelContainer.new()
	gauche.add_theme_stylebox_override(&"panel",
			UiKit.segment(Color("2f6ee0"), true, false))
	gauche.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(gauche)
	_alive_label = _label("4 VIVANTS", 27)
	gauche.add_child(_alive_label)

	var droite := PanelContainer.new()
	droite.add_theme_stylebox_override(&"panel",
			UiKit.segment(Color("111a30"), false, true))
	droite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(droite)
	_timer_label = _label("0:00", 27)
	droite.add_child(_timer_label)

func _build_center() -> void:
	# Une PLAQUE et non un texte nu : une élimination est un évènement, elle
	# mérite un objet à l'écran. Un mot qui apparaît seul se confond avec le
	# décor ; une plaque dorée s'impose et s'oublie aussitôt après.
	_announce = UiKit.Banniere.new()
	_announce.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_announce.offset_top = 92
	_announce.offset_bottom = 92 + 84
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	_health_bar = UiKit.BarreVie.new()
	_health_bar.custom_minimum_size = Vector2(360, 38)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_row.add_child(_health_bar)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override(&"separation", 16)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(slots)

	# CARTES D'ARMES. Le fond est bleu nuit DENSE et non translucide : posé
	# sur un sol clair, un panneau semi-transparent devient illisible
	# exactement quand le joueur cherche à savoir ce qu'il tient.
	for i in 2:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(196, 66)
		panel.add_theme_stylebox_override(&"panel",
				UiKit.panneau(16, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 4))
		# Les emplacements sont TOUCHABLES : passer d'une arme à l'autre en
		# tapant directement sa carte est plus direct qu'un bouton dédié.
		panel.gui_input.connect(_on_slot_input.bind(i))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.pivot_offset = Vector2(98, 33)
		slots.add_child(panel)
		_slot_panels.append(panel)

		var ligne := HBoxContainer.new()
		ligne.alignment = BoxContainer.ALIGNMENT_CENTER
		ligne.add_theme_constant_override(&"separation", 12)
		ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ligne)

		var nom := _label("—", 21)
		nom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ligne.add_child(nom)
		_slot_labels.append(nom)

		# Les munitions ont leur PROPRE étiquette, alignée à droite : mêlées
		# au nom, elles décalaient le titre à chaque coup tiré et la carte
		# tremblait en permanence.
		var muni := _label("", 21, Color(1, 1, 1, 0.72))
		muni.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ligne.add_child(muni)
		_slot_ammo.append(muni)

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

	# BOUTON DE TIR — un vrai bouton, maintenu, et non plus un second
	# joystick.
	#
	# POURQUOI CE CHANGEMENT : le tir était porté par un joystick, qui
	# donnait à la fois la direction et l'ordre de tirer. Deux
	# conséquences fâcheuses. La première est qu'on ne savait pas à quoi
	# il servait — un cercle se manipule, il ne se presse pas. La seconde
	# est qu'il fallait viser ET tirer du même pouce, alors que le genre
	# repose sur une visée automatique.
	#
	# La règle est désormais celle de tout jeu d'arène tactile : le pouce
	# gauche DIRIGE, le pouce droit TIRE, et le jeu accroche la cible.
	_fire_button = UiKit.bouton_rond(FIRE_SIZE, "TIR", &"viseur",
			UiKit.TIR_CLAIR, UiKit.TIR_SOMBRE)
	_fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fire_button.offset_left = -(FIRE_SIZE + MARGIN)
	_fire_button.offset_top = -(FIRE_SIZE + MARGIN)
	_fire_button.offset_right = -MARGIN
	_fire_button.offset_bottom = -MARGIN
	# MAINTENU, et non pas « cliqué » : on lit l'appui et le relâchement.
	# Le signal `pressed` ne se déclencherait qu'au relâchement, ce qui
	# interdirait de tenir la gâchette d'une arme automatique.
	# VOIE SOURIS, pour le bureau. La voie TACTILE est traitée dans
	# `_input`, par index de doigt : un Button n'écoute que la souris
	# émulée, dont le joystick s'empare dès qu'on court.
	_fire_button.button_down.connect(func():
		_fire_held = true
		_fire_tapped = true
		_marquer_tir(true))
	_fire_button.button_up.connect(func():
		_fire_held = false
		if _doigt_tir < 0:
			_marquer_tir(false))
	_root.add_child(_fire_button)

	# HIÉRARCHIE DES TAILLES. Le bouton de tir est le plus gros parce qu'il
	# est pressé cent fois par partie ; l'échange d'arme est le plus petit
	# parce qu'il l'est trois fois. Une taille égale pour les trois ferait
	# manquer le seul qui compte.
	_swap_button = UiKit.bouton_rond(ARME_SIZE, "ARME", &"echange",
			UiKit.ARME_CLAIR, UiKit.ARME_SOMBRE)
	_swap_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_swap_button.offset_left = -(FIRE_SIZE + MARGIN + ARME_SIZE + 18)
	_swap_button.offset_top = -(MARGIN + ARME_SIZE + 8)
	_swap_button.offset_right = -(FIRE_SIZE + MARGIN + 18)
	_swap_button.offset_bottom = -(MARGIN + 8)
	_swap_button.pressed.connect(func(): _swap_queued = true)
	_root.add_child(_swap_button)

	_dash_button = UiKit.bouton_rond(ESQUIVE_SIZE, "ESQUIVE", &"eclair",
			UiKit.ESQUIVE_CLAIR, UiKit.ESQUIVE_SOMBRE)
	_dash_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# MESURÉ EN IMAGE : ESQUIVE mordait sur TIR de vingt-cinq pixels. Deux
	# boutons qui se touchent, ce n'est pas seulement laid — au pouce, on
	# déclenche l'un en visant l'autre. On le cale FRANCHEMENT au-dessus.
	_dash_button.offset_bottom = -(MARGIN + FIRE_SIZE + 16)
	_dash_button.offset_top = _dash_button.offset_bottom - ESQUIVE_SIZE
	_dash_button.offset_right = -(MARGIN + 20)
	_dash_button.offset_left = _dash_button.offset_right - ESQUIVE_SIZE
	_dash_button.pressed.connect(func(): _dash_queued = true)
	_root.add_child(_dash_button)

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

	# BOUTON EN CAPSULE, et non rond : celui-ci porte un mot, pas une icône,
	# et un mot enfermé dans un cercle oblige à rapetisser le texte jusqu'à
	# l'illisible. Il reprend le reste de la charte — dégradé, bord clair,
	# ombre — pour rester de la même famille que les boutons d'action.
	var replay := Button.new()
	replay.text = "REJOUER"
	replay.custom_minimum_size = Vector2(300, 80)
	replay.focus_mode = Control.FOCUS_NONE
	UiKit.texte(replay, 30)
	var repos := UiKit.panneau(24, UiKit.VIE_SOMBRE, Color(1, 1, 1, 0.85), 5)
	replay.add_theme_stylebox_override(&"normal", repos)
	var appuye := UiKit.panneau(24, UiKit.VIE_CLAIR, Color(1, 1, 1, 0.85), 5)
	replay.add_theme_stylebox_override(&"pressed", appuye)
	replay.add_theme_stylebox_override(&"hover", appuye)
	replay.pressed.connect(_on_replay)
	var center := CenterContainer.new()
	center.add_child(replay)
	box.add_child(center)

# --- LECTURE PAR LE CONTRÔLEUR -------------------------------------------

func move_vector() -> Vector2:
	return _move_stick.value if _move_stick else Vector2.ZERO

## Le tactile ne fournit PLUS de direction de visée : le joystick droit a
## laissé la place à un bouton. Le pouce gauche dirige, la visée est
## automatique. La fonction subsiste pour que le contrôleur reste
## indifférent au périphérique.
func aim_vector() -> Vector2:
	return Vector2.ZERO

func is_firing() -> bool:
	return _fire_held or _doigt_tir >= 0

## Consommation à usage unique : sans cela un seul appui vaudrait un
## bonus de cadence à chaque image.
func consume_tap() -> bool:
	var v := _fire_tapped
	_fire_tapped = false
	return v

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
	# La barre se dessine elle-même, teinte comprise : le HUD lui donne des
	# chiffres, pas des pixels.
	_health_bar.regler(current, maximum)

func _on_inventory_changed(slots: Array, active: int) -> void:
	for i in _slot_panels.size():
		var id: StringName = slots[i] if i < slots.size() else &""
		var data := Registry.weapon(id)
		var style := _slot_panels[i].get_theme_stylebox(&"panel") as StyleBoxFlat
		if data == null:
			_slot_labels[i].text = "—"
			_slot_ammo[i].text = ""
			style.border_color = UiKit.PANNEAU_BORD
			style.bg_color = UiKit.PANNEAU
			style.set_border_width_all(4)
			continue
		_slot_labels[i].text = data.display_name
		_slot_ammo[i].text = player.weapon.ammo_text() \
				if i == active and player and player.weapon else ""
		# L'arme ACTIVE porte un bord ÉPAIS à sa couleur et un fond éclairci.
		# Le bord seul ne suffisait pas : sur un téléphone tenu à bout de
		# bras, trois pixels de différence ne se voient pas.
		if i == active:
			style.border_color = data.color
			style.bg_color = UiKit.PANNEAU.lerp(data.color, 0.26)
			style.set_border_width_all(6)
			var tw := create_tween()
			tw.tween_property(_slot_panels[i], "scale", Vector2(1.07, 1.07), 0.07)
			tw.tween_property(_slot_panels[i], "scale", Vector2.ONE, 0.1)
		else:
			style.border_color = Color(data.color.r, data.color.g,
					data.color.b, 0.45)
			style.bg_color = UiKit.PANNEAU
			style.set_border_width_all(4)

func _on_alive_changed(count: int) -> void:
	_alive_label.text = "%d VIVANT%s" % [count, "S" if count > 1 else ""]

func _on_countdown(value: int) -> void:
	# « GO » : la partie commence, la légende doit libérer l'écran.
	if value == 0:
		_hide_help()
	_countdown.text = str(value) if value > 0 else "GO"
	_countdown.modulate.a = 1.0
	_countdown.scale = Vector2(1.6, 1.6)
	_countdown.pivot_offset = _countdown.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown, "modulate:a", 0.0, 0.8).set_delay(0.2)

func _on_announce(text: String, color: Color) -> void:
	# La plaque prend la TEINTE de l'évènement — dorée pour une élimination,
	# rouge pour la mort du joueur — tout en gardant son dégradé. Une
	# couleur plate perdrait le relief qui la fait exister.
	_announce.afficher(text, color.lightened(0.30), color.darkened(0.22))
	_announce.modulate.a = 1.0
	# Elle ARRIVE, elle ne se contente pas d'apparaître : un objet qui
	# surgit se remarque, un objet qui se révèle en fondu se manque.
	_announce.scale = Vector2(0.7, 0.7)
	_announce.pivot_offset = Vector2(_announce.size.x * 0.5, 40.0)
	var tw := create_tween()
	tw.tween_property(_announce, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
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


# --- LÉGENDE DES COMMANDES ----------------------------------------------
#
# Affichée pendant le compte à rebours, puis effacée au « GO ».
#
# POURQUOI ELLE EST NÉCESSAIRE : quatre boutons sans explication, c'est
# quatre boutons qu'on n'utilise pas. Un joueur qui ignore l'existence de
# l'esquive ou du changement d'arme ne joue qu'à la moitié du jeu. La
# légende ne coûte rien puisqu'elle occupe un temps mort — celui du
# décompte, pendant lequel il n'y a de toute façon rien à faire.

func _build_help() -> void:
	_help = Control.new()
	_help.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_help)

	# Chaque encart est ancré PRÈS de la commande qu'il décrit : une
	# légende déportée en liste obligerait à faire la correspondance
	# soi-même, ce que personne ne fait sous la pression d'un décompte.
	_help_note("SE DÉPLACER\nUNIQUEMENT", Cfg.COL_LOCAL_PLAYER,
			Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN + 14, -(STICK_SIZE + 74)))
	# LES TROIS ENCARTS DE DROITE SONT REGROUPÉS EN UNE COLONNE.
	#
	# Éparpillés, chacun collé à son bouton, ils se chevauchaient entre eux
	# ET recouvraient les cartes d'armes — vérifié en image, deux fois. Le
	# coin bas-droit d'un écran de téléphone en paysage n'a tout simplement
	# pas la place d'accueillir trois blocs de texte et trois boutons.
	#
	# La colonne est alignée à DROITE et remonte au-dessus des commandes :
	# elle reste du côté des boutons qu'elle décrit, sans jamais mordre
	# dessus. Chaque ligne garde la couleur de son bouton, ce qui suffit à
	# faire la correspondance sans flèche ni encadré.
	var aide := VBoxContainer.new()
	aide.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	aide.offset_right = -(MARGIN + 14)
	aide.offset_bottom = -(MARGIN + FIRE_SIZE + ESQUIVE_SIZE + 34)
	aide.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	aide.grow_vertical = Control.GROW_DIRECTION_BEGIN
	aide.alignment = BoxContainer.ALIGNMENT_END
	aide.add_theme_constant_override(&"separation", 4)
	aide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(aide)

	for entree in [
			{"t": "MAINTENIR POUR TIRER · VISÉE AUTOMATIQUE", "c": Cfg.COL_SHOTGUN},
			{"t": "ESQUIVER", "c": Cfg.COL_BASIC},
			{"t": "CHANGER D'ARME", "c": Cfg.COL_ENERGY}]:
		var ligne := _label(entree["t"], 19, entree["c"])
		ligne.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		aide.add_child(ligne)

	var goal := _label("TUEZ LES MOBS · RAMASSEZ LEURS ARMES · SOYEZ LE DERNIER",
			24, Color(1, 1, 1, 0.92))
	goal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# 196 et non 150 : la plaque d'annonce occupe la bande 92-176, et les
	# deux se superposaient dès qu'une élimination tombait.
	goal.offset_top = 196
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.add_child(goal)

func _help_note(text: String, color: Color, preset: int, offset: Vector2) -> void:
	var lbl := _label(text, 19, color)
	lbl.set_anchors_preset(preset)
	lbl.offset_left = offset.x
	lbl.offset_top = offset.y
	lbl.grow_horizontal = Control.GROW_DIRECTION_END
	lbl.grow_vertical = Control.GROW_DIRECTION_END
	_help.add_child(lbl)

func _hide_help() -> void:
	if _help == null or not is_instance_valid(_help):
		return
	var tw := create_tween()
	tw.tween_property(_help, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_help.queue_free)
	_help = null
