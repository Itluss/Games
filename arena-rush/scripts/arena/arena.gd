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

## Nombre de cellules par côté du monde. C'est aussi la maille du semis et
## celle du sol : une seule grille pour tout, donc un seul endroit où
## l'enroulement peut se tromper.
const NB_CELLULES := int(PlanMonde.COTE / PlanMonde.CELLULE)

var mob_spawn_points: Array[Vector3] = []
var player_spawn_points: Array[Vector3] = []

var _zone_ring: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _obstacles: StaticBody3D
var _semis: int = 0
var _props: int = 0

func _ready() -> void:
	var depart := Time.get_ticks_msec()
	_obstacles = StaticBody3D.new()
	_obstacles.name = "Obstacles"
	_obstacles.collision_layer = Cfg.LAYER_WORLD
	_obstacles.collision_mask = 0
	add_child(_obstacles)

	_build_environment()
	_build_ground()
	_batir_secteurs()
	_batir_points_interet()
	_build_pieces()
	_build_zone_ring()
	# LES APPARITIONS D'ABORD, LA COUTURE ENSUITE. Le calcul des apparitions
	# parcourt tous les obstacles ; le faire après la duplication lui en
	# donnait 1 398 au lieu de 528, dont 870 copies situées HORS du carré où
	# l'on cherche justement à faire apparaître. Deux tiers du travail
	# portaient sur des formes qui ne pouvaient rien bloquer — mesuré, cette
	# seule inversion et l'index spatial font passer l'étape de 304 à 5 ms.
	_compute_spawns()
	_replier_les_collisions()
	# LE TEMPS DE CONSTRUCTION EST AFFICHÉ, et ce n'est pas de la curiosité :
	# il se passe en UNE SEULE image, écran figé. C'est la toute première
	# impression du jeu sur un téléphone, et la seule dépense que personne
	# ne pense à mesurer parce qu'elle n'apparaît sur aucun compteur d'images.
	print("Monde : %.0f × %.0f m sans bord · %d props en %d semis · %d apparitions · bâti en %d ms."
			% [PlanMonde.COTE, PlanMonde.COTE, _props, _semis,
			player_spawn_points.size(), Time.get_ticks_msec() - depart])


# --- ENROULEMENT ---------------------------------------------------------

## RECOLLE LES COLLISIONS À LA COUTURE.
##
## LE DÉCOR SE REPLIE, PAS LA PHYSIQUE. Les cellules visuelles se
## repositionnent autour de la caméra à chaque image ; les corps, eux,
## doivent rester immobiles — déplacer des corps statiques soixante fois par
## seconde ruinerait le moteur physique et ferait traverser les murs.
##
## Les collisions vivent donc à leur place dans le carré de référence. Mais
## un rocher posé à un mètre du bord doit arrêter un joueur qui arrive de
## l'AUTRE côté, à un mètre de lui — et pour la physique, ces deux-là sont
## séparés de 142 m.
##
## On duplique donc les formes proches d'un bord dans les huit cases
## voisines.
##
## LA BANDE FAIT QUARANTE MÈTRES, ET CE N'EST PLUS LA TAILLE D'UNE PIÈCE.
## Douze mètres suffisaient tant que les corps se repliaient dans le carré
## de référence. Ils se replient maintenant autour du JOUEUR, ce qui les
## emmène jusqu'à septante-deux mètres au-delà — c'est le prix à payer pour
## qu'aucun combat ne soit coupé par la limite.
##
## Quarante mètres couvrent tout ce que le joueur peut VOIR : la caméra ne
## montre qu'une trentaine de mètres de sol. Au-delà, un mob lointain peut
## traverser un rocher — personne n'est là pour le voir, et il retrouve des
## obstacles dès qu'il se rapproche. Doubler la bande jusqu'à septante-deux
## aurait exigé de recopier NEUF FOIS tout le décor solide du monde.
const MARGE_COUTURE := 40.0

