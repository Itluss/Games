extends Control
class_name Portrait
## PORTRAIT — le visage de Kael dans le bloc de profil.
##
## POURQUOI UN VRAI RENDU ET NON UN DESSIN. On aurait pu tracer une tête
## stylisée en 2D : moins cher, plus sûr. Mais Kael vient des dessins de la
## joueuse, passés par Meshy ; sa veste bleue, sa mèche et son accent orange
## SONT le personnage. Un visage inventé au trait dans l'interface serait un
## second Kael, qui ne ressemblerait au premier que de loin — et deux
## versions d'un même personnage, c'est une de trop.
##
## On rend donc le vrai modèle dans une petite fenêtre, une seule fois.
##
## LE MASQUE CIRCULAIRE se fait par découpe : ce Control dessine un disque,
## et `clip_children` interdit à son contenu d'en sortir. Aucun shader, donc
## rien qui puisse se comporter autrement sur le rendu de compatibilité du
## navigateur — qui est celui du téléphone.

const RENDU := 160

var _vue: SubViewport

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_vue = SubViewport.new()
	_vue.size = Vector2i(RENDU, RENDU)
	_vue.transparent_bg = true
	# SON PROPRE MONDE. Sans cela le portrait partagerait la scène du jeu :
	# il montrerait l'arène, la brume et les mobs, et son éclairage suivrait
	# le crépuscule au lieu de rester lisible.
	_vue.own_world_3d = true
	# UNE SEULE IMAGE. Le personnage ne bouge pas ; le redessiner soixante
	# fois par seconde reviendrait à payer un second rendu du jeu pour une
	# vignette de soixante-seize pixels.
	_vue.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vue)

	var scene := Node3D.new()
	_vue.add_child(scene)

	var kael := CharacterVisual.new()
	scene.add_child(kael)
	kael.build(Cfg.COL_LOCAL_PLAYER, Cfg.COL_KAEL_ACCENT, 1.9)
	kael.rotation.y = 0.42

	# ÉCLAIRAGE DE STUDIO, PAS CELUI DU JEU. Une clé chaude de trois quarts
	# sculpte le visage, une ambiante froide relève les ombres pour qu'aucune
	# partie ne tombe dans le noir. Le portrait doit rester lisible quelle
	# que soit l'heure qu'il fait dans le monde.
	var cle := DirectionalLight3D.new()
	cle.light_energy = 1.5
	cle.light_color = Color("fff0dc")
	cle.rotation_degrees = Vector3(-26.0, 38.0, 0.0)
	scene.add_child(cle)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa8d8")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 34.0
	# Cadré sur la TÊTE ET LES ÉPAULES. Le personnage entier ferait de lui
	# une figurine de six pixels de haut ; le buste est ce qu'on reconnaît.
	# CADRAGE MESURÉ EN IMAGE, pas calculé. Le premier réglage donnait un
	# personnage entier haut de vingt pixels : ce qu'on voit dépend de la
	# hauteur réelle de la tête du modèle, que seul un rendu révèle.
	cam.position = Vector3(0.30, 1.74, 0.96)
	scene.add_child(cam)
	cam.look_at(Vector3(0.0, 1.62, 0.0), Vector3.UP)
	cam.current = true

	# TROIS COUCHES, ET L'ORDRE EST LE SUJET.
	#
	# Un CanvasItem se dessine AVANT ses enfants. L'anneau ne peut donc pas
	# être tracé par ce nœud : il passerait sous le portrait. Et il ne peut
	# pas non plus l'être par le nœud qui découpe, puisque `clip_children`
	# transforme tout ce qu'il dessine en masque — l'anneau deviendrait un
	# trou. Il lui faut son propre calque, ajouté en dernier.
	var masque := Decoupe.new()
	masque.set_anchors_preset(Control.PRESET_FULL_RECT)
	masque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(masque)

	var tex := TextureRect.new()
	tex.texture = _vue.get_texture()
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	masque.add_child(tex)

	var anneau := Anneau.new()
	anneau.set_anchors_preset(Control.PRESET_FULL_RECT)
	anneau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anneau)


## Le disque de fond, qui sert AUSSI de pochoir à ce qu'il contient.
class Decoupe extends Control:
	func _init() -> void:
		clip_children = CanvasItem.CLIP_CHILDREN_ONLY

	func _draw() -> void:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, Color("22335f"))


## L'ANNEAU CYAN. C'est lui qui détache le portrait de n'importe quel fond
## et qui le rattache au joueur — le cyan est sa couleur dans tout le jeu.
class Anneau extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r - 2.0, 0.0, TAU, 40, UiKit.CYAN, 5.0, true)
		# Un liseré sombre à l'extérieur : sans lui, l'anneau clair se
		# confond avec le bord clair du panneau qui l'entoure.
		draw_arc(c, r + 1.0, 0.0, TAU, 40, Color(0.04, 0.07, 0.16, 0.85),
				2.5, true)
