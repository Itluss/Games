extends Node
## EFFETS ET « JUICE » — secousse caméra, arrêt sur image, particules.
##
## Les effets visuels sont ici traités comme du GAMEPLAY, pas comme de la
## décoration : ce sont eux qui disent au joueur « ton coup a porté »,
## « tu as pris un coup », « ce mob va exploser ». Ils sont donc
## centralisés pour rester dosés — un effet ajouté au hasard dans un coin
## finit toujours par saturer l'écran.
##
## Tout passe par `Cfg.fx_scale()` : baisser la qualité réduit les
## particules sans jamais changer ce qui est jouable.
##
## Autoload : Fx

## Caméra active, enregistrée par elle-même au démarrage. On ne la cherche
## pas dans l'arbre à chaque impact.
var camera: Camera3D = null

var _shake_strength: float = 0.0
var _shake_decay: float = 16.0
var _noise_t: float = 0.0
var _hit_stop_until: float = 0.0

## Délai minimal entre deux arrêts sur image. Sans lui, chaque mort de mob
## en déclenchait un : avec vingt mobs, le jeu se figeait par micro-coups
## en continu et le joueur ressentait une saccade, pas de l'impact.
const HIT_STOP_COOLDOWN := 0.45
var _next_hit_stop_allowed: float = 0.0

func _process(delta: float) -> void:
	# L'arrêt sur image utilise le temps RÉEL : sinon il ne se terminerait
	# jamais, puisqu'il ralentit précisément l'horloge qui le mesure.
	if _hit_stop_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _hit_stop_until:
		_hit_stop_until = 0.0
		Engine.time_scale = 1.0

	if _shake_strength <= 0.001 or camera == null:
		return
	_noise_t += delta * 34.0
	# Décroissance EXPONENTIELLE franche, avec extinction nette. L'ancienne
	# formule mettait près d'une seconde à retomber : à six tirs par
	# seconde, la secousse ne s'éteignait jamais et laissait une
	# oscillation permanente d'environ 5 Hz — un tremblement, pas du punch.
	_shake_strength *= exp(-_shake_decay * delta)
	if _shake_strength < 0.004:
		_shake_strength = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	var amp := _shake_strength
	# Décalage de l'offset seulement : on ne touche jamais à la position de
	# la caméra, que le suivi du joueur pilote déjà.
	camera.h_offset = sin(_noise_t) * amp * 0.5
	camera.v_offset = cos(_noise_t * 1.37) * amp * 0.5
	if _shake_strength <= 0.001:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

## Secousse caméra. `amount` ~0.1 pour un tir léger, ~0.6 pour une explosion.
func shake(amount: float) -> void:
	if Cfg.quality == Cfg.Quality.LOW:
		amount *= 0.5
	# Plafond bas : des secousses qui s'empilent produisent une vibration
	# continue au lieu d'accents distincts.
	_shake_strength = minf(0.55, _shake_strength + amount)

## Micro-suspension du temps sur un impact important. Très court par
## conception : au-delà de ~120 ms, ça ne donne plus du punch mais du lag.
func hit_stop(duration: float = 0.05, scale: float = 0.05) -> void:
	if Cfg.quality == Cfg.Quality.LOW:
		return
	var now := Time.get_ticks_msec() / 1000.0
	# Un arrêt sur image n'a de valeur que s'il reste RARE.
	if now < _next_hit_stop_allowed:
		return
	_next_hit_stop_allowed = now + HIT_STOP_COOLDOWN
	Engine.time_scale = scale
	_hit_stop_until = now + duration

## Secousse ATTÉNUÉE PAR LA DISTANCE.
##
## Un mob qui meurt à l'autre bout de l'arène ne doit pas secouer l'écran.
## Sans atténuation, une vague de vingt mobs faisait trembler la caméra en
## permanence — ce qui se lit comme une saccade, jamais comme du punch.
func shake_at(pos: Vector3, amount: float) -> void:
	if camera == null:
		shake(amount)
		return
	var d := PlanMonde.distance3(camera.global_position, pos)
	# Pleine intensité sous 10 m, plus rien au-delà de 32 m.
	var falloff := clampf(1.0 - (d - 10.0) / 22.0, 0.0, 1.0)
	if falloff <= 0.02:
		return
	shake(amount * falloff)

func _parent_for(node: Node) -> Node:
	# Les effets vivent dans l'arbre courant : ils disparaissent donc
	# automatiquement au changement de scène, sans nettoyage manuel.
	var tree := get_tree()
	return tree.current_scene if tree and tree.current_scene else self

# --- GERBES DE PARTICULES -------------------------------------------------

## POURQUOI CE CODE A ÉTÉ ENTIÈREMENT REPRIS.
##
## Chaque impact, chaque mort, chaque ramassage construisait SIX objets
## neufs : un nœud de particules, un matériau de traitement, une courbe,
## une texture de courbe, un maillage et un matériau lumineux. Puis les
## détruisait un demi-seconde plus tard. À trente mobs et une gâchette
## maintenue, cela fait plusieurs dizaines de constructions par seconde.
##
## Ce n'est pas une dépense de calcul ordinaire : créer un maillage envoie
## des sommets à la carte graphique, créer un matériau de particules monte
## un jeu d'uniformes. Sur le pilote d'un téléphone, ces opérations-là ne
## se répartissent pas dans le temps — elles bloquent. C'est la signature
## exacte des « petits lags de temps en temps » signalés en jeu.
##
## Désormais : le maillage est UNIQUE pour tout le jeu, les matériaux sont
## mis en cache par teinte, et les nœuds de particules sont RECYCLÉS. Une
## gerbe ne coûte plus qu'un réglage de position et un signal de départ.

## Réservoir de nœuds de particules disponibles.
var _gerbes_libres: Array[GPUParticles3D] = []
## Matériaux de traitement, par signature d'effet.
var _mat_gerbe: Dictionary = {}
## Matériaux lumineux, par teinte.
var _mat_lueur: Dictionary = {}
## Maillage des particules — un seul pour tout le jeu.
var _grain: SphereMesh = null
## Courbe de taille — une seule, partagée par tous les matériaux.
var _courbe: CurveTexture = null

## Capacité fixe d'un nœud de particules.
##
## ELLE NE CHANGE JAMAIS, et c'est le cœur du recyclage : modifier `amount`
## réalloue le tampon de la carte graphique, ce qui ramènerait exactement la
## dépense qu'on cherche à supprimer. On règle `amount_ratio`, qui ne fait
## qu'en émettre une part.
const GRAINS := 36


