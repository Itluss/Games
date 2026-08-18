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
	var d := camera.global_position.distance_to(pos)
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

func _emit_burst(parent: Node, pos: Vector3, color: Color, amount: int,
		velocity: float, radius: float, lifetime: float,
		gravity: float = -6.0) -> void:
	var scaled := maxi(3, int(amount * Cfg.fx_scale()))
	var p := GPUParticles3D.new()
	p.amount = scaled
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = pos

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
	# La courbe de taille fait « éclore puis disparaître » : sans elle les
	# particules s'éteignent brutalement et l'effet paraît bon marché.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	m.scale_curve = tex
	m.color = color
	p.process_material = m

	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 3
	p.draw_pass_1 = mesh
	p.material_override = VisualKit.glow_mat(color, 2.6)

	parent.add_child(p)
	p.emitting = true
	_autofree(p, lifetime + 0.4)

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