func _replier_les_collisions() -> void:
	var doubles := 0
	var bord := PlanMonde.DEMI + MARGE_COUTURE
	for n in _obstacles.get_children().duplicate():
		var forme := n as CollisionShape3D
		# Le sol est déjà large de trois mondes : le dupliquer n'aurait
		# aucun sens, et sa boîte est justement celle qu'il ne faut pas
		# multiplier par neuf.
		if forme == null or forme.position.y <= 0.0:
			continue
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var q := Vector3(forme.position.x + float(dx) * PlanMonde.COTE,
						forme.position.y,
						forme.position.z + float(dz) * PlanMonde.COTE)
				if absf(q.x) > bord or absf(q.z) > bord:
					continue
				var copie := CollisionShape3D.new()
				copie.shape = forme.shape
				copie.position = q
				copie.rotation = forme.rotation
				_obstacles.add_child(copie)
				doubles += 1
	print("Couture : %d formes de collision dupliquées." % doubles)



## CE QUI REND LE MONDE SANS COUTURE, ET COMMENT.
##
## Le contenu du monde est rangé dans des CELLULES : une grille de 6 × 6
## conteneurs de 24 m. Chaque cellule connaît sa position de référence, et
## tout ce qu'elle porte est exprimé RELATIVEMENT à elle.
##
## À chaque image, on repose chaque cellule à celle de ses images qui est la
## plus proche de la caméra. Une cellule située à 70 m « à l'ouest » est donc
## dessinée à 74 m à l'est si c'est plus court — et comme le monde est
## périodique, l'image est rigoureusement la même.
##
## La bascule d'une image à l'autre se produit à un demi-monde de la caméra,
## soit 72 m, alors que le cadre n'en montre qu'une trentaine. Elle est donc
## toujours invisible : c'est ce qui fait qu'on ne voit jamais la couture.
##
## Rien de tout cela ne concerne les COLLISIONS. Les corps, eux, gardent
## leur position dans le carré de référence et c'est leur position qui
## s'enroule — voir `_replier_les_bords`.
var _cellules: Dictionary = {}
var _ancres: Array[Vector2] = []
var _conteneurs: Array[Node3D] = []
## Conteneur courant des `_ajouter` — nul pour poser directement sur le monde.
var _groupe: Node3D = null


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	for i in _conteneurs.size():
		var d := PlanMonde.ecart(c, _ancres[i])
		_conteneurs[i].position = Vector3(c.x + d.x, 0.0, c.y + d.y)


## Position de référence de la cellule (ix, iz) — son centre.
func _base_cellule(ix: int, iz: int) -> Vector2:
	return Vector2(
			-PlanMonde.DEMI + (float(ix) + 0.5) * PlanMonde.CELLULE,
			-PlanMonde.DEMI + (float(iz) + 0.5) * PlanMonde.CELLULE)


## Position de référence de la cellule qui contient un point du monde.
func _base_cellule_de(p: Vector2) -> Vector2:
	var q := PlanMonde.enrouler(p)
	return _base_cellule(
			floori((q.x + PlanMonde.DEMI) / PlanMonde.CELLULE),
			floori((q.y + PlanMonde.DEMI) / PlanMonde.CELLULE))


## Le conteneur d'une cellule, créé à la demande.
##
## LA CLÉ EST UN ENTIER, PAS UNE CHAÎNE. Construire « %.0f_%.0f » coûte un
## formatage de texte et une allocation ; multiplié par les mille cinq cents
## props du monde et les deux cent vingt-six semis, cela représentait une
## part notable des deux cent soixante millisecondes de construction des
## secteurs. Une clé entière ne coûte rien et se compare instantanément.
func _cellule(base: Vector2) -> Node3D:
	var cle := _cle_index(base.x, base.y)
	if _cellules.has(cle):
		var connu: Node3D = _cellules[cle]
		return connu
	return _ancrer(base, cle)


## Crée un conteneur ancré en `base`. Sert aussi aux repères, qui ne suivent
## pas la grille : un repère est son propre point d'ancrage.
func _ancrer(base: Vector2, cle := 0) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(base.x, 0.0, base.y)
	add_child(n)
	_conteneurs.append(n)
	_ancres.append(PlanMonde.enrouler(base))
	if cle != 0:
		_cellules[cle] = n
	return n