func _grain_partage() -> SphereMesh:
	if _grain == null:
		_grain = SphereMesh.new()
		_grain.radius = 0.09
		_grain.height = 0.18
		_grain.radial_segments = 6
		_grain.rings = 3
	return _grain


func _courbe_partagee() -> CurveTexture:
	if _courbe == null:
		# La courbe fait « éclore puis disparaître » : sans elle les
		# particules s'éteignent brutalement et l'effet paraît bon marché.
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.2))
		c.add_point(Vector2(0.25, 1.0))
		c.add_point(Vector2(1.0, 0.0))
		_courbe = CurveTexture.new()
		_courbe.curve = c
	return _courbe


func _lueur(color: Color) -> StandardMaterial3D:
	var cle := color.to_html(false)
	if not _mat_lueur.has(cle):
		_mat_lueur[cle] = VisualKit.glow_mat(color, 2.6)
	var m: StandardMaterial3D = _mat_lueur[cle]
	return m


## LUEUR VISIBLE DES DEUX CÔTÉS.
##
## L'étoile est un maillage plat écrit à la main : selon le sens de
## rotation de ses triangles, une face sur deux pourrait être écartée. On
## retire la question au lieu d'y répondre — une étoile plate, brève et
## lumineuse n'a rien à gagner au tri des faces arrière.
##
## ATTENTION, CE N'ÉTAIT PAS LA CAUSE DE L'ÉTOILE INVISIBLE, et je l'ai
## cru une demi-heure. `glow_mat` désactivait déjà ce tri. Le vrai coupable
## était la DURÉE : soixante millisecondes d'effet, contre trois cents
## millisecondes par image dans le rendu logiciel des bancs. L'étoile
## naissait et mourait entre deux images. En jeu, à soixante images par
## seconde, elle occupe quatre images — c'est le bon réglage. Cette
## fonction reste parce qu'elle est juste, pas parce qu'elle a corrigé
## quoi que ce soit.
func _lueur_deux_faces(color: Color) -> StandardMaterial3D:
	var cle := color.to_html(false) + "|2f"
	if not _mat_lueur.has(cle):
		var m := VisualKit.glow_mat(color, 2.6)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		_mat_lueur[cle] = m
	var connu: StandardMaterial3D = _mat_lueur[cle]
	return connu


func _materiau_gerbe(color: Color, velocity: float, radius: float,
		gravity: float) -> ParticleProcessMaterial:
	# La signature ne retient que ce qui distingue VRAIMENT deux effets. Les
	# vitesses sont arrondies au dixième : sans cet arrondi, un flottant
	# calculé ferait une clé nouvelle à chaque appel et le cache ne
	# servirait à rien — il grossirait, ce qui est pire que pas de cache.
	var cle := "%s|%.1f|%.1f|%.1f" % [color.to_html(false), velocity, radius,
			gravity]
	if _mat_gerbe.has(cle):
		var connu: ParticleProcessMaterial = _mat_gerbe[cle]
		return connu
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0
	m.initial_velocity_min = velocity * 0.4
	m.initial_velocity_max = velocity
	m.gravity = Vector3(0, gravity, 0)
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.25
	m.scale_max = 0.7
	m.scale_curve = _courbe_partagee()
	m.color = color
	_mat_gerbe[cle] = m
	return m


func _emit_burst(parent: Node, pos: Vector3, color: Color, amount: int,
		velocity: float, radius: float, lifetime: float,
		gravity: float = -6.0) -> void:
	var scaled := maxi(3, int(amount * Cfg.fx_scale()))
	var p: GPUParticles3D = null
	while p == null and not _gerbes_libres.is_empty():
		var candidat: GPUParticles3D = _gerbes_libres.pop_back()
		if is_instance_valid(candidat):
			p = candidat
	if p == null:
		p = GPUParticles3D.new()
		p.amount = GRAINS
		p.one_shot = true
		p.explosiveness = 1.0
		p.draw_pass_1 = _grain_partage()
	else:
		# Le nœud recyclé peut encore appartenir à une scène détruite.
		var ancien := p.get_parent()
		if ancien != null:
			ancien.remove_child(p)

	p.amount_ratio = clampf(float(scaled) / float(GRAINS), 0.05, 1.0)
	p.lifetime = lifetime
	p.process_material = _materiau_gerbe(color, velocity, radius, gravity)
	p.material_override = _lueur(color)
	p.position = pos
	parent.add_child(p)
	p.restart()
	p.emitting = true
	_ranger(p, lifetime + 0.4)


## Nombre de gerbes en attente de réemploi. Exposé pour les bancs de test :
## sans lui, on ne peut pas distinguer « ça marche » de « ça reconstruit
## tout à chaque fois », qui donnent la même image.
func reservoir() -> int:
	return _gerbes_libres.size()


## Remet une gerbe au réservoir quand elle a fini de vivre.
func _ranger(p: GPUParticles3D, delai: float) -> void:
	var t := get_tree().create_timer(delai, false)
	await t.timeout
	if not is_instance_valid(p):
		return
	p.emitting = false
	var parent := p.get_parent()
	if parent != null:
		parent.remove_child(p)
	# PLAFOND SUR LE RÉSERVOIR. Sans lui, une bataille de cent gerbes
	# laisserait cent nœuds en mémoire pour toujours ; au-delà, on rend au
	# système ce qui ne resservira pas.
	if _gerbes_libres.size() < 24:
		_gerbes_libres.append(p)
	else:
		p.queue_free()


## Lumière brève. Sur mobile les lumières dynamiques coûtent cher : elles
## sont donc réservées aux évènements FORTS et supprimées aussitôt.
func _flash_light(parent: Node, pos: Vector3, color: Color, energy: float,
		range_m: float, duration: float) -> void:
	if Cfg.quality == Cfg.Quality.LOW:
		return
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)

func _autofree(node: Node, delay: float) -> void:
	var t := get_tree().create_timer(delay, false)
	t.timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())

# --- EFFETS DE JEU -------------------------------------------------------

