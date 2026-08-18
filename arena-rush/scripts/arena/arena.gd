extends Node3D
class_name Arena
## LE MONDE — une grande carte ouverte, cinq secteurs et un noyau.
##
## POURQUOI CETTE CLASSE S'APPELLE ENCORE « Arena ». Six fichiers en
## dépendent : le monde de jeu, la réapparition, le directeur de partie, le
## pondeur de mobs et deux bancs de test. Renommer aurait imposé de les
## toucher tous pour un gain nul — et le meilleur moyen de casser la boucle
## PvPvE qu'on vient de valider. L'INTERFACE est donc intacte
## (`player_spawn_points`, `mob_spawn`, `update_zone`…) ; seul le contenu a
## changé d'échelle.
##
## ─── CE QUI A CHANGÉ, ET POURQUOI ───────────────────────────────────────
##
## L'ancienne arène faisait 34 m de rayon. Le monde en fait 78 : cinq fois
## la surface. Mais agrandir ne suffit pas — un grand disque vide paraît
## PLUS petit qu'une carte dense, parce que rien n'y marque la distance
## parcourue. Trois choses fabriquent la sensation d'ouverture, et elles
## sont réparties ici :
##
##   • DES SOLS DISTINCTS par secteur. Vu de dessus, le sol occupe les
##     trois quarts de l'écran : c'est lui, et non les props, qui fait dire
##     « je suis dans le canyon ».
##   • DES REPÈRES HAUTS, visibles d'un secteur à l'autre. Sans eux, un
##     grand terrain devient désorientant plutôt qu'ouvert.
##   • UN GRADIENT DE DANGER du bord vers le centre, qui donne une
##     direction à l'exploration.
##
## ─── LE MUR DE LA PERFORMANCE, ET COMMENT ON LE PASSE ───────────────────
##
## À la densité de l'ancienne arène, cette carte demanderait près de huit
## cents maillages individuels — donc autant d'appels de dessin, donc
## injouable sur téléphone. C'est le mur sur lequel butent la plupart des
## agrandissements de carte.
##
## Deux réponses, toutes deux natives :
##
##   1. MULTIMESH PAR TUILE. Chaque famille de décor est dessinée en un
##      seul appel. Mais un MultiMesh n'est écarté qu'en entier : un semis
##      couvrant tout un secteur serait dessiné dès qu'un seul de ses
##      rochers entre dans le champ. On le DÉCOUPE donc en tuiles de 26 m,
##      chacune écartée séparément quand elle sort du champ.
##   2. `visibility_range_end` sur la garniture. Les cailloux et les
##      touffes disparaissent au loin ; les repères, jamais — c'est
##      précisément à distance qu'ils servent.

const PLAYER_SPAWN_RADIUS := PlanMonde.RAYON * 0.7

## Côté d'une tuile de semis. 26 m est un compromis mesuré : plus petit, on
## multiplie les nœuds et donc le coût fixe ; plus grand, chaque tuile
## traîne trop de props hors champ.
const TAILLE_TUILE := 26.0

var mob_spawn_points: Array[Vector3] = []
var player_spawn_points: Array[Vector3] = []

var _zone_ring: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _obstacles: StaticBody3D
## Corps distinct pour le mur du monde : la caméra l'ignore volontairement.
var _enceinte: StaticBody3D
var _semis: int = 0
var _props: int = 0

func _ready() -> void:
	_enceinte = null
	_obstacles = StaticBody3D.new()
	_obstacles.name = "Obstacles"
	_obstacles.collision_layer = Cfg.LAYER_WORLD
	_obstacles.collision_mask = 0
	add_child(_obstacles)

	_build_environment()
	_build_ground()
	_build_perimeter()
	_batir_secteurs()
	_batir_points_interet()
	_build_pieces()
	_build_zone_ring()
	_compute_spawns()
	print("Monde : rayon %.0f m · %d props en %d semis · %d apparitions."
			% [PlanMonde.RAYON, _props, _semis, player_spawn_points.size()])

# --- AMBIANCE ------------------------------------------------------------

## CRÉPUSCULE, ET NON PLEINE NUIT — le choix qui porte tout le reste.
##
## Une cité néon, on l'imagine de nuit sur un asphalte noir. Ce serait un
## contresens ici : Kael porte une veste bleu roi, et sur un sol bleu-nuit
## il disparaît. Dans un jeu vu de dessus, distinguer son personnage d'un
## coup d'œil passe avant la beauté de l'image.
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Cfg.COL_CIEL_HAUT
	sky_mat.sky_horizon_color = Cfg.COL_CIEL_HORIZON
	sky_mat.ground_bottom_color = Cfg.COL_METAL_SOMBRE
	sky_mat.ground_horizon_color = Cfg.COL_CIEL_HORIZON
	sky_mat.sky_curve = 0.11
	sky_mat.ground_curve = 0.2
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Cfg.COL_AMBIANTE_VILLE
	env.ambient_light_energy = 0.26

	# LE HALO EST COUPÉ SUR TÉLÉPHONE. Il coûte plusieurs passes en plein
	# écran, et le plein écran d'un téléphone compte trois fois plus de
	# pixels qu'on ne le croit. C'est le second poste de dépense après les
	# ombres, pour un effet que le soleil rasant rend déjà à moitié.
	env.glow_enabled = not Cfg.est_mobile()
	env.glow_intensity = 1.15
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.95
	env.glow_strength = 1.15

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.52

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.0

	# LA BRUME DEVIENT UN OUTIL DE PROFONDEUR, plus un simple effet.
	#
	# Sur 156 m de large, elle sépare les plans : le secteur où l'on se
	# trouve est net, le suivant est voilé, la limite du monde a disparu.
	# C'est ce qui fait qu'on ne voit jamais « le bout » de la carte, donc
	# qu'elle paraît continuer. Elle reste assez faible pour ne pas voiler
	# le combat, qui se joue toujours à moins de vingt mètres.
	env.fog_enabled = true
	env.fog_light_color = Cfg.COL_BRUME_VILLE
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -38, 0)
	sun.light_color = Cfg.COL_SOLEIL_VILLE
	sun.light_energy = 1.05
	sun.shadow_enabled = Cfg.shadows_enabled()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# La portée d'ombre ne suit PAS la taille du monde : elle suit celle de
	# l'écran. Étendre la carte sans toucher à ce réglage est volontaire —
	# une ombre à 150 m ne serait jamais vue et diviserait par quatre la
	# résolution de celles qu'on voit.
	# 58 m sur ordinateur, 34 m sur téléphone : la carte d'ombres couvre une
	# surface qui varie avec le carré de cette distance, et au-delà de 34 m
	# l'ombre d'un rocher n'est plus qu'une tache grise de quelques pixels.
	sun.directional_shadow_max_distance = 34.0 if Cfg.est_mobile() else 58.0
	sun.shadow_bias = 0.09
	sun.shadow_normal_bias = 3.2
	add_child(sun)