# --- FUSION ---------------------------------------------------------------

## FOND PLUSIEURS FORMES EN UN SEUL MAILLAGE, PAR TEINTE.
##
## POURQUOI. Chaque `MeshInstance3D` est un appel de dessin, quel que soit
## ce qu'il contient : une tour faite de trente cubes coûte trente appels,
## une tour faite d'un maillage de trente cubes en coûte un. Mesuré sur le
## monde construit, cent cinquante-neuf maillages individuels dont trente
## flaques de néon et une quarantaine de blocs de repères — tous immobiles,
## tous groupés au même endroit, donc tous fusionnables sans rien perdre.
##
## ON NE FUSIONNE QUE CE QUI VIT ENSEMBLE. Fondre deux rochers distants de
## cinquante mètres produirait un maillage dont la boîte englobante couvre
## les deux : il serait dessiné dès que l'un des deux entre dans le champ,
## et on aurait échangé un appel de dessin contre du travail inutile. La
## fusion est donc ouverte et refermée autour d'UN repère à la fois.
var _fusion: Dictionary = {}

func _ouvrir_fusion() -> void:
	_fusion.clear()


## Ajoute une forme à l'accumulateur de sa teinte.
func _fondre(forme: Mesh, tr: Transform3D, teinte: Color,
		emissif := false) -> void:
	var cle := teinte.to_html(false) + ("!" if emissif else "")
	if not _fusion.has(cle):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_fusion[cle] = {"st": st, "teinte": teinte, "emissif": emissif}
	var e: Dictionary = _fusion[cle]
	(e["st"] as SurfaceTool).append_from(forme, 0, tr)


## Referme la fusion : un maillage par teinte, posé dans le groupe courant.
func _fermer_fusion() -> void:
	for cle: String in _fusion:
		var e: Dictionary = _fusion[cle]
		var st: SurfaceTool = e["st"]
		# Normales à plat : les formes fondues sont des blocs, et un lissage
		# arrondirait leurs arêtes — exactement ce que la direction
		# artistique évite.
		st.generate_normals(false)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var teinte: Color = e["teinte"]
		if bool(e["emissif"]):
			var m := VisualKit.glow_mat(teinte, 1.5)
			m.albedo_color.a = 0.30
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.material_override = VisualKit.mat(teinte, 0.0, 0.9)
		# Les sommets portent des coordonnées DU MONDE : `_ajouter` retranche
		# la position du groupe, ce qui les y ramène exactement.
		mi.position = Vector3.ZERO
		_ajouter(mi)
	_fusion.clear()


## Pose un élément de décor dans le groupe courant, en convertissant sa
## position du monde vers celle du groupe.
##
## LA POSITION DOIT ÊTRE RÉGLÉE AVANT L'APPEL — c'est la convention de tous
## les constructeurs de ce fichier, et elle est ce qui rend ce raccordement
## possible sans les réécrire un par un.
func _ajouter(n: Node3D) -> void:
	if _groupe == null:
		add_child(n)
		return
	n.position -= _groupe.position
	_groupe.add_child(n)

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

