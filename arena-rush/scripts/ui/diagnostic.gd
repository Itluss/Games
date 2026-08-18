extends Control
class_name Diagnostic
## PANNEAU DE DIAGNOSTIC — TEMPORAIRE, et à retirer une fois la cause tenue.
##
## POURQUOI IL EXISTE. Un aplat brun plein écran est signalé depuis le
## téléphone. Le HUD reste intact, la minicarte fonctionne, les commandes
## répondent, le joueur se déplace, et l'aplat SURVIT À LA MORT ET À LA
## RÉAPPARITION. Neuf sondes ne l'ont pas reproduit sur cette machine.
##
## Les veilles existantes vérifient qu'une caméra existe, qu'un
## environnement existe, qu'un soleil existe, qu'il y a du sol dessous et
## du décor autour. Un monde peut satisfaire les cinq et n'afficher qu'un
## aplat : elles disent que le monde EST LÀ, jamais qu'il est VU.
##
## On arrête donc de chercher à l'aveugle. Ce panneau montre l'état réel du
## rendu, et surtout il permet trois TESTS DE DISCRIMINATION qui découpent
## l'espace des causes en trois :
##
##   1. une caméra neuve et minimale — si l'image revient, la caméra
##      d'arène ou son état est en cause ;
##   2. le décor masqué — si l'image revient, un maillage ou un matériau
##      bouche le cadre ;
##   3. un environnement minimal — si l'image revient, la cause est dans
##      le ciel, la brume, le tonemap ou le halo.
##
## Trois boutons, trois réponses. Aucune ne demande de reproduire quoi que
## ce soit ici : c'est le téléphone qui répond.

const ROUGE := Color("ff5a5a")
const VERT := Color("9ee87f")
const PALE := Color("cfd6e6")
## Période de rafraîchissement. Quatre fois par seconde suffit à lire, et
## ne coûte rien.
const PERIODE := 0.25

var _panneau: PanelContainer
var _texte: RichTextLabel
var _t := 0.0
var _battements_avant := -1
var _cam_debug: Camera3D = null
var _cam_avant: Camera3D = null
var _decor_masque := false
var _env_avant: Environment = null
var _env_minimal: Environment = null


func _ready() -> void:
	name = "Diagnostic"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_construire()
	set_process(true)


func _construire() -> void:
	# LE BOUTON EST PETIT ET DISCRET mais toujours là : il faut pouvoir
	# l'atteindre AU MOMENT du défaut, pas après avoir relancé le jeu.
	var ouvrir := Button.new()
	ouvrir.text = "DIAG"
	ouvrir.focus_mode = Control.FOCUS_NONE
	ouvrir.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ouvrir.offset_left = 8
	ouvrir.offset_top = 118
	ouvrir.offset_right = 78
	ouvrir.offset_bottom = 152
	ouvrir.modulate.a = 0.55
	ouvrir.pressed.connect(func(): _panneau.visible = not _panneau.visible)
	add_child(ouvrir)

	_panneau = PanelContainer.new()
	_panneau.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panneau.offset_left = 8
	_panneau.offset_top = 156
	_panneau.offset_right = 470
	_panneau.offset_bottom = 676
	_panneau.visible = false
	add_child(_panneau)

	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(0.04, 0.05, 0.09, 0.93)
	fond.set_corner_radius_all(10)
	fond.set_content_margin_all(10)
	_panneau.add_theme_stylebox_override(&"panel", fond)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	_panneau.add_child(col)

	_texte = RichTextLabel.new()
	_texte.bbcode_enabled = true
	_texte.fit_content = false
	_texte.scroll_active = false
	_texte.custom_minimum_size = Vector2(444, 392)
	_texte.add_theme_font_size_override(&"normal_font_size", 14)
	col.add_child(_texte)

	var boutons := HBoxContainer.new()
	boutons.add_theme_constant_override(&"separation", 6)
	col.add_child(boutons)
	boutons.add_child(_bouton("CAM NEUVE", _basculer_camera))
	boutons.add_child(_bouton("DÉCOR OFF", _basculer_decor))
	boutons.add_child(_bouton("ENV MINI", _basculer_env))


