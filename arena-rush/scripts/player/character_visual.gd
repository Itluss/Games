extends Node3D
class_name CharacterVisual
## APPARENCE D'UN PERSONNAGE — animation procédurale, zéro logique de jeu.
##
## POURQUOI CE NŒUD EXISTE : le prototype n'a pas encore de modèles animés.
## Plutôt que de bloquer le gameplay en attendant des .glb, on anime des
## primitives par le code. La frontière est nette — ce nœud ne connaît ni
## les PV, ni les dégâts, ni le réseau ; il reçoit un ÉTAT et le joue.
##
## REMPLACEMENT PAR DE VRAIS MODÈLES : garder `set_state()`, `flash()`,
## `attach_weapon()` et `get_weapon_mount()`, remplacer le contenu par un
## AnimationPlayer. Aucun appelant n'a à changer.

enum State { IDLE, RUN, ATTACK, HIT, DEATH }

var state: State = State.IDLE
var _rig: Node3D
var _parts: Dictionary = {}          # nom -> MeshInstance3D
var _base_pos: Dictionary = {}       # nom -> position de repos
var _materials: Array[StandardMaterial3D] = []
var _mount: Node3D
var _weapon_model: Node3D = null

var _time: float = 0.0
## Mouvement reçu du corps, exprimé dans son repère et normalisé.
var _vel: Vector3 = Vector3.ZERO
var _acc: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO     # x = tangage, y = roulis
var _squash: Vector3 = Vector3.ONE
var _squash_target: Vector3 = Vector3.ONE
## Phase de la foulée simulée. Elle n'avance qu'avec la vitesse réelle,
## sinon le personnage « courrait » sur place à l'arrêt.
var _run_phase: float = 0.0
var _squelette: Skeleton3D = null
## Mise en joue, lissée : passer sec de « bras ballants » à « bras tendus »
## produit un à-coup très laid à chaque pression sur la gâchette.
var _vise: float = 0.0
var _vise_cible: float = 0.0
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _dead: bool = false

## Modèle 3D du personnage joueur, généré par Meshy depuis la planche de
## Camille. Sa hauteur réelle est mesurée une fois pour toutes ici : le
## gabarit du jeu vise 1,70 m, le modèle en fait 1,90.
const MODELE := "res://assets/models/kael.glb"
const MODELE_HAUTEUR := 1.903
## Le modèle regarde vers +Z, alors que l'avant d'un nœud Godot est -Z.
const MODELE_DEMI_TOUR := PI
## MESURÉ sur le maillage : son origine est en son CENTRE, pas sous ses
## pieds. Sans ce relèvement, la moitié du personnage passe sous le sol —
## et tout repère placé en supposant une origine aux pieds se retrouve
## décalé d'une hauteur d'homme, ce qui expliquait l'arme volante.
const MODELE_PIEDS := 0.952
## Main droite, mesurée dans le repère D'ORIGINE du modèle (centré).
const MODELE_MAIN := Vector3(-0.40, -0.09, 0.06)
## Les armes procédurales ont 72 cm de canon, dessinées pour l'ancien
## gabarit. On les ramène à l'échelle du porteur.
const ARME_ECHELLE := 0.5

func build(color: Color, accent: Color, height: float = 1.7) -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	# On tente le vrai modèle ; à défaut on retombe sur les primitives.
	# Ce repli n'est pas de la coquetterie : il garde le jeu lançable si
	# l'asset manque, ce qui arrive dès qu'on travaille sur une branche
	# où il n'a pas encore été déposé.
	if ResourceLoader.exists(MODELE):
		_monter_modele(height)
	else:
		push_warning("Modèle %s absent — repli sur le gabarit primitif." % MODELE)
		_monter_primitives(color, accent, height)
# --- MONTAGE DU VRAI MODÈLE ---------------------------------------------