## Départ de coup : éclair de bouche court et lumineux.
## ─── LES FORMES DE DÉPART ET D'IMPACT ──────────────────────────────────
##
## POURQUOI UNE ÉTOILE EN MAILLAGE, ET PAS SEULEMENT DES PARTICULES.
##
## La consigne est qu'un joueur reconnaisse l'arme SANS la couleur. Une
## gerbe de particules ne se distingue d'une autre gerbe que par sa teinte
## et sa densité : passée en niveaux de gris, elle ne dit plus rien. Une
## ÉTOILE À TROIS BRANCHES et une ÉTOILE À SEPT BRANCHES restent
## différentes en gris, et c'est le seul test qui compte.
##
## Chaque étoile est un maillage plat dans le plan du sol. La caméra plonge
## à 52° : une étoile horizontale y est vue à peine raccourcie, alors
## qu'une étoile verticale se réduirait à un trait.

## Étoiles en attente de réemploi. Dix joueurs à cinq coups par seconde
## font cinquante départs par seconde : les créer et les détruire à ce
## rythme serait une allocation permanente sur un téléphone.
var _etoiles_libres: Array[MeshInstance3D] = []
var _mesh_etoile: Dictionary = {}
var _mesh_gerbe: Dictionary = {}
var _mesh_tore: TorusMesh = null


## GERBE DE DÉPART — des pointes projetées VERS L'AVANT, dans le plan du sol.
##
## C'EST LA FORME QUE MONTRE LA PLANCHE, et ce n'était pas ce que j'avais
## fait. J'avais posé une étoile SYMÉTRIQUE en panneau face caméra : jolie
## peut-être, mais elle ne dit pas d'où part le coup ni où il va. La
## planche dessine autre chose — une gerbe qui jaillit du canon, une longue
## pointe dans l'axe du tir, deux ou trois pointes obliques plus courtes, et
## presque rien vers l'arrière.
##
## Elle est bâtie dans le PLAN DU SOL, +X vers l'avant du tir. Sur une vue
## de dessus, c'est ce plan-là qui porte la direction : une gerbe couchée
## dit « ça part par là », un panneau face caméra ne dit rien.
##
## `allongement` étire les pointes avant sans toucher aux latérales : c'est
## lui qui sépare la langue de feu de Bruno du petit dard de Nox.
func _gerbe(branches: int, allongement: float) -> ArrayMesh:
	var cle := "%d|%.1f" % [branches, allongement]
	if _mesh_gerbe.has(cle):
		var connu: ArrayMesh = _mesh_gerbe[cle]
		return connu
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in branches:
		var a := TAU * (float(i) + 0.5) / float(branches)
		# Le profil de longueur : plein devant, écrasé derrière. La
		# puissance 1,6 resserre la gerbe dans l'axe au lieu de l'ouvrir en
		# soleil — c'est ce qui la fait lire comme une direction.
		var vers_avant: float = maxf(cos(a), 0.0)
		var l: float = 0.22 + pow(vers_avant, 1.6) * allongement
		var pointe := Vector3(cos(a) * l, 0, sin(a) * l)
		var large := 0.13
		var g := Vector3(cos(a - large), 0, sin(a - large)) * 0.20
		var d := Vector3(cos(a + large), 0, sin(a + large)) * 0.20
		for v in [Vector3.ZERO, d, pointe, Vector3.ZERO, pointe, g]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		# Chaque pointe est doublée en miroir : la gerbe se voit d'en haut
		# ET de dessous, sans dépendre du sens de rotation des triangles.
		for v in [Vector3.ZERO, pointe, d, Vector3.ZERO, g, pointe]:
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v)
	var m := st.commit()
	_mesh_gerbe[cle] = m
	return m


## Pose une gerbe de départ orientée dans l'axe du tir.
func _poser_gerbe(parent: Node, pos: Vector3, dir: Vector3, color: Color,
		branches: int, allongement: float, taille: float,
		duree: float) -> void:
	# ─── DEUX GERBES CROISÉES, ET C'EST CE QUI LA REND VISIBLE ─────────
	#
	# Une seule gerbe couchée dans le plan du sol était ÉCRASÉE par la
	# caméra : elle plonge à 52°, et c'est justement l'axe du tir — donc la
	# longue pointe avant — qui s'y raccourcit le plus. Le rendu ne montrait
	# qu'un trait pâle en travers du canon.
	#
	# On en pose donc DEUX, la seconde roulée d'un quart de tour autour de
	# l'axe du tir. Le volume obtenu se lit depuis n'importe quel angle, et
	# la pointe avant garde sa longueur quoi qu'il arrive. Deux maillages au
	# lieu d'un, sur un effet qui dure soixante millisecondes : le coût est
	# nul, la lisibilité change du tout au tout.
	var lacet := atan2(-dir.z, dir.x)
	for roulis in 2:
		var mi := _prendre_maille()
		mi.mesh = _gerbe(branches, allongement)
		var m := _teinter(mi, color, 5.0, false)
		mi.position = pos
		# Le maillage a son avant sur +X ; on l'aligne sur le tir, puis on
		# roule la seconde autour de ce même axe.
		mi.basis = Basis.from_euler(Vector3(0.0, lacet, 0.0)) \
				* Basis(Vector3.RIGHT, PI * 0.5 * float(roulis))
		mi.scale = Vector3.ONE * taille * 0.5
		parent.add_child(mi)
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(mi, "scale", Vector3.ONE * taille, duree) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(m, "albedo_color:a", 0.0, duree) \
				.set_ease(Tween.EASE_IN)
		t.chain().tween_callback(func():
			m.albedo_color.a = 1.0
			_rendre_maille(mi))


## Prend une maille au réservoir, ou en fabrique une.
func _prendre_maille() -> MeshInstance3D:
	var mi: MeshInstance3D = null
	while mi == null and not _etoiles_libres.is_empty():
		var candidat: MeshInstance3D = _etoiles_libres.pop_back()
		if is_instance_valid(candidat):
			mi = candidat
	if mi == null:
		mi = MeshInstance3D.new()
		# NOMMÉE, et pas seulement pour la lisibilité des rapports : c'est
		# ce nom qui permet à un banc de faire le ménage entre deux essais
		# sans emporter le décor avec les effets.
		mi.name = "EtoileFx"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# ─── UN MATÉRIAU PAR MAILLE, ET C'EST INDISPENSABLE ────────────
		#
		# Les matériaux du cache sont PARTAGÉS : y animer une transparence
		# ferait disparaître d'un coup toutes les gerbes de la même
		# couleur, y compris celles qui viennent de naître. Chaque maille
		# du réservoir porte donc le sien, créé une fois pour toutes et
		# reconfiguré à chaque emploi. Le réservoir supprime le coût ; le
		# matériau privé rend le fondu possible.
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# ─── MÉLANGE NORMAL, PLUS ADDITIF ──────────────────────────────
		#
		# `glow_mat` avait déjà tiré cette leçon pour les projectiles ; les
		# mailles du réservoir, elles, étaient restées en additif. Sur le
		# sable en plein soleil, ajouter de l'or à du beige clair donne du
		# blanc : l'éclair de bouche de Milo se rendait en rayures
		# blanches, et celui de Ruby en anneau blanc. Aucune des deux
		# identités ne survivait à ça.
		#
		# En mélange normal, la teinte REMPLACE le fond ; une étoile or sur
		# du sable se lit, une étoile rose aussi. Le débordement lumineux
		# reste assuré par la sur-exposition de l'albédo (`_teinter`).
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.disable_receive_shadows = true
		mi.material_override = m
	else:
		var ancien := mi.get_parent()
		if ancien != null:
			ancien.remove_child(mi)
	return mi


