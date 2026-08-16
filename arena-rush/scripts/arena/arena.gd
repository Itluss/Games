extends Node3D
class_name Arena
## ARÈNE — décor, éclairage, points d'apparition, zone de jeu.
##
## PARTI PRIS DE CONCEPTION : l'arène est COMPACTE. Un grand terrain vide
## produit exactement le défaut à éviter — marcher longtemps sans rien
## rencontrer. Ici, le rayon est court et les obstacles sont placés en
## couronnes, ce qui garantit qu'on croise quelqu'un en quelques secondes
## tout en offrant de quoi casser une ligne de vue.
##
## LES OBSTACLES SONT DU GAMEPLAY, pas du décor : ils bloquent les charges,
## coupent les tirs du Shooter et servent d'abri contre les explosions.
## Ils sont donc disposés à la main, jamais au hasard.

const PLAYER_SPAWN_RADIUS := 26.0

var mob_spawn_points: Array[Vector3] = []
var player_spawn_points: Array[Vector3] = []

var _zone_ring: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _ground_mat: StandardMaterial3D

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_perimeter()
	_build_obstacles()
	_build_decor()
	_build_zone_ring()
	_compute_spawns()

# --- AMBIANCE ------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Ciel chaud en bas, franc en haut : l'ambiance « chaleureuse » demandée
	# vient d'abord de là, avant tout autre effet.
	sky_mat.sky_top_color = Cfg.COL_SKY_TOP
	sky_mat.sky_horizon_color = Cfg.COL_SKY_HORIZON
	sky_mat.ground_bottom_color = Cfg.COL_SAND_DARK
	sky_mat.ground_horizon_color = Cfg.COL_SKY_HORIZON
	sky_mat.sky_curve = 0.25
	sky_mat.ground_curve = 0.2
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ambiante de COULEUR plutôt que du ciel : cela permet de la teinter en
	# bleu. Les zones d'ombre virent alors au bleu froid au lieu d'un gris
	# terne — c'est la signature chromatique du dessin animé, où l'ombre
	# est une autre couleur, pas la même en plus sombre.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5c7fb0")
	# Ambiante VOLONTAIREMENT basse. Cumulée au soleil sur un sol sable
	# déjà très clair, une ambiante forte lessivait toute la scène au blanc
	# — le contraire de l'éclairage travaillé recherché. C'est le soleil
	# directionnel qui doit sculpter les volumes, pas l'ambiante les noyer.
	env.ambient_light_energy = 0.22

	# Le halo lumineux est ce qui fait « lire » les projectiles et le loot
	# comme des objets émissifs. Le seuil est haut pour ne toucher QUE ce
	# qui est réellement émissif, jamais le décor éclairé.
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.5

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Un point blanc bas écrase tout le haut de la plage dynamique ; à 1,6
	# le sable saturait avant même d'être éclairé.
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.52

	# Étalonnage : couleurs franches et contraste marqué. Un rendu cartoon
	# assume la saturation, là où un rendu réaliste la fuit.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.16
	env.adjustment_contrast = 1.04
	env.adjustment_brightness = 1.0
	# Brume légère et lointaine : donne de la profondeur sans jamais voiler
	# le combat, qui se déroule toujours près de la caméra.
	env.fog_enabled = true
	env.fog_light_color = Cfg.COL_SKY_HORIZON
	env.fog_density = 0.006
	env.fog_sky_affect = 0.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# UNE SEULE lumière directionnelle avec ombres. Sur mobile, chaque
	# lumière dynamique supplémentaire se paie comptant.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -46, 0)
	sun.light_color = Cfg.COL_SUN
	sun.light_energy = 1.15
	sun.shadow_enabled = Cfg.shadows_enabled()
	sun.directional_shadow_mode = \
			DirectionalLight3D.SHADOW_ORTHOGONAL
	# Portée d'ombre calée sur l'arène : au-delà, on gaspillerait de la
	# résolution sur du vide.
	sun.directional_shadow_max_distance = 62.0
	sun.shadow_bias = 0.04
	add_child(sun)

