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
## Prochain foyer à servir en arène de combat. Voir `mob_spawn`.
var _index_mob_test: int = 0
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

	# RETROUVABLE PAR LA CAMÉRA. Elle a besoin de nous dire quel repère
	# effacer ; sans groupe, elle devrait deviner un chemin dans l'arbre.
	add_to_group(&"arene")
	_build_environment()

	# ─── ARÈNE DE COMBAT : UN AUTRE MONDE, LE MÊME JEU ──────────────────
	#
	# Tout ce que le monde ouvert fait ici — semer le décor, poser les
	# repères, replier les collisions à la couture, repositionner les
	# cellules à chaque image — est SAUTÉ. Ce n'est pas une optimisation :
	# c'est la condition pour juger un level design. Un semis qui repasse
	# par-dessus une composition manuelle en détruit la lecture, et l'on ne
	# saurait plus si ce qu'on voit vient du plan ou du hasard.
	if Cfg.arene_test:
		# ─── L'ARÈNE WESTERN REMPLACE L'ANCIENNE, ELLE NE S'Y AJOUTE PAS ──
		#
		# L'arène de combat 40 × 40 en pierre solaire ne se construit plus.
		# Son plan reste dans le dépôt — l'historique dira toujours ce
		# qu'elle valait — mais plus rien ne l'appelle : mélanger deux
		# cartes serait le contraire de ce qui est demandé.
		#
		# LE REPLIEMENT TORIQUE EST COUPÉ, et ce n'est pas un détail. Les
		# bots, les mobs, les effets et la réapparition mesurent leurs
		# distances avec `PlanMonde`, qui replie sur 144 m. L'ancienne
		# arène faisait 40 m — écart maximal 56 m, sous le demi-côté de
		# 72, le repliement ne se déclenchait jamais. Celle-ci fait 80 m,
		# diagonale 113 m : deux joueurs opposés seraient calculés comme
		# voisins, et l'IA deviendrait incohérente sans un seul message
		# d'erreur.
		PlanMonde.enroulement = false
		_batir_arene_western()
		print("Arène Western : %.0f × %.0f m · %d crêtes · %d murs · %d piles · "
				% [PlanAreneWestern.COTE, PlanAreneWestern.COTE,
					PlanAreneWestern.FORMATIONS.size(),
					PlanAreneWestern.MURS.size(),
					PlanAreneWestern.PILES.size()]
				+ "%d pièces posées · %d apparitions · %d mobs · bâtie en %d ms."
				% [_props, player_spawn_points.size(),
					mob_spawn_points.size(),
					Time.get_ticks_msec() - depart])
		return

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
## Ambiance et soleil, gardés sous la main par la veille — voir `_veiller`.
var _ambiance: WorldEnvironment
var _soleil: DirectionalLight3D
var _veille := 0.0
var _plaintes: Dictionary = {}


func _process(delta: float) -> void:
	# L'arène de combat n'a ni cellules à replier ni couture à surveiller :
	# elle tient d'un seul tenant autour de l'origine. La veille du monde
	# ouvert n'aurait ici rien à mesurer, et se plaindrait de l'absence
	# d'un décor qui n'est pas censé exister.
	if Cfg.arene_test:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_veiller(null)
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	for i in _conteneurs.size():
		var d := PlanMonde.ecart(c, _ancres[i])
		_conteneurs[i].position = Vector3(c.x + d.x, 0.0, c.y + d.y)

	if _repit > 0.0:
		_repit -= delta

	_veille -= delta
	if _veille <= 0.0:
		_veille = 1.0
		_veiller(cam)


# --- VEILLE DU MONDE -----------------------------------------------------

## VÉRIFIE UNE FOIS PAR SECONDE QUE LE MONDE EST ENCORE MONTRABLE.
##
## POURQUOI CETTE VEILLE EXISTE, ET CE QU'ELLE AVOUE.
##
## Un écran entièrement vide a été signalé quatre fois depuis un téléphone.
## Huit sondes l'ont cherché : trous de carte, décrochages de caméra, images
## plates, luminance, étanchéité du mur, cellules autour de l'œil, et enfin
## le vrai export web joué dans un vrai navigateur. Aucune ne l'a reproduit.
## La dernière capture a pourtant tranché sur un point : la MINICARTE
## fonctionnait, montrant la joueuse entourée de décor et d'adversaires. Le
## monde existait donc, à sa place — il n'était simplement pas dessiné.
##
## Chercher plus longtemps à l'aveugle sur une machine qui n'a pas le défaut
## coûterait des heures pour, au mieux, une hypothèse de plus. On change de
## méthode : le monde vérifie lui-même, chaque seconde, les quatre
## conditions SANS LESQUELLES IL NE PEUT PAS S'AFFICHER. Si l'une manque,
## elle est réparée sur-le-champ et nommée à l'écran.
##
## Deux issues, et les deux sont un progrès : ou le défaut disparaît de
## lui-même, ou la prochaine capture porte le nom de sa cause.
func _veiller(cam: Camera3D) -> void:
	# 1. UNE CAMÉRA ACTIVE. Sans elle, rien n'est rendu du tout, et le
	#    repositionnement du décor s'arrête aussi — donc même en la
	#    retrouvant plus tard, le monde resterait garé où il était.
	if cam == null:
		var reprise := _retrouver_camera()
		_signaler("camera", "CAMERA ABSENTE%s" % ("" if reprise else " (ECHEC)"))
		return

	# 2. UNE AMBIANCE. Le ciel, la brume et la lumière ambiante en
	#    dépendent : sans elle, le fond devient un aplat et le décor perd
	#    tout éclairage indirect.
	var monde3d := get_viewport().world_3d
	if monde3d != null and _ambiance != null and _ambiance.environment != null \
			and monde3d.environment != _ambiance.environment:
		monde3d.environment = _ambiance.environment
		_signaler("ambiance", "AMBIANCE PERDUE")

	# 3. UN SOLEIL. Éteint, tout le décor tombe au noir tandis que le ciel,
	#    lui, continue de s'afficher — ce qui donne exactement une image
	#    vide sur un dégradé.
	if _soleil == null or not is_instance_valid(_soleil):
		_signaler("soleil", "SOLEIL DISPARU")
	elif not _soleil.visible or _soleil.light_energy <= 0.01:
		_soleil.visible = true
		_soleil.light_energy = maxf(_soleil.light_energy, 1.15)
		_signaler("soleil", "SOLEIL ETEINT")

	# 4. DU DÉCOR AUTOUR DE L'ŒIL. C'est la garantie du monde enroulé, et
	#    elle ne peut faillir que si la boucle de repositionnement ne tourne
	#    plus. On la vérifie quand même : une garantie qu'on ne mesure pas
	#    est une garantie qu'on croit tenir.
	if _conteneurs.is_empty():
		_signaler("cellules", "MONDE NON CONSTRUIT")
		return
	var proche := false
	for n in _conteneurs:
		if n.global_position.distance_to(cam.global_position) < 60.0:
			proche = true
			break
	if not proche:
		_signaler("cellules", "DECOR HORS DE PORTEE")


## Rend une caméra au monde quand il n'en a plus.
func _retrouver_camera() -> bool:
	for n in get_tree().get_nodes_in_group(&"camera_arene"):
		var c := n as Camera3D
		if c != null and is_instance_valid(c):
			c.make_current()
			return true
	return false


## Chaque défaut n'est annoncé QU'UNE FOIS. Un bandeau qui se répète soixante
## fois par seconde masquerait le jeu au lieu de renseigner sur lui.
func _signaler(cle: String, texte: String) -> void:
	push_warning("Veille du monde : %s" % texte)
	if _plaintes.has(cle):
		return
	_plaintes[cle] = true
	if MatchDirector and MatchDirector.has_signal(&"announce"):
		MatchDirector.announce.emit("VEILLE : %s" % texte, Cfg.COL_DANGER)


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
		# NOMMÉE POUR CE QU'ELLE EST : UN LOT FONDU, PAS UNE PIÈCE.
		#
		# La sonde de scintillement relevait ces maillages comme des props
		# ordinaires. Or un lot fondu couvre TOUTE l'arène : sa boîte
		# englobante recouvre celle de tous les autres à cent pour cent, et
		# la sonde criait au chevauchement pathologique sur ce qui est
		# précisément l'optimisation qu'on cherche. Le nom lui permet de
		# les écarter — et à moi de lire ses rapports.
		mi.name = "Fusion_%s" % cle
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
	sky_mat.ground_bottom_color = Cfg.COL_PIERRE_CHAUDE.darkened(0.35)
	sky_mat.ground_horizon_color = Cfg.COL_CIEL_HORIZON
	sky_mat.sky_curve = 0.11
	sky_mat.ground_curve = 0.2
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Cfg.COL_AMBIANTE_JOUR
	# 0,26 → 0,50 : c'est le réglage qui décide si une face non éclairée est
	# une forme lisible ou une tache noire. Sur téléphone, en extérieur, la
	# moitié de l'écran est en ombre portée — il faut qu'on y voie encore.
	env.ambient_light_energy = 0.4

	# ─── LE HALO EST RALLUMÉ SUR TÉLÉPHONE, ET C'ÉTAIT LE DÉFAUT MAJEUR ──
	#
	# Il était coupé dès que `est_mobile()` — donc sur la SEULE plateforme
	# visée. Conséquence : tous les effets de tir y étaient rendus à plat.
	# Un départ de coup n'était plus de la lumière, seulement une forme
	# colorée, et c'est exactement le reproche qu'on m'a fait : « pas
	# spectaculaire ». Aucune quantité de particules n'aurait compensé ça.
	#
	# Le raisonnement d'origine — « plusieurs passes en plein écran » —
	# datait d'avant Godot 4.3, qui rend le halo en Compatibility. Il est
	# donc branché sur la QUALITÉ et non sur la plateforme : un téléphone
	# qui peine passe en LOW et le perd, les autres le gardent.
	#
	# LE SEUIL RESTE À 1,0, et ce n'est pas un détail. Le sable ensoleillé
	# frôle 0,94 de luminance : au-dessous de 1,0, c'est tout le sol qui se
	# mettrait à luire et l'image deviendrait laiteuse. Les effets, eux,
	# émettent au-delà de 1 par construction — ce sont donc EUX, et eux
	# seuls, qui débordent.
	env.glow_enabled = Cfg.quality != Cfg.Quality.LOW
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 1.5
	env.glow_bloom = 0.28
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_strength = 1.25

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	# 0,52 → 0,58. L'ancienne exposition sous-exposait l'image : c'était la
	# cause principale du rendu terne. Mais 0,80, essayé d'abord, brûlait le
	# sable en crème et effaçait le relief des murets — vérifié en image.
	env.tonemap_exposure = 0.45

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.32
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
	env.fog_light_color = Cfg.COL_BRUME_JOUR
	# Densité abaissée avec la clarté : une brume claire ET dense efface les
	# silhouettes à quinze mètres, ce qui casserait la lisibilité du combat.
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_ambiance = we

	var sun := DirectionalLight3D.new()
	# Soleil relevé de 34° à 52° : un soleil rasant allonge des ombres qui
	# traversent tout l'écran et brouillent la lecture du sol. Plus haut, les
	# ombres sont courtes, nettes, et servent à ANCRER les objets au sol.
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Cfg.COL_SOLEIL_JOUR
	sun.light_energy = 1.0
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
	_soleil = sun

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
	# LES DEUX FACES SONT DESSINÉES, ET CE N'EST PAS UN CAPRICE.
	#
	# Écrite à la main, la nappe est sortie TOURNÉE VERS LE BAS : le moteur
	# l'écartait en entier et le sable lointain se voyait à travers. Rien
	# n'avait l'air cassé — c'est le pire des symptômes, et il m'a coûté
	# trois rendus avant que je pense à mettre le doute sur l'orientation
	# plutôt que sur la couleur. Plutôt que de raisonner une fois de plus
	# sur un sens de rotation, on retire la question : une nappe plate que
	# la caméra ne voit jamais par en dessous n'a rien à gagner au tri des
	# faces arrière.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for iz in NB_CELLULES:
		for ix in NB_CELLULES:
			var base := _base_cellule(ix, iz)
			var mi := MeshInstance3D.new()
			# NOMMÉE : c'est à ce nom qu'on reconnaît une dalle de sol
			# parmi les enfants d'une cellule, ce qui a servi à isoler une
			# panne d'affichage et resservira.
			mi.name = "Sol"
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
			var monde := PlanMonde.enrouler(base + local)
			var s := PlanMonde.secteur(PlanMonde.secteur_de(monde))
			var teinte: Color = s["sol"] if s.has("sol") else Cfg.SOL_ESPLANADE
			teintes.append(_ondulation(teinte, monde))
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


