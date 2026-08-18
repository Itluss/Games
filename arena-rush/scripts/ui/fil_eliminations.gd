extends Control
class_name FilEliminations
## FIL DES ÉLIMINATIONS — qui vient de tuer qui.
##
## POURQUOI CE FIL EXISTE DANS UN MONDE PERSISTANT. Sans manche ni tableau
## final, plus rien ne dit qu'il se passe quelque chose ailleurs. Deux bots
## qui s'affrontent à quarante mètres sont, pour le joueur, un monde vide.
## Le fil est ce qui transforme des adversaires en HABITANTS : on lit qu'ils
## se battent entre eux, donc que le monde tourne sans nous.
##
## Il est court par construction — deux lignes. Un fil qui déborde devient
## un mur de texte qu'on cesse de lire, et il occuperait la place de la
## carte, qui compte davantage.

const MAX := 2
## Durée d'affichage d'une ligne, en secondes.
const DUREE := 7.0

var _lignes: Array[Dictionary] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_process(true)


func ajouter(tueur: String, victime: String, mien: bool) -> void:
	_lignes.push_front({"tueur": tueur, "victime": victime, "mien": mien,
			"reste": DUREE})
	while _lignes.size() > MAX:
		_lignes.pop_back()
	queue_redraw()


func _process(delta: float) -> void:
	if _lignes.is_empty():
		return
	var vivantes: Array[Dictionary] = []
	for l in _lignes:
		l["reste"] = float(l["reste"]) - delta
		if float(l["reste"]) > 0.0:
			vivantes.append(l)
	_lignes = vivantes
	queue_redraw()


func _draw() -> void:
	var f := UiKit.police()
	var haut := 30.0
	for i in _lignes.size():
		var l: Dictionary = _lignes[i]
		var y := float(i) * (haut + 5.0)
		# Les dernières secondes s'effacent en fondu : une ligne qui
		# disparaît d'un coup se lit comme un défaut d'affichage.
		var a := clampf(float(l["reste"]) / 1.2, 0.0, 1.0)
		var boite := Rect2(0.0, y, size.x, haut)
		draw_style_box(UiKit.panneau(12, Color(UiKit.PANNEAU.r,
				UiKit.PANNEAU.g, UiKit.PANNEAU.b, 0.9 * a),
				Color(1, 1, 1, 0.14 * a), 2), boite)
		var t := 17
		var tueur: String = l["tueur"]
		var victime: String = l["victime"]
		# LE TUEUR EN CYAN QUAND C'EST NOUS, en blanc sinon ; la victime
		# toujours en rouge. Deux couleurs suffisent à lire la ligne sans
		# la lire vraiment, ce qui est tout ce qu'on lui demande.
		var c_tueur: Color = UiKit.CYAN if bool(l["mien"]) else UiKit.BLANC
		var x := 12.0
		var base := y + haut * 0.68
		x = _mot(f, tueur, x, base, t, Color(c_tueur.r, c_tueur.g, c_tueur.b, a))
		UiKit.icone(self, &"crane", Vector2(x + 12.0, y + haut * 0.5), 8.0,
				Color(1, 1, 1, 0.75 * a))
		x += 26.0
		_mot(f, victime, x, base, t, Color(UiKit.ROUGE.r, UiKit.ROUGE.g,
				UiKit.ROUGE.b, a))


func _mot(f: Font, t: String, x: float, y: float, taille: int,
		c: Color) -> float:
	draw_string_outline(f, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1,
			taille, 5, Color(0.04, 0.07, 0.16, c.a * 0.95))
	draw_string(f, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, c)
	return x + f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille).x