# --- SOL -----------------------------------------------------------------

func _build_ground() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 3,0 ET NON 2,4. Une boîte carrée de 2,4 rayons ne couvre que 93 m sur
	# ses axes, alors que le disque VISIBLE en fait 107 : il existait une
	# couronne où l'on voyait du sol sans qu'il y en ait sous les pieds.
	# Passer à 3,0 met la collision partout où il y a quelque chose à voir.
	box.size = Vector3(PlanMonde.RAYON * 3.0, 1.0, PlanMonde.RAYON * 3.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	_obstacles.add_child(col)

	# Disque de fond, sous tout le reste : il bouche les interstices entre
	# les quartiers de secteur, qu'aucun ajustement d'angle ne rendrait
	# parfaitement jointifs.
	var fond := MeshInstance3D.new()
	var disque := CylinderMesh.new()
	# 1,38 et non 1,16 : le disque doit passer SOUS la ceinture de mesas,
	# repoussée à 94-99 m. Sans cela, elles se dresseraient au-dessus du
	# vide et l'horizon montrerait le ciel entre leurs pieds.
	disque.top_radius = PlanMonde.RAYON * 1.38
	disque.bottom_radius = PlanMonde.RAYON * 1.38
	disque.height = 0.4
	disque.radial_segments = 56
	fond.mesh = disque
	fond.material_override = VisualKit.mat(Cfg.SOL_NOYAU.darkened(0.1), 0.0, 0.92)
	# EMPILEMENT VERTICAL, ET IL COMPTE. Un CylinderMesh est centré sur sa
	# position : à -0,24 avec 0,4 de haut, sa face SUPÉRIEURE est à -0,04.
	# Les quartiers de secteur, posés à -0,18, se retrouvaient donc DEDANS —
	# invisibles. Vérifié en image : le monde entier était d'une seule
	# teinte, et toute l'identité des secteurs avait disparu.
	#
	# L'ordre est désormais explicite : fond (-0,20) < quartiers (-0,02)
	# < noyau (0,00). Les props reposent à 0, donc jamais enterrés.
	fond.position = Vector3(0, -0.4, 0)
	fond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fond)

	# UN QUARTIER DE SOL PAR SECTEUR. C'est le levier n° 1 de l'identité :
	# on reconnaît un secteur à la couleur sous ses pieds bien avant de
	# reconnaître ses props.
	for s: Dictionary in PlanMonde.SECTEURS:
		var mi := MeshInstance3D.new()
		# 1,04 et non 1,06 : les secteurs pavent désormais exactement, un
		# recouvrement trop généreux ferait repeindre chaque voisin par le
		# suivant. Un chouïa suffit à masquer la couture.
		mi.mesh = _quartier(PlanMonde.angle_de(s["id"]),
				PlanMonde.ouverture_de(s["id"]) * 1.04,
				PlanMonde.RAYON_NOYAU * 0.8, PlanMonde.RAYON * 1.1)
		mi.material_override = VisualKit.mat(s["sol"], 0.0, 0.93)
		mi.position = Vector3(0, -0.02, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# Le noyau par-dessus : il doit rester net et refermé sur lui-même.
	var noyau := MeshInstance3D.new()
	var d2 := CylinderMesh.new()
	d2.top_radius = PlanMonde.RAYON_NOYAU
	d2.bottom_radius = PlanMonde.RAYON_NOYAU
	d2.height = 0.3
	d2.radial_segments = 44
	noyau.mesh = d2
	noyau.material_override = VisualKit.mat(Cfg.SOL_NOYAU, 0.0, 0.9)
	noyau.position = Vector3(0, -0.15, 0)
	noyau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(noyau)

	_marquer_noyau()


## Quartier d'anneau — la forme exacte d'un secteur.
##
## POURQUOI IL ONDULE. La première version traçait un éventail à bords
## parfaitement radiaux. Vu de dessus, le monde lisait « camembert » : cinq
## parts égales et rectilignes trahissent la découpe, et une carte dont on
## devine la construction cesse d'être un monde.
##
## Les bords sont donc déviés par une fonction qui ne dépend QUE de l'angle
## du bord et du rayon. Deux secteurs voisins partageant une frontière
## évaluent la même fonction sur la même valeur : ils ondulent donc
## ensemble, et restent jointifs. C'est ce qui permet d'avoir une limite
## organique sans avoir à coudre les secteurs entre eux.
func _quartier(centre: float, ouverture: float, r0: float,
		r1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 18
	var nr := 9
	var a_deb := centre - ouverture * 0.5
	var a_fin := centre + ouverture * 0.5
	for j in nr:
		var ra := lerpf(r0, r1, float(j) / float(nr))
		var rb := lerpf(r0, r1, float(j + 1) / float(nr))
		var da0 := _ondulation(a_deb, ra)
		var da1 := _ondulation(a_fin, ra)
		var db0 := _ondulation(a_deb, rb)
		var db1 := _ondulation(a_fin, rb)
		for i in na:
			var t0 := float(i) / float(na)
			var t1 := float(i + 1) / float(na)
			var p00 := _point(lerpf(a_deb + da0, a_fin + da1, t0), ra)
			var p01 := _point(lerpf(a_deb + da0, a_fin + da1, t1), ra)
			var p10 := _point(lerpf(a_deb + db0, a_fin + db1, t0), rb)
			var p11 := _point(lerpf(a_deb + db0, a_fin + db1, t1), rb)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	return st.commit()


func _point(a: float, r: float) -> Vector3:
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## Déviation d'une frontière. Deux sinusoïdes incommensurables : leur somme
## ne se répète pas à l'échelle de la carte, donc l'œil n'y lit aucun motif.
static func _ondulation(angle_bord: float, r: float) -> float:
	return 0.13 * sin(r * 0.13 + angle_bord * 3.1) \
			+ 0.07 * sin(r * 0.31 + angle_bord * 7.7)


## Marquages lumineux du noyau — repris de l'ancienne arène, restreints au
## centre. Étendus au monde entier, ils auraient annulé l'identité des
## secteurs qu'on vient de leur donner.
func _marquer_noyau() -> void:
	for i in 2:
		var r := 9.0 + i * 7.5
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r - 0.16
		torus.outer_radius = r
		torus.rings = 40
		torus.ring_segments = 6
		ring.mesh = torus
		var m := VisualKit.glow_mat(Cfg.COL_NEON_CYAN, 1.25)
		m.albedo_color.a = 0.5
		ring.material_override = m
		ring.position = Vector3(0, 0.03, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	var bord := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = PlanMonde.RAYON_NOYAU - 0.35
	t.outer_radius = PlanMonde.RAYON_NOYAU
	t.rings = 56
	t.ring_segments = 6
	bord.mesh = t
	var mb := VisualKit.glow_mat(Cfg.COL_NEON_MAGENTA, 1.9)
	mb.albedo_color.a = 0.66
	bord.material_override = mb
	bord.position = Vector3(0, 0.04, 0)
	bord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bord)

# --- LIMITE DU MONDE -----------------------------------------------------

## L'ENCEINTE N'EST PLUS UN MUR, C'EST UN RELIEF.
##
## Un mur régulier dit « arène » à chaque coup d'œil — c'est exactement la
## sensation dont on veut sortir. Une ligne de mesas irrégulières dit
## « le terrain s'arrête là », ce qui est la même information sans l'aveu.
## La brume achève le travail : on ne voit jamais la limite en entier.
## LE MUR D'ENCEINTE A SON PROPRE CORPS, ET C'EST LA CAMÉRA QUI L'EXIGE.
##
## Ce mur est une boîte de 14 m de haut et 5 m d'épaisseur, INVISIBLE : les
## mesas qu'il représente se dressent 15 m plus loin. Or la caméra se tient
## 10 m derrière le joueur sur l'axe Z du monde : collée au bord, elle a
## forcément ce mur entre elle et le personnage.
##
## Le dégagement le prenait donc pour un obstacle et rabattait la caméra —
## puis la relâchait au pas suivant, puis la rabattait. C'est le « zoom
## désagréable au bord de la carte » signalé en jeu, et il se calcule : la
## sphère de sonde, partie de la poitrine du joueur plaqué contre la face
## intérieure, chevauche le mur dès le premier instant, ce qui envoie le
## dégagement directement à son minimum.
##
## Se cacher derrière une limite du monde n'a aucun sens. Le mur reste un
## obstacle pour les corps, il cesse d'en être un pour le regard.
func _build_perimeter() -> void:
	_enceinte = StaticBody3D.new()
	_enceinte.name = "Enceinte"
	_enceinte.collision_layer = Cfg.LAYER_WORLD
	_enceinte.collision_mask = 0
	_enceinte.add_to_group(&"enceinte")
	add_child(_enceinte)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var segments := 52
	var formes: Array[Transform3D] = []
	for i in segments:
		var a := TAU * float(i) / float(segments)
		# REPOUSSÉES ET RESSERRÉES. Mesuré en image : à 2,2-3,4 de large et
		# posées au rayon exact, les mesas formaient un mur de dents pâles
		# qui occupait la moitié de l'horizon depuis n'importe quel secteur.
		# Une limite doit se DEVINER au loin, pas dominer chaque plan.
		#
		# REPOUSSÉES UNE SECONDE FOIS, ET CETTE FOIS PAS POUR LA BEAUTÉ. La
		# caméra se tient 10 m DERRIÈRE le joueur, sur l'axe Z du monde. Le
		# mur de collision arrête le joueur à 77,5 m ; la caméra, elle,
		# arrivait donc à 87,5 m — c'est-à-dire À L'INTÉRIEUR de la ceinture
		# de mesas, alors posée entre 82 et 87 m. Une sonde d'occlusion l'a
		# chiffré : au bord nord, le cadre était bouché à 100 %, la roche
		# remplissait l'écran entier. La ceinture commence maintenant à 94 m,
		# soit 6,5 m au-delà du point le plus reculé que la caméra atteint.
		var r := PlanMonde.RAYON + rng.randf_range(16.0, 21.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var base := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))
		# La hauteur varie du simple au double : une crête régulière se lit
		# comme une palissade, une crête irrégulière comme du relief.
		base = base.scaled(Vector3(rng.randf_range(1.5, 2.4),
				rng.randf_range(1.3, 2.9), rng.randf_range(1.5, 2.4)))
		formes.append(Transform3D(base, pos))

		# La COLLISION reste régulière et généreuse, elle. Le joueur ne doit
		# jamais pouvoir se glisser entre deux mesas : c'est laid à voir et
		# c'est un bogue à corriger plus tard.
		var shape := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(12.0, 14.0, 5.0)
		shape.shape = cbox
		shape.position = Vector3(cos(a) * (PlanMonde.RAYON + 2.0), 6.0,
				sin(a) * (PlanMonde.RAYON + 2.0))
		shape.rotation.y = -a - PI / 2.0
		_enceinte.add_child(shape)

	var mur := KitDecor.semer(&"mesa", formes, 0.0, false)
	add_child(mur)
	_semis += 1
	_props += formes.size()

# --- SECTEURS ------------------------------------------------------------

## SÈME LE DÉCOR DE CHAQUE SECTEUR, EN TUILES.
##
## Le bucketing par tuile est le cœur de la tenue en performance : sans
## lui, un semis couvrant un secteur entier serait dessiné dès qu'un seul
## de ses rochers entre dans le champ de la caméra.
func _batir_secteurs() -> void:
	var rng := RandomNumberGenerator.new()
	# Graine FIXE : le monde doit être le même pour tout le monde et d'une
	# session à l'autre. Une carte qu'on ne peut pas apprendre ne s'habite
	# jamais — et deux joueurs verraient des décors différents.
	rng.seed = 20260818

	# famille -> { cellule -> [Transform3D] }
	var tuiles: Dictionary = {}
	var collisions: Array[Dictionary] = []

	for s: Dictionary in PlanMonde.SECTEURS:
		var ouverture: float = PlanMonde.ouverture_de(s["id"])
		var angle: float = PlanMonde.angle_de(s["id"])
		var familles: Array = s["familles"]
		var surface: float = 0.5 * ouverture \
				* (PlanMonde.RAYON * PlanMonde.RAYON
				- PlanMonde.RAYON_NOYAU * PlanMonde.RAYON_NOYAU)
		var total := int(surface * float(s["densite_decor"]))

		for i in total:
			var a := angle + rng.randf_range(-0.5, 0.5) * ouverture
			# Racine carrée du tirage : sans elle, les points s'entassent
			# près du centre, où l'anneau est plus étroit. C'est le piège
			# classique du semis en coordonnées polaires.
			var t := rng.randf()
			var r := sqrt(lerpf(PlanMonde.RAYON_NOYAU * PlanMonde.RAYON_NOYAU,
					PlanMonde.RAYON * PlanMonde.RAYON, t))
			var p := Vector2(cos(a) * r, sin(a) * r)
			if not _emplacement_libre(p):
				continue

			var famille: StringName = familles[rng.randi() % familles.size()]
			var ech := rng.randf_range(0.75, 1.45)
			# ÉCHELLE NON UNIFORME : c'est elle, et non des maillages
			# différents, qui fait qu'aucun rocher ne ressemble à son voisin.
			var base := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))
			base = base.scaled(Vector3(ech * rng.randf_range(0.85, 1.2),
					ech * rng.randf_range(0.85, 1.25),
					ech * rng.randf_range(0.85, 1.2)))
			var tr := Transform3D(base, Vector3(p.x, 0.0, p.y))

			if not tuiles.has(famille):
				tuiles[famille] = {}
			var cle := "%d_%d" % [floori(p.x / TAILLE_TUILE),
					floori(p.y / TAILLE_TUILE)]
			var par_cellule: Dictionary = tuiles[famille]
			if not par_cellule.has(cle):
				par_cellule[cle] = ([] as Array[Transform3D])
			(par_cellule[cle] as Array[Transform3D]).append(tr)

			if famille in FAMILLES_SOLIDES:
				collisions.append({"pos": p, "rayon": ech * RAYON_SOLIDE[famille],
						"haut": ech * HAUTEUR_SOLIDE[famille]})

	for famille: StringName in tuiles:
		var par_cellule: Dictionary = tuiles[famille]
		for cle: String in par_cellule:
			var liste: Array[Transform3D] = par_cellule[cle]
			var noeud := KitDecor.semer(famille, liste,
					_portee(famille), famille in FAMILLES_SOLIDES)
			add_child(noeud)
			_semis += 1
			_props += liste.size()

	for c: Dictionary in collisions:
		_poser_collision_ronde(c["pos"], c["rayon"], c["haut"])


