extends Control
class_name VirtualJoystick
## JOYSTICK VIRTUEL — base fixe, poignée mobile, suivi multi-doigts.
##
## DEUX EXIGENCES QUI DICTENT TOUT LE CODE :
##
##  1. MULTI-DOIGTS. Se déplacer et tirer en même temps est la base du
##     genre. On mémorise donc l'INDEX du doigt qui nous a saisis et on
##     ignore tous les autres — sans cela, le pouce droit volerait le
##     contrôle au pouce gauche.
##
##  2. ORIGINE DYNAMIQUE. Le joystick se recentre là où le doigt se pose,
##     au lieu d'imposer un centre fixe. Sur un téléphone tenu à deux
##     mains, le pouce ne retombe jamais deux fois au même endroit.

signal released()

@export var radius: float = 92.0
@export var deadzone: float = 0.14
## Si vrai, la base se replace sous le doigt au moment du toucher.
@export var dynamic_origin: bool = true

var value: Vector2 = Vector2.ZERO
var pressed: bool = false

var _finger: int = -1
var _origin: Vector2 = Vector2.ZERO
var _base: Control
var _knob: Control
var _base_home: Vector2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_base = _make_circle(radius, Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.28))
	add_child(_base)
	_knob = _make_circle(radius * 0.42, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.8))
	add_child(_knob)
	# `resized` plutôt qu'un calcul immédiat : à la première image, la
	# taille dépend du conteneur parent et n'est pas encore connue.
	resized.connect(_recenter)
	_recenter()

func _recenter() -> void:
	_base_home = size * 0.5
	_origin = _base_home
	_base.position = _base_home
	_knob.position = _base_home

func _make_circle(r: float, fill: Color, border: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta(&"r", r)
	c.set_meta(&"fill", fill)
	c.set_meta(&"border", border)
	c.draw.connect(func():
		c.draw_circle(Vector2.ZERO, r, fill)
		# Anneau dessiné en arcs : net à toute résolution, et aucune
		# texture à charger.
		c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, border, 3.0, true))
	return c

## RELÂCHEMENT GLOBAL — corrige un tir qui ne s'arrête plus.
##
## `_gui_input` ne reçoit que les évènements survenant DANS la zone du
## contrôle. Un doigt posé sur le bouton de tir puis relevé en dehors ne
## produisait donc aucun relâchement : `pressed` restait vrai et le
## personnage tirait indéfiniment sans que le joueur touche quoi que ce
## soit. On écoute donc la fin du geste au niveau global, où qu'elle ait
## lieu, dès lors que ce joystick a capturé le doigt.
func _input(event: InputEvent) -> void:
	if _finger == -1:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if not t.pressed and t.index == _finger:
			_end()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _finger:
			# La position est globale : on la ramène dans le repère local,
			# sinon la poignée saute dès que le doigt quitte la zone.
			_update(d.position - global_position)
	elif event is InputEventMouseButton and _finger == -2:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_end()
	elif event is InputEventMouseMotion and _finger == -2:
		_update((event as InputEventMouseMotion).position - global_position)

## Sécurité de dernier recours : si un relâchement se perdait malgré tout
## (perte de focus de l'onglet, interruption système), on ne reste pas
## bloqué en tir. Aucun bouton réellement pressé ne peut passer ici.
func _process(_delta: float) -> void:
	if _finger == -2 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1:
			_finger = event.index
			_begin(event.position)
			accept_event()
		elif not event.pressed and event.index == _finger:
			_end()
			accept_event()
	# Le glissement et le relâchement sont traités dans `_input`, qui les
	# reçoit même hors de la zone du contrôle.
	# La souris permet de tester la disposition tactile sur ordinateur.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _finger == -1:
			_finger = -2
			_begin(event.position)
			accept_event()
		elif not event.pressed and _finger == -2:
			_end()
			accept_event()
	elif event is InputEventMouseMotion and _finger == -2:
		_update(event.position)
		accept_event()

func _begin(pos: Vector2) -> void:
	pressed = true
	_origin = pos if dynamic_origin else _base_home
	_base.position = _origin
	_knob.position = _origin
	value = Vector2.ZERO

func _update(pos: Vector2) -> void:
	var delta := pos - _origin
	var clamped := delta.limit_length(radius)
	_knob.position = _origin + clamped
	var raw := clamped / radius
	# Zone morte remise à l'échelle : sans cela, franchir le seuil
	# provoquerait un saut de vitesse au lieu d'un démarrage progressif.
	var mag := raw.length()
	if mag < deadzone:
		value = Vector2.ZERO
	else:
		value = raw.normalized() * ((mag - deadzone) / (1.0 - deadzone))

func _end() -> void:
	_finger = -1
	pressed = false
	value = Vector2.ZERO
	_base.position = _base_home
	_origin = _base_home
	# Retour élastique de la poignée : minuscule, mais l'interface paraît
	# vivante plutôt que figée.
	var tw := create_tween()
	tw.tween_property(_knob, "position", _base_home, 0.09) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	released.emit()
