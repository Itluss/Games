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
	Fx.explosion(mondial, RAYON_IMPACT, Color("ff8a3c"))
	Fx.shake_at(mondial, 0.26)
	if not _autoritaire:
		return
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