## Familles qui BLOQUENT. Les autres — cailloux, touffes, buissons — sont
## traversables, et c'est délibéré : un buisson qui arrête un joueur
## transforme le bosquet en labyrinthe frustrant, et chaque forme de
## collision se paie sur un téléphone.
const FAMILLES_SOLIDES := [&"mesa", &"rocher", &"arbre", &"pin", &"ruine",
		&"pilier", &"tente"]
const RAYON_SOLIDE := {
	&"mesa": 1.2, &"rocher": 0.95, &"arbre": 0.32, &"pin": 0.3,
	&"ruine": 1.5, &"pilier": 0.45, &"tente": 1.3,
}
const HAUTEUR_SOLIDE := {
	&"mesa": 4.0, &"rocher": 1.3, &"arbre": 2.0, &"pin": 1.4,
	&"ruine": 2.0, &"pilier": 3.4, &"tente": 2.0,
}
## Distance d'effacement par famille. Zéro = jamais effacé.
const PORTEE := {
	&"caillou": 46.0, &"touffe": 34.0, &"buisson": 52.0, &"tonneau": 58.0,
	&"caisse": 62.0, &"cloture": 62.0,
}

## Distance d'effacement effective, raccourcie de 40 % sur téléphone.
##
## C'EST LE RÉGLAGE QUI SUIT LA DENSITÉ. Le nombre de semis dessinés dépend
## de ce que la caméra voit : dans un secteur clairsemé une poignée, dans
## les ruines ou le bosquet plusieurs dizaines. C'est ce qui explique qu'un
## défaut de performance se manifeste « à certains endroits » et pas
## ailleurs — la carte n'a pas un coût, elle en a cinq.
##
## Les petites pièces sont celles qu'on efface : un caillou à 28 m sur un
## écran de téléphone fait trois pixels.
func _portee(famille: StringName) -> float:
	var base: float = PORTEE.get(famille, 0.0)
	if base <= 0.0:
		return 0.0
	return base * 0.6 if Cfg.est_mobile() else base


