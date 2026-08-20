extends Area3D
class_name Projectile
## PROJECTILE — recyclé par le réservoir, jamais libéré à la main.
##
## AUTORITÉ : le projectile est simulé et affiché sur TOUS les pairs (sinon
## on ne verrait pas tirer les autres), mais SEUL le serveur applique des
## dégâts. Le champ `_authoritative` porte cette distinction ; c'est la
## seule chose qui sépare une balle décorative d'une balle qui tue.
##
## Chaque arme donne au projectile sa couleur, sa taille, sa traînée et sa
## trajectoire : c'est ce qui rend une arme reconnaissable en vol.

## PROJECTILES RÉELLEMENT ÉMIS DEPUIS LE LANCEMENT.
##
## POURQUOI UN COMPTEUR QUI NE REDESCEND JAMAIS — c'est la même leçon que
## `Weapon.tirs`, et elle a été apprise deux fois. Compter les projectiles
## PRÉSENTS dans la scène revient à échantillonner : le réservoir les
## reprend au bout de cinquante millisecondes, si bien qu'un banc qui
## regarde après une rafale trouve moins de projectiles qu'au départ — et
## conclut qu'il en est parti un nombre négatif. C'est exactement ce que le
## premier banc des armes a affiché.
static var emis: int = 0

var data: WeaponData = null
var direction: Vector3 = Vector3.FORWARD
var shooter_id: int = 0
var shooter_team: int = Cfg.Team.PLAYER
var _authoritative: bool = false

var _velocity: Vector3 = Vector3.ZERO
var _life: float = 0.0
var _max_life: float = 3.0
var _bounces_left: int = 0
var _done: bool = false

var _mesh: MeshInstance3D
var _halo: MeshInstance3D
var _allonge: float = 1.0
var _trail: GPUParticles3D
var _shape: CollisionShape3D
## Identité visuelle du TIREUR — voir `setup`.
var _identite: ProfilTir = null
## Couleur effectivement rendue : celle du tireur, ou celle de l'arme.
var _teinte: Color = Color.WHITE
var _sphere: SphereShape3D

func _ready() -> void:
	# Construction unique : l'objet étant recyclé, on ne rebâtit jamais sa
	# géométrie — c'est tout l'intérêt du réservoir.
	# ─── LE NOYAU EST UNE BALLE, PAS UNE BILLE ─────────────────────────
	#
	# La planche dessine six projectiles ALLONGÉS — nez rond, corps droit,
	# culot net. Une sphère, si nette soit-elle, ne dit pas dans quel sens
	# elle va, et c'est précisément ce qu'on veut lire d'un coup d'œil.
	# L'axe d'une capsule Godot est +Y ; un quart de tour l'envoie sur
	# l'axe du projectile, dont l'avant est -Z.
	_mesh = MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radial_segments = 10
	m.rings = 4
	_mesh.mesh = m
	_mesh.rotation.x = PI * 0.5
	add_child(_mesh)

	# TRAÎNÉE — un cône effilé PLACÉ DERRIÈRE le noyau, pas une enveloppe
	# autour de lui.
	#
	# Le premier jet étirait le noyau lui-même et l'entourait d'un halo
	# étiré : deux formes floues superposées, sans début ni fin nets. En
	# jeu, cela donnait un trait sale — « brouillon et moins détaillé »
	# qu'avant, et c'était juste. Une balle se lit comme un POINT NET suivi
	# d'une queue qui s'efface : deux formes distinctes, chacune avec son
	# rôle. Le point dit où elle est, la queue dit d'où elle vient.
	_halo = MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 1.0
	hm.height = 1.0
	hm.radial_segments = 8
	hm.cap_top = false
	hm.cap_bottom = false
	# L'axe d'un cylindre est +Y ; une rotation de +90° autour de X l'envoie
	# sur +Z, c'est-à-dire DERRIÈRE le projectile — dont l'avant est -Z.
	# La pointe traîne donc dans le dos de la balle, comme il se doit.
	_halo.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.mesh = hm
	add_child(_halo)

	_sphere = SphereShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _sphere
	add_child(_shape)

	_trail = GPUParticles3D.new()
	_trail.emitting = false
	add_child(_trail)

	# Différé : un projectile peut naître pendant la diffusion des signaux
	# physiques (un mob qui explose en déclenche d'autres), et le moteur
	# refuse alors toute modification directe de la surveillance.
	set_deferred(&"monitoring", true)
	set_deferred(&"monitorable", false)
	collision_layer = 0
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

