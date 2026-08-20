extends Node3D
class_name HealthBar3D
## PLAQUE DE PERSONNAGE — nom, barre de vie, et l'étoile du porteur.
##
## Volontairement construite en quads plutôt qu'en Viewport d'interface :
## un Viewport par entité coûterait une passe de rendu par mob, ce qui est
## exactement le genre de détail qui fait chuter les FPS sur tablette.
##
## ─── POURQUOI ELLE PORTE MAINTENANT UN NOM ────────────────────────────
##
## La maquette d'interface montre au-dessus de chaque combattant son nom,
## dans SA couleur, surmontant une barre fine de la même teinte. Ce n'est
## pas de la décoration : sur une arène où six héros se ressemblent de
## dessus, la couleur de la barre est la réponse la plus rapide à « qui je
## vise ? ». Une barre verte pour tout le monde ne répondait à rien.
##
## ─── LA BARRE EST CONTINUE, ET ELLE L'ÉTAIT DÉJÀ ──────────────────────
##
## La consigne insiste : pas de barre segmentée. Elle ne l'a jamais été —
## c'est un quad qu'on met à l'échelle. Ce qui manquait, ce sont les BOUTS
## ARRONDIS : deux rectangles nets faisaient « jauge de moteur de jeu ». Un
## petit dégradé alpha aux extrémités suffit à les adoucir, et il tient
## dans une texture de trente-deux pixels partagée par toute la partie.

## Rayon d'arrondi, en fraction de la hauteur de la barre.
const ARRONDI := 0.5
## Largeur de la texture d'arrondi, en pixels. Minuscule : elle n'a qu'un
## profil horizontal à décrire, l'interpolation linéaire fait le reste.
const TEX_LARGE := 48
const TEX_HAUT := 12

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _nom: Label3D
var _etoile: MeshInstance3D
var _width: float = 1.0
var _ratio: float = 1.0
var _teinte: Color = Color("4cd964")
var _t: float = 0.0

## Texture d'arrondi partagée. Une seule pour tout le jeu : elle ne dépend
## ni du personnage ni de sa couleur, seulement de la forme.
static var _galet: ImageTexture = null


## Texture d'un « galet » : opaque au centre, transparente aux extrémités
## selon un profil de demi-cercle. Multipliée par la couleur du matériau,
## elle arrondit n'importe quelle barre sans géométrie supplémentaire.
static func _texture_galet() -> ImageTexture:
	if _galet != null:
		return _galet
	var img := Image.create(TEX_LARGE, TEX_HAUT, false, Image.FORMAT_RGBA8)
	var r := ARRONDI * float(TEX_HAUT)
	for y in TEX_HAUT:
		for x in TEX_LARGE:
			var dx := 0.0
			if float(x) + 0.5 < r:
				dx = r - (float(x) + 0.5)
			elif float(x) + 0.5 > float(TEX_LARGE) - r:
				dx = (float(x) + 0.5) - (float(TEX_LARGE) - r)
			var dy: float = absf(float(y) + 0.5 - float(TEX_HAUT) * 0.5)
			var d := sqrt(dx * dx + maxf(dy - (float(TEX_HAUT) * 0.5 - r), 0.0)
					** 2)
			# Bord adouci sur un pixel : sans lui, l'arrondi crénelle dès
			# que la barre s'éloigne de la caméra.
			var a: float = clampf((r - d) + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_galet = ImageTexture.create_from_image(img)
	return _galet


func build(width: float = 1.0, color: Color = Color("4cd964"),
		nom: String = "") -> void:
	_width = width
	_teinte = color
	var galet := _texture_galet()

	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.04, 0.05, 0.08, 0.82)
	bg_mat.albedo_texture = galet
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Billboard : la barre reste lisible quel que soit l'angle de caméra.
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.billboard_keep_scale = true
	# Toujours visible, même derrière un rocher : perdre de vue la santé
	# d'un ennemi derrière un obstacle rendrait le combat illisible.
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1

	_fill_mat = bg_mat.duplicate()
	_fill_mat.albedo_color = color
	_fill_mat.render_priority = 2

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(width, width * 0.115)
	_bg = MeshInstance3D.new()
	_bg.mesh = bg_mesh
	_bg.material_override = bg_mat
	_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bg)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(width * 0.92, width * 0.075)
	_fill = MeshInstance3D.new()
	_fill.mesh = fill_mesh
	_fill.material_override = _fill_mat
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)

	if nom != "":
		# UN `Label3D`, pas un panneau d'interface projeté : il se tourne
		# seul vers la caméra, il s'occlut correctement, et il ne coûte pas
		# de passe de rendu supplémentaire.
		_nom = Label3D.new()
		_nom.text = nom.to_upper()
		_nom.font_size = 96
		# La taille APPARENTE est réglée par l'échelle du pixel, pas par la
		# taille de police : une grande police rendue petite reste nette,
		# l'inverse bave.
		_nom.pixel_size = 0.0033
		_nom.modulate = color
		# Contour sombre : le nom passe au-dessus du sable clair comme
		# au-dessus d'un rocher sombre, sans jamais disparaître.
		_nom.outline_size = 26
		_nom.outline_modulate = Color(0.03, 0.04, 0.07, 0.95)
		_nom.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_nom.no_depth_test = true
		_nom.render_priority = 3
		_nom.outline_render_priority = 2
		_nom.position = Vector3(0, width * 0.22, 0)
		add_child(_nom)

	set_ratio(1.0)