func _poser_collision_ronde(p: Vector2, rayon: float, haut: float) -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = rayon
	cyl.height = haut
	shape.shape = cyl
	shape.position = Vector3(p.x, haut * 0.5, p.y)
	_obstacles.add_child(shape)


## Un emplacement est-il libre pour du décor ?
##
## On écarte le noyau (déjà meublé par le plan de l'ancienne arène), les
## abords immédiats des points d'intérêt (qui doivent rester praticables)
## et les points d'apparition (naître dans un arbre serait un défaut
## immédiat).
func _emplacement_libre(p: Vector2) -> bool:
	if p.length() < PlanMonde.RAYON_NOYAU + 2.0:
		return false
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var c := PlanMonde.position_poi(poi)
		if p.distance_to(c) < float(poi["rayon_actif"]) * 0.52:
			return false
	for sp: Vector3 in PlanMonde.apparitions_joueurs():
		if p.distance_to(Vector2(sp.x, sp.z)) < 4.5:
			return false
	return true

# --- POINTS D'INTÉRÊT ----------------------------------------------------

## LES REPÈRES. Ce sont eux qui transforment un grand terrain en monde.
##
## Chacun est construit à la main, en primitives, parce qu'un repère doit
## être UNIQUE : semé en MultiMesh, il cesserait d'être un repère. Six
## silhouettes reconnaissables coûtent moins cher qu'un seul modèle importé,
## et ne se confondent avec rien.
##
## RÈGLE COMMUNE : haut, ajouré, et surmonté d'une lueur. La hauteur le
## rend visible par-dessus la brume ; l'ajour évite qu'il ne bouche le
## combat ; la lueur le fait exister au crépuscule, quand la silhouette
## seule se perdrait.
func _batir_points_interet() -> void:
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var p := PlanMonde.position_poi(poi)
		var socle := Vector3(p.x, 0.0, p.y)
		match poi["id"]:
			&"tour": _poi_tour(socle)
			&"pont": _poi_pont(socle)
			&"temple": _poi_temple(socle)
			&"depot": _poi_depot(socle)
			&"carcasse": _poi_carcasse(socle)
			&"place": pass   # le noyau est meublé par le plan d'origine
		if poi["id"] != &"place":
			_balise(socle, float(poi["hauteur"]))


