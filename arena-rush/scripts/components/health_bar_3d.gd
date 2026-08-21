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

## Les trois valeurs de la jauge. Franches, saturées, et choisies pour
## trancher sur un sol ocre : c'est le seul fond que la carte propose.
const COL_PLEINE := Color("46d63c")
const COL_MOYENNE := Color("ffc02e")
const COL_BASSE := Color("ff3b30")

## Rayon d'arrondi, en fraction de la hauteur de la barre.
const ARRONDI := 0.5
## Largeur de la texture d'arrondi, en pixels. Minuscule : elle n'a qu'un
## profil horizontal à décrire, l'interpolation linéaire fait le reste.
const TEX_LARGE := 48
const TEX_HAUT := 12

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _etoile: MeshInstance3D
var _width: float = 1.0
var _ratio: float = 1.0
var _teinte: Color = Color("4cd964")
var _t: float = 0.0
## Plaque réduite à sa seule étoile — le joueur local. Voir `mode_discret`.
var _discret: bool = false

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
	# QUASI OPAQUE, ET TRÈS SOMBRE. À 0,82 d'opacité, le sable clair
	# transparaissait au travers et mangeait le contraste du contour.
	bg_mat.albedo_color = Color(0.03, 0.035, 0.055, 0.96)
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
	# ─── PLUS ÉPAISSE, ET AVEC UN VRAI BORD ───────────────────────────
	#
	# Le fond sombre dépassait du remplissage de deux centimètres de chaque
	# côté, soit UN PIXEL à la caméra de jeu : autant dire aucun contour.
	# C'est pourtant lui qui détache la barre du décor, quel que soit ce
	# décor. Il passe à quatre centimètres et demi, et la barre entière
	# s'épaissit de moitié.
	bg_mesh.size = Vector2(width, width * 0.20)
	_bg = MeshInstance3D.new()
	_bg.mesh = bg_mesh
	_bg.material_override = bg_mat
	_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bg)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(width * 0.88, width * 0.12)
	_fill = MeshInstance3D.new()
	_fill.mesh = fill_mesh
	_fill.material_override = _fill_mat
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)

	# ─── LE NOM A ÉTÉ RETIRÉ ──────────────────────────────────────────
	#
	# Il était écrit au-dessus de chaque combattant, dans sa couleur. À
	# l'usage il n'apportait rien : on ne lit pas « BOT 10 » en plein
	# combat, on lit une silhouette et une barre. Six héros aux couleurs et
	# aux formes distinctes se reconnaissent sans étiquette, et le
	# classement porte déjà les noms pour qui veut les consulter.
	#
	# Ce qu'il coûtait, en revanche, était réel : un `Label3D` par joueur,
	# dix panneaux de texte allumés en permanence, et une plaque plus haute
	# qui repoussait la barre loin au-dessus des têtes.
	#
	# Le paramètre `nom` reste dans la signature : les appelants le passent
	# déjà, et le retirer demanderait de les modifier pour un gain nul.

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


## ─── LA PLAQUE S'ÉTEINT QUAND ELLE DEVIENT ILLISIBLE ─────────────────
##
## Distance au-delà de laquelle nom et barre disparaissent, en mètres.
##
## POURQUOI CE RÉGLAGE EXISTE. La sonde de stabilité compte les maillages
## VISIBLES à l'image, et son plafond — 720 en profil téléphone — est calé
## sur des mesures : 686 tient en zone grise, 782 tue l'écran. Le jeu
## culmine entre 683 et 720 : la marge est nulle, et la barrière tombe au
## hasard des passes.
##
## Or les plaques de nom que porte chaque combattant ajoutent un `Label3D`
## par joueur — dix en partie complète, allumés en permanence, y compris
## pour ceux qui sont à quarante mètres où le nom fait trois pixels. C'est
## de la charge payée pour une information que personne ne lit.
##
## VINGT-SIX MÈTRES, ET PAS DIX. La caméra plonge de 10,4 m et embrasse une
## bonne vingtaine de mètres de terrain : couper trop court ferait
## disparaître la barre d'un adversaire encore parfaitement visible, ce qui
## serait un défaut de jeu bien pire que quelques instances de plus.
const PORTEE_LISIBLE := 26.0

## Période de vérification, en secondes. Cinq fois par seconde : une plaque
## qui s'allume un dixième de seconde trop tard ne se remarque pas, et l'on
## évite dix mesures de distance par image.
const PERIODE_PORTEE := 0.2

var _prochain_test := 0.0


func _process(delta: float) -> void:
	_prochain_test -= delta
	if _prochain_test <= 0.0:
		_prochain_test = PERIODE_PORTEE
		_regler_portee()
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
	# L'ÉTAT EST MÉMORISÉ, ET C'EST INDISPENSABLE. `_regler_portee` rallume
	# la plaque cinq fois par seconde dès qu'elle revient à portée : sans
	# ce drapeau, le joueur local retrouverait son propre nom au-dessus de
	# la tête un cinquième de seconde après le montage.
	_discret = actif
	_regler_portee()


## L'ÉTOILE DU PORTEUR N'EST JAMAIS ÉTEINTE, elle. C'est l'objectif du
## mode : la voir de loin est exactement son travail, et il n'y en a qu'une
## sur la carte — le coût est d'une instance, pas de dix.
func _regler_portee() -> void:
	if _bg == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var loin := global_position.distance_to(cam.global_position) \
			> PORTEE_LISIBLE
	var montrer := not loin and not _discret
	_bg.visible = montrer
	_fill.visible = montrer


func set_ratio(value: float) -> void:
	_ratio = clampf(value, 0.0, 1.0)
	if _fill == null:
		return
	# On rétrécit depuis la gauche (et non depuis le centre) : c'est la
	# lecture attendue d'une jauge.
	_fill.scale.x = maxf(_ratio, 0.001)
	_fill.position.x = -(_width * 0.88) * (1.0 - _ratio) * 0.5
	# ─── ELLE SE LIT PAR LA VALEUR, PLUS PAR LA TEINTE DU HÉROS ────────
	#
	# Elle portait la couleur d'identité du personnage. C'était cohérent
	# avec le reste de l'interface, et c'était illisible : le rose de Ruby
	# sur du sable orange, à quinze mètres, disparaît. Le vert de Nox se
	# confondait avec les cactus. Une barre par héros, c'est six problèmes
	# de contraste différents à résoudre sur tous les fonds de la carte —
	# et aucun n'était résolu.
	#
	# Une barre de vie ne répond qu'à une question : COMBIEN IL EN RESTE.
	# Vert franc, orange, rouge : trois valeurs que tout le monde lit sans
	# apprendre, identiques pour les six, et choisies pour trancher sur un
	# désert. L'identité, elle, se lit sur la silhouette du personnage, sur
	# la minicarte et dans le classement — trois endroits, c'est assez.
	var c: Color
	if _ratio > 0.55:
		c = COL_PLEINE.lerp(COL_MOYENNE, (1.0 - _ratio) / 0.45)
	else:
		c = COL_MOYENNE.lerp(COL_BASSE, clampf((0.55 - _ratio) / 0.4, 0.0, 1.0))
	_fill_mat.albedo_color = c


func set_bar_color(color: Color) -> void:
	_teinte = color
	if _fill_mat:
		set_ratio(_ratio)