func _monter_modele(height: float) -> void:
	var scene: PackedScene = load(MODELE)
	var modele: Node3D = scene.instantiate()
	var facteur := height / MODELE_HAUTEUR

	# Conteneur portant échelle, demi-tour et relèvement. Le squelette
	# vit dedans, donc il en hérite : ses os restent exprimés dans le
	# repère d'origine du maillage, ce qui évite d'avoir à convertir
	# chaque position d'os.
	var socle := Node3D.new()
	socle.name = "Socle"
	socle.scale = Vector3.ONE * facteur
	socle.rotation.y = MODELE_DEMI_TOUR
	socle.position.y = MODELE_PIEDS * facteur
	_rig.add_child(socle)

	_squelette = ProceduralRig.construire_squelette()
	socle.add_child(_squelette)

	# On récupère le maillage brut, on l'habille d'attaches osseuses, et
	# on jette le nœud importé : il ne servait qu'à porter la géométrie.
	var source: Mesh = null
	for brut in _mailles(modele):
		source = (brut as MeshInstance3D).mesh
		break
	modele.queue_free()
	if source == null:
		push_warning("Maillage introuvable dans %s." % MODELE)
		return

	var habille := ProceduralRig.habiller(source)
	var mi := MeshInstance3D.new()
	mi.name = "Corps"
	mi.mesh = habille
	_squelette.add_child(mi)
	# Le maillage habillé est PARTAGÉ entre tous les personnages ; seuls
	# les squelettes diffèrent. C'est ce qui permet de ne payer le calcul
	# des poids qu'une seule fois.
	mi.skeleton = mi.get_path_to(_squelette)
	mi.skin = _squelette.create_skin_from_rest_transforms()

	for i in habille.get_surface_count():
		var src: Material = habille.surface_get_material(i)
		var copie: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D \
				else StandardMaterial3D.new()
		copie.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		copie.specular_mode = BaseMaterial3D.SPECULAR_TOON
		copie.rim_enabled = true
		copie.rim = 0.4
		# Indispensable sur un maillage habillé : sans cela le moteur
		# calcule ses limites sur la pose de repos et fait disparaître le
		# personnage dès qu'un membre en sort.
		mi.set_surface_override_material(i, copie)
		_materials.append(copie)

	# ARME accrochée à l'OS de la main droite : elle suit désormais le
	# balancement du bras au lieu de flotter à côté du corps.
	var attache := BoneAttachment3D.new()
	attache.name = "AttacheMain"
	attache.bone_name = "main_d"
	_squelette.add_child(attache)
	_mount = Node3D.new()
	_mount.name = "WeaponMount"
	# Le canon des armes pointe vers -Z ; l'avant du modèle est +Z.
	_mount.rotation.y = PI
	attache.add_child(_mount)