## BALISE — une lueur au sommet de chaque repère.
##
## Sans elle, un repère se perd dès que la brume mord dessus, c'est-à-dire
## exactement à la distance où l'on en a besoin. Elle ne projette pas de
## lumière : c'est un point émissif, donc gratuit.
func _balise(base: Vector3, hauteur: float) -> void:
	var orbe := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.75
	s.height = 1.5
	s.radial_segments = 10
	s.rings = 6
	orbe.mesh = s
	orbe.material_override = VisualKit.glow_mat(Cfg.COL_NEON_CYAN, 3.2)
	orbe.position = base + Vector3(0, hauteur + 0.8, 0)
	orbe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orbe)


func _bloc(taille: Vector3, pos: Vector3, teinte: Color, rot := 0.0,
		solide := true) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = taille
	mi.mesh = b
	mi.material_override = VisualKit.mat(teinte, 0.0, 0.9)
	mi.position = pos
	mi.rotation.y = rot
	add_child(mi)
	if not solide:
		return
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = taille
	shape.shape = cb
	shape.position = pos
	shape.rotation.y = rot
	_obstacles.add_child(shape)


## TOUR DE GUET — le repère principal du monde, et le plus haut.
##
## Quatre pieds évasés, une cage, une plateforme. La silhouette ajourée est
## volontaire : massive, elle boucherait la vue depuis le camp.
func _poi_tour(base: Vector3) -> void:
	var bois := Cfg.COL_BOIS
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		# Pieds INCLINÉS vers l'extérieur : c'est ce qui donne l'assise et
		# rend la tour crédible plutôt que posée.
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.bottom_radius = 0.34
		c.top_radius = 0.24
		c.height = 13.0
		c.radial_segments = 6
		mi.mesh = c
		mi.material_override = VisualKit.mat(bois, 0.0, 0.9)
		mi.position = base + d * 2.1 + Vector3(0, 6.5, 0)
		mi.rotation = Vector3(d.z * 0.1, 0, -d.x * 0.1)
		add_child(mi)
	for niveau in 3:
		var y := 4.0 + niveau * 4.0
		_bloc(Vector3(5.6, 0.3, 5.6), base + Vector3(0, y, 0),
				bois.darkened(0.08), 0.0, niveau == 0)
	_bloc(Vector3(6.4, 0.4, 6.4), base + Vector3(0, 13.4, 0),
			Cfg.COL_TOILE, 0.0, false)
	_bloc(Vector3(5.0, 1.5, 0.3), base + Vector3(0, 14.2, 2.6), bois, 0.0, false)
	_bloc(Vector3(5.0, 1.5, 0.3), base + Vector3(0, 14.2, -2.6), bois, 0.0, false)
	# Toit conique, la touche qui la fait lire comme un poste et non une
	# grue.
	var toit := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.bottom_radius = 4.6
	cone.top_radius = 0.0
	cone.height = 2.6
	cone.radial_segments = 6
	toit.mesh = cone
	toit.material_override = VisualKit.mat(Cfg.COL_KAEL_ACCENT.darkened(0.2),
			0.0, 0.85)
	toit.position = base + Vector3(0, 16.0, 0)
	add_child(toit)