## Règle le matériau privé d'une maille. `energie` au-dessus de 1 est ce qui
## la fait DÉBORDER dans le halo — c'est de là que vient l'éclat.
func _teinter(mi: MeshInstance3D, color: Color, energie: float,
		panneau: bool) -> StandardMaterial3D:
	var m := mi.material_override as StandardMaterial3D
	# L'ÉNERGIE PASSE PAR L'ALBÉDO. En mode non éclairé, Godot n'ajoute
	# jamais l'émission : ce paramètre ne servait à rien depuis le premier
	# jour (démonstration chiffrée au-dessus de `VisualKit.noyau_mat`).
	# La sur-exposition plafonne le canal dominant pour que la teinte
	# survive au lieu de virer au blanc.
	m.albedo_color = VisualKit.sur_expose(color, energie, 1.0)
	m.emission = color
	m.emission_energy_multiplier = energie
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if panneau \
			else BaseMaterial3D.BILLBOARD_DISABLED
	m.billboard_keep_scale = panneau
	return m


## ANNEAU DE CHOC — l'élément qui manquait le plus.
##
## C'est lui qui donne à un tir sa DÉTONATION : un cercle qui jaillit du
## canon, s'ouvre en quelques dizaines de millisecondes et s'efface. Sans
## lui, un départ n'est qu'une lumière ; avec lui, c'est un événement. Et
## comme il est fin et qu'il disparaît vite, il n'occulte jamais personne —
## ce que la planche interdit explicitement.
##
## `normale` porte son axe : dans l'axe du tir pour un départ (l'anneau
## part vers l'avant), vers le haut pour un impact (il s'étale au sol).
func _anneau(parent: Node, pos: Vector3, normale: Vector3, color: Color,
		rayon: float, duree: float, energie := 3.4) -> void:
	var mi := _prendre_maille()
	mi.mesh = _tore()
	var m := _teinter(mi, color, energie, false)
	mi.position = pos
	# L'axe d'un tore Godot est +Y ; on l'aligne sur la normale demandée.
	var axe := normale.normalized()
	if absf(axe.dot(Vector3.UP)) < 0.999:
		var droite := Vector3.UP.cross(axe).normalized()
		mi.basis = Basis(droite, axe, droite.cross(axe))
	else:
		mi.basis = Basis.IDENTITY
	mi.scale = Vector3.ONE * rayon * 0.12
	parent.add_child(mi)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * rayon, duree) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	t.tween_property(m, "albedo_color:a", 0.0, duree) \
			.set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func():
		m.albedo_color.a = 1.0
		_rendre_maille(mi))


func _tore() -> TorusMesh:
	if _mesh_tore == null:
		_mesh_tore = TorusMesh.new()
		_mesh_tore.inner_radius = 0.86
		_mesh_tore.outer_radius = 1.0
		_mesh_tore.rings = 24
		_mesh_tore.ring_segments = 6
	return _mesh_tore


func _rendre_maille(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi):
		return
	var p := mi.get_parent()
	if p != null:
		p.remove_child(mi)
	_etoiles_libres.append(mi)


## Maillage d'étoile à `branches` branches, dans le plan XY, rayon 1.
##
## LE PLAN XY, ET PAS XZ, PARCE QUE L'ÉTOILE EST UN PANNEAU TOURNÉ VERS LA
## CAMÉRA. Posée à plat dans le plan du sol, elle était vue sous 52° :
## écrasée en ellipse, sa branche la plus proche recouvrait les jambes du
## personnage et on ne lisait plus ni ses pointes ni leur nombre. Or c'est
## le NOMBRE DE BRANCHES qui sépare Gus de Milo une fois la couleur
## retirée. Un panneau garde sa forme quel que soit l'angle — et la planche
## de référence dessine bien des étoiles plates, pas des soleils au sol.
## `phase` fait TOURNER LA FORME ELLE-MÊME, et pas le nœud qui la porte.
##
## Le panneau du départ regarde toujours la caméra : lui appliquer une
## rotation n'a aucun effet, le moteur la remplace. Pour que la silhouette
## change d'un tir à l'autre — ce dont Gus a besoin, et ce qui doit rester
## vrai en niveaux de gris — il faut donc une AUTRE maille, cuite une fois
## et gardée en cache comme les autres.
func _etoile(branches: int, phase: float = 0.0) -> ArrayMesh:
	var cle := "%d:%.3f" % [branches, phase]
	if _mesh_etoile.has(cle):
		var connu: ArrayMesh = _mesh_etoile[cle]
		return connu
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# ─── UNE ÉTOILE A UN CORPS, PAS SEULEMENT DES RAYONS ───────────────
	#
	# La version précédente n'était QUE des rayons, larges de 0,05 radian
	# à un rayon de 0,14 — soit sept millimètres. À l'écran, ça ne faisait
	# pas une étoile : ça faisait des cheveux. Ce qu'on voyait du départ de
	# Milo, c'était en réalité la gerbe couchée derrière, et l'étoile
	# passait pour un trait.
	#
	# On dessine donc un DISQUE central plein, d'où partent des rayons
	# effilés mais assez larges à la base pour se lire. C'est la forme que
	# la planche dessine : un cœur lumineux et des pointes franches.
	var base := 0.30
	var large := 0.34
	var seg := maxi(branches * 3, 12)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(cos(a0), sin(a0), 0) * base)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(cos(a1), sin(a1), 0) * base)
	for i in branches:
		var a := TAU * float(i) / float(branches) + phase
		# L'ALTERNANCE N'A DE SENS QUE SUR UN NOMBRE PAIR. À cinq branches,
		# elle laissait DEUX grands rayons côte à côte et une étoile
		# bancale ; or cinq branches, c'est exactement ce que la planche
		# dessine pour Milo et pour Ruby. Sur un nombre impair, on garde
		# donc des rayons égaux.
		var l: float = 1.0
		if branches % 2 == 0 and i % 2 == 1:
			l = 0.46
		var pointe := Vector3(cos(a) * l, sin(a) * l, 0)
		var g := Vector3(cos(a - large), sin(a - large), 0) * base
		var d := Vector3(cos(a + large), sin(a + large), 0) * base
		for v in [g, d, pointe]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(v)
	var m := st.commit()
	_mesh_etoile[cle] = m
	return m