## MODULATION DU SABLE — ce qui empêche le sol d'être un aplat.
##
## LE DÉFAUT QUE CECI CORRIGE. Passer le monde entier en un seul biome
## règle le problème des six univers contradictoires, mais en crée un
## autre : six teintes de sable très proches donnent, vues de la caméra,
## un aplat beige de bord à bord. Le sol occupe les trois quarts de
## l'écran — un aplat sur les trois quarts de l'écran, c'est une carte qui
## paraît vide même quand elle est meublée.
##
## On module donc la CLARTÉ de chaque sommet, jamais sa teinte. Deux sinus
## de longues périodes font les ondulations de dune, un troisième beaucoup
## plus court fait le grain. L'amplitude reste sous les 7 % : de près on ne
## voit rien de particulier, de loin le sol respire et la distance
## parcourue se lit.
##
## LES PÉRIODES DIVISENT LE CÔTÉ DU MONDE. Sans cela l'ondulation ne se
## recollerait pas d'un bord à l'autre, et la couture qu'on passe tout ce
## fichier à masquer réapparaîtrait — une seule fois, en pleine lumière.
func _ondulation(teinte: Color, p: Vector2) -> Color:
	var dune := sin(p.x * TAU / 48.0 + p.y * TAU / 72.0) * 0.5 \
			+ sin(p.y * TAU / 36.0 - p.x * TAU / 144.0) * 0.35 \
			+ sin((p.x + p.y) * TAU / 18.0) * 0.15
	var f := dune * 0.068
	return teinte.lightened(f) if f > 0.0 else teinte.darkened(-f)


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
const FAMILLES_SOLIDES := [&"rocher", &"pilier", &"mur_bas", &"bloc",
		&"cristal_grand", &"arche_basse", &"borne"]
const RAYON_SOLIDE := {
	&"rocher": 0.95, &"pilier": 0.45, &"mur_bas": 1.05, &"bloc": 0.6,
	&"cristal_grand": 0.55, &"arche_basse": 1.4, &"borne": 0.28,
}
const HAUTEUR_SOLIDE := {
	&"rocher": 1.3, &"pilier": 3.4,
	# Le muret arrête les corps mais pas le regard : 1,1 m, sous la ligne
	# des yeux de la caméra. C'est toute la différence entre un abri et un
	# mur qui cache le combat.
	&"mur_bas": 1.1, &"bloc": 0.62,
	&"cristal_grand": 2.6, &"arche_basse": 2.4, &"borne": 1.5,
}
## Distance d'effacement par famille. Zéro = jamais effacé.
##
## RÈGLE : une famille solide n'a JAMAIS de portée. Un obstacle effacé au
## loin reste un obstacle — on se cognerait dans du vide.
const PORTEE := {
	&"caillou": 46.0, &"gravier": 34.0, &"plante": 50.0, &"cactus": 50.0,
	&"caisse": 62.0, &"dalle": 44.0, &"cristal": 58.0,
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
		_toit_boites.clear()
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
		# Le repère devient effaçable : c'est ce qui empêche son tablier ou
		# sa halle de remplir l'écran quand on passe dessous.
		_declarer_toit()
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
	# ÉCLAIRÉE, PAS EN APLAT. Un matériau de halo est non éclairé : la
	# sphère rendait alors un disque turquoise parfaitement plat, vérifié en
	# image — de près, une gommette collée sur le ciel. Un matériau éclairé
	# ET émissif garde les facettes visibles tout en brillant dans la
	# brume, ce qui est précisément le travail d'une balise.
	orbe.material_override = VisualKit.mat(Cfg.COL_TURQUOISE, 1.4, 0.3)
	orbe.position = base + Vector3(0, hauteur + 0.8, 0)
	orbe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ajouter(orbe)


func _bloc(taille: Vector3, pos: Vector3, teinte: Color, rot := 0.0,
		solide := true) -> void:
	var b := BoxMesh.new()
	b.size = taille
	_fondre(b, Transform3D(Basis.from_euler(Vector3(0, rot, 0)), pos), teinte)
	# Une pièce dont le dessous passe au-dessus des têtes est un TOIT : on
	# la retient pour pouvoir l'effacer quand on passera dessous.
	if pos.y - taille.y * 0.5 >= SOUS_TOIT:
		_toit_boites.append({"taille": taille, "pos": pos, "rot": rot})
	if not solide:
		return
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = taille
	shape.shape = cb
	shape.position = pos
	shape.rotation.y = rot
	_obstacles.add_child(shape)


## LE PILIER SOLAIRE — le repère principal du monde, et le plus haut.
##
## LA PLANCHE EN FAIT SON SUJET CENTRAL, ET ELLE A RAISON. Sur un monde qui
## s'enroule, aucun bord ne dit où l'on est : il faut UNE silhouette qu'on
## reconnaisse à cent mètres et sous n'importe quel angle. Un obélisque
## étagé la donne — chaque étage plus étroit que le précédent, un liseré
## d'or à chaque rupture, un cœur turquoise au sommet.
##
## Il est ÉTROIT. Une tour massive de dix-sept mètres au milieu du secteur
## le plus dégagé masquerait justement ce qu'on vient y voir : les autres.
func _poi_tour(base: Vector3) -> void:
	var pierre := Cfg.COL_PIERRE_CREME
	var ombre := Cfg.COL_PIERRE_OMBRE
	# Socle large, en deux marches : c'est lui qui donne l'assise. Sans
	# marches, un fût planté dans le sable a l'air posé, pas bâti.
	_bloc(Vector3(9.0, 0.7, 9.0), base + Vector3(0, 0.35, 0), ombre, 0.0, false)
	_bloc(Vector3(7.0, 0.6, 7.0), base + Vector3(0, 1.0, 0), pierre, 0.0, false)
	# Fût étagé : quatre tronçons de moins en moins larges, chacun coiffé
	# d'un bandeau d'or. C'est le biseau de la planche, répété — la seule
	# règle de forme qui tient toute l'unité de la carte.
	var y := 1.3
	var large := 3.2
	for etage in 4:
		var h := 3.6 - etage * 0.35
		_bloc(Vector3(large, h, large), base + Vector3(0, y + h * 0.5, 0),
				pierre if etage % 2 == 0 else ombre, 0.0, etage == 0)
		y += h
		_bloc(Vector3(large + 0.5, 0.28, large + 0.5), base + Vector3(0, y, 0),
				Cfg.COL_OR, 0.0, false)
		y += 0.28
		large -= 0.5
	# Quatre contreforts cobalt en bas : ils ancrent la base et donnent au
	# pilier la seule touche froide qui le détache d'un ciel chaud.
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		_bloc(Vector3(0.8, 4.2, 0.8), base + d * 2.4 + Vector3(0, 2.1, 0),
				Cfg.COL_COBALT, a, false)
	# Cœur d'énergie au sommet : c'est lui qu'on voit percer la brume.
	var noyau := MeshInstance3D.new()
	var oct := SphereMesh.new()
	oct.radius = 1.0
	oct.height = 2.6
	oct.radial_segments = 6
	oct.rings = 3
	noyau.mesh = oct
	noyau.material_override = VisualKit.mat(Cfg.COL_TURQUOISE, 1.6, 0.28)
	noyau.position = base + Vector3(0, y + 1.4, 0)
	noyau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ajouter(noyau)


## L'ARCHE ANCIENNE — une arche que l'on franchit PAR-DESSOUS.
##
## Le passage obligé est le vrai sujet : il fabrique des rencontres, ce
## qu'aucun décor purement visuel ne fait.
func _poi_pont(base: Vector3) -> void:
	var pierre := Cfg.COL_PIERRE_CREME
	var ombre := Cfg.COL_PIERRE_OMBRE
	for cote in [-1.0, 1.0]:
		# Pile en deux volumes : un fût, puis un chapiteau plus large. Le
		# ressaut est ce qui distingue une pile bâtie d'un bloc dressé.
		_bloc(Vector3(3.0, 7.2, 5.0), base + Vector3(cote * 6.0, 3.6, 0), ombre)
		_bloc(Vector3(3.6, 0.8, 5.6), base + Vector3(cote * 6.0, 7.6, 0),
				pierre, 0.0, false)
		_bloc(Vector3(3.2, 0.3, 5.2), base + Vector3(cote * 6.0, 8.15, 0),
				Cfg.COL_OR, 0.0, false)
	# Tablier en trois segments légèrement cintrés : trois boîtes suffisent
	# à faire lire une arche, là où une vraie courbe coûterait une géométrie
	# sur mesure pour un gain nul à cette distance.
	_bloc(Vector3(6.0, 1.4, 5.2), base + Vector3(-3.6, 8.6, 0), pierre, 0.0, false)
	_bloc(Vector3(6.0, 1.4, 5.2), base + Vector3(3.6, 8.6, 0), pierre, 0.0, false)
	_bloc(Vector3(4.4, 1.6, 5.2), base + Vector3(0, 9.1, 0), pierre, 0.0, false)
	_bloc(Vector3(15.0, 0.8, 0.6), base + Vector3(0, 10.2, 2.4),
			Cfg.COL_COBALT, 0.0, false)
	_bloc(Vector3(15.0, 0.8, 0.6), base + Vector3(0, 10.2, -2.4),
			Cfg.COL_COBALT, 0.0, false)
	# Clé de voûte dorée : le point que l'œil accroche sous l'arche, et le
	# seul détail qui dise que ce pont a été CONSTRUIT.
	_bloc(Vector3(1.6, 0.6, 5.4), base + Vector3(0, 8.0, 0), Cfg.COL_OR, 0.0, false)


## LE TEMPLE ENSABLÉ — des colonnes émergeant de l'oasis.
##
## Le seul volume bâti du secteur, donc son unique repère. Il est
## volontairement INCOMPLET : une ruine se lit à ce qui lui manque.
func _poi_temple(base: Vector3) -> void:
	var pierre := Cfg.COL_PIERRE_CREME
	var ombre := Cfg.COL_PIERRE_OMBRE
	_bloc(Vector3(13.0, 0.8, 13.0), base + Vector3(0, 0.4, 0), ombre, 0.0, false)
	_bloc(Vector3(10.0, 0.6, 10.0), base + Vector3(0, 1.0, 0), pierre, 0.0, false)
	var debout := [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4),
			Vector2(4, 4), Vector2(0, -4.6)]
	for i in debout.size():
		var c: Vector2 = debout[i]
		var h := 6.5 if i < 3 else 3.4     # deux colonnes brisées
		_bloc(Vector3(1.0, h, 1.0), base + Vector3(c.x, 1.3 + h * 0.5, c.y),
				pierre)
		# Bague d'or à la cassure ou au chapiteau : c'est elle qui empêche
		# une colonne claire de se fondre dans un ciel clair.
		_bloc(Vector3(1.3, 0.24, 1.3), base + Vector3(c.x, 1.3 + h, c.y),
				Cfg.COL_OR, 0.0, false)
	_bloc(Vector3(10.4, 0.9, 2.2), base + Vector3(0, 8.3, -4.0), pierre, 0.0, false)
	# Un fragment de linteau tombé au sol : c'est ce détail qui raconte que
	# le lieu s'est effondré, et non qu'il a été bâti comme ça.
	_bloc(Vector3(3.2, 0.9, 1.9), base + Vector3(2.6, 1.8, 3.4), ombre, 0.5)


## LE HANGAR COBALT — la seule grande masse bleue de la carte.
##
## POURQUOI IL EST BLEU ALORS QUE TOUT LE RESTE EST SABLE. Un monde d'une
## seule matière devient illisible : il faut UN contrepoint froid, un seul,
## assez grand pour servir de repère et assez rare pour ne pas casser
## l'unité. Ce hangar le porte, et le champ de cristaux qui l'entoure le
## prolonge en petit.
func _poi_depot(base: Vector3) -> void:
	var cobalt := Cfg.COL_COBALT
	var clair := Cfg.COL_COBALT_CLAIR
	_bloc(Vector3(16.0, 0.5, 12.0), base + Vector3(0, 0.25, 0),
			Cfg.COL_PIERRE_OMBRE, 0.0, false)
	# DES PILES, PAS DEUX MURS PLEINS. Deux parois de 12 m faisaient de la
	# halle une boîte : on n'y voyait pas au travers, donc on ne savait pas
	# s'il y avait quelqu'un dedans avant d'y entrer. Trois piles par côté
	# laissent voir à travers le bâtiment tout en gardant les mêmes appuis.
	for cote in [-1.0, 1.0]:
		for k in 3:
			_bloc(Vector3(1.1, 7.0, 2.6),
					base + Vector3(cote * 7.6, 3.5, (k - 1) * 4.6), cobalt)
		# UN CHAPITEAU PAR PILE, ET NON UNE POUTRE CONTINUE. La poutre
		# faisait 12,4 m de long sur 1,4 m de large : vérifiée en image,
		# elle sortait comme une barre jaune vif traversant tout l'écran.
		# La règle de la planche est « l'or par touches » — une poutre de
		# douze mètres n'est pas une touche, c'est une façade.
		for k in 3:
			_bloc(Vector3(1.3, 0.22, 2.8),
					base + Vector3(cote * 7.6, 7.15, (k - 1) * 4.6),
					Cfg.COL_OR, 0.0, false)
	# TOIT À LANTERNEAU, PAS UN PLATEAU. Premier jet : une dalle de
	# 17 × 13 m d'un bleu uni, vérifiée en image — de la caméra de jeu, elle
	# lisait comme un plateau de table posé sur quatre pieds. Deux versants
	# bas et une travée centrale SURÉLEVÉE, portée par un bandeau clair,
	# donnent une échelle au bâtiment et le font lire comme une halle.
	for cote in [-1.0, 1.0]:
		_bloc(Vector3(17.0, 0.6, 4.4), base + Vector3(0, 7.6, cote * 4.3),
				cobalt, 0.0, false)
	# Le bandeau du lanterneau : c'est la seule bande vraiment claire du
	# bâtiment, et elle court sur toute sa longueur — de loin, c'est elle
	# qu'on reconnaît.
	_bloc(Vector3(17.0, 0.9, 4.4), base + Vector3(0, 8.35, 0), clair, 0.0, false)
	_bloc(Vector3(17.2, 0.5, 4.6), base + Vector3(0, 8.95, 0), cobalt, 0.0, false)
	# PAS DE LISERÉ D'OR SUR LES JOINTS DU TOIT. Il y en avait un de chaque
	# côté du lanterneau, longs de 17 m : deux lignes jaunes qui coupaient
	# tout le bâtiment. Le décrochement du lanterneau donne déjà la ligne
	# horizontale ; l'or ajouté par-dessus ne dessinait plus rien, il
	# répétait.
	# Un pignon ouvert d'un côté : on peut entrer, donc s'y battre.
	_bloc(Vector3(16.0, 5.0, 0.6), base + Vector3(0, 3.5, -6.0), cobalt)
	_bloc(Vector3(12.0, 0.4, 0.7), base + Vector3(0, 5.4, -6.0),
			Cfg.COL_OR, 0.0, false)
	# Mât d'antenne et son bras : la verticale qui dépasse du toit et fait
	# reconnaître le hangar de loin, quand la halle elle-même est masquée.
	var mat := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = 0.4
	c.top_radius = 0.3
	c.height = 9.0
	c.radial_segments = 6
	mat.mesh = c
	mat.material_override = VisualKit.mat(clair, 0.0, 0.7)
	mat.position = base + Vector3(9.5, 4.5, 4.0)
	_ajouter(mat)
	_bloc(Vector3(4.6, 0.26, 0.4), base + Vector3(7.6, 8.8, 4.0), Cfg.COL_OR,
			0.0, false)
	var feu := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.42
	s.height = 0.84
	s.radial_segments = 6
	s.rings = 4
	feu.mesh = s
	feu.material_override = VisualKit.mat(Cfg.COL_TURQUOISE, 1.5, 0.3)
	feu.position = base + Vector3(9.5, 9.3, 4.0)
	feu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ajouter(feu)


