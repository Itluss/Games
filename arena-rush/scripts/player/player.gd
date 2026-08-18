extends CharacterBody3D
class_name Player
## JOUEUR — corps, inventaire, réplication.
##
## RÉPARTITION DE L'AUTORITÉ (voir MultiplayerManager) :
##   • le pair PROPRIÉTAIRE simule son déplacement et diffuse sa position ;
##   • le SERVEUR décide des dégâts, de la mort, du loot et de la victoire.
##
## VISÉE ASSISTÉE : au doigt, viser précisément est impossible. Le joueur
## indique une DIRECTION et le jeu accroche la cible la plus pertinente
## dans ce cône. Sans cette assistance, le jeu serait injouable sur
## téléphone ; avec elle, il reste nerveux et lisible.

signal inventory_changed(slots: Array, active: int)
signal health_changed(current: float, maximum: float)
signal died()
## Émis SUR LA VICTIME, à destination de l'interface du tueur : il porte le
## nom de l'éliminé et le bilan renvoyé par le profil (XP, série, palier).
signal elimination_reussie(nom_victime: String, bilan: Dictionary)

const SPEED := 5.6
## Constantes de TEMPS (secondes pour atteindre ~63 % de la cible), et
## non des taux par image. Un lissage en `facteur * delta` change de
## comportement avec la cadence d'affichage — donc le jeu ne réagit pas
## pareil à 30 et à 120 FPS, ce qui se ressent immédiatement en navigateur
## où la cadence varie. La forme exponentielle `1 - exp(-dt/tau)` est,
## elle, rigoureusement identique à toute cadence.
const ACCEL_TAU := 0.11
const BRAKE_TAU := 0.15
const TURN_TAU := 0.065
const DASH_SPEED := 15.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.5
const NET_SEND_HZ := 20.0
## Hauteur d'affichage du personnage, distincte de sa boîte de collision.
const VISUAL_HEIGHT := 2.5
## Dégâts par seconde hors de la zone sûre.
const ZONE_DPS := 11.0

var peer_id: int = 1
var is_bot: bool = false
var display_name: String = "Joueur"

## Intentions, remplies par le contrôleur (humain) ou le cerveau (bot).
var move_input: Vector2 = Vector2.ZERO
var aim_input: Vector3 = Vector3.FORWARD
var want_fire: bool = false
## Appui NEUF sur la gâchette, latché jusqu'à la prochaine tentative de
## tir. C'est lui qui donne droit à la cadence accélérée au tapotement.
var want_tap: bool = false
## Temps de validité restant du dernier appui mémorisé.
var _tampon_tir: float = 0.0
## ENGAGEMENT AU COMBAT, lissé.
##
## POURQUOI CE LISSAGE EXISTE : maintenue, la gâchette rend `want_fire`
## vrai en continu ; TAPOTÉE, elle ne le rend vrai que quelques trames par
## appui. Or deux règles s'appuyaient dessus — l'orientation du corps et
## le choix de l'animation. En tir à répétition, les deux basculaient donc
## plusieurs fois par seconde : le personnage tressautait entre « je
## regarde où je cours » et « je regarde ma cible », et la posture de tir
## n'avait jamais le temps de s'installer.
##
## L'engagement monte vite et redescend lentement : tapoter au-delà de
## deux fois par seconde le maintient au plafond, ce qui rend le
## comportement IDENTIQUE à la gâchette maintenue. C'est ce que le joueur
## attend — tirer plus vite ne doit pas changer la façon dont on bouge.
var _combat: float = 0.0

## Constantes de temps de l'engagement. La montée est quasi immédiate
## pour que le premier tir réagisse ; la descente couvre largement
## l'intervalle entre deux appuis d'un joueur qui martèle le bouton.
const COMBAT_MONTEE := 0.05
const COMBAT_DESCENTE := 0.55
## Seuil de bascule. Volontairement bas : mieux vaut rester en posture de
## tir un court instant de trop qu'en sortir entre deux appuis.
const COMBAT_SEUIL := 0.35

