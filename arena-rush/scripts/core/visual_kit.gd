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
## ─── L'ÉNERGIE PASSE PAR L'ALBÉDO, PAS PAR `emission` ────────────────
##
## C'EST LE DÉFAUT QUI EXPLIQUE « PAS SPECTACULAIRE », et il ne se voyait
## nulle part dans le code : tout paraissait réglé.
##
## En `SHADING_MODE_UNSHADED`, Godot écrit l'albédo tel quel et SAUTE la
## passe d'éclairage — or `emission` est ajoutée dans cette passe. Un
## matériau non éclairé ignore donc complètement son émission.
##
## Mesuré, pas supposé (`outils_dev/sonde_emission.gd`, trois carrés sur
## fond noir) :
##
##     non éclairé + émission 3,0     →  r=0,027  v=0,000  b=0,000
##     par pixel   + émission 3,0     →  r=1,000  v=1,000  b=0,600
##     non éclairé + albédo 3,0       →  r=1,000  v=1,000  b=0,600
##
## Conséquence : TOUS les matériaux d'effet du jeu étant non éclairés,
## aucun n'a jamais dépassé 1,0 de luminance — donc aucun n'a jamais
## franchi `glow_hdr_threshold`, donc aucun tir n'a jamais fleuri. Monter
## `emission_energy_multiplier` ne faisait littéralement rien.
##
## La troisième ligne donne la sortie : un albédo supérieur à 1 traverse
## le mode non éclairé sans être écrêté. On y verse donc l'énergie.
##
## On garde `emission` renseignée : elle ne coûte rien et redevient juste
## si un jour ces matériaux repassent en éclairage par pixel.
static func noyau_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# À PEINE ÉCLAIRCI. Un premier essai à +35 % de clarté rendait toutes
	# les munitions blanches : la teinte de l'arme, qui est le seul moyen
	# de savoir qui tire quoi, disparaissait au profit d'un trait pâle.
	#
	# LE FACTEUR 3,0 EST CE QUI FAIT BRÛLER LE NOYAU. Au-delà de 1, le
	# pixel dépasse le seuil du halo et déborde ; en dessous, la balle
	# reste une pastille mate. C'est la différence entre une munition
	# qu'on voit et une munition qu'on devine.
	# PAS D'ÉCLAIRCISSEMENT : la sur-exposition suffit à faire brûler le
	# noyau, et un éclaircissement en plus le poussait vers le citron —
	# l'or de Milo perdait sa chaleur, qui est la moitié de sa signature.
	m.albedo_color = sur_expose(color, ENERGIE_NOYAU, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = ENERGIE_NOYAU
	return m

## Facteur appliqué à l'albédo du noyau des projectiles.
const ENERGIE_NOYAU := 1.9

## Plafond du canal le plus clair après sur-exposition.
##
## POURQUOI UN PLAFOND PLUTÔT QU'UN SIMPLE PRODUIT. Premier essai : on
## multipliait les trois canaux par l'énergie, jusqu'à 5,2 pour certaines
## gerbes. L'or de Milo, (0,95 ; 0,70 ; 0,17), devenait (4,9 ; 3,6 ; 0,9) —
## les trois canaux écrêtent, et il ne reste que du BLANC. Vérifié en
## image : la balle de Milo n'était plus qu'une goutte pâle et son éclair
## qu'une rayure blanche. Or la planche est explicite : « aucune
## identification par la couleur seule », mais la couleur reste la moitié
## du message.
##
## À 2,2, le canal dominant dépasse franchement le seuil du halo — donc ça
## déborde — tandis que les autres gardent leur écart relatif : l'or reste
## or, le rose reste rose.
const PIC_SUR_EXPOSE := 2.2

## Sur-expose une couleur SANS lui faire perdre sa teinte : on monte le
## canal dominant jusqu'au plafond et on emmène les autres dans le même
## rapport.
static func sur_expose(color: Color, energie: float,
		alpha: float) -> Color:
	var pic: float = maxf(color.r, maxf(color.g, color.b))
	var f: float = energie
	if pic * f > PIC_SUR_EXPOSE:
		f = PIC_SUR_EXPOSE / maxf(pic, 0.001)
	return Color(color.r * f, color.g * f, color.b * f, alpha)

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
	# `energy` PART DANS L'ALBÉDO — voir la démonstration au-dessus de
	# `noyau_mat`. En mode non éclairé, `emission` n'est jamais lue ; ce
	# paramètre, présent depuis toujours, n'avait donc aucun effet, et
	# c'est pour cela que les gerbes, les anneaux et les traînées
	# ressortaient plats quelle que soit la valeur qu'on y mettait.
	m.albedo_color = sur_expose(color, energy, opacite)
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


# --- OMBRE DE CONTACT ----------------------------------------------------

## Maillage et matériau d'ombre de contact — UNE paire, partagée par les
## héros et par les cent soixante-dix taches des décors.
static var _maille_ombre: ArrayMesh
static var _mat_ombre: StandardMaterial3D


## POURQUOI CES TACHES EXISTENT. Sur téléphone, les vraies ombres sont
## coupées (voir `Cfg.shadows_enabled`) : une carte d'ombres directionnelle
## coûte une passe de géométrie entière, le poste le plus cher de l'image.
## Mais sans elles, PLUS RIEN NE TOUCHE LE SOL : chaque caisse, chaque
## rocher, chaque personnage flotte sur le sable. C'est le premier signal
## « prototype » d'une image mobile, et tous les jeux d'arène mobiles le
## règlent de la même façon — une tache douce peinte sous chaque chose.
##
## LE DÉGRADÉ VIT DANS LES SOMMETS, PAS DANS UNE TEXTURE. La première
## version portait un dégradé radial en GradientTexture2D : correct pixel
## par pixel en mémoire — vérifié —, il sortait à l'écran comme un carré
## sombre UNIFORME dans le rendu Compatibility. Plutôt que de chercher
## lequel des étages (mip, filtrage, téléversement) le perdait, on retire
## l'étage : un disque dont les anneaux de sommets portent la couleur n'a
## rien à échantillonner, donc rien à perdre. C'est la même leçon que les
## décors — la couleur aux sommets est le chemin le plus court ET le plus
## sûr de ce moteur de rendu.
static func maille_ombre_contact() -> ArrayMesh:
	if _maille_ombre != null:
		return _maille_ombre
	const SEG := 20
	# RÉGLÉ SUR CAPTURE, trois itérations — et la troisième a été MESURÉE,
	# pas regardée. Le premier jeu (cœur à 0,58, large) creusait des
	# cratères. Le second, écrit à 0,74, SORTAIT à ×0,52 au pipetage : le
	# rendu Compatibility décode la couleur de sommet comme du sRGB, si
	# bien que la valeur affichée est la valeur écrite élevée à la
	# puissance 2,2. Les teintes ci-dessous sont donc PRÉ-COMPENSÉES :
	# écrites pour qu'à l'écran le cœur multiplie le sable par ~0,76 et
	# que le bord s'éteigne — les valeurs visées, pas les valeurs subies.
	const RAYONS: Array[float] = [0.0, 0.30, 0.44, 0.5]
	const TEINTES: Array[Color] = [
		Color(0.885, 0.868, 0.858), Color(0.935, 0.925, 0.915),
		Color(0.978, 0.975, 0.972), Color.WHITE]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in RAYONS.size() - 1:
		var r0: float = RAYONS[a]
		var r1: float = RAYONS[a + 1]
		var c0: Color = TEINTES[a]
		var c1: Color = TEINTES[a + 1]
		for i in SEG:
			var t0 := TAU * float(i) / SEG
			var t1 := TAU * float(i + 1) / SEG
			var p00 := Vector3(cos(t0) * r0, 0, sin(t0) * r0)
			var p01 := Vector3(cos(t1) * r0, 0, sin(t1) * r0)
			var p10 := Vector3(cos(t0) * r1, 0, sin(t0) * r1)
			var p11 := Vector3(cos(t1) * r1, 0, sin(t1) * r1)
			for tri in [[p00, p10, p11, c0, c1, c1], [p00, p11, p01, c0, c1, c0]]:
				for k in 3:
					st.set_color(tri[3 + k])
					st.set_normal(Vector3.UP)
					st.add_vertex(tri[k])
	_maille_ombre = st.commit()
	return _maille_ombre


## La tache est en MULTIPLICATION, pas en noir translucide : elle assombrit
## la couleur du sable qu'elle recouvre — l'ombre garde donc la chaleur du
## sol — au lieu de poser un voile gris par-dessus.
static func mat_ombre_contact() -> StandardMaterial3D:
	if _mat_ombre != null:
		return _mat_ombre
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	# La brume ne doit pas s'y déposer une seconde fois : elle est déjà
	# dans la couleur du sol que la tache multiplie.
	m.disable_fog = true
	m.render_priority = -3
	_mat_ombre = m
	return m