## LE PORTAIL BRISÉ — un anneau de pierre tombé de travers.
##
## L'INCLINAISON est tout le sujet. Posé droit, c'est une porte ; planté en
## biais et à demi enfoncé dans le sable, c'est un accident, et une
## silhouette qu'on ne confond avec rien d'autre sur la carte.
func _poi_carcasse(base: Vector3) -> void:
	var pierre := Cfg.COL_PIERRE_CREME
	var ombre := Cfg.COL_PIERRE_OMBRE
	# L'ANNEAU EST FAIT DE DOUZE SEGMENTS DROITS, et c'est délibéré. Un tore
	# lisse jurerait au milieu d'un monde entièrement facetté ; douze
	# facettes se lisent comme un anneau et restent dans la langue de la
	# planche.
	var incline := Basis.from_euler(Vector3(0.38, 0.6, 0.24))
	var rayon := 5.4
	# LE SEGMENT EST TANGENT, PAS RADIAL, et c'est tout le sujet. Premier
	# jet : le grand axe des boîtes pointait vers le centre — vérifié en
	# image, l'anneau sortait en ÉTOILE, douze dalles plantées en rayons
	# avec deux mètres de vide entre chacune. Le pas angulaire vaut
	# 2 π R ⁄ 12 ≈ 2,8 m : c'est la longueur que le segment doit couvrir,
	# et la tourner de `a` au lieu de `a + 90°` suffit à l'y mettre.
	var pas := TAU * rayon / 12.0
	for i in 12:
		var a := TAU * float(i) / 12.0
		var local := Vector3(cos(a) * rayon, sin(a) * rayon, 0.0)
		var b := BoxMesh.new()
		# Léger recouvrement (+8 %) : sans lui, les arêtes des segments
		# laissent voir le ciel entre eux dès qu'on tourne autour.
		b.size = Vector3(1.15, pas * 1.08, 1.5)
		# FONDU, PAS POSÉ. Douze MeshInstance3D distincts pour un seul objet
		# décoratif, c'est douze instances de plus sur le compteur qui a
		# déjà tué le rendu web une fois. Deux teintes seulement : elles se
		# fondent en deux maillages, quel que soit le nombre de segments.
		_fondre(b, Transform3D(
				incline * Basis.from_euler(Vector3(0, 0, a)),
				base + Vector3(0, 4.4, 0) + incline * local),
				pierre if i % 2 == 0 else ombre)
	# Le disque d'énergie qui reste allumé dans l'anneau : la seule vraie
	# tache turquoise des ruines, et ce qui dit que le portail fonctionne
	# encore.
	var voile := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 4.7
	cyl.top_radius = 4.7
	cyl.height = 0.14
	cyl.radial_segments = 12
	voile.mesh = cyl
	voile.material_override = VisualKit.glow_mat(Cfg.COL_TURQUOISE, 1.5, 0.42)
	voile.transform = Transform3D(
			incline * Basis.from_euler(Vector3(PI * 0.5, 0, 0)),
			base + Vector3(0, 4.4, 0))
	voile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ajouter(voile)
	# Collision : une seule boîte au pied de l'anneau. On contourne le
	# portail, on ne le traverse pas.
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(9.0, 5.0, 3.0)
	shape.shape = cb
	shape.position = base + Vector3(0, 2.5, 0)
	shape.rotation.y = 0.6
	_obstacles.add_child(shape)

	# Deux fragments de l'anneau plantés dans le sol autour de lui.
	_bloc(Vector3(4.4, 0.9, 1.4), base + Vector3(-5.4, 0.9, 3.6), ombre, 0.9)
	_bloc(Vector3(3.4, 0.9, 1.4), base + Vector3(5.0, 0.7, -3.6), ombre, -0.6)
	# Traînée de dalles descellées : elle dit d'où le portail est tombé.
	for i in 4:
		_bloc(Vector3(3.4 - i * 0.5, 0.3, 2.2),
				base + Vector3(7.0 + i * 4.0, 0.16, -5.0 - i * 2.6),
				Cfg.SOL_RUINES.darkened(0.16), -0.5 + i * 0.1, false)

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
	_toit_boites.clear()
	_ouvrir_fusion()
	for piece in PlanArene.STRUCTURES:
		_poser(piece, Cfg.COL_PIERRE_CREME)
	for piece in PlanArene.ABRIS:
		_poser(piece, Cfg.COL_COBALT)
	var pas := 2 if Cfg.quality == Cfg.Quality.LOW else 1
	var i := 0
	for piece in PlanArene.GARNITURE:
		if i % pas == 0:
			_poser(piece, Cfg.COL_PIERRE_OMBRE, false)
		i += 1
	_fermer_fusion()
	_declarer_toit()
	_groupe = null


# --- TOITS ----------------------------------------------------------------
#
# LE DÉFAUT QUE CECI CORRIGE, ET POURQUOI IL A TENU SI LONGTEMPS.
#
# Un écran entièrement opaque a été signalé cinq fois depuis un téléphone,
# et huit sondes ne l'ont pas reproduit. La cause tient dans une phrase de
# la fiche du pont : « une arche que l'on franchit PAR-DESSOUS ». Son
# tablier est à 8,3 m, la caméra de jeu à 10,4 m. Franchir l'arche met donc
# le tablier et ses deux piles entre la caméra et le joueur, et l'écran se
# remplit de pierre. Vérifié en image, au placement EXACT de la caméra de
# jeu : plus de sol, plus de ciel, plus de personnage.
#
# La halle du Dépôt, le temple et la Place posent le même problème. Ce sont
# tous des lieux CONÇUS pour qu'on passe dessous — le défaut est donc dans
# la caméra, pas dans le niveau.
#
# POURQUOI LES SONDES NE L'ONT PAS VU. Elles cherchaient au RAYON, sur la
# couche du monde. Or les tabliers sont bâtis en pièces NON SOLIDES, pour
# qu'on puisse passer dessous : aucun rayon ne les rencontre. L'instrument
# était aveugle exactement à la géométrie qui produit le défaut.
#
# POURQUOI LE DÉGAGEMENT NE SUFFISAIT PAS. La caméra sait se rapprocher
# quand le joueur est masqué, mais jamais en dessous de 80 % de son recul —
# un plancher mesuré, qui évite les plongeons incessants. Or il faudrait
# descendre à 59 % pour passer sous un tablier à 8,3 m. Le garde-fou
# existait ; il ne pouvait simplement pas aller assez loin.
#
# CE QU'ON FAIT À LA PLACE, et c'est la solution du genre : on n'évite pas
# le toit, ON L'EFFACE. Chaque repère reçoit un volume invisible sur une
# couche à lui ; quand le rayon qui va du joueur à la caméra le traverse,
# les maillages du repère passent en fantôme. Le joueur se voit à travers
# la structure, qui reste lisible en transparence.

## Hauteur du dessous d'une pièce à partir de laquelle elle devient un
## toit : au-dessus des têtes, donc entre le joueur et sa caméra.
const SOUS_TOIT := 2.6

## Repères effaçables : volumes, maillages, et leurs deux tenues.
var _toits: Array[Dictionary] = []
var _toit_voile := -1
## Pièces en surplomb du repère en cours de construction.
var _toit_boites: Array[Dictionary] = []


## Déclare le repère courant comme effaçable, d'après SES pièces en
## surplomb.
##
## LE VOLUME DESCEND JUSQU'AU SOL, et c'est le point délicat.
##
## Un premier jet n'a retenu que la pièce elle-même — le tablier, à 8,3 m.
## Le rayon qui va du joueur à sa caméra passe alors SOUS le tablier et ne
## le rencontre jamais : la caméra est en arrière, pas au-dessus. Or l'écran
## était bel et bien plein, non pas d'une chose entre les deux, mais de la
## STRUCTURE ENTIÈRE — les deux piles de part et d'autre, le tablier
## au-dessus. On est dedans.
##
## Chaque surplomb devient donc une colonne descendant jusqu'au sol : y
## être, c'est être sous un toit. Un second jet avait pris un cylindre
## couvrant tout le repère, mais il effaçait la tour de guet dès qu'on
## passait à dix mètres, en plein air — le repère du monde devenait
## fantôme sans raison.
func _declarer_toit() -> void:
	if _groupe == null or _toit_boites.is_empty():
		_toit_boites.clear()
		return
	var maillages: Array[MeshInstance3D] = []
	var pleins: Array[Material] = []
	var fantomes: Array[Material] = []
	for enfant in _groupe.get_children():
		var mi := enfant as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		maillages.append(mi)
		pleins.append(mi.material_override)
		fantomes.append(_fantome(mi.material_override))
	if maillages.is_empty():
		_toit_boites.clear()
		return

	var corps := StaticBody3D.new()
	corps.collision_layer = Cfg.LAYER_TOIT
	# Il ne DÉTECTE rien : il se contente d'être détecté par la caméra. Ni
	# les corps ni les tirs ne le rencontrent — on passe toujours dessous.
	corps.collision_mask = 0
	for b: Dictionary in _toit_boites:
		var taille: Vector3 = b["taille"]
		var pos: Vector3 = b["pos"]
		var haut: float = pos.y + taille.y * 0.5
		var forme := CollisionShape3D.new()
		var boite := BoxShape3D.new()
		# Un peu débordant en plan : on veut effacer AVANT que la pierre ne
		# remplisse le cadre, pas au moment où elle le remplit déjà.
		boite.size = Vector3(taille.x + 1.6, haut, taille.z + 1.6)
		forme.shape = boite
		forme.position = Vector3(pos.x, haut * 0.5, pos.z) - _groupe.position
		forme.rotation.y = float(b["rot"])
		corps.add_child(forme)
	_groupe.add_child(corps)
	_toit_boites.clear()

	_toits.append({"corps": corps, "maillages": maillages,
			"pleins": pleins, "fantomes": fantomes})


## Version translucide d'un matériau de décor.
##
## ON PRÉPARE LA TENUE DE RECHANGE À LA CONSTRUCTION. Fabriquer un matériau
## au moment où l'on passe sous le pont provoquerait une compilation de
## shader en pleine partie, c'est-à-dire un à-coup à l'endroit précis où
## l'on veut que rien ne bouge.
static func _fantome(plein: Material) -> Material:
	var src := plein as StandardMaterial3D
	if src == null:
		return plein
	var m: StandardMaterial3D = src.duplicate()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.22
	# Sans cela, les faces arrière se dessinent par-dessus les faces avant
	# et le fantôme devient une bouillie.
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## Voile le repère désigné par un corps, et RÉTABLIT tous les autres.
##
## Un seul repère est voilé à la fois : la caméra ne regarde qu'à un
## endroit, et rétablir systématiquement les autres évite qu'un repère
## reste fantôme parce qu'on s'en est éloigné trop vite.
##
## ON VOILE TOUT DE SUITE, ON RÉTABLIT AVEC RETARD, et ce n'est pas une
## coquetterie. Le rayon de la caméra est binaire : au ras d'un volume, un
## pas de côté de dix centimètres le fait entrer et sortir, et la structure
## se mettrait à clignoter entre pleine et fantôme. La publication l'a
## attrapé avant le joueur — la barrière des repères a signalé un toit
## traversé mais non effacé sur une machine chargée, c'est-à-dire ce
## clignotement pris sur le fait.
##
## Le retard rend aussi la règle vraie EN TOUTES CIRCONSTANCES : la caméra
## lance son rayon avant que l'arène n'ait replacé ses groupes pour l'image
## en cours, donc elle raisonne toujours sur une image de retard. Un répit
## d'un tiers de seconde couvre largement cet écart.
const REPIT_TOIT := 0.35
var _repit := 0.0

