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
		_batir_arene_blocs()
		print("Arène aux blocs : %.0f × %.0f m · %d pièces · %d apparitions · %d foyers de mobs · bâtie en %d ms."
				% [PlanAreneBlocs.COTE, PlanAreneBlocs.COTE, _props,
					player_spawn_points.size(), mob_spawn_points.size(),
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
	if Cfg.arene_test:
		# L'ARÈNE BORNÉE N'EST PAS LE MONDE OUVERT. La même densité qui
		# sépare les plans sur 156 m LAVE ici la moitié d'un terrain de
		# 80 m : sur les captures, le fond de l'arène partait en voile
		# bleuté et toute l'image semblait délavée — le premier reproche
		# fait à la carte. Densité réduite de moitié, et teinte ramenée
		# vers le sable chaud : la profondeur reste, le voile bleu part.
		# L'ARÈNE AUX BLOCS EST UNE PLANCHE EN PLEIN SOLEIL. La référence
		# est saturée, lumineuse, joyeuse — et le premier rendu sortait
		# kaki : cette brume plus le tonemap filmique sous-exposé
		# mangeaient toute la palette. Brume quasi nulle (elle ne sert
		# qu'à fondre l'horizon), tonemap LINÉAIRE, exposition pleine :
		# les couleurs du kit arrivent à l'écran telles qu'écrites.
		env.fog_density = 0.0007
		env.fog_light_color = Color("e8d9b8")
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.ambient_light_energy = 0.32
		env.ambient_light_color = Color("f2e8d8")
		# Le halo n'a rien à faire ici : la planche est mate. Et sur les
		# dessus clairs il transformait l'écrêtage en aura lumineuse.
		env.glow_enabled = false

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
	# Un cran de plus dans l'arène bornée : ses décors sans texture vivent
	# de leurs faces éclairées, et la brume réduite rend l'écart visible.
	# 0,95 et pas 1,1 : en tonemap linéaire, tout excédent ÉCRÊTE — les
	# dessus éclaircis partaient en blanc et le pavage du sol disparaissait
	# dans la saturation. Vu sur capture : une arène « radioactive ».
	# 0,75 : mesuré en capture — à 0,95, sable et dessus de blocs passaient
	# l'unité en linéaire, écrêtaient au jaune citron et mangeaient le
	# pavage. Le facteur total (soleil × incidence + ambiante) vise 1,0 :
	# la couleur affichée EST l'albédo, ni plus ni moins.
	sun.light_energy = 0.75 if Cfg.arene_test else 1.0
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
## ─── LE POINT EST-IL SUR LE TERRAIN JOUABLE ? ───────────────────────
##
## « Libre d'obstacle » et « dans le terrain » sont DEUX questions
## différentes, et les confondre a coûté un bug visible : l'étoile WANTED
## apparaissait DEHORS, derrière la clôture, impossible à ramasser.
##
## Le calcul de ses points partait des apparitions de joueurs — toutes
## posées sur la périphérie, à 32,5 m — et s'en écartait de neuf mètres.
## Résultat : des candidats à 41,5 m alors que l'enceinte s'arrête à 36.
## `position_libre` répondait « oui » en toute honnêteté : il n'y a
## effectivement aucun obstacle au-delà de la clôture. Il n'y a pas de jeu
## non plus.
##
## L'arène Western est BORNÉE, le monde ouvert est TORIQUE : la réponse
## dépend donc de ce qui a été bâti, et c'est l'arène qui le sait.
func dans_terrain(p: Vector3, marge := 0.0) -> bool:
	if Cfg.arene_test:
		return PlanAreneBlocs.dans_enceinte(Vector2(p.x, p.z), marge)
	# Le monde ouvert n'a pas de dehors : on y est toujours, par
	# construction — c'est tout l'intérêt du repliement.
	return true


## Demi-étendue du terrain jouable, en mètres. Sert à semer des candidats
## sans connaître la forme de l'enceinte.
func demi_terrain() -> float:
	return PlanAreneBlocs.BORD if Cfg.arene_test else PlanMonde.DEMI


## Ramène un point À L'INTÉRIEUR du terrain en le tirant vers le centre.
## Rend `Vector3.INF` si même le centre n'y arrive pas — ce qui ne devrait
## jamais se produire, mais un appelant qui reçoit INF le saura.
func ramener_dans_terrain(p: Vector3, marge := 0.0) -> Vector3:
	if dans_terrain(p, marge):
		return p
	var d := Vector2(p.x, p.z)
	if d.length() < 0.01:
		return Vector3.ZERO
	# Recherche par dichotomie sur le segment centre → point : plus sûr
	# qu'un pas fixe, qui dépendrait de la taille de la carte.
	var bas := 0.0
	var haut := 1.0
	for _i in 18:
		var m := (bas + haut) * 0.5
		if dans_terrain(Vector3(d.x * m, p.y, d.y * m), marge):
			bas = m
		else:
			haut = m
	return Vector3(d.x * bas, p.y, d.y * bas)


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

## Compteur d'alternance des deux formations rocheuses.
var _n_form: int = 0
## Numéro de l'empilement en cours — sert à nommer ses étages.
var _n_pile: int = 0
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


# =========================================================================
# --- L'ARÈNE AUX BLOCS ---------------------------------------------------
# =========================================================================
#
# Le bâtisseur de la carte « Hunt Royale » : il développe le plan
# (PlanAreneBlocs) en trois couches — le sol peint, l'eau, puis les
# modules du kit regroupés en lots MultiMesh. UN matériau pour tout le
# décor, UN appel de dessin par module distinct : la leçon de la carte
# précédente (les appels de dessin se paient en processeur, sur le fil du
# jeu) est appliquée dès la construction au lieu d'être rattrapée après.

## Correspondance nom de teinte → couleur du kit. C'est le SEUL endroit
## où les quartiers rencontrent la palette.
const _TEINTES_BLOCS := {
	"rouge": KitBlocs.ROUGE, "vert": KitBlocs.VERT, "jaune": KitBlocs.JAUNE,
	"violet": KitBlocs.VIOLET, "pierre": KitBlocs.PIERRE,
	"bois": KitBlocs.BOIS,
}


func _batir_arene_blocs() -> void:
	_sol_blocs()
	_eau_blocs()
	_modules_blocs()
	_enceinte_blocs()
	if not Cfg.shadows_enabled():
		_ombres_contact_blocs()

	player_spawn_points.clear()
	for p: Vector2 in PlanAreneBlocs.APPARITIONS:
		# L'ANNEAU PROPOSE, LE TERRAIN DISPOSE. Les apparitions du plan
		# sont un idéal géométrique ; trois d'entre elles tombaient dans
		# une haie ou une enceinte de ruines — mesuré par le banc. Chaque
		# point est donc DÉGAGÉ par l'arène elle-même, puis ramené sur
		# l'île si le dégagement l'a poussé trop loin.
		var s := position_degagee(Vector3(p.x, 0.2, p.y), 0.9)
		if not dans_terrain(s, 1.5):
			s = ramener_dans_terrain(s, 1.5)
		player_spawn_points.append(s)
	mob_spawn_points.clear()
	for p: Vector2 in PlanAreneBlocs.FOYERS_MOBS:
		mob_spawn_points.append(Vector3(p.x, 0.2, p.y))


## LE SOL — un pavage de LOSANGES peint dans les sommets, comme la
## planche : deux ors alternés, joints sombres, allées claires en croix,
## frange d'herbe sur le pourtour de l'île, puis le lointain qui fonce.
## Un seul maillage, un seul appel de dessin, zéro texture.
func _sol_blocs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Demi-diagonale d'une tuile. La tuile est un carré tourné de 45° :
	# c'est exactement le motif de la référence.
	var d := 1.6
	var n := int(64.0 / d)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			# Deux sous-réseaux entrelacés font le pavage complet.
			for sous in 2:
				var c := Vector2((float(i) + 0.5 * sous) * 2.0 * d,
						(float(j) + 0.5 * sous) * 2.0 * d)
				if c.length() > 62.0:
					continue
				var teinte := _teinte_sol_blocs(c, i * 31 + j * 17 + sous * 7)
				var haut := Vector3(c.x, 0.0, c.y - d)
				var droite := Vector3(c.x + d, 0.0, c.y)
				var bas := Vector3(c.x, 0.0, c.y + d)
				var gauche := Vector3(c.x - d, 0.0, c.y)
				var centre := Vector3(c.x, 0.0, c.y)
				var bord := teinte.darkened(0.09)
				# L'ORDRE DES SOMMETS EST LE SENS DU REGARD. Écrit dans
				# l'autre sens, ce pavage se rendait FACE AU SOUS-SOL :
				# vu du ciel, il n'existait pas — diagnostiqué au test du
				# culling coupé, qui l'a fait apparaître verdâtre, éclairé
				# de dos.
				for paire in [[haut, droite], [droite, bas], [bas, gauche],
						[gauche, haut]]:
					st.set_normal(Vector3.UP)
					st.set_color(teinte)
					st.add_vertex(centre)
					for k in 2:
						st.set_normal(Vector3.UP)
						st.set_color(bord)
						st.add_vertex(paire[k])
	var mi := MeshInstance3D.new()
	mi.name = "Sol"
	mi.mesh = st.commit()
	mi.material_override = KitBlocs.materiau()
	mi.position = Vector3(0, -0.008, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# La collision du sol : un seul pavé, sous toute l'île.
	var col := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = Vector3(240, 0.5, 240)
	col.shape = boite
	col.position = Vector3(0, -0.25, 0)
	_obstacles.add_child(col)


## La teinte d'une tuile — TOUT le zonage du sol tient ici.
func _teinte_sol_blocs(c: Vector2, graine: int) -> Color:
	var r := c.length()
	# Damier doré, cassé d'une pointe de hasard stable.
	var t := KitBlocs.SOL if (graine & 1) == 0 else KitBlocs.SOL.darkened(0.028)
	var bruit := float((graine * 2654435761) % 1000) / 1000.0
	t = t.lightened(bruit * 0.035)
	# Les allées, en croix : plus claires, comme le sable damé de la
	# planche. Elles guident vers la place sans jamais être des couloirs.
	if r < 40.0 and (absf(c.x) < 3.4 or absf(c.y) < 3.4):
		t = t.lerp(KitBlocs.CHEMIN, 0.45)
	# La place de l'étoile : un disque à peine rosé qui la nomme.
	if r < 11.0:
		t = t.lerp(KitBlocs.SOL_CLAIR, 0.30)
	# Les abords de la jungle et de l'oasis verdissent : la zone déteint
	# sur son sol, c'est ce qui fait « quartier » vu du ciel.
	for z in [[Vector2(25, 27), 14.0], [Vector2(-23, -23), 13.0]]:
		var e := c.distance_to(z[0])
		if e < z[1]:
			t = t.lerp(KitBlocs.FEUILLE.lightened(0.3),
					(1.0 - e / z[1]) * 0.30)
	# La frange de l'île : l'herbe du pourtour, puis le large qui fonce.
	var enceinte := PlanAreneBlocs.BORD
	# La frange d'herbe est un LISERÉ de deux ou trois tuiles, comme sur
	# la planche — pas une marée. Le premier réglage démarrait à cinq
	# mètres du bord avec une rampe molle : la moitié de l'île virait au
	# vert fluo, mesuré en capture plein cadre.
	if r > enceinte - 2.5:
		t = t.lerp(Color("5da53e"), clampf((r - enceinte + 2.5) / 4.0,
				0.0, 1.0) * 0.65)
	if r > enceinte + 3.0:
		t = t.darkened(clampf((r - enceinte - 3.0) / 8.0, 0.0, 1.0) * 0.8)
	return t


## L'EAU — deux bassins et leur détroit, au shader minimal du kit. L'eau
## est un OBSTACLE : des cylindres invisibles la ferment, et le pont du
## plan enjambe le détroit resté libre.
func _eau_blocs() -> void:
	for b: Dictionary in PlanAreneBlocs.BASSINS:
		var centre: Vector2 = b["centre"]
		var rayon: float = b["rayon"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		const SEG := 22
		for i in SEG:
			var a0 := TAU * float(i) / SEG
			var a1 := TAU * float(i + 1) / SEG
			for v in [Vector3.ZERO,
					Vector3(cos(a0) * rayon, 0, sin(a0) * rayon),
					Vector3(cos(a1) * rayon, 0, sin(a1) * rayon)]:
				st.set_color(Color(0.2, 0.2, 0.2))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.name = "Bassin"
		mi.mesh = st.commit()
		mi.material_override = KitBlocs.materiau_eau()
		# AU-DESSUS du sol (à −0,008), pas en dessous : la première pose à
		# −0,02 mettait toute l'eau SOUS le pavage — deux bassins vides.
		mi.position = Vector3(centre.x, 0.006, centre.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Le liseré du rivage — l'écume claire qui, sur la planche, fait
		# lire « eau » avant même la couleur.
		var anneau := SurfaceTool.new()
		anneau.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in SEG:
			var a0 := TAU * float(i) / SEG
			var a1 := TAU * float(i + 1) / SEG
			var q := [Vector3(cos(a0) * (rayon - 0.10), 0, sin(a0) * (rayon - 0.10)),
					Vector3(cos(a1) * (rayon - 0.10), 0, sin(a1) * (rayon - 0.10)),
					Vector3(cos(a1) * (rayon + 0.42), 0, sin(a1) * (rayon + 0.42)),
					Vector3(cos(a0) * (rayon + 0.42), 0, sin(a0) * (rayon + 0.42))]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for idx: int in tri:
					anneau.set_color(KitBlocs.EAU_BORD)
					anneau.set_normal(Vector3.UP)
					anneau.add_vertex(q[idx])
		var rive := MeshInstance3D.new()
		rive.name = "Rive"
		rive.mesh = anneau.commit()
		rive.material_override = KitBlocs.materiau()
		rive.position = Vector3(centre.x, 0.016, centre.y)
		rive.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rive)
		_poser_collision_ronde(centre, rayon - 0.25, 1.4)
	# Le détroit entre les deux bassins : une nappe d'eau rectangulaire
	# sous le pont. Sa collision est VOLONTAIREMENT absente — le passage
	# du pont est le seul franchissement, et il est au sec.
	var b0: Vector2 = PlanAreneBlocs.BASSINS[0]["centre"]
	var b1: Vector2 = PlanAreneBlocs.BASSINS[1]["centre"]
	var milieu := (b0 + b1) * 0.5
	var axe := (b1 - b0).angle()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var demi_l := b0.distance_to(b1) * 0.5
	var q2 := [Vector3(-demi_l, 0, -2.2), Vector3(demi_l, 0, -2.2),
			Vector3(demi_l, 0, 2.2), Vector3(-demi_l, 0, 2.2)]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for idx: int in tri:
			st2.set_color(Color(0.2, 0.2, 0.2))
			st2.set_normal(Vector3.UP)
			st2.add_vertex(q2[idx])
	var neck := MeshInstance3D.new()
	neck.name = "Detroit"
	neck.mesh = st2.commit()
	neck.material_override = KitBlocs.materiau_eau()
	neck.position = Vector3(milieu.x, 0.006, milieu.y)
	neck.rotation.y = -axe
	neck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neck)


## LES MODULES — chaque pièce du plan rejoint le LOT de sa maille : un
## MultiMesh par module distinct, environ vingt-cinq appels de dessin
## pour tout le décor de l'île. Les collisions, primitives, se posent au
## passage — une boîte ou un cylindre par pièce solide, jamais la
## géométrie visuelle.
func _modules_blocs() -> void:
	var lots: Dictionary = {}
	for e: Dictionary in PlanAreneBlocs.PIECES:
		var maille := _maille_module(e)
		if maille == null:
			continue
		if not lots.has(maille):
			lots[maille] = []
		var pos: Vector2 = e["pos"]
		var a: float = deg_to_rad(float(e.get("a", 0.0)))
		# `y` est l'ÉTAGE : la planche empile de VRAIS cubes, elle n'étire
		# pas de monolithes. Un bloc d'étage est le même cube, posé deux
		# mètres plus haut — même lot, même appel de dessin.
		(lots[maille] as Array).append(Transform3D(
				Basis.from_euler(Vector3(0, -a, 0)),
				Vector3(pos.x, PlanAreneBlocs.LEVEE + float(e.get("y", 0.0)),
						pos.y)))
		# L'étage n'a pas de collision : rien ne vole à trois mètres, et
		# le cube du dessous bloque déjà corps et tirs.
		if float(e.get("y", 0.0)) == 0.0:
			_collision_module(e)
	for maille: Mesh in lots.keys():
		var entrees: Array = lots[maille]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = maille
		mm.instance_count = entrees.size()
		for i in entrees.size():
			mm.set_instance_transform(i, entrees[i])
			# LÉGÈRE VARIATION PAR EXEMPLAIRE — le grain de la planche :
			# deux cubes voisins n'y ont jamais exactement le même ton.
			# La couleur d'instance MULTIPLIE la couleur de sommets.
			var v := 0.94 + float(((i * 2654435761) % 100 + 100) % 100) * 0.0012
			mm.set_instance_color(i, Color(v, v, v))
		var inst := MultiMeshInstance3D.new()
		inst.name = "LotBlocs"
		inst.multimesh = mm
		inst.material_override = KitBlocs.materiau()
		add_child(inst, true)
		_props += entrees.size()


func _maille_module(e: Dictionary) -> Mesh:
	var teinte: Color = _TEINTES_BLOCS.get(e.get("c", "pierre"),
			KitBlocs.PIERRE)
	match e["m"]:
		"bloc": return KitBlocs.bloc(teinte, float(e.get("g", 1.0)))
		"plateforme": return KitBlocs.plateforme()
		"caisse": return KitBlocs.caisse()
		"tonneau": return KitBlocs.tonneau()
		"barriere": return KitBlocs.barriere()
		"palmier": return KitBlocs.palmier()
		"arbre": return KitBlocs.arbre()
		"buisson": return KitBlocs.buisson()
		"cactus": return KitBlocs.cactus()
		"touffe": return KitBlocs.touffe()
		"cabane": return KitBlocs.cabane()
		"machine": return KitBlocs.machine()
		"rocher": return KitBlocs.rocher()
		"pont": return KitBlocs.pont()
	return null


## La collision d'une pièce — la primitive la plus simple qui la couvre.
## Les buissons et les touffes n'en ont AUCUNE : ce sont des CACHES, on
## s'y glisse ; les blocs, murs et bâtiments arrêtent corps et tirs.
func _collision_module(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var a := deg_to_rad(float(e.get("a", 0.0)))
	match e["m"]:
		"bloc":
			var g: float = float(e.get("g", 1.0))
			_collision_boite(p, Vector2(2.0, 2.0), -a, g * 2.0)
		"cabane":
			_collision_boite(p, Vector2(4.2, 3.4), -a, 2.6)
		"machine":
			_collision_boite(p, Vector2(2.4, 1.8), -a, 1.8)
		"rocher":
			_collision_boite(p, Vector2(1.7, 1.4), -a, 1.0)
		"caisse":
			_collision_boite(p, Vector2(1.15, 1.15), -a, 1.1)
		"barriere":
			_collision_boite(p, Vector2(2.6, 0.3), -a, 1.0)
		"tonneau":
			_poser_collision_ronde(p, 0.46, 1.0)
		"palmier":
			_poser_collision_ronde(p, 0.30, 2.6)
		"arbre":
			_poser_collision_ronde(p, 0.34, 2.4)
		"cactus":
			_poser_collision_ronde(p, 0.35, 2.0)


## L'ENCEINTE — invisible. L'île se termine par sa frange de végétation ;
## ce qui retient les joueurs est un anneau de boîtes posé sur le contour
## à congés, épaules comprises. Pas de clôture dessinée : la planche n'en
## a pas.
func _enceinte_blocs() -> void:
	var b := PlanAreneBlocs.BORD + 1.0
	var noyau := b - PlanAreneBlocs.CONGE
	# Les quatre côtés droits.
	for cote in 4:
		var a := TAU * float(cote) / 4.0
		var u := Vector2(cos(a), sin(a))
		var v := Vector2(-u.y, u.x)
		var pas := noyau * 2.0 / 6.0
		for i in 6:
			var t := -noyau + pas * (float(i) + 0.5)
			_collision_boite(u * b + v * t, Vector2(pas + 0.4, 2.0),
					-a + PI * 0.5, 4.0)
	# Les quatre congés, en trois pans chacun.
	for coin in 4:
		var base := TAU * float(coin) / 4.0 + PI * 0.25
		var centre := Vector2(signf(cos(base)) * noyau,
				signf(sin(base)) * noyau)
		for k in 3:
			var a2 := base - PI * 0.20 + PI * 0.20 * float(k)
			var q := centre + Vector2(cos(a2), sin(a2)) * PlanAreneBlocs.CONGE
			_collision_boite(q, Vector2(7.0, 2.0), -a2 + PI * 0.5, 4.0)


## Ombres de contact — mêmes disques que l'arène précédente, mais bâtis
## depuis le PLAN : chaque pièce connaît son emprise, aucun parcours
## d'arbre, aucun socle à deviner.
func _ombres_contact_blocs() -> void:
	var taches: Array[Transform3D] = []
	for e: Dictionary in PlanAreneBlocs.PIECES:
		var emprise := Vector2.ZERO
		match e["m"]:
			"bloc": emprise = Vector2(2.5, 2.5)
			"cabane": emprise = Vector2(5.4, 4.4)
			"machine": emprise = Vector2(3.0, 2.4)
			"rocher": emprise = Vector2(2.3, 2.0)
			"caisse": emprise = Vector2(1.5, 1.5)
			"tonneau": emprise = Vector2(1.15, 1.15)
			"barriere": emprise = Vector2(2.9, 0.9)
			"palmier": emprise = Vector2(1.5, 1.5)
			"arbre": emprise = Vector2(2.3, 2.3)
			"buisson": emprise = Vector2(1.3, 1.3)
			"cactus": emprise = Vector2(1.3, 1.3)
			_: continue
		if float(e.get("y", 0.0)) > 0.0:
			continue
		var p: Vector2 = e["pos"]
		var a := deg_to_rad(float(e.get("a", 0.0)))
		taches.append(Transform3D(
				Basis.from_euler(Vector3(0, -a, 0)) * Basis.from_scale(
						Vector3(emprise.x, 1.0, emprise.y)),
				Vector3(p.x, 0.004, p.y)))
	if taches.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = VisualKit.maille_ombre_contact()
	mm.instance_count = taches.size()
	for i in taches.size():
		mm.set_instance_transform(i, taches[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "OmbresContact"
	mi.multimesh = mm
	mi.material_override = VisualKit.mat_ombre_contact()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