## L'ÉTOILE DU PORTEUR — au-dessus du nom, et rien d'autre.
##
## La consigne est explicite : PAS de compteur 18/30 au-dessus du
## personnage. Dans le monde, l'étoile dit « c'est lui » ; le chiffre, lui,
## appartient au bas de l'écran, où on le lit quand on a le temps.
func afficher_etoile(actif: bool) -> void:
	if not actif:
		if _etoile != null and is_instance_valid(_etoile):
			_etoile.queue_free()
			_etoile = null
		return
	if _etoile != null and is_instance_valid(_etoile):
		return
	_etoile = MeshInstance3D.new()
	_etoile.name = "EtoilePorteur"
	_etoile.mesh = EtoileWanted._maille_etoile()
	var m := VisualKit.glow_mat(Color("ffc73a"), 1.9)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = 4
	_etoile.material_override = m
	_etoile.scale = Vector3.ONE * (_width * 0.62)
	_etoile.position = Vector3(0, _width * 0.62, 0)
	_etoile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_etoile)


func _process(delta: float) -> void:
	if _etoile == null or not is_instance_valid(_etoile):
		return
	# Un battement lent : l'étoile respire pour attirer l'œil sans tourner,
	# parce qu'un panneau qui tourne autour de l'axe caméra donne le
	# tournis quand on le suit du regard pendant trente secondes.
	_t += delta
	var b := 1.0 + sin(_t * 3.2) * 0.09
	_etoile.scale = Vector3.ONE * (_width * 0.62 * b)


## MODE DISCRET — la plaque ne montre plus QUE l'étoile.
##
## Le joueur local n'a pas besoin de lire son nom ni sa vie au-dessus de sa
## tête : le HUD du bas les porte déjà, et les répéter au centre de l'écran
## encombre la seule zone qu'on regarde vraiment. Mais s'il porte l'étoile,
## il doit la voir sur lui — c'est le retour qui confirme qu'il l'a bien.
##
## D'où ce mode plutôt qu'un simple `visible = false` sur toute la plaque :
## on éteint le nom et la barre, on garde l'étoile.
func mode_discret(actif: bool) -> void:
	if _bg:
		_bg.visible = not actif
	if _fill:
		_fill.visible = not actif
	if _nom:
		_nom.visible = not actif


func set_ratio(value: float) -> void:
	_ratio = clampf(value, 0.0, 1.0)
	if _fill == null:
		return
	# On rétrécit depuis la gauche (et non depuis le centre) : c'est la
	# lecture attendue d'une jauge.
	_fill.scale.x = maxf(_ratio, 0.001)
	_fill.position.x = -(_width * 0.92) * (1.0 - _ratio) * 0.5
	# ─── LA COULEUR D'IDENTITÉ TIENT, LE ROUGE NE VIENT QU'À LA FIN ────
	#
	# L'ancienne version repeignait la barre en vert→rouge à chaque appel,
	# ce qui écrasait silencieusement `set_bar_color` : la teinte du héros
	# ne survivait pas au premier point de dégât. On garde donc SA couleur
	# et l'on ne vire au rouge que sous un quart de vie — l'alerte reste
	# lisible, l'identité aussi.
	var alerte: float = clampf((0.25 - _ratio) / 0.25, 0.0, 1.0)
	_fill_mat.albedo_color = _teinte.lerp(Cfg.COL_DANGER, alerte)


func set_bar_color(color: Color) -> void:
	_teinte = color
	if _fill_mat:
		set_ratio(_ratio)