func voiler_toit(corps: Node) -> void:
	var cible := -1
	for i in _toits.size():
		if _toits[i]["corps"] == corps:
			cible = i
			break
	if cible < 0:
		# Plus rien devant le regard : on laisse au répit le soin de décider.
		return
	_repit = REPIT_TOIT
	if cible == _toit_voile:
		return
	_appliquer_toit(_toit_voile, false)
	_toit_voile = cible
	_appliquer_toit(cible, true)


func devoiler_toits() -> void:
	if _toit_voile < 0:
		return
	# Le décompte tourne dans `_process` ; ici on ne fait que constater
	# qu'aucun toit n'est devant le regard à cette image.
	if _repit <= 0.0:
		_appliquer_toit(_toit_voile, false)
		_toit_voile = -1


func _appliquer_toit(i: int, fantome: bool) -> void:
	if i < 0 or i >= _toits.size():
		return
	var t: Dictionary = _toits[i]
	var maillages: Array = t["maillages"]
	var tenue: Array = t["fantomes"] if fantome else t["pleins"]
	for k in maillages.size():
		var mi: MeshInstance3D = maillages[k]
		if is_instance_valid(mi):
			mi.material_override = tenue[k]


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

## APRON DALLÉ au pied d'une pièce de l'Esplanade.
##
## Trente d'entre elles, chacune avec son propre matériau lumineux : trente
## appels de dessin pour un liseré décoratif, mesuré. Elles sont maintenant
## fondues avec les autres — deux maillages, un par couleur.
##
## RENDUES AU TÉLÉPHONE. Elles en étaient coupées du temps où chacune
## coûtait son propre appel de dessin ; fondues, les trente n'en coûtent
## plus que deux, et elles sont devenues le dallage qui donne son nom à
## l'Esplanade. Couper sur mobile ce qui ne coûte rien et porte la
## direction artistique n'a plus de sens.
func _flaque(pos: Vector3, taille: Vector3, rot: float) -> void:
	var b := BoxMesh.new()
	b.size = Vector3(taille.x + 0.5, 0.02, taille.z + 0.5)
	# NON ÉMISSIF, ET C'EST LE CORRECTIF. Ces liserés étaient des néons :
	# transposés tels quels en turquoise, ils sortaient — vérifié en image —
	# comme des flaques d'eau lumineuses sous chaque abri, une trentaine de
	# taches brillantes sur une esplanade en plein soleil. Ce ne sont pas
	# des néons ici, ce sont des DALLES : de la pierre posée au pied de
	# chaque volume, plus claire que le sol, qui dit « bâti » sans briller.
	#
	# Or sur les hauts volumes, pierre claire sur les bas : deux couleurs,
	# donc deux maillages fondus, et l'œil apprend en une partie que le
	# doré marque ce qui dépasse.
	var couleur := Cfg.COL_OR if taille.y > 3.0 else Cfg.COL_PIERRE_CREME
	_fondre(b, Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
			pos + Vector3(0, 0.05, 0)), couleur)

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
## POSITION DÉGAGÉE — porte d'entrée PUBLIQUE de la recherche d'espace
## libre. `_degager` fait le travail depuis toujours, mais il était privé et
## les nouveaux venus (l'étoile WANTED et ses points d'apparition) auraient
## dû aller le chercher dans le dos de l'arène.
##
## Rendre la fonction publique plutôt que la recopier : le monde sait seul
## où se trouvent ses obstacles, et deux versions de cette réponse
## finiraient par diverger.
func position_degagee(p: Vector3, rayon: float) -> Vector3:
	return _degager(p, rayon)


## La position est-elle libre de tout obstacle solide ? Réponse franche,
## sans déplacement — pour VÉRIFIER un point plutôt que le corriger.
func position_libre(p: Vector3, rayon: float) -> bool:
	return _libre_monde(Vector2(p.x, p.z), rayon)


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
	# EN ARÈNE DE COMBAT, LES DIX POSITIONS SONT ÉCRITES À LA MAIN et on
	# les consomme dans l'ordre. Le choix « au foyer le plus proche d'un
	# joueur, à 26 m environ » est réglé pour un monde de 144 m ; sur 40 m
	# aucun point n'est à 26 m de qui que ce soit, et le score deviendrait
	# arbitraire. Or ce qu'on veut ici est précisément l'inverse d'un
	# choix : que les mobs soient là où le plan les a mis.
	if Cfg.arene_test:
		if mob_spawn_points.is_empty():
			return Vector3.ZERO
		var p := mob_spawn_points[_index_mob_test % mob_spawn_points.size()]
		_index_mob_test += 1
		return p
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


# --- ARÈNE DE COMBAT -----------------------------------------------------
#
# BÂTIE PIÈCE PAR PIÈCE DEPUIS `PlanAreneTest`, sans une seule ligne de
# semis. Ce bloc est délibérément court : toute la réflexion de level
# design vit dans le plan, ici on ne fait que poser.

## Bord de l'arène : au-delà, un mur invisible. Il est à un mètre du bord
## déclaré pour que le joueur ne colle jamais la limite exacte.
const MARGE_BORD := 1.0


func _batir_arene_test() -> void:
	_sol_arene_test()
	_groupe = null
	for piece: Dictionary in PlanAreneTest.toutes_les_pieces():
		_poser_arene_test(piece)
	_mur_arene_test()

	player_spawn_points.clear()
	for p: Vector3 in PlanAreneTest.APPARITIONS:
		player_spawn_points.append(p)
	mob_spawn_points.clear()
	for p: Vector3 in PlanAreneTest.positions_mobs():
		mob_spawn_points.append(p)


## LE SOL : UNE SEULE DALLE, UNE SEULE COULEUR, AUCUN MOTIF.
##
## POURQUOI PAS LA MOSAÏQUE DU MONDE. Le sol du monde ouvert est un
## assemblage de trente-six dalles à couleurs de sommets, avec ondulation
## de dune et frontières de secteur qui se fondent. C'est ce qu'il faut
## pour donner de la distance à 144 m. Sur 40 m, c'est exactement le
## contraire du besoin : le sol doit être un FOND, c'est-à-dire la seule
## surface de l'écran dont on n'a rien à lire. Tout motif y entre en
## concurrence avec les silhouettes qu'on doit repérer en une fraction de
## seconde.
##
## Une dalle, une teinte sable claire et chaude, et c'est tout.
func _sol_arene_test() -> void:
	# LE SOL DÉBORDE TRÈS LARGEMENT L'ARÈNE, et ce n'est pas du gaspillage.
	#
	# Premier jet : une dalle de 46 m pour une arène de 40. Vérifié en
	# image depuis la caméra de jeu, posée dans un bastion d'angle — le
	# BORD DE LA DALLE entrait dans le cadre, et l'on voyait le vide
	# derrière. Une arène dont on aperçoit la fin du monde cesse d'être un
	# lieu. Le sol va donc jusqu'à 120 m : la caméra n'en voit jamais la
	# limite, et cela ne coûte rien — c'est une seule boîte, un seul appel
	# de dessin, quelle que soit sa taille.
	#
	# Les murs invisibles, eux, restent à 20 m : c'est l'arène qui borne le
	# jeu, pas le sol qui borne le regard.
	var cote := 120.0
	var mi := MeshInstance3D.new()
	mi.name = "Sol"
	var b := BoxMesh.new()
	b.size = Vector3(cote, 0.5, cote)
	mi.mesh = b
	# SABLE ÉCLAIRCI ET ADOUCI. Celui du monde ouvert (e2b968) est réglé
	# pour une carte qu'on traverse ; sur une arène où l'œil ne quitte
	# jamais le sol, ce jaune saturé fatigue et concurrence les props. Un
	# fond se remarque par son silence.
	mi.material_override = VisualKit.mat(Color("ecd7a4"), 0.0, 0.95)
	# Le dessus de la dalle affleure y = 0 : les pièces sont posées dessus.
	# LE DESSUS DU SOL EST HUIT MILLIMÈTRES SOUS ZÉRO, et c'est le
	# correctif anti-scintillement de toute la carte, en un seul nombre.
	#
	# Caisses, tonneaux, bottes, murets et poteaux sont posés base à y = 0
	# — c'est la façon naturelle de les écrire. Leur face inférieure était
	# donc COPLANAIRE avec le sol : les deux surfaces se disputent le même
	# pixel, et laquelle gagne dépend de l'angle de la caméra. Le prop
	# clignote dès qu'on bouge, et jamais sur une capture fixe.
	#
	# Descendre le SOL plutôt que lever chaque pièce règle le cas une fois
	# pour toutes, y compris pour les pièces qu'on ajoutera plus tard sans
	# y penser. Huit millimètres sont sous le seuil du visible depuis dix
	# mètres de haut.
	mi.position = Vector3(0, -0.258, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cote, 0.5, cote)
	col.shape = box
	# La COLLISION, elle, reste à zéro : c'est le sol sur lequel on marche,
	# et le décaler ferait flotter les personnages de huit millimètres.
	col.position = Vector3(0, -0.25, 0)
	_obstacles.add_child(col)



