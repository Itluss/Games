extends Node3D
class_name Arena
## ARÈNE — « Secteur 9 », un carrefour de cité au crépuscule.
##
## Ce fichier MONTE l'arène ; il ne la dessine pas. Le dessin — quelle
## pièce, où, tournée comment — vit dans `PlanArene`, qui est une donnée
## relisible. L'habillage de chaque pièce vit dans `PropKit`, qui pose le
## modèle Meshy s'il existe et un volume de secours sinon.
##
## Cette séparation en trois a une conséquence directe : le jeu tourne, et
## reste vérifiable, AVANT que le moindre modèle 3D ne soit livré. Chaque
## fichier qui arrive embellit l'arène sans qu'une ligne de code change.
##
## PARTI PRIS DE CONCEPTION — l'arène est COMPACTE. Un grand terrain vide
## produit exactement le défaut à éviter : marcher longtemps sans rien
## rencontrer. Le rayon est court, et les masses sont disposées pour qu'on
## croise quelqu'un en quelques secondes tout en ayant toujours de quoi
## casser une ligne de vue.
##
## LES OBSTACLES SONT DU GAMEPLAY, pas du décor : ils bloquent les charges,
## coupent les tirs du Shooter et servent d'abri contre les explosions.

const PLAYER_SPAWN_RADIUS := PlanArene.RAYON_APPARITION

var mob_spawn_points: Array[Vector3] = []
var player_spawn_points: Array[Vector3] = []

var _zone_ring: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _ground_mat: StandardMaterial3D
## Compte des pièces réellement habillées d'un modèle, pour le journal de
## démarrage et pour le test : « c'est joli » n'est pas une mesure, « 26
## pièces sur 26 » en est une.
var _pieces_habillees: int = 0
var _pieces_totales: int = 0

## Journal de mise à l'échelle. Le volume DÉCLARÉ par le plan et le volume
## RÉELLEMENT occupé par le modèle ne coïncident pas : le modèle est ramené
## à l'intérieur du volume, donc il peut être plus petit. Or c'est le
## volume réel qui porte la collision — et donc le gameplay. Sans cette
## trace, l'écart entre ce qu'on a dessiné et ce qu'on joue reste invisible.
const JOURNAL_TAILLES := false

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_perimeter()
	_build_pieces()
	_build_zone_ring()
	_compute_spawns()
	print("Arène : %d/%d pièces habillées d'un modèle 3D."
			% [_pieces_habillees, _pieces_totales])

# --- AMBIANCE ------------------------------------------------------------

