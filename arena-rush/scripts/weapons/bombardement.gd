extends Node3D
class_name Bombardement
## LE BOMBARDEMENT DE CORSAIR — la compétence spéciale de sa planche :
## « marque une zone et déclenche un bombardement de 4 tirs de canon
## après un court délai ».
##
## FIDÈLE AUX VIGNETTES, pièce par pièce : les anneaux ROUGES au sol qui
## disent exactement où il ne faut pas être (le langage déjà appris des
## mobs exploseurs), les boules NOIRES qui tombent en diagonale avec leur
## traînée de feu, et l'explosion orange de la planche des effets.
##
## LES VISUELS JOUENT PARTOUT, LES DÉGÂTS SONT AU SERVEUR — la règle de
## toutes les armes du jeu. Les quatre points d'impact voyagent dans le
## RPC : chaque pair voit les mêmes anneaux au même endroit, et le
## serveur frappe exactement là où les anneaux ont prévenu.

## Anticipation entre la marque et la première boule. Assez longue pour
## sortir de la zone en marchant — la compétence contrôle le terrain,
## elle n'assassine pas.
const DELAI := 1.0
## Écart entre deux boules : le bombardement TOMBE EN PLUIE, il ne
## claque pas d'un bloc.
const CADENCE := 0.18
## Durée de chute d'une boule.
const CHUTE := 0.5
const HAUTEUR := 13.0
const RAYON_IMPACT := 2.3
const DEGATS := 42.0

var _impacts: Array[Vector3] = []
var _anneaux: Array[MeshInstance3D] = []
var _tireur_id := 0
var _equipe := 0
var _autoritaire := false


static func lancer(scene_root: Node, centre: Vector3, decalages: Array,
		tireur_id: int, equipe: int, autoritaire: bool) -> void:
	var b := Bombardement.new()
	b.name = "Bombardement"
	b.position = Vector3(centre.x, 0.0, centre.z)
	b._tireur_id = tireur_id
	b._equipe = equipe
	b._autoritaire = autoritaire
	for d in decalages:
		var v := d as Vector3
		b._impacts.append(Vector3(v.x, 0.0, v.z))
	scene_root.add_child(b)


func _ready() -> void:
	for p in _impacts:
		_anneaux.append(_anneau(p))
	var tw := create_tween()
	tw.tween_interval(DELAI)
	for i in _impacts.size():
		tw.tween_callback(_tomber.bind(i))
		tw.tween_interval(CADENCE)
	tw.tween_interval(CHUTE + 0.8)
	tw.tween_callback(queue_free)


## L'anneau de danger, un par impact — même vocabulaire que l'exploseur :
## le cercle grandit pendant l'anticipation, la montée EST le compte à
## rebours.
func _anneau(p: Vector3) -> MeshInstance3D:
	var a := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RAYON_IMPACT
	cyl.bottom_radius = RAYON_IMPACT
	cyl.height = 0.04
	cyl.radial_segments = 24
	a.mesh = cyl
	var m := VisualKit.glow_mat(Cfg.COL_DANGER, 1.6)
	m.albedo_color.a = 0.32
	a.material_override = m
	a.position = p + Vector3(0, 0.04, 0)
	a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(a)
	a.scale = Vector3(0.15, 1.0, 0.15)
	var tw := create_tween()
	tw.tween_property(a, "scale", Vector3.ONE, DELAI)

	# Le DISQUE intérieur se remplit pendant l'anticipation : la cible de
	# la planche, et une horloge lisible — plein = la boule arrive.
	var disque := MeshInstance3D.new()
	var cd := CylinderMesh.new()
	cd.top_radius = RAYON_IMPACT * 0.94
	cd.bottom_radius = RAYON_IMPACT * 0.94
	cd.height = 0.02
	cd.radial_segments = 24
	disque.mesh = cd
	var md := VisualKit.glow_mat(Cfg.COL_DANGER, 1.1)
	md.albedo_color.a = 0.16
	disque.material_override = md
	disque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Enfant de l'anneau : il disparaît avec lui à l'impact, et l'échelle
	# composée (anneau qui grandit × disque qui se remplit) reste
	# monotone — pleine exactement quand la boule arrive.
	disque.position = Vector3(0, -0.01, 0)
	disque.scale = Vector3(0.01, 1.0, 0.01)
	a.add_child(disque)
	var td := create_tween()
	td.tween_property(disque, "scale", Vector3.ONE, DELAI) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return a