## LA NAPPE DE DALLES — ce qui sort l'aire de jeu de l'aplat.
##
## Un seul aplat de sable sur quatre-vingts mètres ne donne AUCUN repère :
## le joueur ne voit pas qu'il avance, et les distances deviennent
## illisibles. La maquette ne fait pas ça — elle montre un sol craquelé en
## plaques, chacune d'une valeur légèrement différente.
##
## POURQUOI DES COULEURS DE SOMMET ET PAS DES PLAQUES POSÉES DESSUS. Une
## plaque posée sur le sol serait COPLANAIRE avec lui, et c'est exactement
## le défaut de scintillement que le décalage de huit millimètres a coûté
## cher à corriger. Ici il n'y a qu'un seul maillage : la variation est
## portée par la couleur des sommets, donc aucune surface n'en dispute une
## autre. Un matériau, un appel de rendu, environ seize cents triangles.
func _dalles_western() -> void:
	# UNE SEULE NAPPE, D'UN BORD À L'AUTRE DU MONDE.
	#
	# La version précédente en faisait deux : une fine sur l'aire de jeu,
	# une grossière au loin. Leurs grilles n'étaient pas alignées, et il
	# restait entre elles un ANNEAU DE VIDE de douze mètres — un trou par
	# lequel on voyait le fond de la scène, et au-dessus duquel les mesas
	# de l'horizon avaient l'air de flotter. Deux grilles, c'est une
	# couture ; une couture, c'est un défaut qui attend.
	#
	# Vingt-deux mille triangles pour une seule maille et un seul appel de
	# rendu : sur un téléphone, c'est moins cher qu'une couture à corriger.
	const PORTEE := 112.0
	const PAS := 3.0
	const GIGUE := 0.85
	var n := int(PORTEE * 2.0 / PAS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4477

	# LES SOMMETS SONT DÉPLACÉS AVANT D'ÊTRE UTILISÉS, ET C'EST TOUT
	# L'INTÉRÊT DE LA NAPPE.
	#
	# Une grille régulière donne un damier de cuisine — c'est ce qu'a
	# rendu le premier essai. En bougeant chaque NOEUD de la grille d'un
	# tirage partagé par les quatre dalles qui s'y touchent, les dalles
	# deviennent des quadrilatères irréguliers qui se raccordent quand
	# même sans trou. C'est la craquelure de la maquette.
	var noeuds: Array = []
	for ix in n + 1:
		var colonne: Array = []
		for iz in n + 1:
			colonne.append(Vector2(
					-PORTEE + float(ix) * PAS + rng.randf_range(-GIGUE, GIGUE),
					-PORTEE + float(iz) * PAS + rng.randf_range(-GIGUE, GIGUE)))
		noeuds.append(colonne)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in n:
		for iz in n:
			var a2: Vector2 = noeuds[ix][iz]
			var b2: Vector2 = noeuds[ix + 1][iz]
			var c2: Vector2 = noeuds[ix + 1][iz + 1]
			var d2: Vector2 = noeuds[ix][iz + 1]
			var m2: Vector2 = (a2 + b2 + c2 + d2) * 0.25
			var teinte: Color = W_DALLES[rng.randi_range(0, 3)]
			# AU-DELÀ DE L'AIRE DE JEU, LE SOL SE TAIT. Les dalles se
			# fondent progressivement dans le sable sourd du lointain :
			# l'arène doit rester l'îlot clair de l'image, et un sol
			# craquelé jusqu'à l'horizon lui volerait l'attention.
			var loin: float = clampf((m2.length() - 44.0) / 26.0, 0.0, 1.0)
			teinte = teinte.lerp(W_SABLE, loin * 0.85)
			# Le centre porte la teinte pleine, les coins une version
			# assombrie : le dégradé entre les deux creuse un joint sombre
			# le long de chaque bord, sans une seule texture.
			var bord := teinte.darkened(0.13 * (1.0 - loin * 0.8))
			var m := Vector3(m2.x, 0.0, m2.y)
			for paire in [[a2, b2], [b2, c2], [c2, d2], [d2, a2]]:
				st.set_normal(Vector3.UP)
				st.set_color(teinte)
				st.add_vertex(m)
				for k in 2:
					var v: Vector2 = paire[1 - k]
					st.set_normal(Vector3.UP)
					st.set_color(bord)
					st.add_vertex(Vector3(v.x, 0.0, v.y))

	var mi := MeshInstance3D.new()
	mi.name = "Sol"
	mi.mesh = st.commit()
	var mat := VisualKit.mat(Color.WHITE, 0.0, 0.95)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	# Huit millimètres sous les pieds des props : la seule marge qui
	# compte encore, puisqu'il n'y a plus qu'un plan de sol.
	mi.position = Vector3(0, -0.008, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## POSE UNE PIÈCE, ET LA LÈVE DE DOUZE MILLIMÈTRES.
##
## LA LEVÉE EST LE CORRECTIF ANTI-SCINTILLEMENT. PropKit pose chaque modèle
## pieds à y = 0, donc sa face inférieure exactement dans le plan du sol.
## Deux surfaces coplanaires se disputent le même pixel, et le gagnant
## dépend de l'arrondi de la profondeur : la pièce clignote dès que la
## caméra bouge. Douze millimètres les départagent sans qu'on voie rien
## flotter depuis dix mètres de haut.
func _poser_arene_test(piece: Dictionary) -> void:
	var plan_pos: Vector2 = piece["pos"]
	var taille: Vector3 = piece["taille"]
	var rendu := PropKit.instancier(piece["modele"], taille,
			piece.get("teinte", Cfg.COL_PIERRE_CREME))
	var noeud: Node3D = rendu["noeud"]
	var reelle: Vector3 = rendu["taille"]
	# NOMMÉE PAR SON MODÈLE. Sans cela, une anomalie signalée par la sonde
	# de scintillement s'appelle « @Node3D@102 » et il faut la retrouver à
	# la main dans le plan. Un diagnostic qu'on ne peut pas relier à une
	# ligne de code ne sert à rien.
	noeud.name = "Prop_%s" % piece["modele"]
	noeud.position = Vector3(plan_pos.x, PlanAreneTest.LEVEE, plan_pos.y)
	noeud.rotation.y = piece["rot"]
	add_child(noeud)
	_props += 1

	# COLLISION AUX DIMENSIONS RENDUES, PAS AUX DIMENSIONS DEMANDÉES.
	# Meshy livre souvent plus petit que le volume réclamé ; une collision
	# à la taille demandée entourerait la pièce d'un mur invisible, et l'on
	# se cognerait dans du vide à côté d'un conteneur.
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(maxf(reelle.x, 0.3), maxf(reelle.y, 0.3),
			maxf(reelle.z, 0.3))
	shape.shape = cb
	shape.position = Vector3(plan_pos.x, reelle.y * 0.5, plan_pos.y)
	shape.rotation.y = piece["rot"]
	_obstacles.add_child(shape)


## LE BORD DE L'ARÈNE — quatre murs invisibles, et rien de visible.
##
## POURQUOI RIEN DE VISIBLE. Un mur bâti sur 40 m de côté, c'est quatre
## murs qui entrent dans le champ de la caméra dès qu'on approche du bord,
## et l'écran se remplit de paroi. C'est le défaut qui a coûté trois
## corrections au monde ouvert avant qu'on ne supprime la limite. Ici la
## limite est nécessaire — une arène a des bords — mais elle n'a aucune
## raison d'être VUE : la couronne d'apparitions et les repères d'angle
## disent déjà où s'arrête le terrain.
func _mur_arene_test() -> void:
	# SUR SA PROPRE COUCHE, ET C'EST TOUT LE SUJET. Sur la couche du monde,
	# l'enceinte bloquait le regard de la caméra dès qu'on longeait le bord
	# sud — voir Cfg.LAYER_BORDURE. Elle a donc son propre corps.
	var enceinte := StaticBody3D.new()
	enceinte.name = "Bordure"
	enceinte.collision_layer = Cfg.LAYER_BORDURE
	enceinte.collision_mask = 0
	add_child(enceinte)

	var d := PlanAreneTest.DEMI + MARGE_BORD
	var h := 6.0
	for i in 4:
		var a := TAU * float(i) / 4.0
		var n := Vector2(cos(a), sin(a))
		var shape := CollisionShape3D.new()
		var cb := BoxShape3D.new()
		cb.size = Vector3(1.0, h, PlanAreneTest.COTE + MARGE_BORD * 4.0)
		shape.shape = cb
		shape.position = Vector3(n.x * d, h * 0.5, n.y * d)
		shape.rotation.y = a
		enceinte.add_child(shape)


# --- ARENE WESTERN -------------------------------------------------------
#
# GREYBOX D'ABORD, ASSETS ENSUITE, et jamais l'inverse. Tout ce qui suit
# batit la carte en primitives : c'est ce qui permet de valider la
# CIRCULATION — contournements, boucles, absence d'impasse — avant qu'un
# seul modele n'existe. L'habillage ne changera plus une seule position.

## Teintes du greybox, prises sur la palette de la planche.
## SABLE DU SOL, ACCORDÉ AUX SOCLES DES ASSETS.
##
## Prélevé en image plutôt que choisi : les modèles Meshy arrivent posés
## sur un petit disque de sable qui rend #eca256, quand le sol du greybox
## rendait #f6dd9d. L'écart faisait un HALO ORANGE autour de chaque rocher,
## de chaque caisse et de chaque cactus — soixante-dix taches qui disaient
## « asset collé sur un fond » au lieu de « objet posé sur du sable ».
##
## La teinte écrite ici est plus sombre que celle qu'on veut à l'écran :
## le sol est un plan sans relief qui prend la lumière de plein fouet,
## alors que les socles sont bombés et s'auto-ombrent. Réglé à l'oeil sur
## la capture, pas au nuancier.
## Sable du LOINTAIN — tout ce qui est au-delà de la clôture. Plus sourd
## que celui de l'aire de jeu : sur la maquette, l'arène est un îlot clair
## posé sur un désert plus foncé, et c'est ce contraste qui dit au joueur
## où finit le terrain.
const W_SABLE := Color("a87b3f")
## Les quatre valeurs des dalles de l'aire de jeu, prises sur la maquette.
## Les quatre valeurs des dalles de l'aire de jeu. Elles sont VOLONTAIREMENT
## proches les unes des autres : le premier essai les écartait de vingt pour
## cent et le sol devenait un damier de cuisine, qui tirait l'oeil au lieu
## de le laisser tranquille. Ce qu'on veut, c'est un sol qui ne soit pas
## plat — pas un sol qui se remarque.
const W_DALLES := [Color("cf9c58"), Color("c6934f"),
		Color("bd8a48"), Color("b48141")]
const W_ROCHE := Color("c0603c")
const W_ROCHE_SOMMET := Color("d87a52")
## Les trois valeurs de la pierre des murets, prises sur la planche : un
## crème clair, un moyen, un plus chaud. Trois teintes SEULEMENT — chaque
## teinte crée son propre matériau à la fusion, et une pierre par teinte
## rendrait la fusion inutile.
const W_MURET := [Color("d3c7ae"), Color("bcae92"), Color("a2947a")]
const W_BOIS := Color("9c6334")
const W_FOIN := Color("e0b352")
const W_CACTUS := Color("5f9c4a")
## Le vert des cactus FONDUS de la lisière. Plus sourd que celui du modèle
## Meshy : sans texture pour le casser, un aplat vert franc éclairé par le
## liseré du matériau ressortait fluo au milieu du sable, et la lisière se
## lisait comme une rangée de bâtons peints.
const W_CACTUS_LOIN := Color("47713a")
## Les teintes du semis de décor. Deux valeurs par famille, pas plus :
## chaque teinte crée son propre matériau à la fusion.
## Le premier essai les avait en vert franc et en pierre presque blanche :
## les buissons se lisaient comme des objets à ramasser et les cailloux
## comme des hexagones posés là. Sourdes, les deux redeviennent du décor.
const W_BUISSON := [Color("4c7133"), Color("42632c")]
const W_CAILLOU := [Color("94805f"), Color("7e6c50")]
const W_HERBE := [Color("9a9a52"), Color("87873f")]

## Compteur d'alternance des deux formations rocheuses.
var _n_form: int = 0
## Numéro de l'empilement en cours — sert à nommer ses étages.
var _n_pile: int = 0


func _batir_arene_western() -> void:
	_sol_western()
	_ouvrir_fusion()
	_formations_western()
	_murs_western()
	_margelle_centre()
	_piles_western()
	_barrieres_western()
	_chariots_western()
	_petits_western()
	_vegetation_western()
	_semis_decor_western()
	_cloture_western()
	_lisiere_western()
	_horizon_western()
	_fermer_fusion()

	player_spawn_points.clear()
	for p: Vector2 in PlanAreneWestern.APPARITIONS:
		player_spawn_points.append(Vector3(p.x, 0.2, p.y))
	# AUCUN FOYER DE MOB. La consigne est explicite pour cette etape : la
	# carte se valide sans PvE. Laisser des foyers « au cas ou » ferait
	# apparaitre des mobs des que le pondeur tournerait.
	mob_spawn_points.clear()


## LE SOL — large, uni, silencieux.
##
## Il deborde tres largement l'arene : depuis la camera, on ne doit jamais
## en voir la fin. Un sol qui s'arrete transforme un desert en plateau de
## tournage.
##
## Il est en DEUX morceaux. Un grand pave sombre pour le lointain, et
## par-dessus l'aire de jeu, la nappe de dalles craquelees de
## `_dalles_western`. Le pave seul suffisait a la lisibilite mais donnait
## un aplat sans aucun repere : on ne voyait plus qu'on avancait, et les
## distances devenaient impossibles a juger.
func _sol_western() -> void:
	var cote := 220.0
	# ─── LE PAVÉ N'A PLUS DE MAILLE, ET C'EST UN CORRECTIF ─────────────
	#
	# Il y avait DEUX plans de sol : ce pavé, dessus à −2,8 cm, et la nappe
	# de dalles à −0,8 cm. Deux plans, c'est deux chances pour la base d'une
	# pièce de tomber pile dessus. C'est arrivé : les tonneaux, une fois
	# grossis pour la lisibilité mobile, se sont posés à −2,79 cm — un
	# dixième de millimètre du pavé. La sonde l'a vu ; à l'œil, cela se
	# serait vu en jeu et jamais sur une capture.
	#
	# Le pavé ne garde donc que sa COLLISION. La nappe de dalles s'étend
	# maintenant jusqu'à l'horizon et devient le seul plan de sol.
	# LE DESSUS DU SOL EST HUIT MILLIMÈTRES SOUS ZÉRO, et c'est le
	# correctif anti-scintillement de toute la carte, en un seul nombre.
	#
	# Caisses, tonneaux, bottes, murets et poteaux sont posés base à y = 0
	# — c'est la façon naturelle de les écrire. Leur face inférieure était
	# donc COPLANAIRE avec le sol : les deux surfaces se disputent le même
	# pixel, et laquelle gagne dépend de l'angle de la caméra. Le prop
	# clignote dès qu'on bouge, et jamais sur une capture fixe.
	#
	# Descendre le SOL plutôt que lever chaque pièce règle le cas une fois
	# pour toutes, y compris pour les pièces qu'on ajoutera plus tard sans
	# y penser. Huit millimètres sont sous le seuil du visible depuis dix
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cote, 0.5, cote)
	col.shape = box
	# La COLLISION, elle, reste à zéro : c'est le sol sur lequel on marche,
	# et le décaler ferait flotter les personnages de huit millimètres.
	col.position = Vector3(0, -0.25, 0)
	_obstacles.add_child(col)

	_dalles_western()



## CRÊTES ROCHEUSES — l'îlot de gameplay.
##
## LA V1 EN FAISAIT DES DISQUES, ET C'ÉTAIT L'ÉCART LE PLUS COÛTEUX AVEC
## LA MAQUETTE. Un disque de quatre mètres de rayon barre quatre mètres de
## ligne de vue quel que soit l'angle d'où on le regarde ; une crête de
## dix mètres en barre dix quand on l'aborde de flanc et trois quand on
## l'aborde par le bout. C'est cette différence qui donne à la poursuite
## des côtés « court » et « long » — donc un choix à faire en courant.
##
## Chaque crête est bâtie en DEUX À QUATRE BLOCS posés bout à bout le long
## de son axe, chacun à SES proportions et légèrement désaxé. On ne les
## étire pas : un rocher Meshy ramené de 1,90 × 1,71 à 10 × 4 se voit tout
## de suite, alors que trois blocs alignés se lisent comme une crête —
## et c'est exactement ainsi que la maquette les dessine.
##
## LA COLLISION EST UNE BOÎTE ORIENTÉE, aux dimensions déclarées dans le
## plan. Elle ne suit pas les blocs : suivre les creux entre eux donnerait
## des accrochages invisibles, et une poursuite qui s'arrête sur un angle
## qu'on ne voit pas est pire qu'une poursuite trop facile.
func _formations_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260820
	_n_form = 0
	for f: Dictionary in PlanAreneWestern.FORMATIONS:
		var c: Vector2 = f["pos"]
		var lg: float = f["long"]
		var la: float = f["large"]
		var h: float = f["hauteur"]
		var a := deg_to_rad(float(f["angle"]))
		var axe := Vector2(cos(a), sin(a))
		# Assez de blocs pour que la crête ne soit pas un seul rocher
		# étiré, pas assez pour qu'elle devienne une file de cailloux.
		var blocs := clampi(int(round(lg / maxf(la * 0.92, 1.0))), 2, 4)
		var pose := false
		for k in blocs:
			var t := (float(k) - float(blocs - 1) * 0.5) * (lg / float(blocs))
			var pb := c + axe * t
			# DEUX MODÈLES EN ALTERNANCE, tournés au hasard. C'est la règle
			# du kit : la variété vient de la RÉUTILISATION — rotation,
			# échelle, alternance — et non de cinquante modèles uniques.
			var modele: StringName = &"west_rock_formation_a" \
					if _n_form % 2 == 0 else &"west_rock_formation_b"
			_n_form += 1
			var n := KitWestern.instancier(modele, Vector3(
					lg / float(blocs) * 1.30,
					h * rng.randf_range(0.78, 1.0),
					la * rng.randf_range(0.84, 1.0)))
			if n == null:
				break
			# NOMMÉE PAR SA CRÊTE, et pas seulement par son modèle. Une
			# crête est UNE pièce faite de plusieurs blocs qui se
			# chevauchent exprès ; sans ce numéro, la sonde de
			# scintillement voyait deux blocs voisins comme deux masses
			# interpénétrées et criait au défaut sur la composition même.
			# `true` N'EST PAS UN DÉTAIL : c'est `force_readable_name`.
			#
			# Sans lui, Godot JETTE le nom qu'on vient de poser dès qu'il
			# est déjà pris et le remplace par « @Node3D@380 ». Tous les
			# rapports de la sonde de scintillement désignaient donc leurs
			# coupables par un numéro interne — j'ai cherché à la main, à
			# partir des coordonnées, ce que le nom aurait dit tout seul.
			n.name = "Crete%02d_%s" % [_n_form / 2, modele]
			n.position = Vector3(pb.x, PlanAreneWestern.LEVEE, pb.y)
			n.rotation.y = -a + rng.randf_range(-0.22, 0.22)
			add_child(n, true)
			_props += 1
			pose = true
		if not pose:
			# REPLI EN PRIMITIVES si le modèle manque. La carte doit rester
			# jouable et testable même sans un seul asset livré.
			for k in blocs:
				var t := (float(k) - float(blocs - 1) * 0.5) * (lg / float(blocs))
				var pb := c + axe * t
				var b := BoxMesh.new()
				b.size = Vector3(lg / float(blocs) * 1.05,
						h * rng.randf_range(0.7, 1.0), la)
				_fondre(b, Transform3D(
						Basis.from_euler(Vector3(0, -a, 0)),
						Vector3(pb.x, b.size.y * 0.5, pb.y)),
						W_ROCHE if k % 2 == 0 else W_ROCHE_SOMMET)
		_collision_boite(c, Vector2(lg, la), -a, h)


## MURS DE PIERRE BAS — couvert moyen, et surtout briseur de ligne de tir.
##
## LA MAQUETTE LES MONTRE DROITS ET COURTS, pas en arcs. La V1 les avait
## courbés au motif qu'« un mur droit est un corridor » — c'est faux tant
## qu'on peut passer des deux côtés : c'est la LONGUEUR qui fait le
## corridor, pas la forme. Six à huit mètres se contournent en deux pas.
##
## ─── DE LA MAÇONNERIE, PAS UN RUBAN ────────────────────────────────────
##
## La planche ne montre pas un mur lisse : elle montre des PIERRES POSÉES —
## deux assises de blocs crème, joints décalés, chacune un peu de travers.
## C'est ce découpage qui donne au mur sa lecture ; un bloc unique de la
## même teinte claire ressortait BLANC à l'écran, sans arête pour accrocher
## la lumière, et se lisait comme un trou dans l'image.
func _murs_western() -> void:
	# Graine FIXE : la décoration doit être la même à chaque partie, sinon
	# deux joueurs ne voient pas la même arène.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for m: Dictionary in PlanAreneWestern.MURS:
		var c: Vector2 = m["pos"]
		var l: float = m["long"]
		var a := deg_to_rad(float(m["angle"]))
		var axe := Vector2(cos(a), sin(a))
		var n := maxi(2, int(round(l / 1.7)))
		for i in n:
			var t := (float(i) - float(n - 1) * 0.5) * (l / float(n))
			_pierres(c + axe * t, -a, l / float(n) + 0.3, rng)
		_collision_boite(c, Vector2(l, 0.85), -a, PlanAreneWestern.H_MOYEN)


## LA MARGELLE DU CENTRE — le seul mur courbe de la carte, et il l'est
## parce que le centre est un rond-point : quatre arcs, quatre brèches.
func _margelle_centre() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for m: Dictionary in PlanAreneWestern.ARCS_CENTRE:
		var c: Vector2 = m["centre"]
		var r: float = m["rayon"]
		var a0 := deg_to_rad(float(m["depart"]))
		var arc := deg_to_rad(float(m["arc"]))
		var n := maxi(3, int(arc * r / 1.6))
		for i in n:
			var a := a0 + arc * (float(i) + 0.5) / float(n)
			var p := c + Vector2(cos(a), sin(a)) * r
			var seg := arc * r / float(n) + 0.35
			_pierres(p, -a + PI * 0.5, seg, rng)
			var sh := CollisionShape3D.new()
			var cb := BoxShape3D.new()
			cb.size = Vector3(seg, PlanAreneWestern.H_MOYEN, 0.75)
			sh.shape = cb
			sh.position = Vector3(p.x, PlanAreneWestern.H_MOYEN * 0.5, p.y)
			sh.rotation.y = -a + PI * 0.5
			_obstacles.add_child(sh)


## UN TRONÇON DE MAÇONNERIE — deux assises de pierres décalées.
##
## LA COLLISION N'EST PAS POSÉE ICI. Elle est d'un seul tenant sur tout le
## mur, chez l'appelant : le level design validé décide des lignes de tir,
## et une collision par pierre rouvrirait la question des accrochages.
func _pierres(p: Vector2, rot: float, seg: float,
		rng: RandomNumberGenerator) -> void:
	var base := Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
			Vector3(p.x, 0, p.y))
	var h_bas: float = PlanAreneWestern.H_MOYEN * 0.58
	var h_haut: float = PlanAreneWestern.H_MOYEN - h_bas
	# Assise du bas : deux pierres. Assise du haut : deux aussi, mais
	# décalées d'une demi-pierre pour croiser les joints.
	for etage in 2:
		var y0: float = 0.0 if etage == 0 else h_bas
		var hp: float = h_bas if etage == 0 else h_haut
		var prof: float = 0.82 if etage == 0 else 0.68
		var decal: float = 0.0 if etage == 0 else 0.5
		for k in 2:
			var u := (float(k) + 0.5 + decal) / 2.0 - 0.5
			if absf(u) > 0.5:
				continue
			var lp := seg * 0.5 * rng.randf_range(0.86, 0.98)
			var pierre := BoxMesh.new()
			pierre.size = Vector3(lp, hp * rng.randf_range(0.94, 1.0),
					prof * rng.randf_range(0.90, 1.0))
			var t := base
			t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(-0.07, 0.07))
			t.origin += base.basis * Vector3(
					u * seg, 0.0, rng.randf_range(-0.05, 0.05))
			t.origin.y = y0 + pierre.size.y * 0.5
			_fondre(pierre, t, W_MURET[rng.randi_range(0, 2)])
	# Éboulis au pied : la planche en pose toujours quelques-uns, et ils
	# cachent la ligne où le mur rencontre le sable.
	if rng.randf() < 0.45:
		var caillou := SphereMesh.new()
		caillou.radius = rng.randf_range(0.13, 0.22)
		caillou.height = caillou.radius * 1.5
		caillou.radial_segments = 6
		caillou.rings = 3
		var tc := base
		tc.origin += base.basis * Vector3(
				rng.randf_range(-0.4, 0.4), 0.0,
				(0.46 if rng.randf() < 0.5 else -0.46))
		tc.origin.y = caillou.radius * 0.5
		_fondre(caillou, tc, W_MURET[2])


