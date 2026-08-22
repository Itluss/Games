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

## ─── L'IDENTITÉ SUIT LE PORTEUR, LA MÉCANIQUE SUIT L'ARME ──────────────
##
## Le retour était juste : « les mêmes personnages ont des effets de tir
## différents ». C'était vrai — le profil vivait dans l'arme, donc Milo qui
## ramassait un fusil à pompe se mettait à tirer comme un fusil à pompe.
## Or la planche répond à la question « QUI me tire dessus », pas « avec
## quoi ». Un joueur doit reconnaître Milo à son tir, toujours.
##
## Le partage est donc net :
##
##   L'ARME décide de la MÉCANIQUE — cadence, nombre de projectiles,
##   dispersion, rafale. Y toucher changerait l'équilibrage.
##
##   LE HÉROS décide de l'IDENTITÉ — couleur, forme du départ, de la
##   traînée, de l'impact, réaction du corps, son. Rien de tout cela ne
##   touche à un seul chiffre de jeu.
##
## Un mob, ou une arme sans porteur identifié, n'a pas d'identité : il
## retombe alors sur celle de son arme, puis sur l'ancien rendu générique.
var identite: ProfilTir = null


## Le profil qui décide de ce qu'on VOIT et de ce qu'on ENTEND.
func profil_visuel() -> ProfilTir:
	if identite != null:
		return identite
	return data.profil if data != null else null


## Le profil qui décide du RYTHME. Il vient de l'arme, jamais du porteur :
## donner la rafale de Poppy à un fusil ramassé tripleraient ses coups.
func profil_mecanique() -> ProfilTir:
	return data.profil if data != null else null

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

## ─── ÉTAT DE RAFALE ────────────────────────────────────────────────────
##
## Une rafale n'est PAS diffusée coup par coup sur le réseau. Le serveur
## envoie un seul ordre de tir ; chaque pair déroule ensuite la même
## séquence, au même intervalle, sur la même horloge physique. Trois coups
## de Poppy coûtent donc un message, pas trois — et ils restent alignés
## parce que rien d'aléatoire n'intervient entre eux.
var _rafale_restante: int = 0
var _rafale_delai: float = 0.0
var _rafale_dir: Vector3 = Vector3.FORWARD
var _rafale_team: int = 0
var _rafale_owner: int = 0
var _rafale_autorite: bool = false

## Canon en cours pour une arme à deux revolvers. Il avance à CHAQUE coup,
## y compris ceux d'une rafale : c'est lui qui fait l'alternance de Gus.
var _canon: int = 0

## Émis à chaque coup effectivement parti, avec le canon utilisé.
## Le visuel du personnage s'y accroche pour son recul.
signal coup_parti(canon: int)

func equip(weapon_data: WeaponData) -> void:
	data = weapon_data
	ammo = weapon_data.max_ammo
	_cooldown = 0.0
	# Une arme qu'on change au milieu d'une rafale ne doit pas continuer à
	# cracher les coups de la précédente.
	_rafale_restante = 0
	_canon = 0
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = VisualKit.build_weapon(weapon_data.silhouette, weapon_data.color)
	_muzzle = _model.get_node_or_null("Muzzle")

func take_model() -> Node3D:
	return _model