## MÉMOIRE D'APPUI, en secondes.
##
## LE DÉFAUT QUE CECI CORRIGE : « quand j'appuie, ça ne tire pas
## immédiatement ». La latence d'entrée était pourtant d'UNE trame,
## mesurée — le tir partait donc bien tout de suite… quand l'arme était
## prête. Le reste du temps, l'appui était purement JETÉ.
##
## Or le blaster de départ recharge en 0,333 s et le fusil à pompe en plus
## d'une seconde. Un appui tombant dans cet intervalle ne produisait rien
## du tout : du point de vue du joueur, le bouton ne répond pas.
##
## L'appui est désormais MÉMORISÉ : dès que l'arme est prête, le coup
## part, sans qu'il faille réappuyer. C'est la solution classique des jeux
## d'action, et elle ne touche pas à la cadence — le serveur la valide
## toujours. La mémoire est courte : au-delà, l'appui est oublié, faute de
## quoi un coup partirait longtemps après qu'on l'ait demandé.
## Mémoire MINIMALE. Elle est étendue à la durée de recharge de l'arme
## portée, sans quoi un appui serait encore perdu sur une arme lente : le
## fusil à pompe met plus d'une seconde à se recharger, et une mémoire de
## trois dixièmes aurait expiré bien avant qu'il ne soit prêt.
const TAMPON_TIR := 0.30
## Plafond, pour qu'un appui oublié ne ressorte jamais très longtemps
## après. Au-delà, le joueur a changé d'avis.
const TAMPON_MAX := 1.20
## Marge ajoutée au temps de recharge restant.
##
## Sans elle, la mémoire expirait pile au moment où l'arme devenait
## prête : la moindre image perdue faisait rater le rendez-vous, et
## l'appui était quand même jeté. C'est ce que la barrière de test a
## attrapé sur un runner à cinq images par seconde.
const TAMPON_MARGE := 0.25
var want_dash: bool = false

var health: HealthComponent
var visual: CharacterVisual
var weapon: Weapon
var health_bar: HealthBar3D

## Inventaire : deux emplacements, remplis d'identifiants d'armes.
var slots: Array[StringName] = [&"", &""]
var active_slot: int = 0

var is_eliminated: bool = false

## Cible actuellement accrochée par la visée assistée, publiée par le
## contrôleur. Sert uniquement à l'affichage de l'indicateur.
var locked_target: Node3D = null
var _aim_line: MeshInstance3D = null
var _lock_ring: MeshInstance3D = null

var _facing: float = 0.0
var _dash_time: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _net_accum: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _zone_accum: float = 0.0
## Accélération instantanée, transmise au visuel pour l'inclinaison.
var _accel: Vector3 = Vector3.ZERO

func get_peer_id() -> int:
	return peer_id

## Vrai si CE pair pilote ce corps. Les bots sont pilotés par le serveur.
func is_local_authority() -> bool:
	if is_bot:
		return Net.is_server()
	return peer_id == Net.local_id()


## LE joueur de cette machine — celui dont la caméra suit les pas.
##
## À distinguer de `is_local_authority()`, qui est vrai aussi pour les bots
## sur le serveur. C'est un personnage HUMAIN et un seul qui sert d'origine
## au repli du monde ; prendre un bot pour ancre ferait sauter le repère à
## chaque fois que ce bot traverse la limite.
func est_local() -> bool:
	return not is_bot and peer_id == Net.local_id()

func setup(id: int, name_text: String, bot: bool) -> void:
	peer_id = id
	display_name = name_text
	is_bot = bot
	name = "Player_%d" % id

func _ready() -> void:
	add_to_group(&"players")
	collision_layer = Cfg.LAYER_PLAYER
	collision_mask = Cfg.LAYER_WORLD

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	# Couleur d'équipe : se distinguer d'un coup d'œil des autres joueurs
	# est une information de survie, pas une coquetterie.
	var is_me := (not is_bot) and peer_id == Net.local_id()
	var body_col := Cfg.COL_LOCAL_PLAYER if is_me else Cfg.COL_ENEMY_PLAYER
	# Accent orange pour Kael, éclairci pour les adversaires : la couleur
	# secondaire porte l'identité autant que la principale.
	var accent := Cfg.COL_KAEL_ACCENT if is_me else body_col.lightened(0.35)
	visual = CharacterVisual.new()
	add_child(visual)
	# Personnage volontairement SURDIMENSIONNÉ par rapport à une taille
	# réaliste. La caméra est en plongée et vise le téléphone : à 1,70 m
	# Kael n'occupait qu'une poignée de pixels et se lisait comme une
	# tache sombre. Les jeux d'arène en vue de dessus exagèrent tous
	# l'échelle du personnage pour cette raison.
	visual.build(body_col, accent, VISUAL_HEIGHT)

	weapon = Weapon.new()
	var mount := visual.get_weapon_mount()
	if mount:
		mount.add_child(weapon)
	else:
		add_child(weapon)

	health = HealthComponent.new()
	health.max_health = 100.0
	add_child(health)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)

	# ANNEAU D'ÉQUIPE. Tous les joueurs partagent le même modèle : sans
	# repère au sol, on ne distingue plus un allié d'un adversaire, ce qui
	# est une information de survie. C'est la solution des jeux d'arène,
	# et elle a l'avantage de ne pas dénaturer le personnage — le teinter
	# salirait ses couleurs d'origine.
	var anneau := MeshInstance3D.new()
	var couronne := TorusMesh.new()
	couronne.inner_radius = 0.52
	couronne.outer_radius = 0.68
	couronne.rings = 24
	couronne.ring_segments = 6
	anneau.mesh = couronne
	anneau.material_override = VisualKit.glow_mat(body_col.lerp(Color.BLACK, 0.15), 0.9)
	anneau.position = Vector3(0, 0.05, 0)
	anneau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(anneau)

	health_bar = HealthBar3D.new()
	health_bar.position = Vector3(0, 2.9, 0)
	add_child(health_bar)
	health_bar.build(1.1)
	# La barre du joueur local est superflue (le HUD la porte déjà) et
	# encombrerait le centre de l'écran.
	health_bar.visible = not is_me

	# INDICATEURS DE VISÉE — joueur local seulement. Une visée assistée
	# qu'on ne voit pas donne l'impression que le personnage décide seul.
	if is_me:
		_build_aim_visuals()

	_target_pos = global_position
	equip_weapon_id(Registry.starting_weapon().id if Registry.starting_weapon() else &"basic_blaster", 0)