## CRÉPUSCULE, ET NON PLEINE NUIT — c'est le choix qui porte tout le reste.
##
## Une cité néon, on l'imagine de nuit sur un asphalte noir. Ce serait un
## contresens ici : Kael porte une veste bleu roi, et sur un sol bleu-nuit
## il disparaît. Dans un jeu vu de dessus, distinguer son personnage d'un
## coup d'œil passe avant la beauté de l'image.
##
## Le ciel est donc un dégradé indigo → corail, le sol un béton pâle et
## froid qui détache toutes les silhouettes, et le néon vient des enseignes
## et des liserés au sol. Le contraste chaud du ciel contre le froid du sol
## fait à lui seul la moitié de l'ambiance.
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Cfg.COL_CIEL_HAUT
	sky_mat.sky_horizon_color = Cfg.COL_CIEL_HORIZON
	sky_mat.ground_bottom_color = Cfg.COL_METAL_SOMBRE
	sky_mat.ground_horizon_color = Cfg.COL_CIEL_HORIZON
	# Courbe serrée : la bande chaude reste basse sur l'horizon, comme un
	# soleil qui vient de passer derrière les tours. Étalée, elle
	# repeindrait tout le ciel en orange et écraserait l'indigo.
	sky_mat.sky_curve = 0.11
	sky_mat.ground_curve = 0.2
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# Ambiante de COULEUR plutôt que du ciel : cela permet de la teinter.
	# Un violet soutenu fait virer les ombres au violet au lieu du gris —
	# c'est la signature chromatique du dessin animé, où l'ombre est une
	# AUTRE couleur, pas la même en plus sombre.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Cfg.COL_AMBIANTE_VILLE
	# Le soleil est rasant, donc c'est l'ambiante qui tient les faces non
	# éclairées au-dessus du noir. Mais MESURÉ EN IMAGE : à 0,38, cumulée à
	# un soleil à 1,35, elle saturait le béton et l'arène entière virait au
	# rose lavé. On redescend, et c'est le soleil qui sculpte.
	env.ambient_light_energy = 0.26

	# LE HALO EST LE SUJET, ici. C'est lui qui transforme un liseré coloré
	# en néon. Le seuil reste au-dessus du béton éclairé (qui plafonne bien
	# en dessous de 1,0 après exposition) pour que SEUL l'émissif rayonne :
	# un seuil trop bas ferait baver toute l'image et donnerait du flou, pas
	# du néon.
	env.glow_enabled = true
	env.glow_intensity = 1.15
	env.glow_bloom = 0.12
	# Le seuil ne vaut que RELATIVEMENT à ce que le décor atteint. Le béton
	# assombri plafonne désormais bien plus bas, donc on peut descendre le
	# seuil sans faire baver l'image : seuls les néons le franchissent.
	env.glow_hdr_threshold = 0.95
	env.glow_strength = 1.15

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.52

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.0

	# Brume plus dense que sur l'arène de sable, et TEINTÉE du corail de
	# l'horizon : c'est elle qui donne la profondeur de rue et fait
	# ressortir les masses proches sur les lointaines. Elle reste assez
	# légère pour ne jamais voiler le combat, qui se joue près de la caméra.
	env.fog_enabled = true
	env.fog_light_color = Cfg.COL_BRUME_VILLE
	# 0,011 était BEAUCOUP trop : sur une arène de 60 m de large, la brume
	# atteignait déjà le sol au premier plan et repeignait tout. Mesuré en
	# image, l'arène entière était monochrome.
	env.fog_density = 0.005
	env.fog_sky_affect = 0.15

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# UNE SEULE lumière directionnelle avec ombres. Sur mobile, chaque
	# lumière dynamique supplémentaire se paie comptant.
	#
	# Elle est RASANTE (-24° au lieu de -52°) : un soleil couchant allonge
	# les ombres, et des ombres longues sur un sol clair, c'est du dessin
	# gratuit. C'est aussi ce qui donne aux immeubles leur présence.
	var sun := DirectionalLight3D.new()
	# -34° et non -24° : plus rasant encore, le soleil frôlait tant les
	# faces verticales qu'elles se striaient de leur propre ombre. On garde
	# des ombres longues, sans les rayures.
	sun.rotation_degrees = Vector3(-34, -38, 0)
	sun.light_color = Cfg.COL_SOLEIL_VILLE
	sun.light_energy = 1.05
	sun.shadow_enabled = Cfg.shadows_enabled()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 62.0
	# Un soleil rasant frôle les surfaces : le biais doit être plus généreux,
	# sinon chaque face presque parallèle aux rayons se couvre de rayures
	# d'ombre sur elle-même.
	# MESURÉ EN IMAGE : à 2,2 les faces presque parallèles aux rayons se
	# striaient encore de leur propre ombre. Un soleil rasant frôle tout, il
	# faut donc un biais franchement plus généreux que la valeur par défaut.
	# Le coût est un léger décollement des ombres au contact, invisible ici
	# parce que les pièces sont massives et posées à plat.
	sun.shadow_bias = 0.09
	sun.shadow_normal_bias = 3.2
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

	_ground_mat = VisualKit.mat(Cfg.COL_BETON, 0.0, 0.88)
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

	_build_dallage()
	_build_marquages()

