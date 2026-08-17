extends Node3D
class_name Weapon
## ARME ÉQUIPÉE — cadence, munitions, éjection des projectiles.
##
## L'arme ne décide JAMAIS des dégâts : elle produit des projectiles, et
## c'est le projectile côté serveur qui tranche. Elle n'est donc pas un
## point de triche, seulement un émetteur.
##
## Toute la personnalité d'une arme vient de sa WeaponData : nombre de
## projectiles, dispersion, secousse, recul, couleur, silhouette. Deux
## armes ne se distinguent pas par un chiffre de dégâts mais par la
## sensation complète du tir.

const PROJECTILE_SCENE := "res://scenes/projectiles/projectile.tscn"

var data: WeaponData = null
var ammo: int = 0

## Nombre de coups RÉELLEMENT partis depuis le début de la partie.
##
## POURQUOI UN COMPTEUR QUI NE REDESCEND JAMAIS : un tir est un évènement
## INSTANTANÉ. Le vérifier en comptant les projectiles présents à l'écran
## revient à échantillonner : si la trame suivante arrive après que le
## projectile a déjà touché un mur, on conclut que le coup n'est jamais
## parti. C'est exactement ce qui a fait échouer la publication sur un
## runner lent alors que le jeu fonctionnait. Un compteur monotone ne peut
## pas être manqué, quelle que soit la cadence d'images.
var tirs: int = 0

var _cooldown: float = 0.0
var _model: Node3D = null
var _muzzle: Node3D = null
var _recoil_offset: float = 0.0

func equip(weapon_data: WeaponData) -> void:
	data = weapon_data
	ammo = weapon_data.max_ammo
	_cooldown = 0.0
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = VisualKit.build_weapon(weapon_data.silhouette, weapon_data.color)
	_muzzle = _model.get_node_or_null("Muzzle")

func take_model() -> Node3D:
	return _model

func muzzle_position() -> Vector3:
	if _muzzle and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return global_position

## LA RECHARGE EST DU JEU, pas de l'affichage : elle décompte donc sur
## l'horloge de la PHYSIQUE.
##
## Elle vivait dans `_process`, c'est-à-dire sur l'horloge d'affichage,
## alors que le tir et la mémoire d'appui sont traités dans
## `_physics_process`. Les deux horloges avancent au même rythme quand
## tout va bien, mais DIVERGENT dès que les images tombent — et sur un
## runner en rendu logiciel, à cinq images par seconde, la divergence
## suffisait à faire expirer une mémoire d'appui avant que l'arme ne soit
## prête. La cadence dépendait donc de la fluidité, ce qui n'a aucun sens
## pour une règle de jeu.
func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

## Temps restant avant que l'arme ne puisse tirer. Publié pour que le
## joueur dimensionne exactement sa mémoire d'appui.
func temps_restant() -> float:
	return maxf(_cooldown, 0.0)

func _process(delta: float) -> void:
	# Le recul revient à zéro tout seul : l'arme « respire » à chaque tir,
	# ce qui donne du poids sans coûter une animation. C'est de la
	# présentation : elle reste sur l'horloge d'affichage.
	if _model and _recoil_offset > 0.001:
		_recoil_offset = move_toward(_recoil_offset, 0.0, delta * 2.4)
		_model.position.z = _recoil_offset

## Part de la cadence qu'un appui NEUF permet d'écourter.
##
## POURQUOI CE RÉGLAGE EXISTE : maintenu, le bouton tire à la cadence
## propre de l'arme. Tapoté, il ne donnait rien de plus — l'appui tombait
## dans le temps de recharge et était simplement ignoré, si bien que
## marteler le bouton semblait sans effet.
##
## Un appui neuf peut désormais entamer les 45 % restants du délai, soit
## au mieux un tir toutes les 55 % de la cadence : environ 1,8 fois plus
## vite en tapotant, au prix des munitions, qui partent d'autant plus
## vite. Le rythme devient une compétence, sans transformer l'arme en
## mitrailleuse.
const TAP_AVANCE := 0.45


## `tap` : l'appel provient-il d'un appui NEUF sur la gâchette ?
func can_fire(tap: bool = false) -> bool:
	if data == null:
		return false
	if _cooldown > _seuil(tap):
		return false
	return data.is_infinite_ammo() or ammo > 0


## Reste de temps de recharge au-delà duquel le tir est refusé.
##
## LE PLAFOND EST VOLONTAIRE. Le serveur ne peut pas savoir si un humain
## a réellement tapoté : il ne reçoit qu'un drapeau, qu'un client modifié
## pourrait toujours lever. Le gain est donc BORNÉ par construction — au
## pire, un tricheur obtient la cadence d'un joueur qui tapote bien, et
## rien de plus. C'est la seule façon d'offrir ce bonus sans faire
## confiance au client.
func _seuil(tap: bool) -> float:
	return data.cooldown() * TAP_AVANCE if tap else 0.0

## Consomme le tir côté demandeur. Retourne false si le tir n'est pas dû —
## c'est aussi ce que le serveur appelle pour VALIDER une demande client.
func consume(tap: bool = false) -> bool:
	if not can_fire(tap):
		return false
	_cooldown = data.cooldown()
	if not data.is_infinite_ammo():
		ammo -= 1
	return true

## Produit les projectiles et les effets de départ. Exécuté sur tous les
## pairs ; seul le serveur passe `authoritative = true`.
func fire(origin: Vector3, dir: Vector3, team: int, owner_id: int,
		authoritative: bool) -> void:
	if data == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	tirs += 1
	var basis_dir := dir.normalized()
	for i in data.projectile_count:
		var spread_dir := basis_dir
		if data.spread_degrees > 0.0:
			# Dispersion en éventail sur le plan horizontal : lisible vue de
			# haut, là où une dispersion sphérique serait illisible.
			var half := deg_to_rad(data.spread_degrees) * 0.5
			var t := 0.0 if data.projectile_count == 1 \
					else float(i) / float(data.projectile_count - 1) * 2.0 - 1.0
			var angle := t * half + randf_range(-half * 0.16, half * 0.16)
			spread_dir = basis_dir.rotated(Vector3.UP, angle)
		# Le lance-grenades tire vers le haut : c'est ce qui crée l'arc.
		if data.gravity > 0.0:
			spread_dir = (spread_dir + Vector3.UP * 0.42).normalized()

		var p := Pool.acquire(PROJECTILE_SCENE, scene_root)
		if p == null:
			continue
		(p as Projectile).setup(data, origin, spread_dir, team, owner_id,
				authoritative)

	Fx.muzzle_flash(scene_root, origin, data.color,
			clampf(data.damage * data.projectile_count / 20.0, 0.6, 2.0))
	_recoil_offset = data.recoil
	if _model:
		_model.position.z = _recoil_offset

## Secousse réservée au tireur local : sentir SON arme, pas celle des
## autres. Seules les armes LOURDES en déclenchent : une arme à cadence
## rapide qui secoue à chaque tir produit une vibration continue, jamais
## une sensation de puissance.
func shake_local() -> void:
	if data and data.shake > 0.0:
		Fx.shake(data.shake)

func ammo_text() -> String:
	if data == null:
		return ""
	return "∞" if data.is_infinite_ammo() else str(ammo)