## EMPILEMENTS — le couvert qui manquait entre le tonneau et la falaise.
##
## Une caisse seule fait quatre-vingt-dix centimètres : on la voit à peine
## et on ne s'y bat pas. Empilées par deux ou trois, les mêmes caisses font
## deux mètres, se lisent de loin sur un téléphone, et donnent un vrai
## duel. C'est ce que montre la maquette, et c'est ce que la V1 n'avait
## pas : quatre-vingt-quatre pour cent de son emprise tenait dans treize
## grosses masses, et le reste était trop bas pour compter.
## HAUTEUR RÉELLEMENT OCCUPÉE PAR UNE PIÈCE POSÉE, socle compris.
##
## On additionne les boîtes de toutes ses mailles, ramenées dans le repère
## de la pièce. C'est la seule mesure qui ne ment pas : la taille demandée
## à `instancier` n'est qu'un gabarit, et le modèle s'y inscrit comme il
## peut.
func _hauteur_rendue(n: Node3D) -> float:
	var haut := -INF
	var bas := INF
	var file: Array[Node] = [n]
	while not file.is_empty():
		var e: Node = file.pop_back()
		var mi := e as MeshInstance3D
		if mi != null and mi.mesh != null:
			var b := mi.get_aabb()
			for i in 8:
				var coin: Vector3 = mi.global_transform * (b.position + Vector3(
						b.size.x * float(i & 1),
						b.size.y * float((i >> 1) & 1),
						b.size.z * float((i >> 2) & 1)))
				haut = maxf(haut, coin.y)
				bas = minf(bas, coin.y)
		for c in e.get_children():
			file.append(c)
	if haut == -INF:
		return 0.0
	return maxf(haut - maxf(bas, 0.0), 0.05)


func _piles_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	_n_pile = 0
	for e: Dictionary in PlanAreneWestern.PILES:
		_n_pile += 1
		var p: Vector2 = e["pos"]
		var a := deg_to_rad(float(e["angle"]))
		var etages: int = e["etages"]
		var botte: bool = e["type"] == &"botte"
		var modele: StringName = &"west_haybale" if botte else &"west_crate"
		var cote := 1.45 if botte else 1.20
		var haut := 0.95 if botte else 1.05
		var pose := false
		var y := 0.0
		for etage in etages:
			# Chaque étage est un peu plus petit et un peu de travers : un
			# empilement parfaitement aligné se lit comme un mur, pas comme
			# des caisses qu'on a posées là.
			var f := 1.0 - float(etage) * 0.12
			var n := KitWestern.instancier(modele,
					Vector3(cote * f, haut * f, cote * f * (1.15 if botte else 1.0)))
			if n == null:
				break
			n.name = "Pile%02d_%s" % [_n_pile, modele]
			n.position = Vector3(
					p.x + rng.randf_range(-0.14, 0.14) * float(etage),
					y + PlanAreneWestern.LEVEE,
					p.y + rng.randf_range(-0.14, 0.14) * float(etage))
			n.rotation.y = -a + rng.randf_range(-0.35, 0.35) * float(etage)
			add_child(n, true)
			_props += 1
			pose = true
			# ON EMPILE SUR LA HAUTEUR RENDUE, PAS SUR CELLE DEMANDÉE.
			#
			# `instancier` ajuste le modèle dans le volume réclamé par le
			# plus petit rapport : il rend donc souvent PLUS BAS que ce
			# qu'on lui demande. Empiler sur la hauteur demandée laissait
			# un vide entre les caisses, et la pile paraissait flotter.
			y += _hauteur_rendue(n)
		if not pose:
			var yy := 0.0
			for etage in etages:
				var f := 1.0 - float(etage) * 0.12
				var b := BoxMesh.new()
				b.size = Vector3(cote * f, haut * f, cote * f)
				_fondre(b, Transform3D(
						Basis.from_euler(Vector3(0, -a + rng.randf_range(-0.3, 0.3), 0)),
						Vector3(p.x, yy + b.size.y * 0.5, p.y)),
						W_FOIN if botte else W_BOIS)
				yy += b.size.y
		_collision_boite(p, Vector2(cote * 1.05, cote * 1.05), -a,
				maxf(y, haut * float(etages) * 0.9))