func muzzle_position() -> Vector3:
	if _muzzle and _muzzle.is_inside_tree():
		var p := _muzzle.global_position
		# LA HAUTEUR EST BORNÉE À LA POITRINE. Le support d'arme suit l'os
		# de la main à travers les échelles fantasques du rig Meshy : sur
		# le Corsair au gabarit 3,15, la bouche se retrouvait à 0,41 m —
		# les balles partaient DES CHEVILLES, cachées par le moindre
		# muret et illisibles sous la caméra en plongée. Mesuré par la
		# sonde de la balle. Le plan horizontal reste celui de la main ;
		# la hauteur, elle, reste dans la bande crédible d'un tir d'épaule.
		#
		# LA RÉFÉRENCE EST LE CORPS DU PORTEUR, PAS LE PARENT DIRECT. Le
		# parent de l'arme est le support de MAIN, déjà en hauteur : s'y
		# référer ajoutait la bande à la main et le banc de l'enroulement
		# a vu tous ses tirs passer AU-DESSUS des têtes — témoin rouge.
		# On remonte donc à l'ancêtre CharacterBody3D, dont l'origine est
		# aux pieds ; sans porteur, la bouche reste telle quelle.
		var anc: Node = get_parent()
		while anc != null and not (anc is CharacterBody3D):
			anc = anc.get_parent()
		if anc != null:
			var socle := (anc as Node3D).global_position.y
			p.y = socle + clampf(p.y - socle, 0.95, 1.75)
		return p
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
	# LA RAFALE S'ÉCOULE SUR L'HORLOGE PHYSIQUE, comme la cadence. Sur
	# l'horloge d'affichage, elle s'étirerait ou se tasserait selon la
	# fluidité : deux joueurs sur deux téléphones n'entendraient pas le
	# même rythme, et le rythme est précisément ce qui identifie l'arme.
	if _rafale_restante > 0:
		_rafale_delai -= delta
		while _rafale_delai <= 0.0 and _rafale_restante > 0:
			_rafale_restante -= 1
			_coup(muzzle_position(), _rafale_dir, _rafale_team,
					_rafale_owner, _rafale_autorite)
			if _rafale_restante > 0:
				_rafale_delai += maxf(profil_mecanique().rafale_intervalle, 0.02)

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
	var basis_dir := dir.normalized()
	_coup(origin, basis_dir, team, owner_id, authoritative)
	# Le reste de la rafale part tout seul, sur l'horloge physique.
	var coups := data.coups_par_declenchement()
	if coups > 1:
		_rafale_restante = coups - 1
		_rafale_delai = maxf(profil_mecanique().rafale_intervalle, 0.02)
		_rafale_dir = basis_dir
		_rafale_team = team
		_rafale_owner = owner_id
		_rafale_autorite = authoritative


## UN COUP — la brique élémentaire, commune au tir simple et à la rafale.
##
## LA POSITION EST RECALCULÉE À CHAQUE COUP D'UNE RAFALE, jamais reprise
## du premier. Un joueur qui court pendant sa rafale verrait sinon les
## deux derniers coups sortir d'un point resté derrière lui.
func _coup(origin: Vector3, basis_dir: Vector3, team: int, owner_id: int,
		authoritative: bool) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	tirs += 1

	# ─── DEUX REVOLVERS : LE CANON ALTERNE, ET C'EST TOUTE LA SIGNATURE ──
	#
	# L'alternance est calculée à partir d'un compteur local qui avance à
	# chaque coup. Comme `_coup` s'exécute sur TOUS les pairs dans le même
	# ordre, tout le monde voit le même canon tirer au même moment, sans
	# qu'un seul octet de plus circule sur le réseau.
	var canon := 0
	var depart := origin
	var meca := profil_mecanique()
	if meca != null and meca.mode == "alterne":
		canon = _canon
		_canon = 1 - _canon
		depart += global_transform.basis.x * (0.26 if canon == 0 else -0.26)

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
		(p as Projectile).setup(data, depart, spread_dir, team, owner_id,
				authoritative, profil_visuel())

	var vis := profil_visuel()
	if vis != null:
		# LE CANON EST PUBLIÉ AVANT LE DÉPART, pas après. `Fx` en a besoin
		# pour décaler la gerbe du bon côté et tourner l'étoile un coup sur
		# deux — c'est ce qui rend l'alternance de Gus VISIBLE, et pas
		# seulement audible.
		vis.canon_courant = canon
		Fx.depart(scene_root, depart, basis_dir, vis, vis.couleur)
		Sfx.tir(vis, depart)
	else:
		Fx.muzzle_flash(scene_root, depart, data.color,
				clampf(data.damage * data.projectile_count / 20.0, 0.6, 2.0))
	_recoil_offset = data.recoil
	if _model:
		_model.position.z = _recoil_offset
	coup_parti.emit(canon)

## Secousse réservée au tireur local : sentir SON arme, pas celle des
## autres. Seules les armes LOURDES en déclenchent : une arme à cadence
## rapide qui secoue à chaque tir produit une vibration continue, jamais
## une sensation de puissance.
func shake_local() -> void:
	if data == null:
		return
	# Le profil prime sur l'ancien champ : c'est lui qui porte désormais
	# l'identité, et il permet une secousse minuscule là où `shake` était
	# pensé pour les armes lourdes du butin.
	var amplitude := data.shake
	var vis := profil_visuel()
	if vis != null:
		amplitude = vis.secousse_locale
	if amplitude > 0.0:
		Fx.shake(amplitude)

func ammo_text() -> String:
	if data == null:
		return ""
	return "∞" if data.is_infinite_ammo() else str(ammo)