## LE PONT DE PIERRE — une arche que l'on franchit PAR-DESSOUS.
##
## Le passage obligé est le vrai sujet : il fabrique des rencontres, ce
## qu'aucun décor purement visuel ne fait.
func _poi_pont(base: Vector3) -> void:
	var pierre := Cfg.COL_ROCHE_CHAUDE
	for cote in [-1.0, 1.0]:
		_bloc(Vector3(3.0, 8.0, 5.0), base + Vector3(cote * 6.0, 4.0, 0),
				pierre)
	# Tablier en trois segments légèrement cintrés : trois boîtes suffisent
	# à faire lire une arche, là où une vraie courbe coûterait une géométrie
	# sur mesure pour un gain nul à cette distance.
	_bloc(Vector3(6.0, 1.4, 5.2), base + Vector3(-3.6, 8.3, 0), pierre, 0.0, false)
	_bloc(Vector3(6.0, 1.4, 5.2), base + Vector3(3.6, 8.3, 0), pierre, 0.0, false)
	_bloc(Vector3(4.4, 1.6, 5.2), base + Vector3(0, 8.8, 0), pierre, 0.0, false)
	_bloc(Vector3(15.0, 0.8, 0.6), base + Vector3(0, 9.9, 2.4),
			pierre.lightened(0.14), 0.0, false)
	_bloc(Vector3(15.0, 0.8, 0.6), base + Vector3(0, 9.9, -2.4),
			pierre.lightened(0.14), 0.0, false)


## LE TEMPLE ENGLOUTI — des colonnes émergeant du couvert.
##
## Le seul volume clair du bosquet, donc son unique repère. Il est
## volontairement INCOMPLET : une ruine se lit à ce qui lui manque.
func _poi_temple(base: Vector3) -> void:
	var pierre := Cfg.COL_PIERRE
	_bloc(Vector3(13.0, 0.8, 13.0), base + Vector3(0, 0.4, 0),
			pierre.darkened(0.1), 0.0, false)
	_bloc(Vector3(10.0, 0.6, 10.0), base + Vector3(0, 1.0, 0), pierre, 0.0, false)
	var debout := [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4),
			Vector2(4, 4), Vector2(0, -4.6)]
	for i in debout.size():
		var c: Vector2 = debout[i]
		var h := 6.5 if i < 3 else 3.4     # deux colonnes brisées
		_bloc(Vector3(1.0, h, 1.0), base + Vector3(c.x, 1.3 + h * 0.5, c.y),
				pierre)
	_bloc(Vector3(10.4, 0.9, 2.2), base + Vector3(0, 8.1, -4.0),
			pierre.lightened(0.1), 0.0, false)
	# Un fragment de linteau tombé au sol : c'est ce détail qui raconte que
	# le lieu s'est effondré, et non qu'il a été bâti comme ça.
	_bloc(Vector3(3.2, 0.9, 1.9), base + Vector3(2.6, 1.8, 3.4),
			pierre.lightened(0.1), 0.5)


## LE DÉPÔT — halle ouverte et grue. Le meilleur butin hors noyau.
func _poi_depot(base: Vector3) -> void:
	var beton := Cfg.COL_BETON_SOMBRE
	var metal := Cfg.COL_METAL
	_bloc(Vector3(16.0, 0.5, 12.0), base + Vector3(0, 0.25, 0), beton, 0.0, false)
	for cote in [-1.0, 1.0]:
		_bloc(Vector3(0.8, 7.0, 12.0), base + Vector3(cote * 7.6, 3.5, 0), metal)
	_bloc(Vector3(17.0, 0.7, 13.0), base + Vector3(0, 7.3, 0),
			metal.lightened(0.1), 0.0, false)
	# Un pignon ouvert d'un côté : on peut entrer, donc s'y battre.
	_bloc(Vector3(16.0, 5.0, 0.6), base + Vector3(0, 3.5, -6.0), beton)
	var mat := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = 0.5
	c.top_radius = 0.4
	c.height = 11.0
	c.radial_segments = 6
	mat.mesh = c
	mat.material_override = VisualKit.mat(Cfg.COL_KAEL_ACCENT.darkened(0.15),
			0.0, 0.7)
	mat.position = base + Vector3(9.5, 5.5, 4.0)
	add_child(mat)
	_bloc(Vector3(9.0, 0.6, 0.8), base + Vector3(5.6, 10.6, 4.0),
			Cfg.COL_KAEL_ACCENT.darkened(0.15), 0.0, false)