## Une boule de canon tombe en DIAGONALE — la planche les montre penchées,
## traînée de feu derrière — et explose à l'impact.
func _tomber(i: int) -> void:
	if i >= _impacts.size():
		return
	var cible := _impacts[i]
	var depart := cible + Vector3(2.6, HAUTEUR, 1.5)

	var boule := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.34
	sph.height = 0.68
	sph.radial_segments = 10
	sph.rings = 5
	boule.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("23232b")
	m.emission_enabled = true
	m.emission = Color("ff7a2a")
	m.emission_energy_multiplier = 0.8
	boule.material_override = m
	boule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# La traînée de feu : une flamme étirée dans l'axe de la chute,
	# enfant de la boule — elle suit sans une ligne de code de plus.
	var traine := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.22
	cyl.height = 1.6
	cyl.radial_segments = 8
	traine.mesh = cyl
	traine.material_override = VisualKit.glow_mat(Color("ffb03a"), 2.2)
	var axe := (cible - depart).normalized()
	traine.position = -axe * 1.0
	# Le cylindre pousse en +Y : on l'aligne sur l'axe de la chute.
	traine.quaternion = Quaternion(Vector3.UP, -axe)
	boule.add_child(traine)

	boule.position = depart
	add_child(boule)
	var tw := create_tween()
	tw.tween_property(boule, "position", cible + Vector3(0, 0.2, 0), CHUTE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact.bind(i, boule))


func _impact(i: int, boule: Node) -> void:
	if is_instance_valid(boule):
		boule.queue_free()
	if i < _anneaux.size() and is_instance_valid(_anneaux[i]):
		_anneaux[i].queue_free()
	var mondial := global_position + _impacts[i]
	_exploser(mondial)
	Fx.shake_at(mondial, 0.3)
	if not _autoritaire:
		return
	_degats(mondial)