## LE SOL D'UN MONDE QUI S'ENROULE.
##
## L'ancien sol était fait de quartiers en camembert : un disque de fond,
## cinq parts angulaires, un noyau par-dessus. Rien de tout cela n'a de sens
## sans centre ni bord.
##
## Le sol est maintenant une MOSAÏQUE de cellules carrées, une par cellule
## du monde. Chaque cellule porte une grille de sommets, et chaque sommet
## prend la couleur du secteur qui le contient. Les triangles interpolent :
## les frontières se fondent au lieu de se découper, et le tout tient en un
## seul matériau — la couleur voyage dans les sommets, pas dans une texture.
##
## L'avantage décisif est ailleurs : découpé en cellules, le sol s'enroule
## par le même mécanisme que le décor. Il n'y a pas de « bord du sol » à
## traiter à part, donc pas d'endroit où il puisse manquer.
func _build_ground() -> void:
	# UNE SEULE BOÎTE DE COLLISION, LARGE. Les corps vivent toujours dans le
	# carré de référence — c'est leur POSITION qui s'enroule, pas le sol
	# sous eux. Trois fois le côté laisse de la marge à tout ce qui sort
	# momentanément du carré avant d'être ramené.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PlanMonde.COTE * 3.0, 1.0, PlanMonde.COTE * 3.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	_obstacles.add_child(col)

	var mat := VisualKit.mat(Color.WHITE, 0.0, 0.93)
	mat.vertex_color_use_as_albedo = true
	# FACES VISIBLES DES DEUX CÔTÉS. Premier jet : le sol n'apparaissait pas
	# du tout, vérifié en image — les props flottaient sur le ciel. Les
	# normales pointaient pourtant vers le haut ; c'est l'orientation des
	# triangles qui les faisait écarter avant même d'être éclairés.
	#
	# Plutôt que de deviner la convention d'enroulement, on la retire du
	# problème. Sur une dalle plate posée au sol et jamais vue par en
	# dessous, désactiver l'élimination des faces arrière ne coûte rien —
	# aucune face cachée n'est dessinée en plus.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for iz in NB_CELLULES:
		for ix in NB_CELLULES:
			var base := _base_cellule(ix, iz)
			var mi := MeshInstance3D.new()
			mi.mesh = _tapis(base)
			mi.material_override = mat
			mi.position = Vector3(0, -0.02, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cellule(base).add_child(mi)


## Nombre de sous-divisions par cellule de sol. 8 donne un sommet tous les
## trois mètres : assez fin pour que les frontières de secteur ondulent,
## assez grossier pour que tout le sol du monde tienne en 2 300 quadrilatères.
const FINESSE_SOL := 8

## Une dalle de sol, en coordonnées LOCALES à sa cellule.
func _tapis(base: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pas := PlanMonde.CELLULE / float(FINESSE_SOL)
	var demi := PlanMonde.CELLULE * 0.5
	var teintes: Array[Color] = []
	for j in FINESSE_SOL + 1:
		for i in FINESSE_SOL + 1:
			var local := Vector2(-demi + float(i) * pas, -demi + float(j) * pas)
			var s := PlanMonde.secteur(PlanMonde.secteur_de(
					PlanMonde.enrouler(base + local)))
			teintes.append(s["sol"] if s.has("sol") else Cfg.SOL_NOYAU)
	var largeur := FINESSE_SOL + 1
	for j in FINESSE_SOL:
		for i in FINESSE_SOL:
			var a := j * largeur + i
			var b := a + 1
			var c := a + largeur
			var d := c + 1
			_triangle(st, base, i, j, a, c, b, teintes, pas, demi)
			_triangle(st, base, i, j, b, c, d, teintes, pas, demi)
	st.generate_normals()
	return st.commit()


func _triangle(st: SurfaceTool, base: Vector2, i: int, j: int,
		i0: int, i1: int, i2: int, teintes: Array[Color],
		pas: float, demi: float) -> void:
	var largeur := FINESSE_SOL + 1
	for idx: int in [i0, i1, i2]:
		var gx := idx % largeur
		var gz := idx / largeur
		st.set_color(teintes[idx])
		st.add_vertex(Vector3(-demi + float(gx) * pas, 0.0,
				-demi + float(gz) * pas))

# --- LIMITE DU MONDE -----------------------------------------------------
#
# IL N'Y EN A PLUS, ET C'EST TOUT L'INTÉRÊT.
#
# Le monde était ceint d'un mur invisible de 14 m de haut doublé d'une
# ceinture de mesas. Ce mur a coûté trois corrections successives : la
# caméra s'y retrouvait enfermée dans la pierre, il rabattait le cadre sans
# raison visible, et c'est en s'en approchant que l'écran devenait violet.
#
# On ne soigne plus les symptômes d'une limite : on l'a supprimée. Partir
# tout droit ramène au point de départ.

# --- SECTEURS ------------------------------------------------------------

## SÈME LE DÉCOR, PAR CELLULE DU MONDE.
##
## Le semis ne parcourt plus les secteurs un par un — un secteur n'a plus de
## forme analytique dont on saurait tirer une surface. Il parcourt le CARRÉ
## sur une grille régulière, demande à chaque point son secteur, et y pose
## un prop avec la densité de ce secteur. Le résultat est identique et la
## règle tient en trois lignes, quel que soit le découpage.
##
## Le regroupement par cellule reste le cœur de la tenue en performance :
## chaque famille est dessinée en un appel par cellule, et une cellule hors
## champ ne coûte rien. C'est aussi ce regroupement qui fait l'enroulement,
## puisque ce sont les cellules qu'on repositionne autour de la caméra.
func _batir_secteurs() -> void:
	var rng := RandomNumberGenerator.new()
	# Graine FIXE : le monde doit être le même pour tout le monde et d'une
	# session à l'autre. Une carte qu'on ne peut pas apprendre ne s'habite
	# jamais — et deux joueurs verraient des décors différents.
	rng.seed = 20260818

	# cellule -> { famille -> [Transform3D] }
	var tuiles: Dictionary = {}
	var collisions: Array[Dictionary] = []
	# Pas d'échantillonnage. Chaque point tiré porte donc une surface de
	# PAS_SEMIS², et la densité déclarée par le secteur devient directement
	# une probabilité.
	var pas := PAS_SEMIS
	var n := int(PlanMonde.COTE / pas)
	for iz in n:
		for ix in n:
			var p := PlanMonde.enrouler(Vector2(
					-PlanMonde.DEMI + (float(ix) + rng.randf()) * pas,
					-PlanMonde.DEMI + (float(iz) + rng.randf()) * pas))
			var s := PlanMonde.secteur(PlanMonde.secteur_de(p))
			if s.is_empty():
				continue
			if rng.randf() > float(s["densite_decor"]) * pas * pas:
				continue
			if not _emplacement_libre(p):
				continue

			var familles: Array = s["familles"]
			var famille: StringName = familles[rng.randi() % familles.size()]
			var ech := rng.randf_range(0.75, 1.45)
			# ÉCHELLE NON UNIFORME : c'est elle, et non des maillages
			# différents, qui fait qu'aucun rocher ne ressemble à son voisin.
			var base := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))
			base = base.scaled(Vector3(ech * rng.randf_range(0.85, 1.2),
					ech * rng.randf_range(0.85, 1.25),
					ech * rng.randf_range(0.85, 1.2)))

			var ancre := _base_cellule_de(p)
			var cle := _cle_index(ancre.x, ancre.y)
			if not tuiles.has(cle):
				tuiles[cle] = {"ancre": ancre, "familles": {}}
			var par_famille: Dictionary = tuiles[cle]["familles"]
			if not par_famille.has(famille):
				par_famille[famille] = ([] as Array[Transform3D])
			# Les transformations sont LOCALES à leur cellule : c'est ce qui
			# permet de déplacer la cellule entière d'un côté du monde à
			# l'autre sans toucher à son contenu.
			var local := p - ancre
			(par_famille[famille] as Array[Transform3D]).append(
					Transform3D(base, Vector3(local.x, 0.0, local.y)))

			if famille in FAMILLES_SOLIDES:
				collisions.append({"pos": p, "rayon": ech * RAYON_SOLIDE[famille],
						"haut": ech * HAUTEUR_SOLIDE[famille]})

	for cle: int in tuiles:
		var ancre: Vector2 = tuiles[cle]["ancre"]
		var par_famille: Dictionary = tuiles[cle]["familles"]
		for famille: StringName in par_famille:
			var liste: Array[Transform3D] = par_famille[famille]
			var noeud := KitDecor.semer(famille, liste,
					_portee(famille), famille in FAMILLES_SOLIDES)
			_cellule(ancre).add_child(noeud)
			_semis += 1
			_props += liste.size()

	for c: Dictionary in collisions:
		_poser_collision_ronde(c["pos"], c["rayon"], c["haut"])


