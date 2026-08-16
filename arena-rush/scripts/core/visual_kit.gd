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

## Matériau additif pour projectiles, traînées et halos.
static func glow_mat(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## CONTOUR — deuxième signal fort du dessin animé.
##
## Technique de la « coque inversée » : on redessine la même maille
## légèrement dilatée, en noir, en n'affichant que ses faces ARRIÈRE. Le
## résultat est un liseré sombre qui suit exactement la silhouette.
##
## Godot expose `grow` et `cull_mode`, donc là encore aucun shader maison.
static func outline_mat(width: float = 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Pas un noir pur : un violet très sombre s'intègre mieux à une
	# palette chaude qu'un trait de feutre.
	m.albedo_color = Color(0.07, 0.05, 0.10)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	m.disable_receive_shadows = true
	return m

## Greffe un contour sur une maille. Désactivé en qualité basse : c'est un
## doublement des appels de rendu, donc le premier poste à sacrifier.
##
## RÉSERVÉ AUX FORMES RONDES. La dilatation se fait le long des normales ;
## sur une sphère ou une capsule elle produit un liseré net, mais sur un
## cube les trois normales d'un coin divergent et la coque se déchire aux
## arêtes. Les blocs du décor s'en passent donc, et comptent sur leur
## chapeau clair et l'éclairage cellulé pour se détacher.
static func add_outline(mi: MeshInstance3D, width: float = 0.05) -> void:
	if Cfg.quality == Cfg.Quality.LOW or mi.mesh == null:
		return
	var o := MeshInstance3D.new()
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
	var body := mat(Color("3a3f4a"))
	var tint := mat(color, 1.4)

	match silhouette:
		"shotgun":
			# Court, épais, double canon : la brutalité doit se voir.
			root.add_child(box(Vector3(0.13, 0.13, 0.64), body,
					Vector3(0, 0, -0.20)))
			root.add_child(cylinder(0.045, 0.42, tint,
					Vector3(-0.05, 0.02, -0.46), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.045, 0.42, tint,
					Vector3(0.05, 0.02, -0.46), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.10, 0.20, 0.12), body,
					Vector3(0, -0.11, 0.02)))
		"rifle":
			# Long, fin, nervuré d'énergie : cadence rapide.
			root.add_child(box(Vector3(0.10, 0.12, 0.52), body,
					Vector3(0, 0, -0.16)))
			root.add_child(cylinder(0.032, 0.60, body,
					Vector3(0, 0.02, -0.56), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.05, 0.05, 0.34), tint,
					Vector3(0, 0.10, -0.30)))
			root.add_child(box(Vector3(0.09, 0.18, 0.10), body,
					Vector3(0, -0.10, 0.02)))
		"launcher":
			# Gros tube trapu : lourd, lent, dévastateur.
			root.add_child(cylinder(0.13, 0.66, body,
					Vector3(0, 0.02, -0.30), Vector3(PI / 2, 0, 0)))
			root.add_child(cylinder(0.155, 0.10, tint,
					Vector3(0, 0.02, -0.60), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.10, 0.20, 0.14), body,
					Vector3(0, -0.13, 0.0)))
			root.add_child(sphere(0.07, tint, Vector3(0, 0.14, -0.10)))
		_:  # pistol
			root.add_child(box(Vector3(0.10, 0.14, 0.34), body,
					Vector3(0, 0, -0.10)))
			root.add_child(cylinder(0.032, 0.26, tint,
					Vector3(0, 0.02, -0.32), Vector3(PI / 2, 0, 0)))
			root.add_child(box(Vector3(0.08, 0.17, 0.09), body,
					Vector3(0, -0.11, 0.03)))

	# Le canon : les projectiles naissent d'ici, pas du centre du joueur.
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.02, -0.72)
	root.add_child(muzzle)
	return root