## Pose une étoile qui grandit et s'efface. `duree` doit rester courte :
## un départ qui traîne masque le personnage, ce que la consigne interdit.
func _poser_etoile(parent: Node, pos: Vector3, color: Color, branches: int,
		rayon: float, duree: float, phase: float = 0.0) -> void:
	var mi := _prendre_maille()
	mi.mesh = _etoile(branches, phase)
	var m := _teinter(mi, color, 5.0, true)
	mi.position = pos
	# Le panneau ignore la rotation du nœud : la variété vient du nombre de
	# branches et de la taille, pas d'un angle.
	mi.rotation = Vector3.ZERO
	mi.scale = Vector3.ONE * rayon * 0.35
	parent.add_child(mi)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * rayon, duree) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(m, "albedo_color:a", 0.0, duree) \
			.set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func():
		m.albedo_color.a = 1.0
		_rendre_maille(mi))


## DÉPART DE TIR, selon le profil de l'arme. C'est la première demi-seconde
## de l'identité : le joueur doit savoir qui tire avant de voir la balle.
func depart(parent: Node, pos: Vector3, dir: Vector3, profil: ProfilTir,
		color: Color) -> void:
	var t: float = profil.flash_taille
	# LE CŒUR EST PRESQUE BLANC CHEZ TOUS. La planche le montre sur les six :
	# une gerbe colorée avec un noyau clair. C'est ce noyau qui fait
	# « détonation » plutôt que « lumière colorée », et c'est lui qui
	# déborde le plus dans le halo.
	var coeur := color.lerp(Color(1, 0.97, 0.86), 0.66)
	# L'anneau part LÉGÈREMENT DEVANT le canon : jaillissant du point exact
	# du départ, il s'ouvre autour de la main et brouille la silhouette.
	var devant := pos + dir * 0.22
	# ─── LES RAYONS D'ANNEAU SONT EN MÈTRES, PAS EN MULTIPLES ──────────
	#
	# Premier essai : je les avais multipliés par la taille du flash. Celle
	# de Bruno vaut 1,9, et son grand anneau atteignait QUATRE MÈTRES de
	# rayon — huit mètres de diamètre, soit tout l'écran. La planche
	# l'interdit noir sur blanc : « aucun effet ne cache les ennemis ».
	# Un personnage fait soixante centimètres de large ; un anneau de
	# départ doit se lire à cette échelle-là, pas à celle de l'arène.
	match profil.flash:
		"fin":
			# NOX : un dard. Rien ne traîne, rien ne s'étale — sa puissance
			# est dans la VITESSE : l'anneau s'ouvre en trente-cinq
			# millisecondes, moitié moins que celui des autres.
			_poser_gerbe(parent, pos, dir, color, profil.flash_branches,
					3.0, 0.60 * t, 0.05)
			_poser_gerbe(parent, pos, dir, coeur, 3, 2.0, 0.28 * t, 0.04)
			_anneau(parent, devant, dir, color, 0.30, 0.035, 4.2)
			_flash_light(parent, pos, color, 1.6, 2.4, 0.045)
		"large":
			# POPPY : la gerbe s'ouvre et crache. DEUX anneaux décalés dans
			# le temps donnent le « bra-ta-ta » à l'œil, avant même que
			# l'oreille ne l'entende.
			_poser_gerbe(parent, pos, dir, color, profil.flash_branches,
					1.6, 1.05 * t, 0.075)
			_poser_gerbe(parent, pos, dir, coeur, 5, 1.3, 0.50 * t, 0.06)
			_anneau(parent, devant, dir, color, 0.62, 0.09, 4.0)
			_anneau(parent, devant + dir * 0.35, dir,
					color.lerp(coeur, 0.5), 0.42, 0.07, 3.4)
			_emit_burst(parent, pos + dir * 0.35, color, 18, 8.5, 0.10,
					0.20, -2.0)
			_flash_light(parent, pos, color, 2.4, 3.4, 0.065)
		"massif":
			# BRUNO : le seul dont le départ est un ÉVÉNEMENT. La plus
			# longue langue de feu, un anneau de choc large, une seconde
			# onde plus lente derrière, de la fumée, et une lumière qui
			# frappe. Tout est éteint en cent millisecondes : la planche
			# interdit qu'un effet persiste, et un souffle qui reste
			# cacherait l'adversaire au moment où on doit le suivre.
			_poser_gerbe(parent, pos, dir, color, profil.flash_branches,
					4.0, 0.72 * t, 0.09)
			_poser_gerbe(parent, pos, dir, coeur, 5, 2.2, 0.48 * t, 0.07)
			# ─── LES ANNEAUX SE RESSERRENT — 0,52 ET 0,80, PAS 0,82 ET 1,30
			#
			# Vu à la caméra de jeu, l'anneau de 1,30 m de RAYON faisait
			# 2,60 m de diamètre, soit cent quarante-cinq pixels sur un
			# écran qui en compte trois cent quatre-vingt-dix de haut : un
			# tiers de la hauteur, posé sur Bruno, qui disparaissait
			# dessous. La planche est catégorique — « aucun effet ne cache
			# les ennemis » — et son propre projectile devenait invisible
			# dans son flash.
			#
			# Un personnage fait soixante centimètres de large. Un souffle
			# de départ se lit à cette échelle : plus large, il cesse
			# d'être une détonation pour devenir un voile.
			_anneau(parent, devant, dir, coeur, 0.52, 0.075, 5.0)
			_anneau(parent, devant, dir, color, 0.80, 0.13, 3.0)
			_emit_burst(parent, pos + dir * 0.5, color, 20, 9.5, 0.16,
					0.26, -2.5)
			_emit_burst(parent, pos + dir * 0.8, Color(0.44, 0.36, 0.32),
					10, 2.2, 0.30, 0.42, -0.6)
			_flash_light(parent, pos, color, 4.2, 5.2, 0.085)
		_:
			match profil.heros:
				&"milo":
					_depart_milo(parent, pos, devant, dir, color, coeur, t)
				&"ruby":
					_depart_ruby(parent, pos, devant, dir, profil, color,
							coeur, t)
				&"gus":
					_depart_gus(parent, pos, devant, dir, profil, color,
							coeur, t)
				_:
					# Les armes de butin gardent le départ générique
					# d'avant : elles n'ont pas de profil de héros, donc
					# rien à quoi les rendre reconnaissables.
					_poser_gerbe(parent, pos, dir, color,
							profil.flash_branches, 2.4, 0.78 * t, 0.06)
					_poser_gerbe(parent, pos, dir, coeur, 4, 1.6,
							0.36 * t, 0.05)
					_anneau(parent, devant, dir, color, 0.46, 0.06, 4.0)
					_flash_light(parent, pos, color, 1.9, 2.8, 0.05)