## DALLAGE — casse l'uniformité du sol.
##
## Un sol d'une seule teinte lit comme du carton, quelle que soit la
## qualité de l'éclairage : rien n'y accroche l'œil et l'échelle disparaît.
## Quelques dalles de tons voisins suffisent à donner une matière, et elles
## ne coûtent rien puisqu'elles ne projettent pas d'ombre et ne reçoivent
## aucune logique.
##
## Le tirage est à graine FIXE : le sol doit être le même à chaque partie,
## sinon deux joueurs ne verraient pas la même carte, et une capture
## d'écran ne serait jamais reproductible.
func _build_dallage() -> void:
	# La place centrale, plus sombre : elle marque le cœur de l'arène avant
	# même qu'on lise l'anneau magenta qui l'entoure.
	var place := MeshInstance3D.new()
	var d := CylinderMesh.new()
	d.top_radius = 6.4
	d.bottom_radius = 6.4
	d.height = 0.06
	d.radial_segments = 40
	place.mesh = d
	place.material_override = VisualKit.mat(Cfg.COL_BETON.darkened(0.22), 0.0, 0.9)
	place.position = Vector3(0, 0.015, 0)
	place.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(place)

	if Cfg.quality == Cfg.Quality.LOW:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260817
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, Cfg.ARENA_RADIUS - 4.0)
		var dalle := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(3.5, 8.0), 0.04,
				rng.randf_range(3.5, 8.0))
		dalle.mesh = b
		var ton := Cfg.COL_BETON.darkened(rng.randf_range(0.04, 0.16))
		if rng.randf() < 0.3:
			ton = Cfg.COL_BETON.lightened(rng.randf_range(0.04, 0.10))
		dalle.material_override = VisualKit.mat(ton, 0.0, 0.9)
		dalle.position = Vector3(cos(a) * r, 0.012, sin(a) * r)
		dalle.rotation.y = rng.randf() * TAU
		dalle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dalle)


## MARQUAGES AU SOL — le néon là où la caméra le voit le mieux.
##
## La caméra est en plongée : elle passe l'essentiel de son temps à
## regarder le SOL. Y mettre la lumière colorée rapporte donc bien plus que
## de la mettre en haut des façades, qu'on ne voit jamais.
##
## Les anneaux concentriques ne sont pas décoratifs : ils disent au joueur
## à quelle distance du centre il se trouve, ce qui est décisif quand la
## zone se referme. Ils étaient déjà là en pierre sombre ; ils rendent
## désormais le même service en étant beaux.
func _build_marquages() -> void:
	var seuil_rues := Cfg.quality != Cfg.Quality.LOW

	# Anneaux de distance.
	for i in 3:
		var r := 11.0 + i * 8.5
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r - 0.16
		torus.outer_radius = r
		torus.rings = 44
		torus.ring_segments = 6
		ring.mesh = torus
		# Cyan à faible énergie : présent, jamais concurrent des
		# projectiles, qui doivent rester ce qu'il y a de plus lumineux.
		#
		# Le matériau est tenu dans une variable AVANT d'être posé :
		# `material_override` est typé `Material`, qui ne connaît pas
		# `albedo_color`. Le relire pour le régler ne compilerait pas.
		var m_ring := VisualKit.glow_mat(Cfg.COL_NEON_CYAN, 1.25)
		m_ring.albedo_color.a = 0.5
		ring.material_override = m_ring
		ring.position = Vector3(0, 0.03, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	# Cercle de la place centrale : il dit « ici, c'est le centre ».
	var place := MeshInstance3D.new()
	var t_place := TorusMesh.new()
	t_place.inner_radius = 6.3
	t_place.outer_radius = 6.6
	t_place.rings = 40
	t_place.ring_segments = 6
	place.mesh = t_place
	var m_place := VisualKit.glow_mat(Cfg.COL_NEON_MAGENTA, 1.8)
	m_place.albedo_color.a = 0.62
	place.material_override = m_place
	place.position = Vector3(0, 0.035, 0)
	place.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(place)

	if not seuil_rues:
		return

	# LES RUES. Quatre saignées lumineuses sur les axes, exactement là où
	# les immeubles laissent passer. Elles ne servent pas qu'à décorer :
	# elles indiquent au joueur où l'on peut courir sans être arrêté.
	for i in 4:
		var a := TAU * float(i) / 4.0
		var bande := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.28, 0.02, 23.0)
		bande.mesh = b
		var m_bande := VisualKit.glow_mat(Cfg.COL_NEON_CYAN, 1.1)
		m_bande.albedo_color.a = 0.42
		bande.material_override = m_bande
		var d := 7.0 + 23.0 * 0.5
		bande.position = Vector3(cos(a) * d, 0.03, sin(a) * d)
		bande.rotation.y = -a
		bande.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bande)

