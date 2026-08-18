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
var _sphere: SphereShape3D

func _ready() -> void:
	# Construction unique : l'objet étant recyclé, on ne rebâtit jamais sa
	# géométrie — c'est tout l'intérêt du réservoir.
	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radial_segments = 10
	m.rings = 5
	_mesh.mesh = m
	add_child(_mesh)

	# HALO — une sphère translucide plus large autour du noyau opaque.
	# Un seul appel de dessin de plus par projectile, et c'est lui qui
	# donne l'impression d'énergie ; le noyau, lui, garantit qu'on lise la
	# couleur de l'arme même sur le sable le plus clair.
	_halo = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radial_segments = 8
	hm.rings = 4
	_halo.mesh = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
func setup(weapon_data: WeaponData, origin: Vector3, dir: Vector3,
		team: int, owner_id: int, authoritative: bool) -> void:
	data = weapon_data
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
	var rv := r * 1.35
	(_mesh.mesh as SphereMesh).radius = rv
	(_mesh.mesh as SphereMesh).height = rv * 2.0
	_mesh.material_override = VisualKit.noyau_mat(data.color)
	(_halo.mesh as SphereMesh).radius = rv * 1.9
	(_halo.mesh as SphereMesh).height = rv * 3.8
	_halo.material_override = VisualKit.glow_mat(data.color, 2.0, 0.34)

	# ÉTIREMENT DANS L'AXE DE VOL — la traînée du pauvre, et la seule qui
	# tienne sur un téléphone.
	#
	# Les traînées de particules sont coupées en qualité basse : à trente
	# mètres par seconde, un projectile parcourt un demi-mètre entre deux
	# images, et une bille ronde saute d'un point à l'autre sans qu'on
	# puisse suivre sa course. Étiré dans son axe, il redevient un TRAIT :
	# on lit sa direction, sa vitesse et son origine d'un seul regard, pour
	# zéro particule et zéro appel de dessin supplémentaire.
	#
	# Les grenades gardent leur forme ronde : elles décrivent une cloche et
	# rebondissent, un trait mentirait sur leur trajectoire.
	_allonge = 1.0 if data.bounces > 0 or data.gravity > 0.0 else 3.2
	_mesh.scale = Vector3(1.0, 1.0, _allonge)
	_halo.scale = Vector3(1.0, 1.0, maxf(1.0, _allonge * 0.8))
	_orienter()

	_setup_trail()
	visible = true
	set_physics_process(true)

## Aligne le corps du projectile sur sa vitesse réelle, pas sur la
## direction de tir : une grenade qui retombe doit pointer vers le bas.
func _orienter() -> void:
	if _allonge <= 1.0:
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

func _setup_trail() -> void:
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
	pm.color = data.color
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
		Fx.explosion(at, data.splash_radius, data.color)
		if _authoritative:
			_apply_splash(at)
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
