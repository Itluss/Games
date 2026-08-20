extends PanelContainer
class_name BarreWanted
## LA BARRE WANTED — l'état de l'étoile, en un coup d'œil.
##
## DEUX ÉTATS, ET UN SEUL BANDEAU. On aurait pu faire apparaître et
## disparaître deux panneaux ; ils auraient sauté l'un sur l'autre à chaque
## ramassage. Un seul bandeau qui change de contenu garde sa place, et le
## joueur sait toujours où regarder.
##
##   A — personne ne la porte : « ÉTOILE DISPONIBLE », jauge éteinte.
##   B — quelqu'un la porte : « <NOM> DÉTIENT L'ÉTOILE ! », jauge 0→30.
##
## LE NOM PORTE SA COULEUR D'IDENTITÉ, le reste du texte est blanc. C'est
## la même règle que le classement et que les plaques de tête : une teinte
## veut dire un personnage, partout, sans exception.
##
## PAS DE POPUP. Les trois événements — ramassage, chute, victoire — se
## disent DANS le bandeau, en changeant son texte une seconde. La consigne
## est explicite là-dessus, et elle a raison : un encart qui surgit au
## milieu d'une fusillade cache exactement ce qu'on regardait.

## Durée d'affichage des messages d'événement.
const FLASH := 1.1

var _icone: Control
var _titre: Label
var _jauge: ProgressBar
var _chiffre: Label
var _flash_restant := 0.0
var _lueur := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel",
			UiKit.panneau(20, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 3))

	var marge := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right"]:
		marge.add_theme_constant_override(cote, 14)
	for cote in [&"margin_top", &"margin_bottom"]:
		marge.add_theme_constant_override(cote, 7)
	marge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marge)

	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override(&"separation", 12)
	ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marge.add_child(ligne)

	_icone = Control.new()
	_icone.custom_minimum_size = Vector2(46, 46)
	_icone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icone.draw.connect(_dessiner_etoile)
	ligne.add_child(_icone)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ligne.add_child(col)

	_titre = Label.new()
	UiKit.texte(_titre, 20, UiKit.BLANC)
	_titre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_titre)

	var bas := HBoxContainer.new()
	bas.add_theme_constant_override(&"separation", 10)
	bas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bas)

	_jauge = ProgressBar.new()
	_jauge.show_percentage = false
	_jauge.min_value = 0.0
	_jauge.max_value = EtoileDirector.DUREE
	_jauge.custom_minimum_size = Vector2(240, 14)
	_jauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jauge.add_theme_stylebox_override(&"background",
			UiKit.panneau(7, UiKit.CREUX, Color(1, 1, 1, 0.10), 2))
	_jauge.add_theme_stylebox_override(&"fill",
			UiKit.panneau(7, UiKit.OR_CLAIR, UiKit.OR_SOMBRE, 0))
	bas.add_child(_jauge)

	_chiffre = Label.new()
	UiKit.texte(_chiffre, 19, UiKit.OR_CLAIR)
	_chiffre.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_chiffre.custom_minimum_size = Vector2(74, 0)
	_chiffre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bas.add_child(_chiffre)

	EtoileDirector.ramassee.connect(_sur_ramassage)
	EtoileDirector.lachee.connect(_sur_chute)
	EtoileDirector.gagnee.connect(_sur_victoire)
	set_process(true)


## L'étoile du bandeau, dessinée et non texturée : c'est le même contour à
## cinq branches que la maille 3D, donc la même silhouette dans le monde et
## dans l'interface.
func _dessiner_etoile() -> void:
	var c := _icone.size * 0.5
	var r: float = minf(c.x, c.y) * 0.94
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0 - PI * 0.5
		var rayon: float = r if i % 2 == 0 else r * 0.44
		pts.append(c + Vector2(cos(a), sin(a)) * rayon)
	# La lueur pulse une seconde après chaque événement : c'est le « petit
	# flash doré » demandé, obtenu sans effet de particules ni tween.
	if _lueur > 0.0:
		_icone.draw_colored_polygon(pts, Color(1, 0.85, 0.35, _lueur * 0.5))
	_icone.draw_colored_polygon(pts, UiKit.OR_CLAIR)
	var contour := pts.duplicate()
	contour.append(pts[0])
	_icone.draw_polyline(contour, Color(0.35, 0.22, 0.04, 0.9), 2.0, true)


func _process(delta: float) -> void:
	if _lueur > 0.0:
		_lueur = maxf(_lueur - delta * 1.6, 0.0)
		_icone.queue_redraw()
	if _flash_restant > 0.0:
		_flash_restant -= delta
		if _flash_restant > 0.0:
			# Pendant un message d'événement, la jauge suit quand même
			# l'état réel : rien ne se fige derrière le texte.
			_maj_jauge()
			return
	_maj_texte()
	_maj_jauge()


func _maj_jauge() -> void:
	var t: float = EtoileDirector.temps
	_jauge.value = t
	if EtoileDirector.porteur_id == 0:
		_chiffre.text = ""
		return
	# ARRONDI AU PLUS PROCHE ENTIER INFÉRIEUR, et borné à la durée : sans
	# la borne, la dernière image affiche « 30 / 30 » un instant avant que
	# la victoire ne soit annoncée, ce qui donne l'impression d'un raté.
	_chiffre.text = "%d / %d" % [mini(int(t), int(EtoileDirector.DUREE)),
			int(EtoileDirector.DUREE)]


func _maj_texte() -> void:
	if EtoileDirector.porteur_id == 0:
		# ÉTAT A. Pas de nom, pas de chiffre — juste l'invitation.
		_titre.text = "ÉTOILE DISPONIBLE"
		_titre.add_theme_color_override(&"font_color", UiKit.OR_CLAIR)
		return
	var j := EtoileDirector.porteur()
	var nom := j.display_name.to_upper() if j != null else "?"
	_titre.text = "%s DÉTIENT L'ÉTOILE !" % nom
	_titre.add_theme_color_override(&"font_color",
			Cfg.couleur_identite(j.heros()) if j != null else UiKit.BLANC)


func _message(t: String, couleur: Color) -> void:
	_titre.text = t
	_titre.add_theme_color_override(&"font_color", couleur)
	_flash_restant = FLASH
	_lueur = 1.0
	_icone.queue_redraw()


func _sur_ramassage(_peer_id: int) -> void:
	# Pas de message dédié au ramassage : le nom du porteur EST le message,
	# et il reste affiché tant qu'il la garde. Un « ÉTOILE PRISE » d'une
	# seconde ne ferait que retarder l'information utile.
	_maj_texte()
	_lueur = 1.0
	_icone.queue_redraw()


func _sur_chute(_position: Vector3) -> void:
	_message("ÉTOILE LÂCHÉE", UiKit.ROUGE)


func _sur_victoire(peer_id: int, _victoires: int) -> void:
	var j := MatchDirector.players.get(peer_id) as Player
	var nom := j.display_name.to_upper() if j != null else ""
	_message("ÉTOILE GAGNÉE ! %s" % nom, UiKit.OR_CLAIR)