## ─── L'EXPLOSION DE LA PLANCHE, EN QUATRE TEMPS ─────────────────────────
##
## Le premier jet appelait `Fx.explosion` — une gerbe générique de dix
## grains et un anneau. Verdict du test sur appareil : « des ronds rouges
## au sol, c'est nul ». La planche des effets montre autre chose : un CŒUR
## éclatant, une boule de feu orange bordée de rouge sombre, des éclats
## qui fusent, des volutes de fumée rondes. On la reconstruit donc pièce
## par pièce, sur la partition classique des explosions de dessin animé :
##
##   t=0        ÉCLAIR   une sphère blanc-jaune qui claque et disparaît —
##                       c'est lui qui donne l'instant exact du coup ;
##   t=0→0,25   FEU      la boule orange qui gonfle vite puis s'éteint en
##                       s'assombrissant — le corps de l'explosion ;
##   t=0→0,45   ÉCLATS   six braises qui fusent en cloche et meurent en
##                       vol — elles donnent l'échelle et la violence ;
##   t=0,1→1,0  FUMÉE    trois volutes grises qui montent en gonflant —
##                       la trace qui reste quand le feu est passé ;
##   et au sol, une brûlure sombre qui s'efface — la preuve que le canon
##   a frappé LÀ.
##
## Tout est fait de sphères et de tweens : pas de shader, pas de texture —
## le rendu web en gl_compatibility joue ça sans broncher, et le style
## « jouet » du jeu s'en trouve mieux servi qu'avec des particules
## réalistes.
func _exploser(mondial: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	# ÉCLAIR.
	var eclair := _sphere(parent, mondial + Vector3.UP * 0.9, 1.0,
			Color(1.0, 0.96, 0.78), 2.6, 0.95)
	eclair.scale = Vector3.ONE * 0.4
	var tw := create_tween().set_parallel(true)
	tw.tween_property(eclair, "scale", Vector3.ONE * RAYON_IMPACT * 1.05, 0.09) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(eclair, "transparency", 1.0, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(eclair.queue_free)

	# BOULE DE FEU : gonfle vite, s'assombrit en mourant — l'orange de la
	# planche, bordé de rouge par la traînée de l'éclair au centre.
	var feu := _sphere(parent, mondial + Vector3.UP * 0.85, 1.0,
			Color("ff7a2a"), 2.0, 1.0)
	feu.scale = Vector3.ONE * 0.3
	var mf := feu.material_override as StandardMaterial3D
	var tf := create_tween().set_parallel(true)
	tf.tween_property(feu, "scale", Vector3.ONE * RAYON_IMPACT * 0.92, 0.24) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tf.tween_property(mf, "emission", Color("8a2410"), 0.34) \
			.set_delay(0.10)
	tf.tween_property(feu, "transparency", 1.0, 0.26).set_delay(0.16)
	tf.chain().tween_callback(feu.queue_free)

	# ÉCLATS : six braises en cloche, tuées en vol.
	for k in 6:
		var ang := TAU * float(k) / 6.0 + randf() * 0.6
		var portee := RAYON_IMPACT * randf_range(0.8, 1.45)
		var cible := mondial + Vector3(cos(ang) * portee,
				randf_range(0.3, 1.4), sin(ang) * portee)
		var e := _sphere(parent, mondial + Vector3.UP * 0.8,
				randf_range(0.14, 0.24),
				Color("ffb03a") if k % 2 == 0 else Color("ff5a1e"), 2.4, 1.0)
		var te := create_tween().set_parallel(true)
		te.tween_property(e, "position", cible, randf_range(0.28, 0.42)) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		te.tween_property(e, "scale", Vector3.ONE * 0.05, 0.42) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		te.chain().tween_callback(e.queue_free)

	# FUMÉE : trois volutes mates qui montent en gonflant.
	for k in 3:
		var dep := mondial + Vector3(randf_range(-0.7, 0.7), 0.7,
				randf_range(-0.7, 0.7))
		var fum := _sphere(parent, dep, randf_range(0.5, 0.7),
				Color(0.34, 0.30, 0.28), 0.0, 0.85)
		var tfu := create_tween().set_parallel(true)
		tfu.tween_property(fum, "position",
				dep + Vector3(0, randf_range(1.2, 1.9), 0), 0.9) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tfu.tween_property(fum, "scale", Vector3.ONE * 1.9, 0.9)
		tfu.tween_property(fum, "transparency", 1.0, 0.9) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tfu.chain().tween_callback(fum.queue_free)

	# BRÛLURE au sol, qui s'efface lentement.
	var tache := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RAYON_IMPACT * 0.8
	cyl.bottom_radius = RAYON_IMPACT * 0.8
	cyl.height = 0.02
	cyl.radial_segments = 20
	tache.mesh = cyl
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(0.16, 0.11, 0.08, 0.55)
	tache.material_override = mt
	tache.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tache.position = mondial + Vector3(0, 0.03, 0)
	parent.add_child(tache)
	var tt := create_tween()
	tt.tween_property(mt, "albedo_color:a", 0.0, 1.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tt.tween_callback(tache.queue_free)

	# Et la poussière du sol autour — le sable répond au coup.
	Fx.poussiere(mondial + Vector3.UP * 0.15, Color("e6cfa0"), 2.2)


## Sphère lumineuse jetable : la brique de l'explosion.
func _sphere(parent: Node, pos: Vector3, rayon: float, couleur: Color,
		energie: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = rayon
	sph.height = rayon * 2.0
	sph.radial_segments = 12
	sph.rings = 6
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(couleur.r, couleur.g, couleur.b, alpha)
	if energie > 0.0:
		m.emission_enabled = true
		m.emission = couleur
		m.emission_energy_multiplier = energie
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi


func _degats(mondial: Vector3) -> void:
	# Dégâts de zone avec atténuation — la recette de l'exploseur, mais
	# frappant joueurs ET mobs. Le lanceur est épargné : une compétence
	# qui punit son propre appui n'apprend que la peur du bouton.
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RAYON_IMPACT
	params.shape = sphere
	params.transform = Transform3D(Basis(), mondial)
	params.collision_mask = Cfg.LAYER_PLAYER | Cfg.LAYER_MOB
	for hit in espace.intersect_shape(params, 12):
		var corps = hit.get("collider")
		if corps == null or not corps.has_method(&"server_take_damage"):
			continue
		if corps.has_method(&"get_peer_id") \
				and corps.call(&"get_peer_id") == _tireur_id:
			continue
		var d: float = PlanMonde.distance3(corps.global_position, mondial)
		var att := clampf(1.0 - d / RAYON_IMPACT, 0.35, 1.0)
		corps.call(&"server_take_damage", DEGATS * att, mondial,
				_tireur_id, _equipe)