func _barrieres_western() -> void:
	for f: Dictionary in PlanAreneWestern.BARRIERES:
		var p: Vector2 = f["pos"]
		var a := deg_to_rad(float(f["angle"]))
		var l: float = f["long"]
		# ─── ON RÉPÈTE LE MODULE, ON NE L'ÉTIRE PAS ────────────────────
		#
		# Le modèle de barrière fait 1,90 m de long. Lui demander de
		# couvrir six mètres d'un coup, c'est le contraindre par sa
		# LARGEUR : l'ajustement rendait une barrière de 1,5 m au milieu
		# d'une collision de six. Une barrière est un élément MODULAIRE —
		# on en pose trois bout à bout, ce qui est aussi la façon dont la
		# planche la présente.
		var pas_bar := 1.85
		var combien := maxi(1, int(round(l / pas_bar)))
		var pose := false
		for k in combien:
			var t := (float(k) - float(combien - 1) * 0.5) * (l / float(combien))
			var pp := p + Vector2(cos(a), -sin(a)) * t
			var bar := KitWestern.instancier(&"west_fence_straight",
					Vector3(l / float(combien) * 1.02, 1.3, 0.6))
			if bar == null:
				break
			bar.name = "Prop_west_fence_straight"
			bar.position = Vector3(pp.x, PlanAreneWestern.LEVEE, pp.y)
			bar.rotation.y = a
			add_child(bar, true)
			_props += 1
			pose = true
		if pose:
			var sh0 := CollisionShape3D.new()
			var cb0 := BoxShape3D.new()
			cb0.size = Vector3(l, 1.25, 0.3)
			sh0.shape = cb0
			sh0.position = Vector3(p.x, 0.62, p.y)
			sh0.rotation.y = a
			_obstacles.add_child(sh0)
			continue
		for lisse in 2:
			var y := 0.55 + float(lisse) * 0.55
			var b := BoxMesh.new()
			b.size = Vector3(l, 0.16, 0.14)
			_fondre(b, Transform3D(Basis.from_euler(Vector3(0, a, 0)),
					Vector3(p.x, y, p.y)), W_BOIS)
		for k in 3:
			var t := (float(k) / 2.0 - 0.5) * l
			var pp := p + Vector2(cos(a), -sin(a)) * t
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.2, 1.25, 0.2)
			_fondre(b2, Transform3D(Basis.IDENTITY,
					Vector3(pp.x, 0.62, pp.y)), W_BOIS)
		var sh := CollisionShape3D.new()
		var cb := BoxShape3D.new()
		cb.size = Vector3(l, 1.25, 0.3)
		sh.shape = cb
		sh.position = Vector3(p.x, 0.62, p.y)
		sh.rotation.y = a
		_obstacles.add_child(sh)


## CHARIOTS BACHES — couvert complet, et surtout REPERE. Trois seulement :
## c'est la silhouette la plus reconnaissable de la planche, et elle
## perdrait ce role repetee dix fois.
func _chariots_western() -> void:
	for c: Dictionary in PlanAreneWestern.CHARIOTS:
		var p: Vector2 = c["pos"]
		var a := deg_to_rad(float(c["angle"]))
		var n := KitWestern.instancier(&"west_wagon", Vector3(4.6, 2.8, 2.6))
		if n != null:
			n.name = "Prop_west_wagon"
			n.position = Vector3(p.x, PlanAreneWestern.LEVEE, p.y)
			n.rotation.y = a
			add_child(n, true)
			_props += 1
			_collision_boite(p, Vector2(4.4, 2.4), a, 2.6)
			continue
		var base := Basis.from_euler(Vector3(0, a, 0))
		# Caisse
		var b := BoxMesh.new()
		b.size = Vector3(4.2, 1.1, 2.0)
		_fondre(b, Transform3D(base, Vector3(p.x, 1.0, p.y)), W_BOIS)
		# Bache : un demi-cylindre suffit a la faire lire.
		var t := CylinderMesh.new()
		t.top_radius = 1.15
		t.bottom_radius = 1.15
		t.height = 4.0
		t.radial_segments = 8
		_fondre(t, Transform3D(
				base * Basis.from_euler(Vector3(0, 0, PI * 0.5)),
				Vector3(p.x, 2.15, p.y)), Color("efe6d2"))
		# Roues
		for cote in [-1.0, 1.0]:
			for avant in [-1.0, 1.0]:
				var d := base * Vector3(avant * 1.5, 0.0, cote * 1.1)
				var r := CylinderMesh.new()
				r.top_radius = 0.62
				r.bottom_radius = 0.62
				r.height = 0.18
				r.radial_segments = 10
				_fondre(r, Transform3D(
						Basis.from_euler(Vector3(PI * 0.5, a, 0)),
						Vector3(p.x + d.x, 0.62, p.y + d.z)), W_BOIS)
		_collision_boite(p, Vector2(4.4, 2.4), a, 2.6)


## PETIT COUVERT. Il ne bloque pas la course : il casse la ligne de tir et
## donne ou se jeter.
func _petits_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	for e: Dictionary in PlanAreneWestern.PETITS:
		var p: Vector2 = e["pos"]
		var a := rng.randf() * TAU
		var modele := StringName("west_%s" % ({
			&"tonneau": "barrel", &"botte": "haybale"}.get(e["type"], "crate")))
		# ─── GROSSIS POUR ÊTRE LISIBLES SUR UN TÉLÉPHONE ────────────────
		#
		# À quatre-vingt-dix centimètres, une caisse vue de dix mètres de
		# haut fait une tache de quelques pixels sur un écran de six
		# pouces : le joueur ne la voit pas, donc elle ne sert à rien.
		# C'est la consigne de lisibilité mobile — la silhouette compte
		# plus que le détail. On monte à 1,15 m, ce qui reste un couvert
		# BAS (on tire par-dessus) mais devient visible.
		var volume := {
			&"tonneau": Vector3(1.15, 1.25, 1.15),
			&"botte": Vector3(1.85, 1.15, 1.30)}.get(e["type"],
			Vector3(1.35, 1.15, 1.35)) as Vector3
		var n := KitWestern.instancier(modele, volume)
		if n != null:
			n.name = "Prop_%s" % modele
			n.position = Vector3(p.x, PlanAreneWestern.LEVEE, p.y)
			n.rotation.y = a
			add_child(n, true)
			_props += 1
			if e["type"] == &"tonneau":
				_collision_ronde(p, 0.56, 1.25)
			else:
				_collision_boite(p, Vector2(volume.x, volume.z), a, volume.y)
			continue
		match e["type"]:
			&"tonneau":
				var t := CylinderMesh.new()
				t.top_radius = 0.42
				t.bottom_radius = 0.42
				t.height = 0.95
				t.radial_segments = 10
				_fondre(t, Transform3D(Basis.IDENTITY,
						Vector3(p.x, 0.48, p.y)), W_BOIS)
				_collision_ronde(p, 0.46, 0.95)
			&"botte":
				var b := BoxMesh.new()
				b.size = Vector3(1.5, 0.95, 1.05)
				_fondre(b, Transform3D(Basis.from_euler(Vector3(0, a, 0)),
						Vector3(p.x, 0.48, p.y)), W_FOIN)
				_collision_boite(p, Vector2(1.5, 1.05), a, 0.95)
			_:
				var c := BoxMesh.new()
				c.size = Vector3(1.1, 0.9, 1.1)
				_fondre(c, Transform3D(Basis.from_euler(Vector3(0, a, 0)),
						Vector3(p.x, 0.45, p.y)), W_BOIS.lightened(0.12))
				_collision_boite(p, Vector2(1.1, 1.1), a, 0.9)


## VEGETATION — AUCUNE COLLISION, et c'est la regle. Un cactus qui arrete
## une poursuite est un defaut : on ne comprend pas pourquoi on s'est
## arrete, et le decor devient un piege.
## LA LISIÈRE — CE QUI POUSSE LE LONG DE LA CLÔTURE.
##
## POURQUOI ELLE EXISTE. Le rendu depuis le bord montrait une bande de
## sable nu de huit mètres entre le dernier couvert et la barrière : le
## relaxeur avait écarté les masses de la clôture pour qu'on puisse passer
## derrière elles, et il avait raison de le faire — mais il avait vidé la
## bande. La maquette, elle, garnit tout son pourtour de cactus, de
## touffes et de pierres.
##
## RIEN ICI N'A DE COLLISION, ET C'EST LA CONDITION POUR QUE CE SOIT
## PERMIS. La bande le long de la clôture est un couloir de fuite : c'est
## par là qu'on continue la boucle quand on est poursuivi. Y poser le
## moindre obstacle solide en ferait un piège. On y met donc ce qui se
## traverse, et rien d'autre.
##
## ON SAUTE LES ABORDS DES APPARITIONS. Naître le nez dans un cactus, même
## traversable, c'est naître aveugle.
func _lisiere_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var pts := PlanAreneWestern.contour(160)
	var n := pts.size()
	for i in n:
		var bord: Vector2 = pts[i]
		var vers_dedans := -bord.normalized()
		# Deux ou trois éléments par point d'ancrage, à des profondeurs
		# différentes : une haie régulière à distance constante se lit
		# comme une clôture bis, ce qui est exactement ce qu'on ne veut pas.
		for k in rng.randi_range(1, 3):
			var p := bord + vers_dedans * rng.randf_range(1.4, 7.0) \
					+ Vector2(-vers_dedans.y, vers_dedans.x) * rng.randf_range(-1.6, 1.6)
			var trop_pres := false
			for ap: Vector2 in PlanAreneWestern.APPARITIONS:
				if p.distance_to(ap) < 4.0:
					trop_pres = true
					break
			if not trop_pres:
				for m: Dictionary in PlanAreneWestern.masses():
					if PlanAreneWestern.ecart_masse(p, m) < 1.4:
						trop_pres = true
						break
			if trop_pres:
				continue
			var quoi := rng.randf()
			if quoi < 0.30:
				_cactus_fondu(p, rng)
			elif quoi < 0.70:
				_touffe_fondue(p, rng)
			else:
				_caillou_fondu(p, rng)


## UN CACTUS EN PRIMITIVES — un fût, deux bras.
##
## POURQUOI PAS LE MODÈLE MESHY ICI. La lisière en compte une centaine.
## Cent instances Meshy, c'est cent appels de rendu de plus sur un
## téléphone, pour des objets qu'on ne voit jamais à moins de trente
## mètres. Fondus, ils n'en coûtent aucun. Le modèle Meshy reste sur les
## cactus du champ de jeu, ceux qu'on longe de près.
func _cactus_fondu(p: Vector2, rng: RandomNumberGenerator) -> void:
	# ─── UNE TOUFFE TRAPUE, PAS UN SAGUARO ─────────────────────────────
	#
	# Deux essais ratés avant celui-ci, et la leçon vaut d'être écrite :
	# CE QUI COMPTE EST LA PROJECTION, PAS LA SILHOUETTE DE FACE.
	#
	# La caméra plonge à 52° depuis dix mètres. Un fût de trois mètres,
	# fin, vu sous cet angle, ne couvre presque aucun pixel : le premier
	# essai donnait des poteaux verts, le deuxième — avec des bras coudés
	# de vrai saguaro — donnait des lettres vertes couchées par terre. Le
	# modèle Meshy, lui, se lit très bien parce qu'il est LARGE.
	#
	# On copie donc sa masse : deux à quatre colonnes trapues et rondes,
	# serrées, de hauteurs différentes. De dessus, une touffe compacte.
	var brins := rng.randi_range(2, 4)
	var a0 := rng.randf() * TAU
	for brin in brins:
		var a := a0 + TAU * float(brin) / float(brins) \
				+ rng.randf_range(-0.4, 0.4)
		var d := 0.0 if brin == 0 else rng.randf_range(0.28, 0.52)
		var c := p + Vector2(cos(a), sin(a)) * d
		var r := rng.randf_range(0.26, 0.36) if brin == 0 \
				else rng.randf_range(0.19, 0.29)
		var h := rng.randf_range(1.5, 2.4) if brin == 0 \
				else rng.randf_range(0.8, 1.7)
		var t := CylinderMesh.new()
		t.top_radius = r * 0.92
		t.bottom_radius = r
		t.height = h
		t.radial_segments = 8
		_fondre(t, Transform3D(Basis.IDENTITY, Vector3(c.x, h * 0.5, c.y)),
				W_CACTUS_LOIN)
		# La calotte ronde : un cylindre coupé net se lit comme un poteau.
		var cap := SphereMesh.new()
		cap.radius = r * 0.92
		cap.height = r * 1.6
		cap.radial_segments = 8
		cap.rings = 4
		_fondre(cap, Transform3D(Basis.IDENTITY, Vector3(c.x, h, c.y)),
				W_CACTUS_LOIN)

func _touffe_fondue(p: Vector2, rng: RandomNumberGenerator) -> void:
	for boule in 3:
		var b := SphereMesh.new()
		b.radius = rng.randf_range(0.30, 0.55)
		b.height = b.radius * 1.2
		b.radial_segments = 7
		b.rings = 3
		_fondre(b, Transform3D(Basis.IDENTITY, Vector3(
				p.x + rng.randf_range(-0.38, 0.38),
				b.radius * 0.34,
				p.y + rng.randf_range(-0.38, 0.38))),
				W_BUISSON[rng.randi_range(0, 1)] as Color)


func _caillou_fondu(p: Vector2, rng: RandomNumberGenerator) -> void:
	for pierre in rng.randi_range(2, 4):
		var c := SphereMesh.new()
		c.radius = rng.randf_range(0.22, 0.48)
		c.height = c.radius * 1.1
		c.radial_segments = 6
		c.rings = 3
		_fondre(c, Transform3D(
				Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)),
				Vector3(p.x + rng.randf_range(-0.6, 0.6), c.radius * 0.4,
						p.y + rng.randf_range(-0.6, 0.6))),
				W_ROCHE.lerp(W_MURET[1], rng.randf_range(0.25, 0.75)))