## Pas d'échantillonnage du semis, en mètres.
const PAS_SEMIS := 2.0

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
## On écarte les abords immédiats des points d'intérêt (qui doivent rester praticables)
## et les points d'apparition (naître dans un arbre serait un défaut
## immédiat).
func _emplacement_libre(p: Vector2) -> bool:
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var c := PlanMonde.position_poi(poi)
		if PlanMonde.distance(p, c) < float(poi["rayon_actif"]) * 0.52:
			return false
	for sp: Vector3 in PlanMonde.apparitions_joueurs():
		if PlanMonde.distance(p, Vector2(sp.x, sp.z)) < 4.5:
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
		# CHAQUE REPÈRE EST SON PROPRE ANCRAGE, et non un locataire de la
		# cellule où il tombe. Une tour de 17 m posée près d'une frontière
		# de cellule déborderait sur sa voisine : à l'instant où les deux
		# cellules basculent d'une image à l'autre, la tour se couperait en
		# deux. Ancrée sur elle-même, elle se déplace d'un bloc.
		_groupe = _ancrer(p)
		_ouvrir_fusion()
		match poi["id"]:
			&"tour": _poi_tour(socle)
			&"pont": _poi_pont(socle)
			&"temple": _poi_temple(socle)
			&"depot": _poi_depot(socle)
			&"carcasse": _poi_carcasse(socle)
			&"place": pass   # meublé par le plan d'origine, voir _build_pieces
		if poi["id"] != &"place":
			_balise(socle, float(poi["hauteur"]))
		_fermer_fusion()
		_groupe = null


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
	_ajouter(orbe)