func _mailles(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_mailles(c, out)
	return out

# --- REPLI : ANCIEN GABARIT DE PRIMITIVES -------------------------------

func _monter_primitives(color: Color, accent: Color, height: float) -> void:
	var gabarit := VisualKit.build_humanoid(color, accent, height)
	_rig.add_child(gabarit)
	for child in gabarit.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		_parts[mi.name] = mi
		_base_pos[mi.name] = mi.position
		var m: Material = mi.material_override
		if m is StandardMaterial3D:
			_materials.append(m)
	_mount = gabarit.get_node_or_null("WeaponMount")

func get_weapon_mount() -> Node3D:
	return _mount

## Greffe le modèle d'arme sur la main. L'ancien est retiré : un joueur ne
## tient jamais deux armes à la fois, même une image.
func attach_weapon(model: Node3D) -> void:
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = model
	if model and _mount:
		model.scale = Vector3.ONE * ARME_ECHELLE
		_mount.add_child(model)

## Vitesse et accélération dans le repère du personnage, normalisées.
## `z > 0` = vers l'avant, `x > 0` = vers la droite.
func set_motion(vel: Vector3, acc: Vector3) -> void:
	_vel = vel
	_acc = acc

## Mise en joue. Appelé en continu par le joueur avec son intention de tir.
func set_aiming(actif: bool) -> void:
	_vise_cible = 1.0 if actif else 0.0

## Déformation ponctuelle — écrasement ou étirement — qui revient d'elle
## même. C'est l'ingrédient qui fait qu'un mouvement brutal se LIT au lieu
## d'être subi : sans déformation, une accélération instantanée n'a aucune
## expression visuelle.
func punch(target: Vector3, duration: float = 0.16) -> void:
	if _dead:
		return
	_squash_target = target
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_squash_target = Vector3.ONE.lerp(target, v), 1.0, 0.0, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func set_state(s: State) -> void:
	if _dead or state == s:
		return
	state = s
	match s:
		State.ATTACK:
			_attack_t = 0.16
			punch(Vector3(1.06, 0.96, 0.94), 0.12)
		State.HIT:
			_hit_t = 0.18
		State.DEATH:
			_dead = true
			_play_death()

## Teinte brève de tout le personnage — c'est LE signal « tu as été
## touché », lisible même quand l'écran est chargé.
## Intensité du flash de dégâts.
##
## Calibrée pour un modèle TEXTURÉ. La valeur d'origine (2,6), pensée pour
## des aplats de couleur unie, noyait complètement les textures de Kael :
## sa veste bleue virait au violet et ses cheveux à l'orange vif. Sur une
## texture, le flash doit TEINTER, pas remplacer.
const FLASH_ENERGIE := 0.9

func flash(color: Color = Color.WHITE, duration: float = 0.12) -> void:
	if _dead:
		return
	for m in _materials:
		m.emission_enabled = true
		m.emission = color
		var tw := create_tween()
		tw.tween_property(m, "emission_energy_multiplier", 0.0, duration) \
				.from(FLASH_ENERGIE)

func _play_death() -> void:
	# Bascule au sol + affaissement : une mort doit se LIRE d'un coup d'œil,
	# y compris à l'autre bout de l'arène.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rig, "rotation:x", -PI / 2.0, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "scale", Vector3(1.15, 0.55, 1.15), 0.32)
	tw.tween_property(self, "position:y", -0.25, 0.5)

## `speed_ratio` : 0 à l'arrêt, 1 à pleine course.
func update_visual(delta: float, speed_ratio: float) -> void:
	if _dead or _rig == null:
		return
	_time += delta

	if _attack_t > 0.0:
		_attack_t -= delta
		if _attack_t <= 0.0 and state == State.ATTACK:
			state = State.RUN if speed_ratio > 0.1 else State.IDLE
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0 and state == State.HIT:
			state = State.RUN if speed_ratio > 0.1 else State.IDLE
	if state == State.IDLE and speed_ratio > 0.1:
		state = State.RUN
	elif state == State.RUN and speed_ratio <= 0.1:
		state = State.IDLE

	# COURSE : les jambes balancent, le torse rebondit. La fréquence suit
	# la vitesse réelle, donc le personnage ne « patine » jamais.
	var swing := sin(_time * lerpf(4.0, 15.0, speed_ratio)) * speed_ratio
	_offset("LegL", Vector3(0, 0, swing * 0.26))
	_offset("LegR", Vector3(0, 0, -swing * 0.26))
	_offset("ArmL", Vector3(0, 0, -swing * 0.2))

	var bob := absf(sin(_time * lerpf(4.0, 15.0, speed_ratio))) * speed_ratio * 0.07
	_offset("Torso", Vector3(0, bob, 0))
	_offset("Head", Vector3(0, bob * 1.1, 0))
	_offset("Shoulders", Vector3(0, bob, 0))
	_offset("Visor", Vector3(0, bob * 1.1, 0))

	# ATTAQUE : le bras armé se détend vers l'avant. Court et sec — c'est
	# la nervosité du geste qui rend un tir satisfaisant.
	var punch := 0.0
	if _attack_t > 0.0:
		punch = sin((1.0 - _attack_t / 0.16) * PI) * 0.22
	_offset("ArmR", Vector3(0, 0, -punch - swing * -0.2))

	# COUP ENCAISSÉ : recul du buste, très bref.
	if _hit_t > 0.0:
		var k := _hit_t / 0.18
		_rig.position.z = k * 0.14
	else:
		_rig.position.z = 0.0

	# FOULÉE. Avec un squelette, ce ne sont plus des artifices de corps
	# entier : les membres bougent réellement.
	#
	# La phase n'avance qu'avec la vitesse, sinon le personnage courrait
	# sur place à l'arrêt. Le rebond du bassin subsiste — un coureur monte
	# et descend à chaque appui — mais il accompagne la foulée au lieu de
	# la remplacer.
	# Cadence proportionnelle à la vitesse. Le corps est au plus HAUT en
	# suspension et au plus BAS au contact : deux appuis par cycle, donc
	# un rebond de fréquence double.
	_run_phase += delta * 9.5 * speed_ratio
	var rebond := pow(sin(_run_phase), 2.0) * REBOND * speed_ratio
	var roulis := sin(_run_phase * 0.5) * 0.04 * speed_ratio
	var appui := maxf(0.0, -sin(_run_phase)) * 0.03 * speed_ratio
	_rig.position.y = rebond
	if _squelette:
		_animer_os(speed_ratio, delta)

	# INCLINAISON — le corps penche dans le sens de la marche et s'incline
	# dans les changements de direction. C'est ce qui distingue un
	# personnage d'un objet qu'on translate : sans elle, il glisse à plat,
	# sans poids ni intention.
	#
	# La vitesse donne l'assiette générale, l'accélération la réaction
	# vive aux changements. Le lissage est exponentiel, donc identique à
	# toute cadence d'affichage.
	var target_lean := Vector2(
			clampf(_vel.z * 0.16 + _acc.z * 0.10, -0.30, 0.30),
			clampf(_vel.x * 0.20 + _acc.x * 0.14, -0.34, 0.34))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta / 0.09))
	# L'avant du gabarit est -Z, d'où les signes : un tangage positif
	# ferait basculer le buste en arrière.
	_rig.rotation.x = -_lean.x
	_rig.rotation.z = -_lean.y + roulis

	# RESPIRATION à l'arrêt : une immobilité parfaitement figée est le
	# signe le plus sûr d'un pantin.
	var breathe := 1.0 + sin(_time * 1.9) * 0.018 * (1.0 - speed_ratio)
	_squash = _squash.lerp(_squash_target, 1.0 - exp(-delta / 0.055))
	_rig.scale = Vector3(
			_squash.x * (1.0 + appui * 0.5),
			_squash.y * breathe * (1.0 - appui),
			_squash.z * (1.0 + appui * 0.5))