## ─── MILO : « ÉTOILE 5 BRANCHES, BREF, SANS FUMÉE » ──────────────────
##
## C'est mot pour mot la fiche de la planche, et la version précédente n'y
## répondait pas : elle posait un ANNEAU de choc — un cerceau ouvert autour
## de la taille du personnage — plus deux gerbes croisées dont les pointes
## traversaient tout le cadre. Vu de côté, on lisait un cerceau et des
## rayures, pas une étoile.
##
## Ici, une seule idée : une étoile plate à cinq rayons, tournée vers la
## caméra, avec un cœur presque blanc plus petit et plus bref à l'intérieur.
## La gerbe reste, mais COURTE, et seulement pour dire la direction du tir.
## Aucun anneau : c'est lui qui faisait « effet de moteur de jeu » plutôt
## que « coup de revolver ».
##
## Durées : 75 ms pour l'étoile, 55 pour le cœur — dans la fourchette
## 0,05–0,10 s de la planche, et assez court pour ne masquer personne.
func _depart_milo(parent: Node, pos: Vector3, devant: Vector3, dir: Vector3,
		color: Color, coeur: Color, t: float) -> void:
	_poser_etoile(parent, devant, color, 5, 0.40 * t, 0.075)
	_poser_etoile(parent, devant, coeur, 5, 0.20 * t, 0.055)
	# La gerbe ne sert plus qu'à ORIENTER, et elle a été réduite de moitié :
	# à 0,30 elle était plus longue que l'étoile et c'est elle qu'on lisait,
	# comme une lame jaune couchée sur le personnage.
	_poser_gerbe(parent, pos, dir, color, 4, 1.8, 0.16 * t, 0.06)
	_emit_burst(parent, pos + dir * 0.25, color, 9, 7.0, 0.09, 0.16, -1.5)
	# LA LUMIÈRE ÉCLAIRE LE CANON, PAS TOUT LE SOL. À trois mètres de
	# portée, elle posait sous le tireur une flaque jaune de six mètres,
	# plus grande et plus voyante que le tir lui-même : le regard partait
	# au sol au lieu de suivre la balle.
	_flash_light(parent, pos, color, 1.8, 1.25, 0.055)


## ─── RUBY : « ÉTOILE ROSE AVEC ACCENT CYAN » ─────────────────────────
##
## Deux étoiles décalées, pas deux anneaux : la rose au canon, la cyan un
## peu devant et à quatre branches. Le décalage dans l'espace ET le nombre
## de branches différent font que les deux se distinguent même en niveaux
## de gris — c'est la règle « jamais par la couleur seule ».
##
## Tout est plus petit et plus court que chez Milo : sa fiche dit « rapide,
## flashy, légère », et sa cadence est double. Un départ aussi gros que
## celui de Milo, répété cinq fois par seconde, remplirait l'écran.
func _depart_ruby(parent: Node, pos: Vector3, devant: Vector3, dir: Vector3,
		profil: ProfilTir, color: Color, coeur: Color, t: float) -> void:
	_poser_etoile(parent, devant, color, 5, 0.36 * t, 0.065)
	_poser_etoile(parent, devant + dir * 0.12, profil.couleur_secondaire,
			4, 0.26 * t, 0.055)
	_poser_etoile(parent, devant, coeur, 4, 0.15 * t, 0.045)
	_poser_gerbe(parent, pos, dir, color, 5, 1.6, 0.13 * t, 0.05)
	_emit_burst(parent, pos + dir * 0.22, profil.couleur_secondaire, 12,
			7.5, 0.07, 0.15, -1.2)
	_flash_light(parent, pos, color, 1.6, 1.15, 0.05)


## ─── GUS : LE DÉPART DIT QUEL CANON A PARLÉ ──────────────────────────
##
## Il tombait jusqu'ici sur la gerbe générique, et c'était le seul des six
## à ne rien avoir en propre. Le problème n'était pas qu'elle soit laide :
## c'est qu'elle est SYMÉTRIQUE, et que la symétrie efface justement ce qui
## fait Gus. Deux revolvers qui alternent, si les deux départs se
## ressemblent trait pour trait, se lisent comme un seul revolver rapide.
##
## Sa signature tient donc en deux dissymétries :
##
##   · LA GERBE PENCHE DU CÔTÉ DU CANON. Le décalage est minuscule — huit
##     centimètres — mais il suffit : deux coups consécutifs ne partent pas
##     du même point de l'écran, et l'œil lit un va-et-vient.
##   · L'ÉTOILE TOURNE D'UN COUP SUR DEUX. Six branches, tournées d'un
##     demi-pas à gauche : la forme change entre deux tirs, ce qui reste
##     vrai en niveaux de gris — c'est exactement ce que le banc exige.
##
## Le canon est lu sur le profil, que `Weapon` met à jour avant chaque
## coup : voir `ProfilTir.canon_courant`.
func _depart_gus(parent: Node, pos: Vector3, devant: Vector3, dir: Vector3,
		profil: ProfilTir, color: Color, coeur: Color, t: float) -> void:
	var droite := profil.canon_courant == 0
	# Le décalage latéral se calcule dans le repère du tir : « à droite »
	# doit vouloir dire à droite DE L'ARME, pas à droite du monde.
	var lat := dir.cross(Vector3.UP).normalized()
	if lat.length() < 0.5:
		lat = Vector3.RIGHT
	var cote: float = 0.08 if droite else -0.08
	var ancre := devant + lat * cote
	# La rotation de l'étoile alterne d'un demi-pas : sur six branches,
	# c'est trente degrés — assez pour que la forme change, trop peu pour
	# qu'on croie à deux armes différentes.
	var pas := TAU / float(maxi(profil.flash_branches, 3)) * 0.5
	_poser_etoile(parent, ancre, color, profil.flash_branches, 0.30 * t,
			0.055, 0.0 if droite else pas)
	_poser_etoile(parent, ancre + dir * 0.10, coeur, 4, 0.17 * t, 0.045)
	_poser_gerbe(parent, pos + lat * cote, dir, color, 4, 2.2, 0.42 * t,
			0.055)
	# UN SEUL ANNEAU, ET PETIT. Gus tire deux fois plus souvent qu'il n'y
	# paraît : deux anneaux par coup, comme Poppy, saturerait la zone du
	# canon en une seconde de tir soutenu.
	_anneau(parent, ancre, dir, coeur, 0.26, 0.05, 3.6)
	_flash_light(parent, pos + lat * cote, color, 1.4, 1.3, 0.05)