## Arme le projectile. `authoritative` n'est vrai que sur le serveur.
## Remet le compteur à zéro. Réservé aux bancs : le jeu ne s'en sert pas.
static func remettre_compteur() -> void:
	emis = 0


func setup(weapon_data: WeaponData, origin: Vector3, dir: Vector3,
		team: int, owner_id: int, authoritative: bool,
		identite: ProfilTir = null) -> void:
	emis += 1
	data = weapon_data
	# L'IDENTITÉ EST CELLE DU TIREUR, pas de l'arme. Un projectile doit dire
	# QUI l'a tiré : c'est toute la demande de la planche. Faute d'identité
	# — un mob, une tourelle — il retombe sur celle de son arme.
	_identite = identite if identite != null else weapon_data.profil
	_teinte = _identite.couleur if _identite != null else weapon_data.color
	direction = dir.normalized()
	shooter_team = team
	shooter_id = owner_id
	_authoritative = authoritative
	_done = false
	_life = 0.0
	_bounces_left = data.bounces
	_max_life = data.fuse_time if data.fuse_time > 0.0 \
			else clampf(data.range / maxf(data.projectile_speed, 1.0), 0.15, 5.0)

	global_position = origin
	_velocity = direction * data.projectile_speed

	# Le projectile ne heurte QUE ses cibles légitimes et le décor. Le
	# tireur ne partage aucune couche avec sa propre munition : se blesser
	# soi-même devient impossible par construction, pas par condition.
	var mask := Cfg.LAYER_WORLD
	mask |= Cfg.LAYER_MOB if shooter_team == Cfg.Team.PLAYER else Cfg.LAYER_PLAYER
	if shooter_team == Cfg.Team.PLAYER:
		mask |= Cfg.LAYER_PLAYER  # le PvP passe par ici
	collision_mask = mask

	var r := data.projectile_radius
	_sphere.radius = r
	# LE CORPS VU EST PLUS GROS QUE LE CORPS TOUCHÉ, et volontairement.
	#
	# `projectile_radius` sert à DEUX choses qui n'ont pas les mêmes
	# besoins : la sphère de collision, qui décide de la difficulté, et la
	# maille, qui décide de la lisibilité. Une munition de treize
	# centimètres est juste à l'échelle du personnage et parfaitement
	# invisible sur un téléphone. On grossit donc ce qu'on voit d'un tiers
	# sans toucher d'un millimètre à ce qui touche — la précision de tir
	# reste exactement celle d'avant.
	var rv := r * 1.3
	var cap := _mesh.mesh as CapsuleMesh
	cap.radius = rv
	# UN CALIBRE ET DEMI DE CORPS, pas deux et demi. Le premier réglage
	# donnait à Bruno une balle de un mètre quatre-vingts — plus longue que
	# lui. La proportion de la planche est celle d'une balle de revolver :
	# une tête ronde et un corps court.
	cap.height = rv * 2.0 + rv * 1.5
	cap.radial_segments = 10
	cap.rings = 4
	_mesh.material_override = VisualKit.noyau_mat(_teinte)
	_mesh.scale = Vector3.ONE

	# ─── LA QUEUE EST UN TRAIT, PAS UN PANACHE ─────────────────────────
	#
	# La planche montre derrière chaque balle une LIGNE fine et droite qui
	# s'efface — pas un nuage. J'avais mis un panache de particules : de
	# loin, une traînée sale, et rien de commun avec le dessin. Le cône
	# était déjà là et faisait presque le travail ; il lui manquait d'être
	# trois fois plus long et deux fois plus fin.
	#
	# Les grenades n'en ont pas — elles décrivent une cloche et
	# rebondissent, une queue rectiligne mentirait sur leur trajectoire.
	# ─── LA LONGUEUR DE QUEUE DÉPEND DE SON TYPE ───────────────────────
	#
	# Un seul multiplicateur pour tous donnait à Bruno une queue de SIX
	# MÈTRES : sa balle et sa traînée fusionnaient en un bloc rouge de deux
	# mètres à l'écran, quand la planche lui dessine une fumée COURTE et
	# épaisse. Le trait long et fin, c'est la signature de Milo, de Nox et
	# de Gus — pas la sienne.
	var longueur := 6.0
	if _identite != null:
		var facteur := 5.0
		match _identite.trainee:
			"epaisse":
				facteur = 1.6
			"multiple":
				facteur = 2.2
			"ruban":
				facteur = 3.4
		longueur = maxf(_identite.trainee_longueur, 3.0) * facteur
	# Et elle est BORNÉE en mètres : une queue plus longue que trois mètres
	# ne se lit plus comme une balle mais comme un rayon continu.
	_allonge = 0.0 if data.bounces > 0 or data.gravity > 0.0 \
			else minf(rv * longueur, 3.0)
	_halo.visible = _allonge > 0.0
	if _halo.visible:
		var cone := _halo.mesh as CylinderMesh
		cone.bottom_radius = rv * 0.5
		cone.height = _allonge
		# Le cône est centré sur son axe : on le décale d'une demi-longueur
		# pour que sa base touche le noyau au lieu de le traverser.
		_halo.position = Vector3(0.0, 0.0, _allonge * 0.5)
		var teinte_queue := _teinte
		if _identite != null and _identite.trainee == "ruban":
			teinte_queue = _teinte.lerp(_identite.couleur_secondaire, 0.55)
		_halo.material_override = VisualKit.glow_mat(teinte_queue, 2.2, 0.55)
	_orienter()

	_setup_trail()
	visible = true
	set_physics_process(true)