func _offset(part: String, delta_pos: Vector3) -> void:
	var node: MeshInstance3D = _parts.get(part)
	if node == null:
		return
	node.position = _base_pos[part] + delta_pos

func revive() -> void:
	_dead = false
	state = State.IDLE
	position = Vector3.ZERO
	if _rig:
		_rig.rotation = Vector3.ZERO
		_rig.scale = Vector3.ONE
		_rig.position = Vector3.ZERO


# --- ANIMATION DU SQUELETTE ---------------------------------------------
#
# Un cycle de course tient en peu de choses, mais toutes sont nécessaires :
#
#   • les jambes balancent en OPPOSITION de phase ;
#   • le genou ne plie que sur la jambe qui recule — une jambe qui plie
#     en avançant donne une démarche de pantin ;
#   • les bras balancent en opposition aux jambes, c'est ce qui équilibre
#     la course et la rend lisible ;
#   • le buste contre-pivote légèrement, sinon le haut du corps paraît
#     posé sur les jambes plutôt que solidaire d'elles.
#
# Tout est proportionnel à la vitesse : à l'arrêt, le cycle s'éteint et
# le personnage revient à sa pose de repos.

# --- CYCLE DE COURSE -----------------------------------------------------
#
# Une foulée n'est PAS un pendule symétrique — c'était le défaut de la
# version précédente, et il se voyait immédiatement. Les traits qui font
# qu'une course se lit comme une course :
#
#   1. LE GENOU SE PLIE AU RETOUR, pas à l'appui. Juste après la poussée,
#      le talon remonte vers la fesse pendant que la cuisse revient vers
#      l'avant, puis la jambe se détend pour aller chercher le sol. Plier
#      le genou quand la jambe est en arrière donne une démarche de
#      pantin.
#   2. LA FLEXION EST FORTE — jusqu'à 90° et au-delà. Une jambe qui reste
#      quasi tendue donne une course de figurine.
#   3. LE CORPS MONTE ET DESCEND, au plus bas au contact du pied, au plus
#      haut en suspension. Deux contacts par cycle, donc deux rebonds.
#   4. LES BRAS SONT PLIÉS, autour de 80°, et balancent depuis l'épaule
#      en opposition à la jambe du même côté.
#   5. LE BUSTE PENCHE VERS L'AVANT. On ne court pas droit comme un i.
#
# La phase avance avec la vitesse ; à l'arrêt elle est ramenée vers une
# station debout au lieu de se figer où elle se trouvait.

## Amplitude de balancement de la cuisse, en radians.
const CUISSE_AMPL := 0.60
## Flexion maximale du genou au retour.
##
## Bornée à ~57° et non aux 90° d'une vraie foulée : au-delà, mes poids
## d'influence lâchent et le mollet s'enfonce dans la cuisse. C'est la
## limite d'un rigging par distance, qui ignore la topologie — un rig
## fait à la main tiendrait une flexion complète.
const GENOU_RETOUR := 1.0
## Flexion d'amorti à l'appui, bien plus discrète.
const GENOU_APPUI := 0.32
## Décalage de phase entre le balancement de cuisse et le pic de flexion.
## C'est LUI qui distingue une course d'un pantin articulé.
const GENOU_DECALAGE := 0.35
## Balancement de l'épaule.
const BRAS_AMPL := 0.62
## Flexion permanente du coude pendant la course.
const COUDE_COURSE := 1.35
## Flexion du coude au repos, bras le long du corps.
const COUDE_REPOS := 0.28
## Rappel des bras vers le corps — le modèle est généré bras écartés.
const BRAS_REPOS := 0.40
## Inclinaison du buste vers l'avant à pleine vitesse.
const BUSTE_PENCHE := 0.20
## Rebond vertical du bassin, en mètres de repère modèle.
const REBOND := 0.055