func _physics_process(delta: float) -> void:
	if is_eliminated:
		return
	# L'invulnérabilité s'écoule sur l'HORLOGE PHYSIQUE, comme la recharge
	# des armes. Sur l'horloge de rendu, sa durée dépendrait de la cadence
	# d'images : deux joueurs sur deux téléphones différents n'auraient pas
	# la même protection, ce qui est inadmissible en jeu compétitif.
	if _protection > 0.0:
		_protection = maxf(0.0, _protection - delta)
	if is_local_authority():
		_simulate(delta)
		_replier_les_bords()
		_replicate(delta)
	else:
		_interpolate(delta)

	if Net.is_server():
		_tick_zone_damage(delta)

	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED,
			0.0, 1.0)
	# L'inclinaison est calculée dans le repère du personnage : pencher
	# « vers l'avant » n'a de sens que relativement à son orientation.
	var local_v := Vector3(velocity.x, 0, velocity.z).rotated(Vector3.UP, -_facing)
	var local_a := _accel.rotated(Vector3.UP, -_facing)
	visual.set_motion(local_v / maxf(SPEED, 0.01), local_a / 40.0)
	# La mise en joue suit l'intention de tir, pas l'évènement de tir :
	# le personnage épaule tant qu'on maintient, et non le temps d'une
	# image à chaque projectile.
	# L'engagement suit l'intention de tir, mais LISSÉ : voir `_combat`.
	var vise := 1.0 if want_fire else 0.0
	var tau := COMBAT_MONTEE if want_fire else COMBAT_DESCENTE
	_combat = lerpf(_combat, vise, 1.0 - exp(-delta / tau))
	visual.set_aiming(en_combat() and not is_eliminated)
	visual.update_visual(delta, speed_ratio)
	_update_aim_visuals()

# --- SIMULATION ----------------------------------------------------------