## Aligne le corps du projectile sur sa vitesse réelle, pas sur la
## direction de tir : une grenade qui retombe doit pointer vers le bas.
func _orienter() -> void:
	if _allonge <= 0.0:
		return
	var v := _velocity
	if v.length_squared() < 0.01:
		return
	var avant := v.normalized()
	# `look_at` refuse une direction colinéaire à son repère vertical ; un
	# tir parfaitement vertical n'existe pas ici, mais un garde-fou coûte
	# une ligne et évite une erreur par image quand il existera.
	if absf(avant.y) > 0.995:
		return
	look_at(global_position + avant, Vector3.UP)

## LA TRAÎNÉE — quatre langages différents, jamais quatre teintes.
##
## FINE      un grain serré derrière le noyau : Milo, Nox, Gus.
## MULTIPLE  un grain plus dispersé : plusieurs traits qui partent
##           ensemble se lisent comme une volée, pas comme une balle.
## EPAISSE   un grain gros et lent, qui donne la masse de Bruno.
## RUBAN     un grain qui s'écarte latéralement : le projectile reste
##           parfaitement DROIT — c'est sa queue qui ondule. C'est la
##           consigne, et c'est aussi la seule façon de ne pas compliquer
##           les collisions pour un effet.
func _setup_trail() -> void:
	if _identite != null and Cfg.quality != Cfg.Quality.LOW:
		_trainee_profil()
		return
	if data.trail_length <= 0.0 or Cfg.quality == Cfg.Quality.LOW:
		_trail.emitting = false
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = Vector3.ZERO
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.color = _teinte
	_trail.process_material = pm
	_trail.amount = int(clampf(data.trail_length * 8.0, 6.0, 28.0) * Cfg.fx_scale())
	_trail.lifetime = clampf(data.trail_length * 0.09, 0.08, 0.35)
	_trail.local_coords = false
	var tm := SphereMesh.new()
	tm.radius = data.projectile_radius * 1.0
	tm.height = data.projectile_radius * 2.0
	tm.radial_segments = 6
	tm.rings = 3
	_trail.draw_pass_1 = tm
	_trail.material_override = VisualKit.glow_mat(data.color, 1.6, 0.75)
	_trail.emitting = true


