extends RefCounted
class_name VisualKit
## ATELIER VISUEL — construit des silhouettes stylisées à partir de
## primitives Godot.
##
## POURQUOI DU PROCÉDURAL : le projet n'a pas encore de modèles 3D. Plutôt
## que de livrer des cubes gris, on assemble des primitives avec des
## proportions exagérées, des couleurs franches et un liseré lumineux — ce
## qui donne une direction artistique cohérente immédiatement.
##
## POURQUOI C'EST JETABLE SANS DOULEUR : rien ici n'est appelé par la
## logique de jeu. Les entités possèdent un nœud `Visual` séparé ; le jour
## où de vrais .glb arrivent, on remplace le contenu de ce nœud et pas une
## ligne de gameplay ne bouge.

## Matériau maison : couleur franche, spéculaire discret, liseré lumineux
## qui détache la silhouette du décor (l'ingrédient « cartoon premium »).
static func mat(color: Color, emission: float = 0.0,
		roughness: float = 0.65) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	m.metallic_specular = 0.35
	# ÉCLAIRAGE CELLULÉ — c'est LUI qui fait le dessin animé. Au lieu d'un
	# dégradé continu du clair au sombre, la lumière se casse en aplats
	# francs : une zone éclairée, une zone d'ombre, une frontière nette.
	# Godot le fournit nativement, donc aucun shader maison à maintenir et
	# aucun risque en WebGL2.
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.3
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

## NOYAU DE PROJECTILE — opaque et lumineux, et c'est tout le sujet.
##
## POURQUOI PAS `glow_mat`. Le matériau additif ajoute sa couleur à ce qui
## est derrière : sur un fond sombre il éclate, sur le sable clair du
## désert il DISPARAÎT — on additionnait du cyan à du blanc, ce qui donne
## du blanc. Depuis que le monde est passé en plein jour, un projectile
## purement additif n'était plus visible là où le joueur passe le plus de
## temps. Le noyau est donc opaque : sa couleur remplace le fond au lieu de
## s'y ajouter, donc elle se voit sur n'importe quel décor. Le halo additif
## vient par-dessus, en second, pour le nerf.
static func noyau_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# À PEINE ÉCLAIRCI. Un premier essai à +35 % de clarté rendait toutes
	# les munitions blanches : la teinte de l'arme, qui est le seul moyen
	# de savoir qui tire quoi, disparaissait au profit d'un trait pâle.
	m.albedo_color = color.lightened(0.1)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.9
	return m

## Matériau lumineux des projectiles, traînées, gerbes et anneaux.
##
## IL N'EST PLUS ADDITIF, ET C'EST LA CORRECTION LA PLUS IMPORTANTE DU LOT.
##
## Le mélange additif ajoute la couleur de l'effet à celle du fond. Sur le
## crépuscule indigo d'avant, un tir cyan éclatait. Depuis que le monde se
## joue en plein jour sur du sable clair, il additionnait du cyan à du
## presque-blanc : le résultat était BLANC. Vérifié en capture — traînées,
## éclairs de bouche et gerbes d'impact ressortaient tous de la même
## couleur, celle du papier. Autrement dit le joueur voyait qu'il se passait
## quelque chose, mais plus QUOI : ni l'arme, ni le camp, ni le type de
## dégât ne se lisaient.
##
## En mélange normal, la couleur de l'effet REMPLACE le fond au lieu de s'y
## ajouter : elle tient sur le sable clair comme sur la pierre sombre.
## L'émission reste, donc le halo de floraison continue de la faire vibrer
## sur les machines qui l'affichent.
##
## `opacite` sert aux enveloppes qu'on veut voir à travers — le halo d'un
## projectile doit laisser deviner son noyau, pas le masquer.
static func glow_mat(color: Color, energy: float = 3.0,
		opacite: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, opacite)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## CONTOUR — deuxième signal fort du dessin animé.
##
## Technique de la « coque inversée » : on redessine la même maille
## légèrement dilatée, en noir, en n'affichant que ses faces ARRIÈRE. Le
## résultat est un liseré sombre qui suit exactement la silhouette.
##
## Godot expose `grow` et `cull_mode`, donc là encore aucun shader maison.
## Matériaux de contour, mis en cache par épaisseur.
##
## CE N'EST PAS LA CORRECTION DE L'ÉCRAN BRUN, et je l'ai cru un moment.
## Partager le matériau entre toutes les mailles ne change RIEN à la panne :
## mesuré au navigateur, elle revient à l'identique. Ce n'était donc jamais
## une question de nombre de matériaux — voir `add_outline` pour la vraie
## cause, qui est le nombre d'INSTANCES.
##
## Le cache reste parce qu'il est juste : tous les contours partagent la
## même couleur et le même mode, rien ne justifie un exemplaire par maille.
static var _cache_contour: Dictionary = {}