## L'HORIZON — DES MESAS AU-DELÀ DE LA CLÔTURE.
##
## POURQUOI CETTE FONCTION EXISTE, ET CE QU'ELLE A CORRIGÉ. La mesure des
## rendus à la caméra de jeu donnait 88 % de sable nu depuis une apparition
## du bord tournée vers l'extérieur : la MOITIÉ HAUTE DU CADRE était de la
## plaine plate jusqu'à l'horizon. C'est là que naissait la sensation de
## « grande plaine » plutôt que d'arène — et aucune densité de couverts à
## l'intérieur ne pouvait la corriger, puisque le problème était dehors.
##
## Les vues 3D de la maquette ferment leur horizon avec des mesas. On fait
## pareil, en deux couronnes : des buttes proches derrière la clôture, des
## mesas hautes et sourdes plus loin. Le brouillard de la scène les fond.
##
## TROIS RÈGLES, ET ELLES SONT TOUTES DES GARDE-FOUS :
##
##   · AUCUNE COLLISION. Rien ici n'est du level design. La clôture reste
##     la seule limite, et elle est déjà infranchissable.
##   · TOUT EST FONDU. Une trentaine de reliefs en primitives, réunis par
##     teinte : deux appels de rendu, pas trente-deux. Sur un téléphone la
##     différence n'est pas cosmétique.
##   · RIEN AVANT 50 m. La clôture est à 36 au plus loin ; quatorze
##     mètres de marge garantissent qu'aucune butte ne pousse dans le champ
##     de jeu, et surtout qu'elle se lise comme un fond et non comme un mur.
func _horizon_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 606
	# ─── LE PREMIER ESSAI LES AVAIT POSÉES BEAUCOUP TROP PRÈS ──────────
	#
	# Couronne à 45 m, hauteur jusqu'à neuf mètres : depuis une apparition
	# du bord, à quinze mètres d'elles, ce n'étaient plus des mesas mais
	# des murs coupés par le haut du cadre. Un fond d'horizon doit se lire
	# comme LOIN — c'est-à-dire bas dans l'image et petit. On les recule,
	# et on lit la règle qui va avec : la distance compte plus que la
	# taille, parce que c'est elle qui décide de l'angle sous lequel on
	# les voit.
	#
	# Le deuxième essai est tombé dans l'excès inverse : à soixante mètres
	# et plus, elles sortaient du cadre par le haut. La caméra plonge à 52°
	# — le haut de l'image montre le sol à une trentaine de mètres, pas le
	# ciel — et tout ce qui est plus loin ne rentre QUE par sa hauteur.
	# Cinquante mètres et six mètres de haut : elles bordent le cadre sans
	# le manger.
	_couronne_horizon(rng, 22, 50.0, 62.0, 3.5, 6.5, W_ROCHE, W_ROCHE_SOMMET)
	# Couronne lointaine : des mesas hautes, plus sourdes — c'est
	# l'éloignement qui délave, et le brouillard finit le travail.
	_couronne_horizon(rng, 18, 72.0, 96.0, 8.0, 15.0,
			W_ROCHE.lerp(W_SABLE, 0.34), W_ROCHE_SOMMET.lerp(W_SABLE, 0.40))


func _couronne_horizon(rng: RandomNumberGenerator, combien: int,
		r_min: float, r_max: float, h_min: float, h_max: float,
		bas: Color, haut: Color) -> void:
	for i in combien:
		# Angle réparti puis bousculé : une couronne régulière se lit comme
		# une palissade, et l'oeil la repère immédiatement pour ce qu'elle
		# est — un décor posé en rond autour du joueur.
		var a := TAU * (float(i) + rng.randf_range(-0.32, 0.32)) / float(combien)
		var r := rng.randf_range(r_min, r_max)
		var c := Vector2(cos(a), sin(a)) * r
		var h := rng.randf_range(h_min, h_max)
		var l := rng.randf_range(h * 1.4, h * 3.0)
		var w := rng.randf_range(h * 0.9, h * 1.8)
		var rot := -a + rng.randf_range(-0.6, 0.6)
		# Trois gradins, chacun plus étroit : c'est la silhouette de mesa,
		# et de loin seule la silhouette compte.
		var y := 0.0
		for etage in 3:
			var f := 1.0 - float(etage) * 0.24
			var he := h * (0.46 if etage == 0 else (0.32 if etage == 1 else 0.22))
			var b := BoxMesh.new()
			b.size = Vector3(l * f, he, w * f)
			var t := Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
					Vector3(c.x, y + he * 0.5, c.y))
			t.origin += t.basis * Vector3(rng.randf_range(-l, l) * 0.08, 0.0,
					rng.randf_range(-w, w) * 0.08)
			_fondre(b, t, bas if etage < 2 else haut)
			y += he


## SEMIS DE DÉCOR — ce qui remplit le vide entre les couverts.
##
## La maquette est DENSE : entre deux rochers il y a toujours une touffe,
## un caillou, un buisson. Le plan de niveau, lui, ne compte que les pièces
## qui décident du jeu — treize formations, dix murets, dix-huit petits
## couverts. Posé tel quel, le terrain était juste : il était aussi vide.
##
## RIEN ICI N'A DE COLLISION, ET C'EST LA RÈGLE. Le level design validé
## fixe les lignes de tir et les contournements ; l'art pass n'a pas le
## droit d'y toucher. Tout ce semis se traverse.
func _semis_decor_western() -> void:
	const COMBIEN := 160
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250820
	var masses := PlanAreneWestern.masses()
	var poses := 0
	var essais := 0
	while poses < COMBIEN and essais < COMBIEN * 12:
		essais += 1
		# TIRAGE DANS LE CARRÉ, PUIS REJET. Un tirage polaire tassait tout
		# au centre et ne savait pas remplir les coins — or les coins sont
		# précisément ce que la forme de la maquette a ajouté.
		var p := Vector2(
				rng.randf_range(-PlanAreneWestern.BORD, PlanAreneWestern.BORD),
				rng.randf_range(-PlanAreneWestern.BORD, PlanAreneWestern.BORD))
		if not PlanAreneWestern.dans_enceinte(p, PlanAreneWestern.MARGE_BORD + 0.8):
			continue
		var libre := true
		for m: Dictionary in masses:
			if PlanAreneWestern.ecart_masse(p, m) < 0.9:
				libre = false
				break
		if not libre:
			continue
		# On ne décore pas le pas de la porte : un joueur qui apparaît doit
		# voir du sol nu autour de lui, pas un buisson collé au visage.
		for ap: Vector2 in PlanAreneWestern.APPARITIONS:
			if p.distance_to(ap) < 2.0:
				libre = false
				break
		if not libre:
			continue
		poses += 1
		var quoi := rng.randf()
		if quoi < 0.34:
			# BUISSON — trois boules serrées, jamais une seule : une sphère
			# isolée se lit comme une balle posée par terre.
			var teinte: Color = W_BUISSON[rng.randi_range(0, 1)]
			for boule in 3:
				var b := SphereMesh.new()
				b.radius = rng.randf_range(0.26, 0.44)
				b.height = b.radius * 1.15
				b.radial_segments = 7
				b.rings = 3
				_fondre(b, Transform3D(Basis.IDENTITY, Vector3(
						p.x + rng.randf_range(-0.28, 0.28),
						b.radius * 0.34,
						p.y + rng.randf_range(-0.28, 0.28))), teinte)
		elif quoi < 0.72:
			# CAILLOU — plat et large, pour qu'on ne le confonde jamais
			# avec un objet à ramasser.
			var c := SphereMesh.new()
			c.radius = rng.randf_range(0.15, 0.30)
			c.height = c.radius * 0.9
			c.radial_segments = 7
			c.rings = 3
			_fondre(c, Transform3D(
					Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)),
					Vector3(p.x, c.radius * 0.35, p.y)),
					W_CAILLOU[rng.randi_range(0, 1)] as Color)
		else:
			# TOUFFE SÈCHE — quelques lames en éventail, à hauteur de
			# cheville : c'est ce qui donne au sable son échelle.
			var teinte: Color = W_HERBE[rng.randi_range(0, 1)]
			for lame in 4:
				var l := CylinderMesh.new()
				l.top_radius = 0.0
				l.bottom_radius = rng.randf_range(0.045, 0.075)
				l.height = rng.randf_range(0.30, 0.52)
				l.radial_segments = 4
				var pen := rng.randf_range(0.18, 0.42)
				_fondre(l, Transform3D(
						Basis.from_euler(Vector3(
								pen * cos(float(lame) * 1.9),
								rng.randf() * TAU,
								pen * sin(float(lame) * 1.9))),
						Vector3(p.x + rng.randf_range(-0.16, 0.16),
								l.height * 0.5,
								p.y + rng.randf_range(-0.16, 0.16))), teinte)

func _vegetation_western() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for v: Dictionary in PlanAreneWestern.VEGETATION:
		var p: Vector2 = v["pos"]
		if v["type"] == &"cactus":
			# La maquette montre des cactus à hauteur d'homme, en touffes.
			# Les nôtres faisaient 2,1 m mais surtout 1,3 de large : de
			# loin, un trait vert. On les élargit autant qu'on les monte.
			var n := KitWestern.instancier(&"west_cactus_a",
					Vector3(1.9, 2.9, 1.9))
			if n != null:
				n.name = "Prop_west_cactus_a"
				n.position = Vector3(p.x, PlanAreneWestern.LEVEE, p.y)
				n.rotation.y = rng.randf() * TAU
				add_child(n, true)
				_props += 1
				continue
			var t := CylinderMesh.new()
			t.top_radius = 0.26
			t.bottom_radius = 0.30
			t.height = 2.1
			t.radial_segments = 8
			_fondre(t, Transform3D(Basis.IDENTITY,
					Vector3(p.x, 1.05, p.y)), W_CACTUS)
			for bras in 2:
				var cote := 1.0 if bras == 0 else -1.0
				var b := CylinderMesh.new()
				b.top_radius = 0.17
				b.bottom_radius = 0.17
				b.height = 0.85
				b.radial_segments = 6
				_fondre(b, Transform3D(Basis.IDENTITY,
						Vector3(p.x + cote * 0.42, 1.35 + cote * 0.16, p.y)),
						W_CACTUS)
		else:
			var s := SphereMesh.new()
			s.radius = 0.62
			s.height = 0.85
			s.radial_segments = 8
			s.rings = 4
			_fondre(s, Transform3D(
					Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)),
					Vector3(p.x, 0.34, p.y)), W_CACTUS.darkened(0.15))


## LA CLOTURE — une limite qu'on VOIT sans se sentir enferme.
##
## Elle est basse : 1,3 m, sous la ligne des yeux de la camera. Un mur
## plein ceinturant l'arene remplirait l'ecran des qu'on longe le bord —
## c'est le defaut qui a coute trois corrections au monde ouvert avant
## qu'on ne supprime sa limite. Ici la limite est necessaire, mais elle n'a
## aucune raison de boucher la vue : au-dela, le desert continue.
##
## LA COLLISION EST SUR SA PROPRE COUCHE. Sur celle du monde, la barriere
## masquerait le joueur des qu'il longe le bord sud — la camera se pose
## huit metres au sud, donc DEHORS. Mesure et corrige une fois deja sur
## l'arene precedente.
func _cloture_western() -> void:
	var enceinte := StaticBody3D.new()
	enceinte.name = "Bordure"
	enceinte.collision_layer = Cfg.LAYER_BORDURE
	enceinte.collision_mask = 0
	add_child(enceinte)

	# LE CONTOUR EST UN CARRÉ AUX ANGLES ARRONDIS, pas un cercle — c'est la
	# forme de la maquette, et elle n'est pas décorative : un disque n'a pas
	# de coins, donc pas de ces poches d'angle où la maquette pose ses plus
	# grosses crêtes et où une poursuite change de rythme.
	#
	# On lit le contour comme une POLYLIGNE et on pose un panneau de
	# clôture entre chaque paire de points. Chaque panneau connaît sa
	# propre longueur et sa propre orientation : sur un cercle tous les
	# panneaux étaient identiques, ici ceux des coins sont plus courts.
	var pts := PlanAreneWestern.contour(96)
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var milieu := (a + b) * 0.5
		var d := b - a
		var l := d.length()
		var rot := -atan2(d.y, d.x)
		for lisse in 2:
			var m := BoxMesh.new()
			m.size = Vector3(l + 0.3, 0.18, 0.16)
			_fondre(m, Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
					Vector3(milieu.x, 0.6 + float(lisse) * 0.55, milieu.y)),
					W_BOIS)
		if i % 3 == 0:
			var po := BoxMesh.new()
			po.size = Vector3(0.24, 1.35, 0.24)
			_fondre(po, Transform3D(Basis.IDENTITY,
					Vector3(a.x, 0.67, a.y)), W_BOIS.darkened(0.12))
		# LE MUR INVISIBLE EST HAUT ET SUR SA PROPRE COUCHE. Il arrête les
		# corps sans jamais gêner la caméra, qui est posée huit mètres en
		# arrière du joueur et se retrouve donc DEHORS quand celui-ci longe
		# le bord sud.
		var sh := CollisionShape3D.new()
		var cb := BoxShape3D.new()
		cb.size = Vector3(l + 0.5, 5.0, 0.6)
		sh.shape = cb
		sh.position = Vector3(milieu.x, 2.5, milieu.y)
		sh.rotation.y = rot
		enceinte.add_child(sh)


func _collision_ronde(p: Vector2, rayon: float, haut: float) -> void:
	var sh := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = rayon
	cy.height = haut
	sh.shape = cy
	sh.position = Vector3(p.x, haut * 0.5, p.y)
	_obstacles.add_child(sh)


func _collision_boite(p: Vector2, taille: Vector2, angle: float,
		haut: float) -> void:
	var sh := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(taille.x, haut, taille.y)
	sh.shape = cb
	sh.position = Vector3(p.x, haut * 0.5, p.y)
	sh.rotation.y = angle
	_obstacles.add_child(sh)