## LA CARCASSE — un vaisseau échoué, planté de travers.
##
## L'INCLINAISON est tout le sujet. Posé droit, c'est un bâtiment ; planté
## en biais, c'est un accident, et une silhouette qu'on ne confond avec
## rien d'autre sur la carte.
func _poi_carcasse(base: Vector3) -> void:
	var coque := Cfg.COL_METAL.lightened(0.12)
	var brulé := Cfg.COL_METAL_SOMBRE
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = 2.6
	c.top_radius = 1.5
	c.height = 15.0
	c.radial_segments = 8
	mi.mesh = c
	mi.material_override = VisualKit.mat(coque, 0.0, 0.66)
	mi.position = base + Vector3(0, 4.2, 0)
	mi.rotation = Vector3(0.42, 0.6, 0.22)
	add_child(mi)
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(9.0, 5.0, 5.0)
	shape.shape = cb
	shape.position = base + Vector3(0, 2.5, 0)
	shape.rotation.y = 0.6
	_obstacles.add_child(shape)

	# Deux ailerons brisés, plantés dans le sol autour de l'épave.
	_bloc(Vector3(5.0, 0.5, 3.0), base + Vector3(-5.4, 1.6, 3.0), brulé, 0.9)
	_bloc(Vector3(4.0, 0.5, 2.4), base + Vector3(5.0, 1.1, -3.6), brulé, -0.6)
	# Traînée d'impact : elle dit d'où l'engin est arrivé.
	for i in 4:
		_bloc(Vector3(3.4 - i * 0.5, 0.35, 2.2), 
				base + Vector3(7.0 + i * 4.0, 0.18, -5.0 - i * 2.6),
				Cfg.SOL_RUINES.darkened(0.22), -0.5 + i * 0.1, false)

# --- NOYAU ---------------------------------------------------------------

## Le noyau REPREND l'ancienne arène telle quelle : son plan, ses abris,
## ses modèles Meshy. C'est délibéré — c'est le seul secteur déjà réglé et
## déjà validé par un test, et il devient naturellement le lieu le plus
## construit du monde, donc le plus disputé.
func _build_pieces() -> void:
	for piece in PlanArene.STRUCTURES:
		_poser(piece, Cfg.COL_METAL)
	for piece in PlanArene.ABRIS:
		_poser(piece, Cfg.COL_BETON_SOMBRE)
	var pas := 2 if Cfg.quality == Cfg.Quality.LOW else 1
	var i := 0
	for piece in PlanArene.GARNITURE:
		if i % pas == 0:
			_poser(piece, Cfg.COL_METAL, false)
		i += 1

func _poser(piece: Dictionary, teinte: Color, solide := true) -> void:
	var plan_pos: Vector2 = piece["pos"]
	var rot: float = piece["rot"]
	var taille: Vector3 = piece["taille"]
	var pos := Vector3(plan_pos.x, 0.0, plan_pos.y)

	var rendu := PropKit.instancier(piece["modele"], taille, teinte)
	var noeud: Node3D = rendu["noeud"]
	var reelle: Vector3 = rendu["taille"]
	noeud.position = pos
	noeud.rotation.y = rot
	add_child(noeud)
	_props += 1
	if rendu.get("reel", false):
		_pieces_habillees += 1
	_pieces_totales += 1

	if not solide:
		_sans_ombre(noeud)
		return

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = reelle
	shape.shape = box
	shape.position = pos + Vector3(0, reelle.y * 0.5, 0)
	shape.rotation.y = rot
	_obstacles.add_child(shape)
	_flaque(pos, reelle, rot)

var _pieces_habillees: int = 0
var _pieces_totales: int = 0

func _flaque(pos: Vector3, taille: Vector3, rot: float) -> void:
	var flaque := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(taille.x + 0.5, 0.02, taille.z + 0.5)
	flaque.mesh = b
	var couleur := Cfg.COL_NEON_MAGENTA if taille.y > 3.0 else Cfg.COL_NEON_CYAN
	var m := VisualKit.glow_mat(couleur, 1.5)
	m.albedo_color.a = 0.30
	flaque.material_override = m
	flaque.position = pos + Vector3(0, 0.05, 0)
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
#
# Conservée intacte pour le mode Battle Royale, qui reste réactivable.
# En mode arène persistante, `update_zone` n'est simplement jamais appelée.

func _build_zone_ring() -> void:
	_zone_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 9.0
	cyl.radial_segments = 56
	cyl.cap_top = false
	cyl.cap_bottom = false
	_zone_ring.mesh = cyl
	_zone_mat = VisualKit.glow_mat(Cfg.COL_DANGER, 1.4)
	_zone_mat.albedo_color.a = 0.2
	_zone_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_zone_ring.material_override = _zone_mat
	_zone_ring.position = Vector3(0, 4.4, 0)
	_zone_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_ring.visible = false
	add_child(_zone_ring)

func update_zone(radius: float, closing: bool) -> void:
	if _zone_ring == null:
		return
	_zone_ring.visible = true
	_zone_ring.scale = Vector3(radius, 1.0, radius)
	_zone_mat.albedo_color.a = 0.32 if closing else 0.18
	_zone_mat.emission_energy_multiplier = 2.4 if closing else 1.2

# --- APPARITIONS ---------------------------------------------------------