func _simulate(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd -= delta

	var wish := Vector3(move_input.x, 0.0, move_input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	if want_dash and _dash_cd <= 0.0:
		want_dash = false
		_dash_cd = DASH_COOLDOWN
		_dash_time = DASH_TIME
		# Une esquive sans direction part vers l'avant : jamais sur place,
		# ce qui rendrait le bouton inutile sous pression.
		_dash_dir = wish if wish.length() > 0.1 \
				else Vector3(sin(_facing), 0, cos(_facing))
		Fx.shake(0.06)
		# Étirement dans l'axe de l'esquive : sans déformation, une
		# accélération brutale ne se lit pas, elle se subit.
		visual.punch(Vector3(0.78, 0.9, 1.35), 0.18)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var before := flat
	if _dash_time > 0.0:
		_dash_time -= delta
		flat = _dash_dir * DASH_SPEED
	else:
		# Approche VECTORIELLE : on lisse le vecteur vitesse entier, pas
		# X et Z séparément. Traiter les axes isolément donnait une
		# accélération différente en diagonale et des trajectoires en
		# escalier — la sensation « mécanique ».
		var target := wish * SPEED
		var tau := ACCEL_TAU if wish.length() > 0.05 else BRAKE_TAU
		flat = flat.lerp(target, 1.0 - exp(-delta / tau))
	velocity.x = flat.x
	velocity.z = flat.z
	# L'accélération réelle nourrit l'inclinaison du corps : c'est elle qui
	# donne du POIDS au personnage.
	_accel = (flat - before) / maxf(delta, 0.001)

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# ORIENTATION — une seule règle, et elle doit être devinable :
	#   on regarde où l'on MARCHE, sauf quand on TIRE.
	#
	# Auparavant le personnage s'orientait en permanence vers la cible
	# auto-visée, donc il pivotait seul, sans cause visible pour le joueur.
	# Ne verrouiller la visée que pendant le tir permet toujours de
	# reculer en tirant — le mouvement clé du genre — sans rendre les
	# déplacements hors combat illisibles.
	var face := Vector3(velocity.x, 0, velocity.z)
	if en_combat() and aim_input.length() > 0.1:
		face = aim_input
	if face.length() > 0.1:
		_facing = lerp_angle(_facing, atan2(face.x, face.z),
				1.0 - exp(-delta / TURN_TAU))
	# `_facing` est l'angle de TIR, mesuré depuis +Z. Or dans Godot l'avant
	# d'un nœud est son axe -Z local : c'est vers -Z que regardent le
	# modèle, le canon de l'arme, le chevron et le télémètre. Sans ce
	# demi-tour, tout l'attirail visuel pointe à l'exact opposé du tir.
	rotation.y = _facing + PI
	visual.rotation.y = 0.0

	# Un appui NEUF arme la mémoire, qu'on puisse tirer ou non à cet
	# instant. C'est ce qui rend le bouton réactif sur une arme lente.
	if want_tap:
		# La mémoire est taillée sur le temps de recharge RESTANT — et non
		# sur la cadence nominale de l'arme : un appui juste après un tir
		# doit attendre une recharge entière, un appui juste avant qu'elle
		# ne s'achève presque rien.
		var duree := TAMPON_TIR
		if weapon:
			duree = maxf(duree, weapon.temps_restant() + TAMPON_MARGE)
		_tampon_tir = minf(duree, TAMPON_MAX)
		want_tap = false
	_tampon_tir = maxf(0.0, _tampon_tir - delta)
	# On tente le tir si la gâchette est TENUE, ou si un appui récent
	# attend encore son tour.
	if want_fire or _tampon_tir > 0.0:
		_try_fire(_tampon_tir > 0.0)

## Le joueur est-il ENGAGÉ ? Sert à la fois à l'orientation du corps et
## au choix de l'animation, pour que les deux restent d'accord.
func en_combat() -> bool:
	return _combat > COMBAT_SEUIL


## `tap` : la tentative vient-elle d'un appui NEUF encore en mémoire ?
## Elle donne alors droit à la cadence accélérée.
func _try_fire(tap: bool = false) -> void:
	if weapon.data == null:
		return
	if not weapon.can_fire(tap):
		# L'arme n'est pas prête : on NE JETTE PAS l'appui, il reste en
		# mémoire et repartira dès que la recharge le permettra.
		return
	var dir := Vector3(sin(_facing), 0, cos(_facing))
	if aim_input.length() > 0.1:
		dir = aim_input.normalized()
	# Le coup est parti : la mémoire est vidée, sinon le même appui
	# vaudrait deux tirs.
	_tampon_tir = 0.0
	# Le client DEMANDE, le serveur DISPOSE. Le tir part visuellement tout
	# de suite chez le tireur (réactivité), mais aucun dégât n'est appliqué
	# tant que le serveur n'a pas rediffusé l'ordre.
	weapon.shake_local()
	Net.to_server(self, &"server_request_fire", [dir, tap])

@rpc("any_peer", "call_local", "reliable")
func server_request_fire(dir: Vector3, tap: bool = false) -> void:
	if not Net.is_server() or is_eliminated:
		return
	# Le serveur revalide la cadence : un client modifié qui spammerait la
	# demande n'obtient rien de plus qu'un joueur honnête.
	if not weapon.consume(tap):
		return
	var origin := weapon.muzzle_position()
	Net.broadcast(self, &"net_fire", [origin, dir.normalized()])

@rpc("authority", "call_local", "reliable")
func net_fire(origin: Vector3, dir: Vector3) -> void:
	if weapon.data == null:
		return
	visual.set_state(CharacterVisual.State.ATTACK)
	weapon.fire(origin, dir, Cfg.Team.PLAYER, peer_id, Net.is_server())

# --- ZONE ----------------------------------------------------------------

func _tick_zone_damage(delta: float) -> void:
	if not MatchDirector.is_outside_zone(global_position):
		_zone_accum = 0.0
		return
	_zone_accum += delta
	# Application par paliers d'une demi-seconde : des dégâts continus
	# déclencheraient un flash à chaque image et rendraient l'écran illisible.
	if _zone_accum >= 0.5:
		_zone_accum -= 0.5
		server_take_damage(ZONE_DPS * 0.5, global_position, 0, Cfg.Team.MOB)

# --- DÉGÂTS (SERVEUR) ----------------------------------------------------

## SERVEUR UNIQUEMENT. Unique porte d'entrée des dégâts sur ce joueur.
func server_take_damage(amount: float, from: Vector3, killer_id: int,
		from_team: int) -> void:
	if not Net.is_server() or is_eliminated or health.is_dead:
		return
	# INVULNÉRABILITÉ DE RETOUR. Elle n'existe que pour empêcher d'être
	# abattu avant d'avoir pu bouger — être tué par quelqu'un qui campe
	# votre point de réapparition n'apprend rien et ne se défend pas.
	if _protection > 0.0:
		return
	# Pas de tir ami entre joueurs sur soi-même ; le PvP entre joueurs
	# distincts reste évidemment actif.
	if from_team == Cfg.Team.PLAYER and killer_id == peer_id:
		return
	if not health.apply_damage(amount, from, killer_id):
		return
	Net.broadcast(self, &"net_health", [health.current_health, from])
	if health.is_dead:
		Net.broadcast(self, &"net_die", [killer_id])
		MatchDirector.eliminate(peer_id)
		# L'ORDRE COMPTE. On crédite le tueur AVANT de programmer le retour
		# de la victime : la réapparition remet l'équipement à zéro, et
		# l'arme employée pour le kill ne serait plus lisible après.
		_crediter_elimination(killer_id, from_team)
		Respawn.appliquer_perte_equipement(self)
		Respawn.signaler_mort(peer_id, killer_id)

## CRÉDITE L'ÉLIMINATION À SON AUTEUR.
##
## Seules les éliminations PAR UN AUTRE JOUEUR comptent : mourir dans la
## zone, sur une explosion de mob ou par sa propre grenade ne doit alimenter
## la série de personne. C'est ce qui empêchera plus tard un groupe de
## s'échanger des kills pour monter.
##
## La progression n'est tenue que pour le joueur LOCAL et humain. Un bot n'a
## pas de profil, et un joueur distant tient le sien sur sa propre machine —
## lui écrire son XP d'ici serait à la fois faux et impossible à valider.
func _crediter_elimination(killer_id: int, from_team: int) -> void:
	if from_team != Cfg.Team.PLAYER or killer_id == 0 or killer_id == peer_id:
		return
	var tueur := MatchDirector.players.get(killer_id) as Node
	if tueur == null or not is_instance_valid(tueur):
		return
	if tueur.get(&"is_bot") == true or tueur.get(&"peer_id") != Net.local_id():
		return
	var arme: StringName = &""
	var w = tueur.get(&"weapon")
	if w != null and w.data != null:
		arme = w.data.id
	var bilan := Profil.enregistrer_kill_joueur(arme)
	elimination_reussie.emit(display_name, bilan)


@rpc("authority", "call_local", "unreliable_ordered")
func net_health(value: float, from: Vector3) -> void:
	if not Net.is_server():
		health.set_replicated_health(value)
	visual.set_state(CharacterVisual.State.HIT)
	visual.flash(Cfg.COL_DANGER)
	Fx.hit(global_position + Vector3(0, 1.0, 0), Cfg.COL_DANGER, 1.0)
	if peer_id == Net.local_id() and not is_bot:
		Fx.shake(0.16)

@rpc("authority", "call_local", "reliable")
func net_die(killer_id: int) -> void:
	if is_eliminated:
		return
	is_eliminated = true
	health.is_dead = true
	visual.set_state(CharacterVisual.State.DEATH)
	Fx.death(global_position, Cfg.COL_ENEMY_PLAYER)
	health_bar.visible = false
	# Le corps reste au sol comme trace de l'affrontement, mais ne bloque
	# plus personne.
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	died.emit()

# --- RÉAPPARITION --------------------------------------------------------

## Invulnérabilité restante après un retour, en secondes.
var _protection: float = 0.0


## REMET LE JOUEUR EN JEU. Exécuté sur TOUS les pairs, à l'identique.
##
## POURQUOI CETTE FONCTION EST LONGUE ET LE RESTE. Mourir a éteint six
## choses distinctes : la vie, la physique, les collisions, la barre de vie,
## le visuel et le drapeau d'élimination. En rallumer cinq sur six donne un
## joueur qui se déplace mais ne peut pas tirer, ou qu'on traverse — et le
## défaut ne se voit qu'après la première mort, donc jamais en test rapide.
## Chaque ligne éteinte par `net_die` a ici sa contrepartie, dans le même
## ordre, pour qu'un simple regard vérifie qu'aucune ne manque.
func revivre(position: Vector3) -> void:
	global_position = position
	_target_pos = position
	velocity = Vector3.ZERO
	_accel = Vector3.ZERO
	_dash_time = 0.0
	_dash_cd = 0.0
	_tampon_tir = 0.0
	_combat = 0.0
	locked_target = null

	is_eliminated = false
	health.reset()
	health_bar.visible = true
	collision_layer = Cfg.LAYER_PLAYER
	collision_mask = Cfg.LAYER_WORLD
	set_physics_process(true)
	visual.revive()

	_protection = ConfigProgression.PROTECTION_RESPAWN
	# L'invulnérabilité doit SE VOIR, sinon l'adversaire s'acharne sur une
	# cible invincible sans comprendre pourquoi rien ne se passe, et le
	# protégé ne sait pas non plus qu'il l'est.
	visual.flash(Cfg.COL_BASIC)
	Fx.impact(position + Vector3(0, 0.6, 0), Cfg.COL_BASIC, 1.4)
	health_changed.emit(health.current_health, health.max_health)
	inventory_changed.emit(slots, active_slot)


## REPLIE LA POSITION DANS LE MONDE — c'est ici que le monde s'enroule.
##
## POURQUOI CE FILET EXISTE. Une capture d'écran envoyée depuis un
## téléphone montrait l'interface intacte — vie à 49, niveau 2 — sur un
## dégradé violet sans le moindre décor. Ce dégradé n'est pas un bogue
## d'affichage : c'est l'HÉMISPHÈRE BAS DU CIEL, corail près de l'horizon
## et bleu nuit à la verticale. Autrement dit la caméra regardait vers le
## bas, correctement orientée, et il n'y avait simplement plus de sol.
##
## Le sol de collision est une boîte carrée : au-delà de ses bords, on
## tombe indéfiniment. Peu importe COMMENT on y arrive — un passage entre
## deux mesas du mur, une esquive qui traverse, une réapparition
## malheureuse : le résultat est une partie perdue sans mort, sans message,
## sans retour possible. C'est le pire défaut qu'un jeu puisse avoir, parce
## qu'il ne se signale pas.
##
## On ne cherche donc pas à énumérer les causes, on rend l'état
## irrécupérable impossible.
func _replier_les_bords() -> void:
	# L'ENROULEMENT, VU DU JOUEUR : deux lignes, et c'est tout.
	#
	# Franchir la limite du monde ne demande ni portail, ni chargement, ni
	# détection : la position REPASSE simplement de l'autre côté. Comme le
	# décor est périodique et que la caméra suit le même repli, l'image ne
	# change pas d'un pixel — on continue tout droit sans rien remarquer.
	# UNE COORDONNÉE NON NUMÉRIQUE EST FATALE, ET SILENCIEUSE.
	#
	# Elle ne fait pas planter le jeu : elle se propage. La position du
	# joueur contamine la visée lissée, qui contamine la caméra, dont le
	# tronc de vision devient invalide — et plus rien ne s'affiche, sauf le
	# ciel et l'interface. On coupe la propagation à la source plutôt que de
	# chercher indéfiniment quelle division l'a produite.
	if not is_finite(global_position.x) or not is_finite(global_position.y) \
			or not is_finite(global_position.z):
		push_warning("Position non numérique — retour au point d'apparition.")
		var secours := PlanMonde.enrouler3(Vector3(0.0, 1.0, 0.0))
		global_position = secours
		_target_pos = secours
		velocity = Vector3.ZERO
		_accel = Vector3.ZERO
		_dash_time = 0.0
		if MatchDirector and MatchDirector.has_signal(&"announce"):
			MatchDirector.announce.emit("VEILLE : POSITION RETABLIE",
					Cfg.COL_DANGER)
		return

	# LE JOUEUR LOCAL EST L'ORIGINE DU REPÈRE : lui seul se replie dans le
	# carré de référence, et il y pose l'ancre autour de laquelle tout le
	# reste du monde vivant se repliera. Les autres corps — adversaires,
	# mobs, projectiles — se replient vers LUI, jamais vers l'origine :
	# c'est ce qui met la limite du monde hors de portée en permanence.
	var replie := global_position
	if est_local():
		replie = PlanMonde.enrouler3(global_position)
		PlanMonde.ancre = replie
	else:
		replie = PlanMonde.replier(global_position)
	if not replie.is_equal_approx(global_position):
		global_position = replie
		_target_pos = PlanMonde.replier_vers(replie, _target_pos)

	# TOMBER SOUS LE SOL RESTE UNE ANOMALIE, elle. Le repli horizontal ne
	# peut rien pour elle, et un joueur qui tombe indéfiniment perd sa
	# partie sans mourir, sans message et sans retour possible.
	if global_position.y < -4.0:
		global_position = Vector3(global_position.x, 1.0, global_position.z)
		_target_pos = global_position
		velocity = Vector3.ZERO
		_accel = Vector3.ZERO
		_dash_time = 0.0
		push_warning("Joueur passé sous le sol — remonté en %s."
				% str(global_position))
		if MatchDirector and MatchDirector.has_signal(&"announce"):
			MatchDirector.announce.emit("JOUEUR SOUS LE SOL", Cfg.COL_DANGER)


## Le joueur est-il actuellement protégé par son invulnérabilité de retour ?
func est_protege() -> bool:
	return _protection > 0.0


## SERVEUR — remet l'équipement de départ. Les armes ramassées sont perdues.
func reinitialiser_equipement() -> void:
	if not Net.is_server():
		return
	var depart := Registry.starting_weapon()
	if depart == null:
		return
	Net.broadcast(self, &"net_set_slot", [0, depart.id, true])
	# Le second emplacement est VIDÉ explicitement : sans cela, l'arme
	# ramassée avant de mourir y resterait, et « perdre son équipement »
	# n'aurait perdu que la moitié.
	Net.broadcast(self, &"net_vider_slot", [1])


@rpc("authority", "call_local", "reliable")
func net_vider_slot(slot: int) -> void:
	slots[slot] = &""
	inventory_changed.emit(slots, active_slot)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.set_ratio(current / maxf(maximum, 0.01))
	health_changed.emit(current, maximum)

func _on_died(killer_id: int) -> void:
	pass  # la mort est diffusée par server_take_damage, pas ici

# --- RÉPLICATION ---------------------------------------------------------

func _replicate(delta: float) -> void:
	if not Net.is_networked():
		return
	_net_accum += delta
	if _net_accum < 1.0 / NET_SEND_HZ:
		return
	_net_accum = 0.0
	net_state.rpc(global_position, _facing)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(pos: Vector3, yaw: float) -> void:
	# Le serveur borne la position reçue : un client ne peut pas se
	# téléporter hors de l'arène, même en trichant sur son propre corps.
	if Net.is_server():
		var flat := Vector2(pos.x, pos.z)
		if flat.length() > Cfg.ARENA_RADIUS + 6.0:
			flat = flat.normalized() * (Cfg.ARENA_RADIUS + 6.0)
			pos = Vector3(flat.x, pos.y, flat.y)
	_target_pos = pos
	_target_yaw = yaw

func _interpolate(delta: float) -> void:
	# Lissage exponentiel : masque la latence sans jamais faire glisser un
	# corps loin derrière sa position réelle.
	var k := 1.0 - exp(-18.0 * delta)
	# LE PLUS COURT CHEMIN, LÀ AUSSI. Une position reçue du serveur peut
	# avoir franchi la limite du monde depuis la précédente : interpolée
	# « à plat », elle ferait traverser toute la carte au personnage en une
	# fraction de seconde, et la vitesse déduite atteindrait des milliers de
	# mètres par seconde — de quoi déclencher tout ce qui dépend d'elle.
	var vers := PlanMonde.ecart3(global_position, _target_pos)
	global_position += vers * k
	_facing = lerp_angle(_facing, _target_yaw, k)
	rotation.y = _facing + PI
	velocity = vers * (1.0 - k) / maxf(delta, 0.001)

# --- INVENTAIRE ----------------------------------------------------------

func equip_weapon_id(id: StringName, slot: int) -> void:
	var data := Registry.weapon(id)
	if data == null:
		return
	slots[slot] = id
	active_slot = slot
	weapon.equip(data)
	visual.attach_weapon(weapon.take_model())
	inventory_changed.emit(slots, active_slot)

## Ramassage. Retourne l'identifiant de l'arme ÉJECTÉE (vide si aucune) :
## l'inventaire étant plein, l'échange doit rendre l'ancienne au sol plutôt
## que de la faire disparaître.
func server_pickup(id: StringName) -> StringName:
	if Registry.weapon(id) == null:
		return &""
	var free_slot := slots.find(&"")
	if free_slot != -1:
		Net.broadcast(self, &"net_set_slot", [free_slot, id, true])
		return &""
	# Inventaire plein : on remplace l'arme ACTIVE. Le joueur choisit donc
	# ce qu'il abandonne, simplement en sélectionnant son slot avant de
	# marcher sur le loot.
	var dropped := slots[active_slot]
	Net.broadcast(self, &"net_set_slot", [active_slot, id, true])
	return dropped

@rpc("authority", "call_local", "reliable")
func net_set_slot(slot: int, id: StringName, make_active: bool) -> void:
	slots[slot] = id
	if make_active:
		equip_weapon_id(id, slot)
	else:
		inventory_changed.emit(slots, active_slot)
	var data := Registry.weapon(id)
	if data:
		Fx.pickup(global_position + Vector3(0, 1.0, 0), data.color)

func swap_weapon() -> void:
	var other := 1 - active_slot
	if slots[other] == &"":
		return
	equip_weapon_id(slots[other], other)

func dash_ready_ratio() -> float:
	return 1.0 - clampf(_dash_cd / DASH_COOLDOWN, 0.0, 1.0)


# --- INDICATEURS DE VISÉE ------------------------------------------------
#
# Trois repères, parce que « je ne sais pas dans quel sens je suis ni où je
# tire » est un défaut de LISIBILITÉ, pas de contrôle :
#
#   • un CHEVRON au sol, toujours visible, qui dit où le corps fait face ;
#   • un TÉLÉMÈTRE dans l'axe de tir, ARRÊTÉ par le premier obstacle, donc
#     qui montre aussi que les murs bloquent réellement les balles ;
#   • un ANNEAU sous la cible accrochée par la visée assistée.

## Longueur maximale du télémètre, faute d'arme équipée.
const AIM_FALLBACK_RANGE := 14.0

func _build_aim_visuals() -> void:
	# CHEVRON d'orientation, aux pieds. Toujours affiché : c'est lui qui
	# répond en permanence à « dans quel sens suis-je ? ».
	var chevron := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.34
	cone.height = 0.5
	cone.radial_segments = 3
	chevron.mesh = cone
	chevron.material_override = VisualKit.glow_mat(Cfg.COL_LOCAL_PLAYER, 1.8)
	# Couché à plat, pointe vers l'avant (-Z).
	chevron.rotation = Vector3(-PI / 2.0, 0, 0)
	chevron.position = Vector3(0, 0.06, -0.72)
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chevron)

	# TÉLÉMÈTRE. Maille de longueur 1 sur Z, étirée par `scale.z` selon la
	# distance réellement libre devant le joueur.
	_aim_line = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.1, 0.02, 1.0)
	_aim_line.mesh = beam
	var lm := VisualKit.glow_mat(Cfg.COL_LOCAL_PLAYER, 1.4)
	lm.albedo_color.a = 0.3
	_aim_line.material_override = lm
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_line)

	# ANNEAU de cible.
	_lock_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.62
	ring.outer_radius = 0.82
	ring.rings = 20
	ring.ring_segments = 6
	_lock_ring.mesh = ring
	_lock_ring.material_override = VisualKit.glow_mat(Cfg.COL_SHOTGUN, 2.4)
	_lock_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# `top_level` : l'anneau vit dans le monde, il n'hérite ni de la
	# position ni de la rotation du joueur.
	_lock_ring.top_level = true
	_lock_ring.visible = false
	add_child(_lock_ring)

