extends Camera3D
class_name ArenaCam
## CAMÉRA ISOMÉTRIQUE — suit le joueur, angle fixe façon Brawl Stars.
## Touche M : bascule vers la vue cartographique complète (ÉTAPE 6).
##
## ANTI-OCCLUSION (V2) : avec des plateformes désormais toujours pleines
## (V2, pour ne plus jamais laisser le joueur marcher — et disparaître —
## sous une dalle), un mur haut ou un socle peut quand même passer entre
## la caméra et le joueur selon l'angle. Filet de sécurité générique et
## réversible : un rayon caméra→joueur, ré-essayé plusieurs fois pour
## traverser les occultations en série ; tout `StaticBody3D` touché voit
## son `MeshInstance3D` masqué (visible=false, PAS sa collision) tant
## qu'il occulte, restauré dès qu'il ne l'occulte plus. Aucune texture
## dupliquée à gérer : masquer le mesh est une des deux stratégies
## explicitement acceptées par la consigne, et évite tout risque de
## clignotement lié au matériau (transparence dépendante de l'angle de
## vue, tri de transparence...).

const HAUTEUR := 13.0
const RECUL := 13.0
const LISSAGE := 8.0
## Largeur couverte par la vue cartographique, en mètres — au-delà du
## diamètre extérieur de l'arène (190 m) pour garder une marge.
const PORTEE_CARTE := 210.0
const OCCLUSION_ESSAIS_MAX := 6

var target: Node3D = null
var vue_carte := false
var _masques_actuels: Dictionary = {}  ## MeshInstance3D -> true (actuellement masqués)


func _ready() -> void:
	fov = 50.0
	_snap()


func _snap() -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3(0, HAUTEUR, RECUL)
	look_at(target.global_position + Vector3(0, 1.0, 0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_M:
		vue_carte = not vue_carte


func _process(delta: float) -> void:
	if target == null:
		return
	if vue_carte:
		# ORTHOGONALE, PAS PERSPECTIVE — la carte doit se lire sans
		# distorsion de bord, quelle que soit la taille de l'arène (elle
		# est passée de 60 à 190 m sans que cette vue n'ait à être
		# retouchée à la main : `size` suit `PORTEE_CARTE`).
		projection = Camera3D.PROJECTION_ORTHOGONAL
		size = PORTEE_CARTE
		global_position = Vector3(0, 200, 0.001)
		look_at(Vector3.ZERO, Vector3.FORWARD)
		_restaurer_tous_les_masques()  # pas d'occlusion à traiter en vue carte
		return
	projection = Camera3D.PROJECTION_PERSPECTIVE
	var voulu := target.global_position + Vector3(0, HAUTEUR, RECUL)
	global_position = global_position.lerp(voulu, 1.0 - exp(-LISSAGE * delta))
	look_at(target.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	_proteger_visibilite_joueur()


## Rayon caméra→joueur, ré-essayé jusqu'à `OCCLUSION_ESSAIS_MAX` fois pour
## percer les occultations en série (un rayon physique s'arrête au
## premier obstacle touché — un seul essai ne verrait donc que le plus
## proche des occultants).
func _proteger_visibilite_joueur() -> void:
	var espace := get_world_3d().direct_space_state
	var origine := global_position
	var oeil_joueur := target.global_position + Vector3(0, 1.0, 0)
	var exclus: Array[RID] = []
	if target is CollisionObject3D:
		exclus.append((target as CollisionObject3D).get_rid())

	var occultants: Dictionary = {}  # MeshInstance3D -> true
	for _essai in OCCLUSION_ESSAIS_MAX:
		var params := PhysicsRayQueryParameters3D.create(origine, oeil_joueur)
		params.exclude = exclus
		params.collide_with_areas = false
		params.collide_with_bodies = true
		var res := espace.intersect_ray(params)
		if res.is_empty():
			break
		var corps: Object = res["collider"]
		if not (corps is CollisionObject3D):
			break
		exclus.append((corps as CollisionObject3D).get_rid())
		if corps is StaticBody3D:
			var mi := _mesh_de(corps as Node3D)
			if mi != null:
				occultants[mi] = true

	_appliquer_masques(occultants)


func _mesh_de(corps: Node3D) -> MeshInstance3D:
	for c in corps.get_children():
		if c is MeshInstance3D:
			return c
	return null


## Ne touche QUE la différence avec l'état précédent — restaurer puis
## re-masquer tout à chaque image créerait un clignotement d'un frame
## sur tout occultant qui reste occultant d'une image à l'autre.
func _appliquer_masques(nouveaux: Dictionary) -> void:
	for mi in _masques_actuels:
		if not nouveaux.has(mi) and is_instance_valid(mi):
			mi.visible = true
	for mi in nouveaux:
		if not _masques_actuels.has(mi) and is_instance_valid(mi):
			mi.visible = false
	_masques_actuels = nouveaux


func _restaurer_tous_les_masques() -> void:
	if _masques_actuels.is_empty():
		return
	for mi in _masques_actuels:
		if is_instance_valid(mi):
			mi.visible = true
	_masques_actuels = {}