static func outline_mat(width: float = 0.05) -> StandardMaterial3D:
	var cle := snappedf(width, 0.005)
	if _cache_contour.has(cle):
		return _cache_contour[cle]
	var m := StandardMaterial3D.new()
	# Pas un noir pur : un violet très sombre s'intègre mieux à une
	# palette chaude qu'un trait de feutre.
	m.albedo_color = Color(0.07, 0.05, 0.10)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	m.disable_receive_shadows = true
	_cache_contour[cle] = m
	return m

## Greffe un contour sur une maille. Désactivé en qualité basse : c'est un
## doublement des appels de rendu, donc le premier poste à sacrifier.
##
## RÉSERVÉ AUX FORMES RONDES. La dilatation se fait le long des normales ;
## sur une sphère ou une capsule elle produit un liseré net, mais sur un
## cube les trois normales d'un coin divergent et la coque se déchire aux
## arêtes. Les blocs du décor s'en passent donc, et comptent sur leur
## chapeau clair et l'éclairage cellulé pour se détacher.
## CONTOUR — greffé sur une maille, et sur téléphone UNIQUEMENT sur celle
## qui fait la silhouette.
##
## CE QUE CE RÉGLAGE CORRIGE : UNE PANNE D'AFFICHAGE COMPLÈTE.
##
## L'écran devenait un aplat brun plein cadre au bout de deux minutes de
## jeu, sur téléphone uniquement, et n'en repartait plus — mort et
## réapparition comprises. Interface intacte, minicarte vivante, 60 images
## par seconde, caméra parfaitement placée qui projetait le joueur au
## centre du cadre. Le monde était là ; il n'était plus DESSINÉ.
##
## Mesuré dans un vrai navigateur, en profil téléphone, sur des sessions de
## huit à neuf minutes identiques — c'est le compte de maillages VISIBLES
## qui décide, et rien d'autre :
##
##     un contour par maille        416 → 782 maillages → écran mort
##                                  primitives 49 565 → 10 730
##     aucun contour                346 → 523 → aucune panne
##                                  primitives 39 946 → 64 308
##
## Plus d'objets ET moins de dessin : ce n'est pas une saturation
## progressive mais un SEUIL du rendu compatibilité de WebGL, au-delà
## duquel la géométrie 3D cesse d'être soumise — sans une ligne d'erreur
## dans le journal du navigateur. La bascule est entre 523 et 782.
##
## DEUX FAUSSES PISTES ÉCARTÉES PAR LA MESURE, annoncées trop vite toutes
## les deux : la mémoire vidéo monte sans à-coup (101 → 114 Mo de part et
## d'autre de la bascule), et partager le matériau de contour entre toutes
## les mailles ne change RIEN. Ni la mémoire, ni les matériaux : les
## INSTANCES.
##
## POURQUOI UNE DÉSIGNATION EXPLICITE ET NON UN SEUIL DE TAILLE. Un seuil a
## été essayé — 0,70 m — et il tient sur huit minutes, mais il laisse 686
## maillages, c'est-à-dire la zone grise entre le dernier point sûr et le
## premier point mortel. Il gardait encore le canon du fusil et le tube du
## lance-grenades, invisibles à treize mètres ; et le monter davantage
## aurait fait perdre son contour au TORSE DU JOUEUR, à 0,78 m, exactement
## celui qui compte le plus. Deviner à la taille était le mauvais outil :
## chaque personnage désigne donc lui-même sa pièce, et l'on retombe à 620.
##
## `impose` est ce que la pièce désignée passe. Sur ordinateur rien ne
## change : toutes les mailles gardent leur contour.
static func add_outline(mi: MeshInstance3D, width: float = 0.05,
		impose := false) -> void:
	if mi == null or mi.mesh == null:
		return
	if Cfg.quality == Cfg.Quality.LOW and not impose:
		return
	# Idempotent : en qualité haute la pièce désignée reçoit déjà son
	# contour par la fabrique commune, et on ne veut pas l'en coiffer deux
	# fois.
	if mi.has_node("Contour"):
		return
	var o := MeshInstance3D.new()
	o.name = "Contour"
	o.mesh = mi.mesh
	o.material_override = outline_mat(width)
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(o)