func _bloc(taille: Vector3, pos: Vector3, teinte: Color, rot := 0.0,
		solide := true) -> void:
	var b := BoxMesh.new()
	b.size = taille
	_fondre(b, Transform3D(Basis.from_euler(Vector3(0, rot, 0)), pos), teinte)
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
		_ajouter(mi)
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
	_ajouter(toit)


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
	_ajouter(mat)
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
	_ajouter(mi)
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

## Le Creuset REPREND l'ancienne arène telle quelle : son plan, ses abris,
## ses modèles Meshy. C'est délibéré — c'est le seul secteur déjà réglé et
## déjà validé par un test, et il devient naturellement le lieu le plus
## construit du monde, donc le plus disputé.
##
## Il ne se trouve plus au centre du monde, puisqu'un tore n'en a pas : il
## est posé au centre de SON secteur, comme n'importe quel autre lieu.
func _build_pieces() -> void:
	_centre_creuset = PlanMonde.secteur(&"creuset")["centre"]
	_groupe = _ancrer(_centre_creuset)
	_ouvrir_fusion()
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
	_fermer_fusion()
	_groupe = null

## Position du Creuset dans le monde, lue une fois à la construction.
var _centre_creuset := Vector2.ZERO

func _poser(piece: Dictionary, teinte: Color, solide := true) -> void:
	var plan_pos: Vector2 = piece["pos"]
	var rot: float = piece["rot"]
	var taille: Vector3 = piece["taille"]
	# Le plan de l'ancienne arène est écrit autour de l'origine : on le
	# translate au Creuset, puis on enroule — s'il déborde d'un bord, il
	# ressort de l'autre, exactement comme le reste du monde.
	var plat := PlanMonde.enrouler(_centre_creuset + plan_pos)
	var pos := Vector3(plat.x, 0.0, plat.y)

	var rendu := PropKit.instancier(piece["modele"], taille, teinte)
	var noeud: Node3D = rendu["noeud"]
	var reelle: Vector3 = rendu["taille"]
	noeud.position = pos
	noeud.rotation.y = rot
	_ajouter(noeud)
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

