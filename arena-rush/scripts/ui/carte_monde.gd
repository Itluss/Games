extends Control
class_name CarteMonde
## UNE CARTE-MONDE DU MENU — la porte d'entrée d'une carte jouable, ou la
## promesse verrouillée de la suivante.
##
## C'EST LA VITRINE DE LA PROGRESSION. Le joueur qui ouvre le jeu doit
## voir DEUX choses en une seconde : où il peut jouer, et ce qui
## l'attend s'il monte. La carte verrouillée n'est pas une case grisée —
## c'est une AFFICHE : silhouette sombre, cadenas doré, « NIVEAU 10 » en
## grand. On ne cache pas la suite, on la fait désirer.
##
## Tout est dessiné : pas d'image à charger, le style vient des mêmes
## couleurs que le jeu.

signal choisie()

## Identité de la carte.
@export var titre := "L'ÎLE SANS BORD"
@export var sous_titre := "NIVEAUX 1-10"
## Verrouillée : silhouette sombre + cadenas + niveau requis.
@export var verrouillee := false
@export var niveau_requis := 10

var _police: Font
var _survol := false
var _appui := false


func _ready() -> void:
	_police = UiKit.police()
	custom_minimum_size = Vector2(234, 176)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_survol = true
		queue_redraw())
	mouse_exited.connect(func():
		_survol = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_appui = true
			elif _appui:
				_appui = false
				if not verrouillee:
					choisie.emit()
			queue_redraw()
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_appui = true
		elif _appui:
			_appui = false
			if not verrouillee:
				choisie.emit()
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _appui and not verrouillee:
		r = r.grow(-3)
	# ─── LE CADRE ──────────────────────────────────────────────────────
	var cadre := StyleBoxFlat.new()
	cadre.bg_color = Color("233048") if verrouillee else Color("2b3b58")
	cadre.set_corner_radius_all(14)
	cadre.border_color = Color("46587e") if verrouillee \
			else (Color("ffd94a") if _survol else Color("6fa8dc"))
	cadre.set_border_width_all(3)
	draw_style_box(cadre, r)
	var interieur := r.grow(-8)

	if verrouillee:
		_dessiner_verrouillee(interieur)
	else:
		_dessiner_ile(interieur)

	# ─── LE BANDEAU DE TITRE ───────────────────────────────────────────
	var bandeau := Rect2(interieur.position.x,
			interieur.end.y - 46, interieur.size.x, 46)
	var fond_bandeau := StyleBoxFlat.new()
	fond_bandeau.bg_color = Color(0.03, 0.05, 0.1, 0.72)
	fond_bandeau.set_corner_radius_all(8)
	draw_style_box(fond_bandeau, bandeau)
	var t := titre if not verrouillee else "? ? ?"
	var lt := _police.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 19)
	draw_string(_police, Vector2(bandeau.get_center().x - lt.x * 0.5,
			bandeau.position.y + 20), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
			Color.WHITE)
	var st := sous_titre
	var ls := _police.get_string_size(st, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(_police, Vector2(bandeau.get_center().x - ls.x * 0.5,
			bandeau.position.y + 39), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UiKit.OR_CLAIR if not verrouillee else Color(1, 1, 1, 0.55))


## L'AFFICHE DE L'ÎLE : ciel, mer, dune de sable, palmier stylisé et
## soleil — les couleurs exactes du jeu, pour que la carte tienne sa
## promesse.
func _dessiner_ile(z: Rect2) -> void:
	var scene := Rect2(z.position, Vector2(z.size.x, z.size.y - 50))
	# Ciel.
	draw_rect(scene, Color("7ec8e8"))
	# Soleil.
	draw_circle(scene.position + Vector2(scene.size.x * 0.78,
			scene.size.y * 0.22), 14, Color("ffe27a"))
	# Mer.
	var mer := Rect2(scene.position + Vector2(0, scene.size.y * 0.52),
			Vector2(scene.size.x, scene.size.y * 0.2))
	draw_rect(mer, Color("6fd8e0"))
	# Dune de sable, en deux bosses.
	var sable := PackedVector2Array()
	var base_y := scene.position.y + scene.size.y
	sable.append(Vector2(scene.position.x, base_y))
	for i in 13:
		var fx := float(i) / 12.0
		var y := base_y - scene.size.y * (0.30 + 0.10 * sin(fx * PI * 2.2))
		sable.append(Vector2(scene.position.x + scene.size.x * fx, y))
	sable.append(Vector2(scene.end.x, base_y))
	draw_colored_polygon(sable, Color("f2d493"))
	# Palmier : tronc penché + palmes.
	var pied := Vector2(scene.position.x + scene.size.x * 0.26,
			base_y - scene.size.y * 0.28)
	var cime := pied + Vector2(10, -34)
	draw_line(pied, cime, Color("9a6a34"), 5.0)
	for i in 5:
		var a := -PI * 0.9 + PI * 0.8 * float(i) / 4.0
		draw_line(cime, cime + Vector2(cos(a), sin(a)) * 18.0,
				Color("57b06a"), 4.0)


## L'AFFICHE VERROUILLÉE : la même île en OMBRE CHINOISE — on devine un
## monde, pas un trou — et le cadenas d'or par-dessus.
func _dessiner_verrouillee(z: Rect2) -> void:
	var scene := Rect2(z.position, Vector2(z.size.x, z.size.y - 50))
	draw_rect(scene, Color("18202f"))
	# Des reliefs mystérieux en silhouette.
	var crete := PackedVector2Array()
	var base_y := scene.position.y + scene.size.y
	crete.append(Vector2(scene.position.x, base_y))
	for i in 13:
		var fx := float(i) / 12.0
		var y := base_y - scene.size.y * (0.22 + 0.28 * absf(sin(fx * 7.0)))
		crete.append(Vector2(scene.position.x + scene.size.x * fx, y))
	crete.append(Vector2(scene.end.x, base_y))
	draw_colored_polygon(crete, Color("0d1220"))
	# Le cadenas d'or, au centre : anse + corps + trou de serrure.
	var c := scene.get_center() + Vector2(0, -4)
	draw_arc(c + Vector2(0, -10), 12.0, PI, TAU, 16, UiKit.OR_CLAIR, 5.0)
	var corps := StyleBoxFlat.new()
	corps.bg_color = UiKit.OR_CLAIR
	corps.set_corner_radius_all(5)
	draw_style_box(corps, Rect2(c + Vector2(-16, -10), Vector2(32, 26)))
	draw_circle(c + Vector2(0, 0), 4.0, Color("6a4a10"))
	draw_rect(Rect2(c + Vector2(-1.6, 2), Vector2(3.2, 8)), Color("6a4a10"))
	# Le niveau requis, sous le cadenas.
	var t := "NIVEAU %d" % niveau_requis
	var lt := _police.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(_police, Vector2(c.x - lt.x * 0.5, c.y + 34), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.OR_CLAIR)