static func _mesh(mesh: Mesh, material: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	# Les silhouettes projettent une ombre, jamais elles n'en reçoivent de
	# leurs propres sous-parties : c'est ce qui garde un rendu net.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_outline(mi)
	return mi

static func box(size: Vector3, material: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(m, material, pos, rot)

static func sphere(radius: float, material: Material, pos: Vector3,
		scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	# Résolution volontairement basse : silhouette lisible, peu de sommets.
	m.radial_segments = 16
	m.rings = 8
	return _mesh(m, material, pos, Vector3.ZERO, scale)

static func capsule(radius: float, height: float, material: Material,
		pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return _mesh(m, material, pos, rot)

static func cylinder(radius: float, height: float, material: Material,
		pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 14
	return _mesh(m, material, pos, rot)

static func cone(radius: float, height: float, material: Material,
		pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	return _mesh(m, material, pos, rot)

# --- PERSONNAGES ---------------------------------------------------------

## Bipède stylisé. Les parties sont NOMMÉES car l'animateur procédural les
## adresse par nom (`get_node_or_null("Head")`) : le squelette est un
## contrat, pas un tas de mailles.
##
## Proportions volontairement exagérées (grosse tête, membres courts,
## épaules larges) — c'est ce qui reste lisible vu de haut sur un écran de
## téléphone.
static func build_humanoid(color: Color, accent: Color,
		height: float = 1.7) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"

	var body_mat := mat(color)
	var accent_mat := mat(accent, 0.6)
	var dark_mat := mat(color.darkened(0.35))

	var u := height / 1.7  # échelle relative à une taille de référence

	var torso := capsule(0.30 * u, 0.78 * u, body_mat, Vector3(0, 0.86 * u, 0))
	torso.name = "Torso"
	# LA PIÈCE DÉSIGNÉE. Sur téléphone, c'est le seul contour du personnage
	# — et c'est celui que l'œil lit : le torse porte la silhouette, les
	# membres et l'arme n'y ajoutent rien à treize mètres de haut.
	add_outline(torso, 0.05, true)
	root.add_child(torso)

	# Épaulières : elles élargissent la silhouette vue du dessus, ce qui
	# rend le personnage lisible même minuscule à l'écran.
	var pads := box(Vector3(0.86 * u, 0.16 * u, 0.44 * u), accent_mat,
			Vector3(0, 1.16 * u, 0))
	pads.name = "Shoulders"
	root.add_child(pads)

	var head := sphere(0.27 * u, body_mat, Vector3(0, 1.52 * u, 0),
			Vector3(1.0, 0.94, 0.96))
	head.name = "Head"
	root.add_child(head)

	# Visière : donne une direction de regard sans avoir à modéliser un
	# visage, et indique instantanément où le personnage fait face.
	var visor := box(Vector3(0.34 * u, 0.11 * u, 0.06 * u), accent_mat,
			Vector3(0, 1.55 * u, -0.24 * u))
	visor.name = "Visor"
	root.add_child(visor)

	var arm_l := capsule(0.10 * u, 0.50 * u, dark_mat,
			Vector3(-0.40 * u, 0.94 * u, 0))
	arm_l.name = "ArmL"
	root.add_child(arm_l)

	var arm_r := capsule(0.10 * u, 0.50 * u, dark_mat,
			Vector3(0.40 * u, 0.94 * u, 0))
	arm_r.name = "ArmR"
	root.add_child(arm_r)

	var leg_l := capsule(0.12 * u, 0.46 * u, dark_mat,
			Vector3(-0.16 * u, 0.30 * u, 0))
	leg_l.name = "LegL"
	root.add_child(leg_l)

	var leg_r := capsule(0.12 * u, 0.46 * u, dark_mat,
			Vector3(0.16 * u, 0.30 * u, 0))
	leg_r.name = "LegR"
	root.add_child(leg_r)

	# Point d'ancrage de l'arme : la main droite. Le modèle d'arme y est
	# greffé, donc changer d'arme ne touche jamais au corps.
	var hand := Node3D.new()
	hand.name = "WeaponMount"
	hand.position = Vector3(0.44 * u, 0.98 * u, -0.28 * u)
	root.add_child(hand)

	return root

# --- ARMES ---------------------------------------------------------------

## Modèle d'arme procédural. Quatre silhouettes RÉELLEMENT distinctes :
## reconnaître son arme d'un coup d'œil fait partie du gameplay.
static func build_weapon(silhouette: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponModel"
	# LE CORPS DE L'ARME PORTE SA COULEUR, il n'est plus gris.
	#
	# Avant, les quatre armes partageaient la même carcasse anthracite et ne
	# se distinguaient que par un liseré de quelques centimètres : à treize
	# mètres de haut, sur un téléphone, ce liseré fait deux pixels. On ne
	# savait donc pas quelle arme on tenait sans lire le bandeau. La teinte
	# de l'arme couvre maintenant sa masse principale, et le noir ne sert
	# plus qu'à détacher la crosse et la poignée du décor.
	var body := mat(color.darkened(0.42), 0.0, 0.5)
	var tint := mat(color, 1.8)
	var noir := mat(Color("2b2f3a"))
	var portee := -0.72

	match silhouette:
		"shotgun":
			# COURT ET TRAPU, à double canon et barillet : la brutalité doit
			# se voir. C'est la seule arme plus large que longue.
			root.add_child(box(Vector3(0.19, 0.18, 0.60), body,
					Vector3(0, 0, -0.18)))
			root.add_child(cylinder(0.058, 0.50, body,
					Vector3(-0.07, 0.03, -0.50), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.058, 0.50, body,
					Vector3(0.07, 0.03, -0.50), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.10, 0.16, tint,
					Vector3(0, 0.0, -0.12), Vector3(0, 0, PI / 2)))
			root.add_child(box(Vector3(0.12, 0.24, 0.14), noir,
					Vector3(0, -0.14, 0.04)))
			portee = -0.76
		"rifle":
			# LONG ET FIN, avec une lunette : la portée doit se voir.
			root.add_child(box(Vector3(0.12, 0.14, 0.60), body,
					Vector3(0, 0, -0.18)))
			root.add_child(cylinder(0.038, 0.78, body,
					Vector3(0, 0.02, -0.66), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.06, 0.06, 0.40), tint,
					Vector3(0, 0.12, -0.34)))
			root.add_child(cylinder(0.035, 0.20, noir,
					Vector3(0, 0.19, -0.20), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.10, 0.20, 0.11), noir,
					Vector3(0, -0.12, 0.03)))
			portee = -1.06
		"energie":
			# FOURCHE À DEUX BRANCHES, avec un noyau qui flotte entre elles.
			# AUCUNE AUTRE ARME N'A DE CREUX DANS SA SILHOUETTE : c'est ce
			# qui la rend reconnaissable du premier coup d'œil, même en
			# vision périphérique. Elle partageait auparavant la silhouette
			# exacte du fusil de base — deux armes indiscernables.
			root.add_child(box(Vector3(0.15, 0.17, 0.44), body,
					Vector3(0, 0, -0.14)))
			root.add_child(box(Vector3(0.06, 0.07, 0.46), body,
					Vector3(-0.11, 0.09, -0.52)))
			root.add_child(box(Vector3(0.06, 0.07, 0.46), body,
					Vector3(0.11, 0.09, -0.52)))
			root.add_child(sphere(0.10, tint, Vector3(0, 0.09, -0.56)))
			root.add_child(cylinder(0.13, 0.05, tint,
					Vector3(0, 0.02, -0.30), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.10, 0.22, 0.11), noir,
					Vector3(0, -0.14, 0.02)))
			portee = -0.82
		"launcher":
			# GROS TUBE ET BARILLET : lourd, lent, dévastateur. C'est la
			# silhouette la plus massive du lot, et de loin.
			root.add_child(cylinder(0.16, 0.74, body,
					Vector3(0, 0.03, -0.32), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.19, 0.12, tint,
					Vector3(0, 0.03, -0.68), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.15, 0.20, body,
					Vector3(0, -0.04, -0.06), Vector3(0, 0, PI / 2)))
			root.add_child(sphere(0.09, tint, Vector3(0, 0.17, -0.12)))
			root.add_child(box(Vector3(0.12, 0.24, 0.15), noir,
					Vector3(0, -0.17, 0.02)))
			portee = -0.84
		_:  # pistolet
			root.add_child(box(Vector3(0.12, 0.16, 0.38), body,
					Vector3(0, 0, -0.11)))
			root.add_child(cylinder(0.038, 0.30, tint,
					Vector3(0, 0.02, -0.36), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.10, 0.19, 0.10), noir,
					Vector3(0, -0.12, 0.03)))
			portee = -0.56

	# Le canon : les projectiles naissent d'ici, pas du centre du joueur.
	# Sa position SUIT la longueur de chaque silhouette — un tir qui part
	# du milieu d'un canon long traverse sa propre arme.
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.02, portee)
	root.add_child(muzzle)
	return root