# --- SOL -----------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Cfg.ARENA_RADIUS * 2.6, 1.0, Cfg.ARENA_RADIUS * 2.6)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)

	_ground_mat = VisualKit.mat(Cfg.COL_SAND, 0.0, 0.92)
	var disc := CylinderMesh.new()
	disc.top_radius = Cfg.ARENA_RADIUS * 1.3
	disc.bottom_radius = Cfg.ARENA_RADIUS * 1.3
	disc.height = 0.4
	disc.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = _ground_mat
	mi.position = Vector3(0, -0.2, 0)
	# Le sol reçoit les ombres mais n'en projette pas : économie gratuite.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)

	# Anneaux concentriques discrets : ils donnent au joueur une notion de
	# distance au centre, ce qui aide énormément quand la zone se referme.
	for i in 3:
		var r := 11.0 + i * 8.5
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r - 0.22
		torus.outer_radius = r
		torus.rings = 40
		torus.ring_segments = 6
		ring.mesh = torus
		var m := VisualKit.mat(Cfg.COL_SAND_DARK, 0.0, 1.0)
		ring.material_override = m
		ring.position = Vector3(0, 0.02, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	# Plaques d'herbe : rompent la monotonie du sable et réchauffent la
	# palette sans coûter un seul draw call de plus par image.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(5.0, Cfg.ARENA_RADIUS - 3.0)
		var patch := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = rng.randf_range(1.6, 3.6)
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.06
		cyl.radial_segments = 12
		patch.mesh = cyl
		patch.material_override = VisualKit.mat(
				Cfg.COL_GRASS.darkened(rng.randf_range(0.0, 0.2)), 0.0, 1.0)
		patch.position = Vector3(cos(a) * d, 0.03, sin(a) * d)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(patch)

# --- MUR D'ENCEINTE ------------------------------------------------------

func _build_perimeter() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var mat := VisualKit.mat(Cfg.COL_ROCK, 0.0, 0.85)
	var mat_dark := VisualKit.mat(Cfg.COL_ROCK_DARK, 0.0, 0.85)

	var segments := 30
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var pos := Vector3(cos(a) * Cfg.ARENA_RADIUS, 0.0,
				sin(a) * Cfg.ARENA_RADIUS)
		var h := 2.6 + (0.7 if i % 3 == 0 else 0.0)
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, h, 2.4)
		block.mesh = box
		block.material_override = mat if i % 2 == 0 else mat_dark
		block.position = pos + Vector3(0, h * 0.5, 0)
		# L'axe long du bloc (X) doit suivre la TANGENTE du cercle, pas le
		# rayon. Avec `-a` seul, les blocs pointaient vers le centre comme
		# des rayons de roue au lieu de former un mur — visible dès la
		# première capture d'écran.
		block.rotation.y = -a - PI / 2.0
		body.add_child(block)

		var shape := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(6.0, 6.0, 2.4)
		shape.shape = cbox
		shape.position = pos + Vector3(0, 3.0, 0)
		shape.rotation.y = -a - PI / 2.0
		body.add_child(shape)

# --- OBSTACLES -----------------------------------------------------------

## Disposition en TROIS COURONNES :
##   • un noyau central qui force le contournement et crée un point chaud ;
##   • une couronne moyenne où se déroule l'essentiel des combats ;
##   • des blocs extérieurs qui protègent les apparitions de joueurs.
## Aucun placement aléatoire : chaque bloc a une raison d'être.
func _build_obstacles() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)

	var layout: Array = []
	# Noyau : le centre doit être disputé, pas confortable.
	layout.append({"pos": Vector3(0, 0, 0), "size": Vector3(5.0, 2.2, 5.0), "rot": 0.0})
	layout.append({"pos": Vector3(-4.6, 0, -4.6), "size": Vector3(2.0, 1.4, 5.0), "rot": 0.7})
	layout.append({"pos": Vector3(4.6, 0, 4.6), "size": Vector3(2.0, 1.4, 5.0), "rot": 0.7})

	# Couronne moyenne : murs bas orientés pour couper les lignes de tir
	# longues sans jamais enfermer un joueur.
	var mid := [
		Vector3(12.5, 0, 2.0), Vector3(-12.5, 0, -2.0),
		Vector3(2.0, 0, 12.5), Vector3(-2.0, 0, -12.5),
		Vector3(9.5, 0, -9.5), Vector3(-9.5, 0, 9.5),
	]
	for i in mid.size():
		layout.append({"pos": mid[i], "size": Vector3(6.4, 1.7, 1.5),
				"rot": TAU * float(i) / float(mid.size()) + 0.4})

	# Couronne extérieure : abris près des points d'apparition.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.39
		layout.append({
			"pos": Vector3(cos(a) * 21.0, 0, sin(a) * 21.0),
			"size": Vector3(3.4, 2.0, 3.4),
			"rot": a})

	var mat := VisualKit.mat(Cfg.COL_ROCK, 0.0, 0.8)
	var cap_mat := VisualKit.mat(Cfg.COL_ROCK.lightened(0.18), 0.0, 0.8)

	for item in layout:
		var pos: Vector3 = item["pos"]
		var size: Vector3 = item["size"]
		var rot: float = item["rot"]

		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.material_override = mat
		mi.position = pos + Vector3(0, size.y * 0.5, 0)
		mi.rotation.y = rot
		body.add_child(mi)

		# Chapeau plus clair : une arête éclairée détache le volume du sol
		# et donne le « relief » demandé sans géométrie coûteuse.
		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(size.x * 1.06, 0.22, size.z * 1.06)
		cap.mesh = cbox
		cap.material_override = cap_mat
		cap.position = pos + Vector3(0, size.y + 0.05, 0)
		cap.rotation.y = rot
		body.add_child(cap)

		var shape := CollisionShape3D.new()
		var sbox := BoxShape3D.new()
		sbox.size = size
		shape.shape = sbox
		shape.position = pos + Vector3(0, size.y * 0.5, 0)
		shape.rotation.y = rot
		body.add_child(shape)