func _trainee_profil() -> void:
	var profil: ProfilTir = _identite
	# ─── LES PARTICULES N'AJOUTENT QUE CE QUE LA PLANCHE DESSINE ───────
	#
	# Le trait derrière la balle est désormais porté par la QUEUE, pas par
	# des particules. Il reste trois cas où la planche montre autre chose
	# que le trait, et trois seulement :
	#
	#   BRUNO  une fumée épaisse qui traîne derrière la grosse balle ;
	#   RUBY   des étincelles roses et cyan qui accompagnent le ruban ;
	#   POPPY  quelques éclats, parce que ce sont des bouts de ferraille.
	#
	# MILO, NOX et GUS n'ont RIEN d'autre que leur trait. C'est ce vide
	# autour du trait qui fait leur netteté, et en mettre plus les
	# rapprocherait de Poppy au lieu de les en éloigner.
	if profil.trainee == "fine":
		_trail.emitting = false
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.gravity = Vector3.ZERO
	pm.color = data.color
	var grain := data.projectile_radius * 0.7
	var duree := 0.12
	var quantite := 8
	match profil.trainee:
		"multiple":
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 1.2
			pm.spread = 35.0
			grain = data.projectile_radius * 0.55
			duree = 0.08
			quantite = 7
		"epaisse":
			# La fumée de Bruno : lente, large, et vite éteinte.
			pm.initial_velocity_min = 0.0
			pm.initial_velocity_max = 0.4
			pm.color = _teinte.lerp(Color(0.45, 0.36, 0.30), 0.45)
			grain = data.projectile_radius * 0.55
			duree = 0.26
			quantite = 16
		"ruban":
			# L'ondulation vient d'ici, et de nulle part ailleurs : les
			# grains sont éjectés sur les côtés, ce qui dessine une vrille
			# derrière une balle qui, elle, reste parfaitement DROITE.
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = data.projectile_radius * 0.5
			pm.initial_velocity_min = 1.4
			pm.initial_velocity_max = 2.4
			pm.spread = 90.0
			pm.damping_min = 4.0
			pm.damping_max = 7.0
			pm.color = profil.couleur_secondaire
			grain = data.projectile_radius * 0.55
			duree = 0.18
			quantite = 16
	pm.scale_min = 0.3
	pm.scale_max = 0.9
	_trail.process_material = pm
	_trail.amount = maxi(4, int(float(quantite) * Cfg.fx_scale()))
	_trail.lifetime = duree
	_trail.local_coords = false
	var tm := SphereMesh.new()
	tm.radius = grain
	tm.height = grain * 2.0
	tm.radial_segments = 6
	tm.rings = 3
	_trail.draw_pass_1 = tm
	_trail.material_override = VisualKit.glow_mat(pm.color, 1.9, 0.7)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	if _done or data == null:
		return
	_life += delta
	if data.gravity > 0.0:
		_velocity.y -= data.gravity * delta
	# ON REPLIE AVANT DE TRACER, pas après. Le tir est un rayon tendu entre
	# la position actuelle et la suivante : replié en cours de route, il
	# enjamberait le monde entier et ne toucherait rien. Replié d'abord, le
	# segment reste court et entièrement du bon côté — au pire un pas de
	# simulation, soit une cinquantaine de centimètres, tombe dans l'angle
	# mort de la limite.
	global_position = PlanMonde.replier(global_position)
	_orienter()
	var next := global_position + _velocity * delta

	# Rebond sur le sol pour les grenades : lues comme des objets qui
	# roulent, elles se placent bien mieux que des tirs tendus.
	if _bounces_left > 0 and next.y <= 0.16:
		next.y = 0.16
		_velocity.y = absf(_velocity.y) * 0.42
		_velocity.x *= 0.72
		_velocity.z *= 0.72
		_bounces_left -= 1
		Fx.impact(next, data.color, 0.4)

	# BALAYAGE PAR RAYON entre l'ancienne et la nouvelle position.
	#
	# La détection par Area3D est DISCRÈTE : elle ne teste que les
	# chevauchements présents au pas de physique. Un projectile à 50 m/s
	# parcourt près d'un mètre par pas et peut donc franchir un mur mince
	# sans jamais le chevaucher au bon instant — d'où l'impression que les
	# tirs traversent les obstacles. Un rayon couvre TOUT le trajet, ce qui
	# rend le tunneling impossible quelle que soit la vitesse.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, next)
	q.collision_mask = collision_mask
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit:
		var collider = hit.get("collider")
		# Type explicite : une chaîne de `and` sur des valeurs non typées
		# empêche GDScript d'inférer le type et refuse de compiler.
		var same_shooter: bool = false
		if collider != null and collider.has_method("get_peer_id") \
				and shooter_team == Cfg.Team.PLAYER:
			same_shooter = collider.call("get_peer_id") == shooter_id
		if not same_shooter:
			global_position = hit.position
			_detonate(hit.position, collider)
			return

	global_position = next
	# Rotation pour les projectiles lents : sans elle une grenade paraît
	# glisser dans l'air.
	if data.gravity > 0.0:
		_mesh.rotate_x(delta * 9.0)

	if _life >= _max_life or global_position.y < -4.0:
		_detonate(global_position)