# --- MUR D'ENCEINTE ------------------------------------------------------

## L'enceinte n'est plus une falaise de roche mais un mur de blocs de béton
## et de métal sombre. Elle garde exactement la même fonction et la même
## collision : c'est l'habillage qui change, pas la limite du terrain.
func _build_perimeter() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var mat := VisualKit.mat(Cfg.COL_METAL, 0.0, 0.7)
	var mat_clair := VisualKit.mat(Cfg.COL_BETON_SOMBRE, 0.0, 0.85)

	var segments := 30
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var pos := Vector3(cos(a) * Cfg.ARENA_RADIUS, 0.0,
				sin(a) * Cfg.ARENA_RADIUS)
		var h := 3.2 + (0.9 if i % 3 == 0 else 0.0)
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, h, 2.4)
		block.mesh = box
		block.material_override = mat if i % 2 == 0 else mat_clair
		block.position = pos + Vector3(0, h * 0.5, 0)
		# L'axe long du bloc (X) doit suivre la TANGENTE du cercle, pas le
		# rayon. Avec `-a` seul, les blocs pointaient vers le centre comme
		# des rayons de roue au lieu de former un mur.
		block.rotation.y = -a - PI / 2.0
		body.add_child(block)

		var shape := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(6.0, 6.0, 2.4)
		shape.shape = cbox
		shape.position = pos + Vector3(0, 3.0, 0)
		shape.rotation.y = -a - PI / 2.0
		body.add_child(shape)

	# UN SEUL anneau lumineux au sommet du mur, plutôt qu'un liseré par
	# bloc : trente petites mailles coûtent trente dessins pour un résultat
	# que celle-ci donne en un. La ceinture de néon referme la ville.
	var couronne := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = Cfg.ARENA_RADIUS - 0.15
	t.outer_radius = Cfg.ARENA_RADIUS + 0.15
	t.rings = 64
	t.ring_segments = 6
	couronne.mesh = t
	var m_couronne := VisualKit.glow_mat(Cfg.COL_NEON_MAGENTA, 2.4)
	m_couronne.albedo_color.a = 0.75
	couronne.material_override = m_couronne
	couronne.position = Vector3(0, 3.3, 0)
	couronne.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(couronne)

# --- PIÈCES DU PLAN ------------------------------------------------------

## Monte tout ce que `PlanArene` déclare.
##
## LA COLLISION NE VIENT JAMAIS DU MODÈLE 3D. Elle est construite à partir
## du volume DÉCLARÉ dans le plan, réduit à la taille effective du modèle
## une fois celui-ci ramené à l'échelle. Autrement dit : une regénération
## Meshy peut changer l'allure d'un abri, jamais la façon dont il joue.
## Sans cette règle, l'équilibrage du niveau dépendrait d'un service
## externe et non déterministe.
func _build_pieces() -> void:
	var solides := StaticBody3D.new()
	solides.name = "Obstacles"
	solides.collision_layer = Cfg.LAYER_WORLD
	solides.collision_mask = 0
	add_child(solides)

	for piece in PlanArene.STRUCTURES:
		_poser(piece, solides, Cfg.COL_METAL, true)
	for piece in PlanArene.ABRIS:
		_poser(piece, solides, Cfg.COL_BETON_SOMBRE, true)

	# La garniture est allégée en qualité basse : c'est le premier poste à
	# sacrifier, puisqu'elle ne porte aucun gameplay.
	var pas := 2 if Cfg.quality == Cfg.Quality.LOW else 1
	var i := 0
	for piece in PlanArene.GARNITURE:
		if i % pas == 0:
			_poser(piece, null, Cfg.COL_METAL, false)
		i += 1