## LES APPARITIONS SONT RÉPARTIES SUR TOUT LE MONDE.
##
## Dix points de joueur, deux par secteur, à des rayons inégaux et jamais
## dans le noyau : réapparaître au cœur du secteur le plus dangereux
## transformerait chaque mort en série de morts.
##
## Les foyers de mobs, eux, suivent les POINTS D'INTÉRÊT et le gradient de
## danger. C'est ce qui donne une RAISON d'aller quelque part : un repère
## sans rien autour n'est qu'une jolie silhouette.
func _compute_spawns() -> void:
	# LE MONDE VALIDE SES PROPRES APPARITIONS.
	#
	# Le plan les place à l'aveugle : il ne sait rien des rochers semés ni
	# des bâtiments des points d'intérêt, qui sont construits après lui.
	# Mesuré : une apparition sur dix tombait dans un obstacle — et un
	# joueur qui réapparaît coincé dans un mur est un défaut qu'on ne
	# découvre qu'en mourant au mauvais endroit.
	#
	# Écarter la contrainte du semis n'aurait réglé que le cas du jour :
	# le prochain bâtiment ajouté aurait reproduit le problème. Ici, tout ce
	# qui sera construit à l'avenir est pris en compte gratuitement.
	player_spawn_points = []
	for p: Vector3 in PlanMonde.apparitions_joueurs():
		player_spawn_points.append(_degager(p, 0.7))

	mob_spawn_points.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 991177
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var centre := PlanMonde.position_poi(poi)
		var rayon: float = poi["rayon_actif"]
		var secteur := PlanMonde.secteur(poi["secteur"])
		# Le nombre de foyers suit le danger du secteur : c'est ainsi que
		# le gradient bord → centre devient réel et pas seulement annoncé.
		var danger: int = int(secteur.get("danger", PlanMonde.Densite.FORTE)) \
				if not secteur.is_empty() else PlanMonde.Densite.EXTREME
		var foyers := 2 + danger
		for i in foyers:
			var a := TAU * float(i) / float(foyers) + rng.randf_range(-0.3, 0.3)
			var r := rayon * rng.randf_range(0.45, 0.95)
			mob_spawn_points.append(
					Vector3(centre.x + cos(a) * r, 0.2, centre.y + sin(a) * r))

	# Quelques foyers de rase campagne : sans eux, tout se passerait aux
	# points d'intérêt et les trajets entre eux seraient morts.
	for i in 14:
		var a := TAU * float(i) / 14.0 + 0.21
		var r := rng.randf_range(PlanMonde.RAYON_NOYAU + 8.0,
				PlanMonde.RAYON - 12.0)
		mob_spawn_points.append(Vector3(cos(a) * r, 0.2, sin(a) * r))

	# Les foyers de mobs sont dégagés eux aussi : un mob qui naît dans un
	# rocher y reste coincé, occupe le plafond et n'affronte personne.
	for i in mob_spawn_points.size():
		mob_spawn_points[i] = _degager(mob_spawn_points[i], 1.0)

	if mob_spawn_points.is_empty():
		push_error("Aucun foyer d'apparition de mob : le plan du monde est vide.")
		mob_spawn_points.append(Vector3(0, 0.2, 12.0))

## POUSSE UN POINT HORS DE TOUT OBSTACLE.
##
## Recherche en spirale : on s'écarte par pas de 1,5 m en tournant, ce qui
## trouve le vide le plus proche sans jamais s'éloigner beaucoup. Rendre le
## point d'origine en cas d'échec est délibéré — mieux vaut une apparition
## imparfaite qu'une apparition absente.
func _degager(p: Vector3, rayon: float) -> Vector3:
	if _libre_monde(Vector2(p.x, p.z), rayon):
		return p
	for pas in range(1, 12):
		var d := 1.5 * float(pas)
		for k in 8:
			var a := TAU * float(k) / 8.0 + float(pas) * 0.4
			var essai := Vector2(p.x + cos(a) * d, p.z + sin(a) * d)
			if essai.length() > PlanMonde.RAYON - 6.0:
				continue
			if _libre_monde(essai, rayon):
				return Vector3(essai.x, p.y, essai.y)
	push_warning("Point d'apparition non dégagé en %s" % str(p))
	return p


## Une position est-elle libre de tout obstacle SOLIDE ?
##
## Le sol est exclu par sa hauteur : sa boîte de collision fait 187 m de
## large et se centre sur l'origine ; comptée comme un obstacle, elle
## déclarerait le monde entier bloqué. Tout obstacle réel a son centre
## au-dessus de zéro, le sol est enterré.
func _libre_monde(p: Vector2, rayon: float) -> bool:
	for n in _obstacles.get_children():
		var forme := n as CollisionShape3D
		if forme == null or forme.position.y <= 0.0:
			continue
		var r := 0.0
		if forme.shape is BoxShape3D:
			var b := forme.shape as BoxShape3D
			r = maxf(b.size.x, b.size.z) * 0.5
		elif forme.shape is CylinderShape3D:
			r = (forme.shape as CylinderShape3D).radius
		else:
			continue
		if p.distance_to(Vector2(forme.position.x, forme.position.z)) < r + rayon:
			return false
	return true


func player_spawn(index: int) -> Vector3:
	if player_spawn_points.is_empty():
		return Vector3.ZERO
	return player_spawn_points[index % player_spawn_points.size()]

## FOYER DE MOB CHOISI PRÈS D'UN JOUEUR, MAIS PAS SUR LUI.
##
## POURQUOI CE CHANGEMENT. Sur l'ancienne arène de 68 m, n'importe quel
## foyer était « près » de tout le monde. Sur 156 m, faire apparaître les
## mobs au hasard les enverrait par paquets là où personne ne va — la carte
## paraîtrait vide là où l'on est, et surchargée là où l'on n'est pas.
##
## On vise donc une distance MOYENNE : assez loin pour ne pas surgir dans
## le dos (injuste), assez près pour être rencontré (sinon le mob vit et
## meurt sans que personne ne le voie, et le plafond se remplit pour rien).
func mob_spawn(players: Array) -> Vector3:
	var best := Vector3.ZERO
	var best_score := -INF
	for point in mob_spawn_points:
		var nearest := INF
		for p in players:
			if is_instance_valid(p) and p.get(&"is_eliminated") != true:
				nearest = minf(nearest, point.distance_to(p.global_position))
		# Aucun joueur en vue : ce foyer n'intéresse personne pour l'instant.
		if nearest == INF:
			continue
		var score := -absf(nearest - 26.0) + randf() * 6.0
		if score > best_score:
			best_score = score
			best = point
	if best == Vector3.ZERO and not mob_spawn_points.is_empty():
		best = mob_spawn_points[randi() % mob_spawn_points.size()]
	return best