func _on_body_entered(body: Node3D) -> void:
	_hit(body)

func _on_area_entered(area: Area3D) -> void:
	_hit(area)

func _hit(node: Node) -> void:
	if _done or data == null:
		return
	# Sécurité de ceinture : le masque de collision exclut déjà le tireur,
	# mais un joueur peut traverser sa propre grenade au rebond.
	if node.has_method("get_peer_id") and node.call("get_peer_id") == shooter_id \
			and shooter_team == Cfg.Team.PLAYER:
		return
	_detonate(global_position, node)

func _detonate(at: Vector3, direct_target: Node = null) -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	visible = false
	_trail.emitting = false

	if data.splash_radius > 0.0:
		Fx.explosion(at, data.splash_radius, _teinte)
		if _authoritative:
			_apply_splash(at)
	else:
		# L'IMPACT PORTE LA MOITIÉ DE LA SIGNATURE. Un joueur qui ne voit
		# que le mur derrière lui doit déjà savoir qui tire : trois éclats
		# dispersés, c'est Poppy ; un point vert minuscule, c'est Nox.
		if _identite != null:
			Fx.impact_profil(at, _identite, _teinte)
			Sfx.impact(_identite, at)
		else:
			Fx.impact(at, data.color, 0.8)
		if _authoritative and direct_target != null:
			_damage(direct_target, data.damage, at)

	# Laisser une image aux particules avant de rendre l'objet au réservoir.
	var t := get_tree().create_timer(0.05, false)
	t.timeout.connect(func(): Pool.release(self))

func _apply_splash(at: Vector3) -> void:
	# Requête de forme plutôt que parcours de l'arbre : on ne teste que ce
	# qui est réellement proche, quel que soit le nombre d'entités.
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = data.splash_radius
	params.shape = sphere
	params.transform = Transform3D(Basis(), at)
	params.collision_mask = Cfg.LAYER_PLAYER | Cfg.LAYER_MOB
	params.collide_with_areas = false
	params.collide_with_bodies = true
	for hit in space.intersect_shape(params, 24):
		var body = hit.get("collider")
		if body == null:
			continue
		if body.has_method("get_peer_id") and body.call("get_peer_id") == shooter_id:
			continue
		# Dégâts dégressifs : être au bord d'une explosion doit se
		# ressentir autrement qu'être dessus.
		var d: float = PlanMonde.distance3(body.global_position, at)
		var falloff := clampf(1.0 - d / data.splash_radius, 0.25, 1.0)
		_damage(body, data.damage * falloff, at)

func _damage(target: Node, amount: float, at: Vector3) -> void:
	if not target.has_method("server_take_damage"):
		return
	target.call("server_take_damage", amount, at, shooter_id, shooter_team)

## Appelé par le réservoir avant remisage.
func _on_despawn() -> void:
	_done = true
	data = null
	set_physics_process(false)
	_trail.emitting = false
	visible = false