func _animer_os(speed_ratio: float, delta: float) -> void:
	var a := clampf(speed_ratio, 0.0, 1.0)
	_vise = lerpf(_vise, _vise_cible, 1.0 - exp(-delta / 0.09))

	# ARRÊT : plutôt que de laisser la phase se figer n'importe où, on la
	# ramène vers le multiple de PI le plus proche — l'instant où les deux
	# jambes passent sous le corps. Le personnage POSE ses pieds au lieu
	# de rester suspendu en plein pas.
	if a < 0.12:
		var cible: float = round(_run_phase / PI) * PI
		_run_phase = lerpf(_run_phase, cible, 1.0 - exp(-delta / 0.11))

	var phi := _run_phase
	_jambe(ProceduralRig.CUISSE_G, ProceduralRig.GENOU_G,
			ProceduralRig.CHEVILLE_G, phi, a)
	_jambe(ProceduralRig.CUISSE_D, ProceduralRig.GENOU_D,
			ProceduralRig.CHEVILLE_D, phi + PI, a)

	# BRAS — en opposition à la jambe du MÊME côté, et pliés en
	# permanence pendant la course.
	var oscillation := sin(phi)
	var coude := lerpf(COUDE_REPOS, COUDE_COURSE, a)
	var libre_g := oscillation * BRAS_AMPL * a
	var libre_d := -oscillation * BRAS_AMPL * a

	var tir_epaule_d := -1.28
	var tir_coude_d := -0.30
	var tir_epaule_g := -1.05
	var tir_coude_g := -1.15

	_poser(ProceduralRig.EPAULE_D, Vector3(
			lerpf(libre_d, tir_epaule_d, _vise),
			lerpf(0.0, 0.28, _vise),
			lerpf(BRAS_REPOS, 0.30, _vise)))
	_poser(ProceduralRig.COUDE_D, Vector3(
			lerpf(-coude, tir_coude_d, _vise), 0, 0))
	_poser(ProceduralRig.EPAULE_G, Vector3(
			lerpf(libre_g, tir_epaule_g, _vise),
			lerpf(0.0, -0.55, _vise),
			lerpf(-BRAS_REPOS, -0.34, _vise)))
	_poser(ProceduralRig.COUDE_G, Vector3(
			lerpf(-coude, tir_coude_g, _vise), 0, 0))

	# BUSTE : penché vers l'avant pendant la course, redressé en visée,
	# avec un léger contre-pivot qui accompagne le balancement des bras.
	var penche := -BUSTE_PENCHE * a * (1.0 - _vise * 0.6)
	var pivot := -oscillation * 0.11 * a * (1.0 - _vise * 0.8)
	_poser(ProceduralRig.BUSTE, Vector3(penche * 0.45, 0, 0))
	_poser(ProceduralRig.TORSE, Vector3(penche * 0.55, pivot, 0))
	# La tête reste droite : le regard ne suit pas le buste.
	_poser(ProceduralRig.TETE, Vector3(-penche * 0.75, -pivot * 0.6, 0))

## Une jambe complète. `phi` est sa phase propre ; les deux jambes sont
## décalées d'une demi-période.
func _jambe(cuisse: int, genou: int, cheville: int, phi: float, a: float) -> void:
	# La cuisse balance en pendule : phi=0 sous le corps, +PI/2 en
	# arrière au moment de la poussée, -PI/2 en avant à la recherche du sol.
	var balancier := sin(phi)
	_poser(cuisse, Vector3(balancier * CUISSE_AMPL * a, 0, 0))

	# Le genou plie surtout au RETOUR, avec un pic décalé après la
	# poussée. L'exposant rend la flexion brève et marquée plutôt
	# qu'étalée sur toute la période.
	var retour := maxf(0.0, sin(phi - GENOU_DECALAGE))
	var flexion := GENOU_RETOUR * pow(retour, 1.4)
	# Amorti discret au contact, quand la jambe passe devant.
	flexion += GENOU_APPUI * maxf(0.0, -sin(phi))
	_poser(genou, Vector3(-flexion * a, 0, 0))

	# La cheville se relève au retour et pousse à la fin de l'appui.
	var pousse := maxf(0.0, sin(phi)) * 0.30 - maxf(0.0, -sin(phi)) * 0.18
	_poser(cheville, Vector3(pousse * a, 0, 0))


## Applique une rotation d'os, exprimée en angles d'Euler.
func _poser(os: int, euler: Vector3) -> void:
	_squelette.set_bone_pose_rotation(os, Quaternion.from_euler(euler))