func _build_decor() -> void:
	# Totems lumineux : repères d'orientation. Dans une arène ronde, sans
	# points de repère, on perd le nord en deux secondes.
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var pos := Vector3(cos(a) * 28.0, 0, sin(a) * 28.0)
		var pole := VisualKit.cylinder(0.24, 5.0,
				VisualKit.mat(Cfg.COL_ROCK_DARK), pos + Vector3(0, 2.5, 0))
		add_child(pole)
		var orb := VisualKit.sphere(0.62,
				VisualKit.glow_mat(Cfg.COL_SHOTGUN, 2.2), pos + Vector3(0, 5.3, 0))
		add_child(orb)

# --- ZONE ----------------------------------------------------------------

func _build_zone_ring() -> void:
	_zone_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 7.0
	cyl.radial_segments = 56
	# Cylindre OUVERT et vu de l'intérieur : c'est un mur d'énergie, il ne
	# doit ni avoir de couvercle ni masquer le décor.
	cyl.cap_top = false
	cyl.cap_bottom = false
	_zone_ring.mesh = cyl
	_zone_mat = VisualKit.glow_mat(Cfg.COL_DANGER, 1.4)
	_zone_mat.albedo_color.a = 0.2
	_zone_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_zone_ring.material_override = _zone_mat
	_zone_ring.position = Vector3(0, 3.4, 0)
	_zone_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_ring.visible = false
	add_child(_zone_ring)

func update_zone(radius: float, closing: bool) -> void:
	if _zone_ring == null:
		return
	_zone_ring.visible = true
	_zone_ring.scale = Vector3(radius, 1.0, radius)
	# Le mur pulse pendant qu'il se déplace : le joueur voit que la limite
	# BOUGE, pas seulement qu'elle existe.
	_zone_mat.albedo_color.a = 0.32 if closing else 0.18
	_zone_mat.emission_energy_multiplier = 2.4 if closing else 1.2

# --- APPARITIONS ---------------------------------------------------------

func _compute_spawns() -> void:
	# Joueurs : répartis aux quatre coins, dos au mur, loin les uns des
	# autres — personne ne doit mourir dans les trois premières secondes.
	for i in Net.MAX_PLAYERS:
		var a := TAU * float(i) / float(Net.MAX_PLAYERS) + PI / 4.0
		player_spawn_points.append(
				Vector3(cos(a) * PLAYER_SPAWN_RADIUS, 0.2,
						sin(a) * PLAYER_SPAWN_RADIUS))

	# Mobs : plusieurs foyers répartis, à l'écart immédiat des joueurs.
	for i in 8:
		var a := TAU * float(i) / 8.0
		mob_spawn_points.append(Vector3(cos(a) * 16.0, 0.2, sin(a) * 16.0))
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.6
		mob_spawn_points.append(Vector3(cos(a) * 8.0, 0.2, sin(a) * 8.0))

func player_spawn(index: int) -> Vector3:
	if player_spawn_points.is_empty():
		return Vector3.ZERO
	return player_spawn_points[index % player_spawn_points.size()]

## Point d'apparition de mob choisi À BONNE DISTANCE des joueurs : voir un
## mob se matérialiser sur soi est le plus sûr moyen de rendre un jeu injuste.
func mob_spawn(players: Array) -> Vector3:
	var best := Vector3.ZERO
	var best_score := -INF
	var radius := MatchDirector.zone_radius
	for point in mob_spawn_points:
		if Vector2(point.x, point.z).length() > radius - 2.0:
			continue
		var nearest := INF
		for p in players:
			if is_instance_valid(p):
				nearest = minf(nearest, point.distance_to(p.global_position))
		# On vise ni trop près (injuste) ni trop loin (le mob n'arrive jamais).
		var score := -absf(nearest - 15.0) + randf() * 3.0
		if score > best_score:
			best_score = score
			best = point
	return best