func _update_aim_visuals() -> void:
	if _aim_line == null:
		return
	if is_eliminated:
		_aim_line.visible = false
		_lock_ring.visible = false
		return

	var col := Cfg.COL_LOCAL_PLAYER
	var reach := AIM_FALLBACK_RANGE
	if weapon and weapon.data:
		col = weapon.data.color
		reach = weapon.data.range

	# Le télémètre s'arrête au premier OBSTACLE — pas sur les créatures, on
	# veut voir la portée utile, pas la première cible. C'est ce qui rend
	# visible le fait qu'un mur coupe la ligne de tir.
	var from := global_position + Vector3(0, 0.9, 0)
	var dir := Vector3(sin(_facing), 0.0, cos(_facing))
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	q.collision_mask = Cfg.LAYER_WORLD
	var hit := space.intersect_ray(q)
	var length: float = reach
	if hit:
		length = maxf(0.6, from.distance_to(hit.position))

	_aim_line.scale = Vector3(1.0, 1.0, length)
	_aim_line.position = Vector3(0, 0.06, -length * 0.5)
	var m := _aim_line.material_override as StandardMaterial3D
	if m:
		# Discret au repos, franc pendant le tir : présent sans encombrer.
		m.albedo_color = Color(col.r, col.g, col.b, 0.5 if want_fire else 0.18)
		m.emission = col
		m.emission_energy_multiplier = 2.2 if want_fire else 0.7

	var show_lock := locked_target != null and is_instance_valid(locked_target)
	_lock_ring.visible = show_lock
	if show_lock:
		_lock_ring.global_position = locked_target.global_position \
				+ Vector3(0, 0.08, 0)