func _poser(piece: Dictionary, corps: StaticBody3D, teinte: Color,
		solide: bool) -> void:
	var modele: StringName = piece["modele"]
	var plan_pos: Vector2 = piece["pos"]
	var rot: float = piece["rot"]
	var taille: Vector3 = piece["taille"]
	var pos := Vector3(plan_pos.x, 0.0, plan_pos.y)
	var grappe: Vector2i = piece.get("grappe", Vector2i.ONE)
	var nx: int = maxi(1, grappe.x)
	var nz: int = maxi(1, grappe.y)
	# EN QUALITÉ BASSE, ON DESSINE MOINS D'EXEMPLAIRES — mais la collision,
	# elle, couvre toujours le volume déclaré (voir plus bas). Un téléphone
	# voit donc un immeuble un peu moins fourni, jamais un immeuble qui
	# n'arrête plus les balles. Baisser la qualité ne doit jamais changer
	# le jeu, seulement son habillage.
	if Cfg.quality == Cfg.Quality.LOW and nx * nz > 1:
		nx = maxi(1, nx - 1)
		nz = maxi(1, nz - 1)

	# CELLULE de la grappe : le volume déclaré divisé par le nombre
	# d'exemplaires. Chacun est mis à l'échelle pour SA cellule, donc la
	# grappe entière remplit le volume que le plan lui prête.
	var cellule := Vector3(taille.x / float(nx), taille.y, taille.z / float(nz))
	var reelle := taille
	var enveloppe := Vector3.ZERO

	for ix in nx:
		for iz in nz:
			# Silhouette : on fait varier la hauteur d'un exemplaire à
			# l'autre. Toutes égales, la grappe ressemblerait à un peigne ;
			# inégales, elle ressemble à une rue.
			var variation := 1.0
			if nx * nz > 1:
				variation = 0.72 + 0.28 * float((ix * 7 + iz * 3) % 5) / 4.0
			var voulu := Vector3(cellule.x, cellule.y * variation, cellule.z)
			var rendu := PropKit.instancier(modele, voulu, teinte)
			var noeud: Node3D = rendu["noeud"]
			var r: Vector3 = rendu["taille"]
			# Position de la cellule dans le repère de la pièce, puis
			# rotation d'ensemble : la grappe tourne d'un bloc.
			var dx := (float(ix) + 0.5) / float(nx) - 0.5
			var dz := (float(iz) + 0.5) / float(nz) - 0.5
			var local := Vector2(dx * taille.x, dz * taille.z).rotated(-rot)
			noeud.position = pos + Vector3(local.x, 0.0, local.y)
			noeud.rotation.y = rot
			add_child(noeud)

			_pieces_totales += 1
			if rendu.get("reel", false):
				_pieces_habillees += 1
			enveloppe = Vector3(maxf(enveloppe.x, r.x), maxf(enveloppe.y, r.y),
					maxf(enveloppe.z, r.z))
			if not solide:
				# La garniture ne projette pas d'ombre : elle est nombreuse,
				# petite, et son ombre n'apprend rien au joueur.
				_sans_ombre(noeud)

	# LA COLLISION D'UNE GRAPPE COUVRE TOUT LE VOLUME DÉCLARÉ, pas un seul
	# exemplaire : les modèles pavent l'espace, l'ensemble est bien plein.
	# Pour une pièce SEULE, en revanche, la collision suit la taille réelle
	# du modèle — promettre un encombrement que le modèle n'a pas était
	# précisément le défaut à corriger.
	if nx * nz == 1:
		reelle = enveloppe
	else:
		reelle = Vector3(taille.x, enveloppe.y, taille.z)

	if JOURNAL_TAILLES:
		print("  %-18s %dx%d  déclaré %4.1f x %4.1f x %4.1f  →  jouable %4.1f x %4.1f x %4.1f"
				% [modele, nx, nz, taille.x, taille.y, taille.z,
				reelle.x, reelle.y, reelle.z])

	if not solide:
		return

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = reelle
	shape.shape = box
	shape.position = pos + Vector3(0, reelle.y * 0.5, 0)
	shape.rotation.y = rot
	corps.add_child(shape)

	_flaque_lumineuse(pos, reelle, rot)