## FLAQUE DE NÉON sous une pièce du Creuset.
##
## Trente d'entre elles, chacune avec son propre matériau lumineux : trente
## appels de dessin pour un liseré décoratif, mesuré. Elles sont maintenant
## fondues avec les autres — deux maillages, un par couleur — et coupées
## sur téléphone, où elles ne valent pas ce qu'elles coûtent.
func _flaque(pos: Vector3, taille: Vector3, rot: float) -> void:
	if Cfg.est_mobile():
		return
	var b := BoxMesh.new()
	b.size = Vector3(taille.x + 0.5, 0.02, taille.z + 0.5)
	var couleur := Cfg.COL_NEON_MAGENTA if taille.y > 3.0 else Cfg.COL_NEON_CYAN
	_fondre(b, Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
			pos + Vector3(0, 0.05, 0)), couleur, true)

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
	# Quatorze foyers tirés dans TOUT le carré, et non sur un anneau : un
	# anneau n'a de sens qu'autour d'un centre, et le monde n'en a plus.
	for i in 14:
		var q := PlanMonde.enrouler(Vector2(
				rng.randf_range(-PlanMonde.DEMI, PlanMonde.DEMI),
				rng.randf_range(-PlanMonde.DEMI, PlanMonde.DEMI)))
		mob_spawn_points.append(Vector3(q.x, 0.2, q.y))

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
			# PLUS AUCUNE POSITION N'EST « TROP LOIN ». L'ancien monde
			# rejetait les essais qui sortaient du disque ; ici il n'y a
			# pas de dehors, seulement un point qui repasse de l'autre côté.
			var essai := PlanMonde.enrouler(
					Vector2(p.x + cos(a) * d, p.z + sin(a) * d))
			if _libre_monde(essai, rayon):
				return Vector3(essai.x, p.y, essai.y)
	push_warning("Point d'apparition non dégagé en %s" % str(p))
	return p


## Une position est-elle libre de tout obstacle SOLIDE ?
##
## Le sol est exclu par sa hauteur : sa boîte de collision couvre trois fois
## le monde et se centre sur l'origine ; comptée comme un obstacle, elle
## déclarerait le monde entier bloqué. Tout obstacle réel a son centre
## au-dessus de zéro, le sol est enterré.
## INDEX SPATIAL DES OBSTACLES — cellule -> [Vector3(x, z, rayon)].
##
## POURQUOI IL EXISTE. Chercher une position libre parcourait TOUS les
## obstacles du monde, et on cherche quarante-cinq fois, chacune pouvant
## sonder quatre-vingt-seize points en spirale. Mesuré : 304 ms sur la
## seule étape des apparitions, sur un processeur de bureau — donc
## plusieurs secondes d'écran figé sur un téléphone, au tout premier
## lancement du jeu.
##
## L'index range les obstacles par cellule de 8 m. Une recherche ne
## consulte alors que les neuf cellules voisines au lieu du monde entier.
const MAILLE_INDEX := 8.0
var _index: Dictionary = {}
var _index_pret := false


func _batir_index() -> void:
	_index.clear()
	for n in _obstacles.get_children():
		var forme := n as CollisionShape3D
		# Le sol est enterré : tout obstacle réel a son centre au-dessus de
		# zéro. C'est ce qui l'écarte sans avoir à le nommer.
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
		var cle := _cle_index(forme.position.x, forme.position.z)
		if not _index.has(cle):
			_index[cle] = ([] as Array[Vector3])
		(_index[cle] as Array[Vector3]).append(
				Vector3(forme.position.x, forme.position.z, r))
	_index_pret = true


func _cle_index(x: float, z: float) -> int:
	# Une clé ENTIÈRE plutôt qu'une chaîne : la construction de milliers de
	# chaînes coûterait une part notable de ce qu'on vient d'économiser.
	return floori(x / MAILLE_INDEX) * 4096 + floori(z / MAILLE_INDEX)


func _libre_monde(p: Vector2, rayon: float) -> bool:
	if not _index_pret:
		_batir_index()
	# Le plus gros obstacle du monde tient dans une maille : trois cellules
	# de part et d'autre suffisent donc à tout voir, et c'est ce qui rend la
	# recherche indépendante de la taille de la carte.
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cle := _cle_index(p.x + float(dx) * MAILLE_INDEX,
					p.y + float(dz) * MAILLE_INDEX)
			if not _index.has(cle):
				continue
			for o: Vector3 in _index[cle]:
				if PlanMonde.distance(p, Vector2(o.x, o.y)) < o.z + rayon:
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
				nearest = minf(nearest,
						PlanMonde.distance3(point, p.global_position))
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
