extends Area3D
class_name LootPickup
## ARME AU SOL — flotte, tourne, appelle.
##
## AUTORITÉ : seul le serveur valide un ramassage. Deux joueurs qui
## arrivent en même temps ne peuvent pas obtenir la même arme, parce que
## le premier traité met `_taken` à vrai côté serveur, et lui seul compte.
##
## Le ramassage doit être GRATIFIANT : l'objet se précipite vers le joueur,
## flashe, et son nom s'affiche. C'est une micro-récompense, elle doit se
## sentir.

signal picked_up(peer_id: int, weapon_id: StringName)

var weapon_id: StringName = &""
var loot_id: int = 0

## Joueur qui vient d'abandonner cette arme lors d'un échange, et jusqu'à
## quand il doit être ignoré.
##
## SANS CE VERROU LE JEU S'EMBALLE : l'arme remplacée retombe aux pieds du
## joueur, donc dans son rayon de ramassage, qui la reprend immédiatement
## et rejette l'autre — un aller-retour infini. Le test automatisé l'a
## révélé sans ambiguïté : 412 butins produits pour 25 mobs tués.
var ignore_peer: int = 0
const IGNORE_TIME := 2.5
var _ignore_until: float = 0.0

var _data: WeaponData
var _model: Node3D
var _halo: MeshInstance3D
var _time: float = 0.0
var _taken: bool = false
var _base_y: float = 0.0

func setup(id: StringName, index: int, dropped_by: int = 0) -> void:
	weapon_id = id
	loot_id = index
	ignore_peer = dropped_by
	name = "Loot_%d" % index

## Instant d'apparition, en secondes d'horloge réelle. C'est le serveur qui
## décide de la disparition, mais chaque exemplaire porte son âge : il n'y a
## ainsi rien à tenir à jour ailleurs, donc rien à désynchroniser.
var ne_le: float = 0.0

func _ready() -> void:
	ne_le = Time.get_ticks_msec() / 1000.0
	add_to_group(&"loot")
	_data = Registry.weapon(weapon_id)
	if _data == null:
		queue_free()
		return

	collision_layer = Cfg.LAYER_PICKUP
	# On ne surveille que les joueurs : inutile de tester les projectiles
	# ou les mobs contre chaque butin à chaque image.
	collision_mask = Cfg.LAYER_PLAYER
	# `set_deferred` obligatoire : ce butin naît au cœur d'une chaîne qui
	# part du signal `body_entered` d'un projectile (projectile touche mob
	# → mob meurt → loot tombe). Le moteur interdit de modifier l'état de
	# surveillance d'une Area3D pendant qu'il diffuse ces signaux.
	set_deferred(&"monitoring", true)
	set_deferred(&"monitorable", false)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Rayon généreux : courir « à côté » d'une arme sans la prendre est
	# une frustration inutile sur écran tactile.
	sphere.radius = 1.5
	shape.shape = sphere
	add_child(shape)

	_model = VisualKit.build_weapon(_data.silhouette, _data.color)
	_model.scale = Vector3.ONE * 1.25
	add_child(_model)

	# Halo au sol : c'est LUI qu'on repère du coin de l'œil, pas l'arme.
	_halo = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.03
	cyl.radial_segments = 20
	_halo.mesh = cyl
	var hm := VisualKit.glow_mat(_data.color, 2.0)
	hm.albedo_color.a = 0.4
	_halo.material_override = hm
	_halo.position = Vector3(0, 0.04, 0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)

	# Colonne de lumière verticale : visible par-dessus les obstacles.
	var beam := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.34
	bc.bottom_radius = 0.5
	bc.height = 3.2
	bc.radial_segments = 12
	bc.cap_top = false
	bc.cap_bottom = false
	beam.mesh = bc
	var bm := VisualKit.glow_mat(_data.color, 1.2)
	bm.albedo_color.a = 0.16
	beam.material_override = bm
	beam.position = Vector3(0, 1.6, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	_base_y = position.y
	_ignore_until = Time.get_ticks_msec() / 1000.0 + IGNORE_TIME
	Fx.loot_spawn(global_position, _data.color)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	# Flottement + rotation lente : le mouvement attire l'œil bien plus
	# sûrement qu'une couleur vive immobile.
	_model.position.y = 0.85 + sin(_time * 2.2) * 0.16
	_model.rotation.y = _time * 1.1
	var pulse := 1.0 + sin(_time * 3.0) * 0.09
	_halo.scale = Vector3(pulse, 1.0, pulse)

func _on_body_entered(body: Node3D) -> void:
	# Le déclenchement n'a lieu QUE sur le serveur : un client qui
	# traverserait le butin ne se l'attribue pas tout seul.
	if _taken or not Net.is_server():
		return
	if not body.is_in_group(&"players"):
		return
	if body.get(&"is_eliminated") == true:
		return
	# Le joueur qui vient de lâcher cette arme ne peut pas la reprendre
	# tout de suite : c'est ce qui casse la boucle d'échange infinie.
	if body.get_peer_id() == ignore_peer \
			and Time.get_ticks_msec() / 1000.0 < _ignore_until:
		return
	_taken = true
	picked_up.emit(body.get_peer_id(), weapon_id)

## Animation d'aspiration puis disparition, jouée sur tous les pairs.
func play_collect(toward: Vector3) -> void:
	_taken = true
	# Même contrainte : l'aspiration est déclenchée depuis le signal de
	# détection du joueur.
	set_deferred(&"monitoring", false)
	if _data:
		Fx.pickup(global_position, _data.color)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", toward + Vector3(0, 1.0, 0), 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Jamais exactement zéro : une échelle nulle rend la matrice de
	# transformation non inversible et le moteur hurle à chaque image.
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.18)
	tw.chain().tween_callback(queue_free)


## DISPARITION D'UN BUTIN OUBLIÉ.
##
## POURQUOI ELLE MANQUAIT, ET CE QU'ELLE A COÛTÉ. Une arme au sol ne
## s'effaçait QUE lorsqu'on la ramassait. Or les mobs meurent en continu et
## lâchent la leur : au bout de cinq minutes, cent-trois butins traînaient
## dans la scène, et le nombre montait sans fin. Mesuré : l'arbre passait de
## 2 446 à 4 611 nœuds, la mémoire de 74 à 92 Mo, et la cadence s'effondrait
## jusqu'à ce que le monde cesse d'être dessiné.
##
## Elle se distingue du ramassage : pas d'aspiration vers le joueur, pas
## d'effet — l'objet s'affaisse sur place. Un butin qui part vers personne
## se lirait comme un vol.
func disparaitre() -> void:
	if _taken:
		return
	_taken = true
	set_deferred(&"monitoring", false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.4, 0.35)
	tw.chain().tween_callback(queue_free)