## FLAQUE DE LUMIÈRE au pied de chaque masse.
##
## POURQUOI AU SOL ET PAS EN HAUT : un liseré posé sur le sommet d'une
## pièce suppose qu'on connaît sa silhouette. Or elle vient d'un modèle
## génératif, dont la forme exacte n'est pas garantie — le liseré
## flotterait au-dessus de l'un, s'enfoncerait dans l'autre. Au sol, le
## contact est certain quelle que soit la forme, et c'est justement là que
## la caméra en plongée regarde.
func _flaque_lumineuse(pos: Vector3, taille: Vector3, rot: float) -> void:
	var flaque := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(taille.x + 0.5, 0.02, taille.z + 0.5)
	flaque.mesh = b
	# Magenta pour les grosses masses, cyan pour les abris : la couleur
	# devient une information — « ça, c'est un immeuble, je ne le
	# contournerai pas en deux pas ».
	var couleur := Cfg.COL_NEON_MAGENTA if taille.y > 3.0 else Cfg.COL_NEON_CYAN
	var m := VisualKit.glow_mat(couleur, 1.5)
	m.albedo_color.a = 0.30
	flaque.material_override = m
	flaque.position = pos + Vector3(0, 0.04, 0)
	flaque.rotation.y = rot
	flaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flaque)

static func _sans_ombre(n: Node) -> void:
	var gi := n as GeometryInstance3D
	if gi != null:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for enfant in n.get_children():
		_sans_ombre(enfant)

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
	player_spawn_points = PlanArene.apparitions_joueurs()

	# Les points de mob sont CALCULÉS, plus écrits en dur.
	#
	# Écrits en dur, ils étaient un pari sur le plan : déplacer un immeuble
	# suffisait à enfermer un foyer d'apparition à l'intérieur, et des mobs
	# seraient nés dans un mur. On balaie donc deux couronnes et on ne garde
	# que les positions réellement libres, en tenant compte du rayon d'un
	# mob. Le plan redevient modifiable sans risque.
	mob_spawn_points.clear()
	for couronne in [{"r": 14.5, "n": 10}, {"r": 7.5, "n": 6}]:
		var rayon: float = couronne["r"]
		var nombre: int = couronne["n"]
		for i in nombre:
			var a := TAU * float(i) / float(nombre) + (0.31 if rayon < 10.0 else 0.0)
			var p := Vector2(cos(a) * rayon, sin(a) * rayon)
			if PlanArene.est_libre(p, 0.9):
				mob_spawn_points.append(Vector3(p.x, 0.2, p.y))

	# Garde-fou explicite. Un plan mal réglé pourrait tout rejeter, et
	# l'arène tournerait alors sans jamais faire apparaître un seul mob —
	# une partie vide, sans le moindre message d'erreur.
	if mob_spawn_points.is_empty():
		push_error("Aucun point d'apparition de mob libre : le plan de "
				+ "l'arène est trop encombré.")
		mob_spawn_points.append(Vector3(0, 0.2, 12.0))

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