## IMPACT DE PROJECTILE, selon le profil. C'est la seconde moitié de la
## signature : on doit reconnaître l'arme même en ne voyant que le mur.
func impact_profil(pos: Vector3, profil: ProfilTir, color: Color) -> void:
	var parent := _parent_for(self)
	var t: float = profil.impact_taille
	var coeur := color.lerp(Color(1, 0.97, 0.86), 0.55)
	match profil.impact:
		"point":
			# NOX : minuscule et net. Un pissenlit de rayons très fins, un
			# anneau qui claque en trois centièmes. La précision se lit à
			# la VITESSE, pas à la taille.
			_poser_etoile(parent, pos, coeur, 8, 0.34 * t, 0.07)
			_anneau(parent, pos, Vector3.UP, color, 0.34, 0.05, 4.0)
			_emit_burst(parent, pos, color, 6, 4.0, 0.05, 0.16)
		"eclats":
			# POPPY : le mitraillage se lit au NOMBRE de marques. Trois
			# étoiles dispersées, chacune son petit anneau.
			for k in 3:
				var d := Vector3(randf_range(-0.4, 0.4), randf_range(-0.25, 0.25),
						randf_range(-0.4, 0.4))
				_poser_etoile(parent, pos + d, color, 4, 0.26 * t, 0.08)
				_anneau(parent, pos + d, Vector3.UP, color, 0.34, 0.07, 3.0)
			_emit_burst(parent, pos, color, 16, 7.5, 0.16, 0.26)
		"explosion":
			# BRUNO : deux ondes, un cœur blanc, des débris sombres qui
			# retombent, et de la poussière. C'est le seul impact des six
			# qui a le droit d'être gros — et il dure moins de deux
			# dixièmes.
			_poser_etoile(parent, pos, coeur, 8, 0.95 * t, 0.10)
			_anneau(parent, pos, Vector3.UP, coeur, 0.90, 0.10, 5.0)
			_anneau(parent, pos, Vector3.UP, color, 1.55, 0.20, 3.0)
			_emit_burst(parent, pos, color, 26, 10.0, 0.22, 0.32)
			_emit_burst(parent, pos, Color(0.30, 0.24, 0.20), 14, 5.0, 0.26,
					0.55, -9.0)
			_emit_burst(parent, pos, Color(0.62, 0.55, 0.46), 10, 2.6, 0.34,
					0.55, -1.2)
			_flash_light(parent, pos, color, 3.4, 4.6, 0.11)
		"scintille":
			# RUBY : « étoile rose + éclats cyan ». Rose au centre, cyan
			# tout autour ; le double anneau la rend reconnaissable même en
			# niveaux de gris.
			#
			# DURÉES RELEVÉES DANS LA FOURCHETTE DE LA PLANCHE (0,10–0,25 s
			# pour un impact). Elles étaient à 0,07–0,09 s, donc plus
			# brèves que le minimum demandé : l'impact passait inaperçu là
			# où il doit confirmer le coup au but.
			_poser_etoile(parent, pos, color, 6, 0.46 * t, 0.12)
			_poser_etoile(parent, pos, coeur, 4, 0.18 * t, 0.07)
			_anneau(parent, pos, Vector3.UP, color, 0.50, 0.10, 4.0)
			_anneau(parent, pos, Vector3.UP, profil.couleur_secondaire,
					0.82, 0.15, 3.2)
			_emit_burst(parent, pos, profil.couleur_secondaire, 12, 7.5,
					0.12, 0.32, -1.0)
		_:
			# MILO et GUS : « petite étoile or + étincelles ». Quatre
			# grands rayons, un anneau net, des étincelles qui retombent.
			#
			# L'ÉTOILE PREND LA COULEUR DU TIREUR, plus le cœur presque
			# blanc. Un impact blanc ne dit pas qui a touché : c'est la
			# moitié de l'information perdue au moment précis où elle
			# compte. Le cœur clair est conservé, mais PLUS PETIT et
			# DERRIÈRE la teinte, comme sur la planche.
			_poser_etoile(parent, pos, color, 8, 0.50 * t, 0.13)
			_poser_etoile(parent, pos, coeur, 4, 0.20 * t, 0.07)
			_anneau(parent, pos, Vector3.UP, color, 0.48, 0.11, 4.0)
			_emit_burst(parent, pos, color, 10, 6.0, 0.09, 0.26, -7.0)


func muzzle_flash(parent: Node, pos: Vector3, color: Color, power: float = 1.0) -> void:
	_emit_burst(parent, pos, color, int(8 * power), 5.0 * power, 0.06, 0.18, -1.0)
	_flash_light(parent, pos, color, 3.0 * power, 4.0 * power, 0.09)

## Impact d'un projectile sur une cible ou un décor.
func impact(pos: Vector3, color: Color, power: float = 1.0) -> void:
	var parent := _parent_for(self)
	_emit_burst(parent, pos, color, int(10 * power), 6.0 * power, 0.1, 0.35)
	if power >= 1.0:
		_flash_light(parent, pos, color, 2.0, 3.5, 0.12)