func _bouton(titre: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = titre
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 46)
	b.pressed.connect(action)
	return b


func _process(delta: float) -> void:
	if not _panneau.visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIODE
	_texte.text = _rapport()


# --- RAPPORT --------------------------------------------------------------

## Un nombre, en rouge s'il n'est pas fini.
##
## C'EST LA MOITIÉ DE L'INTÉRÊT DU PANNEAU. Un NaN qui se propage dans une
## transformation ne se voit nulle part ailleurs : la caméra continue de
## répondre, ses coordonnées s'affichent, et le rendu ne montre plus rien.
func _n(v: float, forme := "%.2f") -> String:
	if is_nan(v) or is_inf(v):
		return "[color=#%s]%s[/color]" % [ROUGE.to_html(false),
				"NaN" if is_nan(v) else "Inf"]
	return forme % v


func _v(p: Vector3) -> String:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return "[color=#%s]NON FINI (%s)[/color]" % [ROUGE.to_html(false), p]
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


func _drapeau(libelle: String, ok: bool) -> String:
	return "[color=#%s]%s[/color]" % [
			(VERT if ok else ROUGE).to_html(false), libelle]


func _rapport() -> String:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	var joueur: Node3D = null
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			joueur = p
			break

	var l: Array[String] = []
	if _cam_debug != null:
		l.append("[b][color=#%s]DEBUG CAMERA NEUVE ACTIVE[/color][/b]"
				% VERT.to_html(false))
	if _decor_masque:
		l.append("[b][color=#%s]DÉCOR MASQUÉ[/color][/b]" % VERT.to_html(false))
	if _env_minimal != null:
		l.append("[b][color=#%s]ENVIRONNEMENT MINIMAL[/color][/b]"
				% VERT.to_html(false))

	if cam == null:
		l.append(_drapeau("AUCUNE CAMÉRA ACTIVE", false))
	else:
		var b := cam.global_transform.basis
		var det := b.determinant()
		l.append("cam #%d  %s  det %s" % [cam.get_instance_id(),
				_drapeau("current", cam.current), _n(det, "%.3f")])
		l.append("  pos %s" % _v(cam.global_position))
		l.append("  fov %s  near %s  far %s"
				% [_n(cam.fov), _n(cam.near, "%.3f"), _n(cam.far, "%.0f")])
		l.append("  h_off %s  v_off %s  masque %d"
				% [_n(cam.h_offset, "%.3f"), _n(cam.v_offset, "%.3f"),
				cam.cull_mask])
		# Une base dont le déterminant s'écarte de 1 n'est plus une
		# rotation : la projection devient dégénérée et plus rien ne passe
		# le test de visibilité, alors que le ciel continue de s'afficher.
		l.append("  base %s" % _drapeau(
				"saine" if absf(det - 1.0) < 0.05 else "DÉGÉNÉRÉE",
				absf(det - 1.0) < 0.05))

	l.append("joueur %s" % (_v(joueur.global_position) if joueur else
			"[color=#%s]ABSENT[/color]" % ROUGE.to_html(false)))

	# LES DEUX LIGNES QUI TRANCHENT.
	#
	# La capture du défaut montre le ciel SEUL — ni sol, ni décor, ni
	# personnage — pendant que la minicarte, elle, situe correctement le
	# joueur au milieu du monde. Le monde existe donc et le joueur y est :
	# c'est la CAMÉRA qui n'est pas là où il faut, ou l'arène qui a cessé de
	# ramener le monde autour d'elle. Ces deux mesures séparent les deux.
	if cam != null and joueur != null:
		var ecart := PlanMonde.distance3(cam.global_position,
				joueur.global_position)
		l.append("cam↔joueur %s   (plat %s)"
				% [_drapeau(_n(ecart, "%.1f m"), ecart < 30.0),
				_n(cam.global_position.distance_to(joueur.global_position),
						"%.1f m")])
	var arene0 := get_tree().get_first_node_in_group(&"arene")
	if arene0 != null:
		var bat: int = arene0.get(&"battements")
		var vif := bat != _battements_avant
		_battements_avant = bat
		l.append("arène %s (%d battements)"
				% [_drapeau("tourne" if vif else "FIGÉE", vif), bat])
	var cam_arene := get_tree().get_first_node_in_group(&"camera_arene")
	if cam_arene != null:
		var cible = cam_arene.get(&"target")
		var valide: bool = cible != null and is_instance_valid(cible)
		l.append("cible caméra %s   dégagement %s"
				% [_drapeau("valide" if valide else "PERDUE", valide),
				_n(cam_arene.get(&"_degagement"), "%.2f")])
	l.append("ancre %s" % _v(PlanMonde.ancre))

	var monde := vp.world_3d if vp else null
	l.append("world3d #%s   env #%s" % [
			monde.get_instance_id() if monde else "—",
			monde.environment.get_instance_id() if monde and monde.environment
					else "—"])

	# LE SOL, ET C'EST LA LIGNE QUI COMPTE.
	#
	# L'aplat plein écran est l'HÉMISPHÈRE BAS DU CIEL PROCÉDURAL : il était
	# bleu nuit tant que le ciel était un crépuscule, il est brun depuis que
	# le ciel est un plein jour. La couleur du défaut a suivi celle du ciel
	# à la lettre, ce qui ne laisse qu'une lecture : le sol du monde n'est
	# PAS DESSINÉ, et l'on voit le ciel à sa place.
	#
	# Reste à savoir pourquoi. Ces trois nombres répondent : combien de
	# dalles existent, combien sont visibles, et à quelle distance se
	# trouve la plus proche de la caméra.
	var dalles := get_tree().get_nodes_in_group(&"dalles_sol")
	var vues := 0
	var plus_proche := INF
	var pos_cam := cam.global_position if cam else Vector3.ZERO
	for d in dalles:
		var mi := d as MeshInstance3D
		if mi == null:
			continue
		if mi.is_visible_in_tree():
			vues += 1
		var dist := Vector2(mi.global_position.x - pos_cam.x,
				mi.global_position.z - pos_cam.z).length()
		plus_proche = minf(plus_proche, dist)
	l.append("sol %s dalles, %d visibles, plus proche %s"
			% [_drapeau(str(dalles.size()), dalles.size() > 0),
			vues, _drapeau(_n(plus_proche, "%.1f m"), plus_proche < 40.0)])

	var c := _compter()
	l.append("meshes visibles %d/%d   géom. %d" % [c["mesh_vus"], c["mesh"],
			c["geom"]])
	l.append("WorldEnvironment %d   Camera3D %d   cellules %d"
			% [c["env"], c["cam"], c["cellules"]])
	l.append("dessins %d   nœuds %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var arene := get_tree().get_first_node_in_group(&"arene")
	if arene:
		l.append("toit voilé %s   répit %s" % [arene.get(&"_toit_voile"),
				_n(arene.get(&"_repit"), "%.2f")])
	l.append("Fx.camera %s   time_scale %s" % [
			"oui" if Fx.camera != null else _drapeau("NON", false),
			_n(Engine.time_scale, "%.2f")])
	return "\n".join(l)


## Recense l'arbre de rendu. Le comptage est volontairement complet plutôt
## que rapide : quatre fois par seconde, et seulement panneau ouvert.
func _compter() -> Dictionary:
	var r := {"mesh": 0, "mesh_vus": 0, "geom": 0, "env": 0, "cam": 0,
			"cellules": 0}
	var pile: Array[Node] = [get_tree().root]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if n is MeshInstance3D:
			r["mesh"] += 1
			if (n as MeshInstance3D).is_visible_in_tree():
				r["mesh_vus"] += 1
		if n is GeometryInstance3D:
			r["geom"] += 1
		elif n is WorldEnvironment:
			r["env"] += 1
		elif n is Camera3D:
			r["cam"] += 1
		for e in n.get_children():
			pile.append(e)
	var arene := get_tree().get_first_node_in_group(&"arene")
	if arene:
		var conteneurs = arene.get(&"_conteneurs")
		if conteneurs is Array:
			r["cellules"] = (conteneurs as Array).size()
	return r


# --- TEST 1 : CAMÉRA NEUVE ------------------------------------------------

## Une caméra NEUVE, MINIMALE, sans rien de ce que fait l'ArenaCamera.
##
## Pas de lissage, pas de dégagement, pas d'avance sur la visée, pas de
## voile de toit, pas d'offset. Si le monde réapparaît, la cause est dans
## la caméra d'arène ou dans son état ; s'il reste brun, elle est innocente
## et il faut chercher ailleurs.
func _basculer_camera() -> void:
	if _cam_debug != null:
		_cam_debug.queue_free()
		_cam_debug = null
		if _cam_avant != null and is_instance_valid(_cam_avant):
			_cam_avant.make_current()
		return
	var joueur: Node3D = null
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			joueur = p
			break
	if joueur == null:
		return
	_cam_avant = get_viewport().get_camera_3d()
	_cam_debug = Camera3D.new()
	_cam_debug.name = "CameraDebug"
	_cam_debug.fov = 58.0
	_cam_debug.near = 0.05
	_cam_debug.far = 400.0
	# Sous la scène courante, donc dans le même World3D que le jeu : on
	# teste la caméra, pas le monde.
	get_tree().current_scene.add_child(_cam_debug)
	_cam_debug.global_position = joueur.global_position + Vector3(0.0, 10.4, 8.0)
	_cam_debug.look_at(joueur.global_position, Vector3.UP)
	_cam_debug.make_current()


func _process_camera_debug() -> void:
	pass


# --- TEST 2 : DÉCOR MASQUÉ ------------------------------------------------

## Masque les CELLULES de décor et les repères, garde le sol, le joueur et
## les mobs.
##
## Si l'image revient, c'est un maillage ou un matériau qui bouche le
## cadre. Si rien ne change, le décor est hors de cause.
func _basculer_decor() -> void:
	var arene := get_tree().get_first_node_in_group(&"arene")
	if arene == null:
		return
	_decor_masque = not _decor_masque
	var conteneurs = arene.get(&"_conteneurs")
	if not (conteneurs is Array):
		return
	for n in (conteneurs as Array):
		var g := n as Node3D
		if g == null:
			continue
		for e in g.get_children():
			var mi := e as MeshInstance3D
			var mm := e as MultiMeshInstance3D
			# LE SOL RESTE. Il est fait d'un seul maillage par cellule, sans
			# multimaillage : on le reconnaît à cela, et on le garde pour
			# pouvoir juger si le cadre s'éclaircit.
			if mm != null:
				mm.visible = not _decor_masque
			elif mi != null and mi.name != "Sol":
				mi.visible = not _decor_masque


# --- TEST 3 : ENVIRONNEMENT MINIMAL ---------------------------------------

## Remplace l'ambiance par la plus simple possible : fond uni, aucune
## brume, aucun halo, aucun ajustement, aucun tonemap particulier.
##
## Si l'image revient, la cause est dans les réglages de rendu et non dans
## la géométrie.
func _basculer_env() -> void:
	var monde := get_viewport().world_3d
	if monde == null:
		return
	if _env_minimal != null:
		monde.environment = _env_avant
		_env_minimal = null
		return
	_env_avant = monde.environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.16, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env.fog_enabled = false
	env.glow_enabled = false
	env.adjustment_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	_env_minimal = env
	monde.environment = env