## Coup encaissé : gerbe vive, secousse, et micro-arrêt si le coup est lourd.
func hit(pos: Vector3, color: Color, power: float = 1.0) -> void:
	var parent := _parent_for(self)
	_emit_burst(parent, pos, color, int(14 * power), 7.0, 0.16, 0.4)
	shake_at(pos, 0.09 * power)
	if power >= 1.5:
		hit_stop(0.045, 0.08)

## Mort d'un mob : l'évènement le plus gratifiant du jeu, donc le plus
## appuyé — gerbe, flash, secousse et arrêt sur image très bref.
func death(pos: Vector3, color: Color) -> void:
	var parent := _parent_for(self)
	_emit_burst(parent, pos + Vector3(0, 0.6, 0), color, 30, 9.0, 0.3, 0.65)
	_flash_light(parent, pos + Vector3(0, 0.8, 0), color, 4.0, 6.0, 0.25)
	shake_at(pos, 0.2)
	# Pas d'arrêt sur image sur une mort de mob ordinaire : c'est
	# l'évènement le plus FRÉQUENT du jeu, donc le pire candidat.
	

## GAIN D'EXPÉRIENCE FLOTTANT — le chiffre qui monte au-dessus du mob mort.
##
## POURQUOI CE CHIFFRE COMPTE. La progression était jusqu'ici invisible en
## jeu : l'XP montait dans une barre au coin de l'écran, qu'on ne regarde
## pas au moment où on la gagne. Le geste et sa récompense étaient séparés
## de deux secondes et de quinze centimètres d'écran — assez pour que le
## lien ne se fasse pas. Un « +5 XP » qui monte à l'endroit exact du coup
## referme cet écart, et c'est tout ce qu'on lui demande.
##
## UN `Label3D`, ET NON UN ÉLÉMENT D'INTERFACE PROJETÉ. Il se tourne vers
## la caméra tout seul, porte son contour sans shader, et se range dans le
## monde — donc il suit le décor, disparaît derrière un rocher, et
## s'enroule avec la carte sans qu'on ait rien à faire.
func gain_xp(pos: Vector3, montant: int, couleur: Color = Color("7fd4ff")) -> void:
	if montant <= 0:
		return
	var parent := _parent_for(self)
	var t := Label3D.new()
	t.text = "+%d XP" % montant
	# CONTOUR MINCE. À 34 pixels pour un corps de 96, il ne détachait plus le
	# chiffre : il le REMPLISSAIT. Vérifié en capture — le « +20 XP » sortait
	# bleu marine presque noir, alors que la couleur demandée était un bleu
	# clair. Un contour sert à séparer du fond, pas à repeindre la lettre.
	t.outline_size = 11
	t.outline_modulate = Color(0.03, 0.05, 0.13, 0.95)
	t.modulate = couleur
	# Le texte est déjà clair ET modulé : sans cela, la teinte multiplie un
	# blanc cassé et sort systématiquement plus sombre que demandé.
	t.font_size = 96
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# PAS DE TEST DE PROFONDEUR EN LECTURE SEULE : le chiffre doit rester
	# lisible même à moitié dans un rocher. Le perdre derrière le décor
	# exactement au moment où le mob s'y effondre le rendrait inutile une
	# fois sur trois.
	t.no_depth_test = true
	t.render_priority = 4
	# TAILLE MESURÉE EN IMAGE, pas choisie. Un `Label3D` se dimensionne en
	# MÈTRES : sa taille à l'écran dépend de la distance à la caméra, pas de
	# `font_size`. Premier réglage : douze pixels de haut, illisible.
	#
	# Le calcul est refait à l'endroit qui compte — la distance de combat.
	# La caméra regarde le sol à une quinzaine de mètres avec 58° de champ,
	# ce qui donne environ quarante pixels par mètre sur un écran de 720
	# lignes. Un chiffre de 1,15 m de haut fait donc une quarantaine de
	# pixels : lisible d'un coup d'œil sans couvrir le combat.
	t.pixel_size = 0.012
	t.position = pos
	parent.add_child(t)

	# Il monte de quatre-vingts centimètres en une seconde, part légèrement
	# de côté pour que deux gains simultanés ne se superposent pas, et
	# s'efface sur la fin. La montée est amortie : un chiffre à vitesse
	# constante se lit comme un objet qui tombe à l'envers.
	var ecart := randf_range(-0.35, 0.35)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(t, "position",
			pos + Vector3(ecart, 0.85, 0.0), 0.95) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "modulate:a", 0.0, 0.4).set_delay(0.55)
	tw.chain().tween_callback(t.queue_free)


## Explosion de zone : lance-grenades et mob Exploder.
func explosion(pos: Vector3, radius: float, color: Color) -> void:
	var parent := _parent_for(self)
	_emit_burst(parent, pos, color, 44, 13.0 * (radius / 4.0), radius * 0.3, 0.8)
	_emit_burst(parent, pos, Color("fff0c0"), 18, 4.0, radius * 0.15, 0.45, -2.0)
	_flash_light(parent, pos + Vector3(0, 0.5, 0), color, 7.0, radius * 3.0, 0.32)
	shake_at(pos, 0.55)
	hit_stop(0.06, 0.06)
	_shockwave(parent, pos, radius, color)

## Onde de choc : anneau plat qui s'étend au sol. Lit instantanément le
## rayon réel de l'explosion, ce qu'aucune particule ne fait aussi bien.
func _shockwave(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 20
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = VisualKit.glow_mat(color, 3.2)
	ring.position = pos + Vector3(0, 0.12, 0)
	ring.scale = Vector3(0.2, 0.2, 0.2)
	parent.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, radius * 0.4, radius), 0.34) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.34)
	tw.chain().tween_callback(ring.queue_free)

## Apparition du loot : petite gerbe montante qui attire l'œil.
func loot_spawn(pos: Vector3, color: Color) -> void:
	_emit_burst(_parent_for(self), pos + Vector3(0, 0.4, 0), color, 14, 3.5,
			0.2, 0.6, -2.0)

## Ramassage : flash net et secousse minuscule — la récompense doit se
## sentir sans interrompre le combat.
func pickup(pos: Vector3, color: Color) -> void:
	var parent := _parent_for(self)
	_emit_burst(parent, pos, color, 20, 5.0, 0.25, 0.4, 1.5)
	_flash_light(parent, pos + Vector3(0, 0.5, 0), color, 3.0, 4.0, 0.2)
	shake_at(pos, 0.05)
