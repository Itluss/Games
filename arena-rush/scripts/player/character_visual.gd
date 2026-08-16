extends Node3D
class_name CharacterVisual
## APPARENCE D'UN PERSONNAGE — aucune logique de jeu.
##
## Ce nœud ne connaît ni les PV, ni les dégâts, ni le réseau : il reçoit
## un ÉTAT et le joue. C'est ce qui permet d'en changer entièrement
## l'implémentation — ce qui vient d'arriver — sans toucher à un seul
## appelant.
##
## HISTOIRE DE CE FICHIER, parce qu'elle explique sa forme actuelle.
##
## Meshy livre un maillage d'un seul tenant, SANS os. Godot anime très
## bien, mais il ne fabrique pas un squelette : il joue celui qui existe.
## J'ai donc d'abord écrit un auto-riggeur en GDScript, qui devinait
## l'appartenance de chaque sommet à un os d'après sa distance. Ça tenait
## pour un bras qui balance ; ça ne tenait pas pour un pied, qui doit
## rester plat et solidaire de sa chaussure. Les poids ignoraient la
## topologie, les pieds se vrillaient, et il fallait brider la flexion du
## genou — donc brider la foulée — pour limiter les dégâts.
##
## La bonne réponse n'était pas de mieux régler ce bricolage, mais d'en
## changer : Meshy dispose d'un vrai auto-riggeur et d'une bibliothèque
## d'animations. Le personnage porte désormais un squelette humanoïde de
## 24 os et de VRAIES animations, jouées par un AnimationPlayer.
##
## Le rig procédural a disparu, et avec lui tout le code de cycle de
## course écrit à la main.

enum State { IDLE, RUN, ATTACK, HIT, DEATH }

## Modèle animé : maillage + squelette + quatre animations, réunis en un
## seul fichier par `outils/fusionner_anims.py`. Meshy livre un fichier
## PAR animation, chacun réembarquant maillage et texture : 27 Mo de
## doublons pour quatre clips. Fusionnés et texture ramenée à 1024, il
## reste 1,3 Mo — ce qui est expédiable sur le web.
const MODELE := "res://assets/models/kael.glb"
## MESURÉ dans Godot sur le modèle riggé : boîte englobante de 0,000 à
## 1,900. Contrairement au maillage brut, dont l'origine était au CENTRE
## — ce qui enfonçait le personnage jusqu'à la taille — le modèle riggé a
## son origine AUX PIEDS. Il n'y a donc plus rien à compenser.
const MODELE_HAUTEUR := 1.9
## Le modèle regarde vers +Z ; l'avant d'un nœud Godot est -Z.
const MODELE_DEMI_TOUR := PI
## Os de la main qui porte l'arme, tel que nommé par le rig Meshy.
const OS_MAIN := "RightHand"
## Les armes procédurales ont été dessinées pour un gabarit plus grand.
const ARME_ECHELLE := 0.5

## Noms des clips, tels que fixés à la fusion.
const A_REPOS := "repos"
const A_COURSE := "course"
const A_COURSE_TIR := "course_tir"
## Posture de combat, jouée À L'ARRÊT gâchette pressée.
##
## POURQUOI ELLE EXISTE : immobile, le jeu jouait « repos » quelle que
## soit la gâchette — appuyer sur TIR ne changeait donc rien à l'écran.
##
## DEUX CANDIDATS ont été générés et rendus au banc avant de trancher,
## parce que leurs noms ne disent pas ce qu'ils montrent : « Side_Shot »
## s'est révélé être un tir plongé au sol, inutilisable debout.
## « Combat_Stance » est une vraie garde — jambes ancrées, appui vers
## l'avant, et elle boucle sur place.
const A_GARDE := "garde"
const A_MORT := "mort"

## Durée du fondu entre deux clips. Assez court pour rester réactif,
## assez long pour qu'on ne voie pas le personnage se téléporter d'une
## pose à l'autre.
const FONDU := 0.18
const FONDU_MORT := 0.10

## Vitesse de lecture de la course selon l'allure. Sans cela, le
## personnage garde la même cadence de foulée à toutes les vitesses et
## PATINE — c'est le défaut le plus visible d'une animation mal branchée.
const CADENCE_MIN := 0.75
const CADENCE_MAX := 1.45

## Seuil de passage repos/course, avec hystérésis : un seul seuil ferait
## clignoter les deux clips quand la vitesse oscille autour de lui.
const SEUIL_COURSE := 0.14
const SEUIL_ARRET := 0.08

var state: State = State.IDLE
var _rig: Node3D
var _modele: Node3D
var _anim: AnimationPlayer
var _squelette: Skeleton3D
var _parts: Dictionary = {}
var _base_pos: Dictionary = {}
var _materials: Array[StandardMaterial3D] = []
var _mount: Node3D
## Sonde posée sur l'os de la main. Elle ne PORTE rien : elle sert
## uniquement à lire la position et l'orientation de la main.
var _attache: BoneAttachment3D = null
var _weapon_model: Node3D = null
## Rapport entre le gabarit voulu et la taille native du modèle.
var _facteur: float = 1.0

var _time: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _acc: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO
var _squash: Vector3 = Vector3.ONE
var _squash_target: Vector3 = Vector3.ONE
var _vise_cible: float = 0.0
var _clip: String = ""
## Verrou du banc de rendu : empêche la machine à états de rechoisir.
var _clip_verrouille: bool = false
var _court: bool = false
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _dead: bool = false


func build(color: Color, accent: Color, height: float = 1.7) -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	# Repli si l'asset manque : le jeu doit rester lançable sur une
	# branche où le modèle n'a pas encore été déposé.
	if ResourceLoader.exists(MODELE):
		_monter_modele(height)
	else:
		push_warning("Modèle %s absent — repli sur le gabarit primitif." % MODELE)
		_monter_primitives(color, accent, height)


# --- MONTAGE DU MODÈLE ANIMÉ --------------------------------------------

func _monter_modele(height: float) -> void:
	var scene: PackedScene = load(MODELE)
	_modele = scene.instantiate()
	_facteur = height / MODELE_HAUTEUR
	_modele.scale = Vector3.ONE * _facteur
	_modele.rotation.y = MODELE_DEMI_TOUR
	_rig.add_child(_modele)

	_anim = _trouver(_modele, "AnimationPlayer") as AnimationPlayer
	_squelette = _trouver(_modele, "Skeleton3D") as Skeleton3D
	if _anim == null:
		push_warning("Aucun AnimationPlayer dans %s." % MODELE)
	else:
		# Les clips arrivent en lecture unique. Sans mise en boucle, le
		# personnage courrait un demi-pas puis se figerait.
		for nom in [A_REPOS, A_COURSE, A_COURSE_TIR, A_GARDE]:
			if _anim.has_animation(nom):
				var clip := _anim.get_animation(nom)
				clip.loop_mode = Animation.LOOP_LINEAR
				_fixer_sur_place(clip, nom)
		_jouer(A_REPOS, 0.0)

	for maille in _mailles(_modele):
		var mi := maille as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var copie: StandardMaterial3D
			if src is StandardMaterial3D:
				copie = (src as StandardMaterial3D).duplicate()
			else:
				copie = StandardMaterial3D.new()
			# MÉTALLICITÉ REMISE À ZÉRO. L'export riggé de Meshy ne
			# précise pas `metallicFactor`, et la valeur par défaut de
			# glTF est 1.0 : le personnage devenait un miroir intégral et,
			# sans réflexion d'environnement, se rendait en SILHOUETTE
			# NOIRE — texture correctement chargée, mais invisible.
			# Le modèle non riggé échappait au piège parce qu'il portait
			# une carte métallique, que le rigging a supprimée.
			# Kael est un personnage de dessin animé : rien chez elle
			# n'est métallique.
			copie.metallic = 0.0
			copie.roughness = 0.72
			copie.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			copie.specular_mode = BaseMaterial3D.SPECULAR_TOON
			copie.rim_enabled = true
			copie.rim = 0.4
			mi.set_surface_override_material(i, copie)
			_materials.append(copie)

	# ARME accrochée à la MAIN — mais hors du squelette.
	#
	# POURQUOI CE DÉTOUR : le rig Meshy est exprimé en CENTIMÈTRES (la
	# hanche est à y=93,9 pour un maillage haut de 1,9), et l'armature
	# porte donc une échelle voisine de 0,01. Un BoneAttachment3D en
	# hérite, et tout ce qu'on y greffe avec : l'arme était bien dans la
	# main, au bon endroit, mais rendue à SEPT MILLIMÈTRES — donc
	# invisible. C'est le défaut rapporté sous la forme « il ne tient plus
	# son arme ».
	#
	# Compenser cette échelle une fois pour toutes ne suffit PAS : les
	# clips animent aussi la taille des os, si bien que le facteur hérité
	# varie au fil de l'animation et que l'arme se mettrait à enfler et
	# rétrécir au rythme du geste.
	#
	# La sonde reste donc sur l'os, mais elle ne porte rien : le support
	# de l'arme vit dans le repère du PERSONNAGE, et se contente de
	# recopier chaque trame la position et l'orientation de la main, sans
	# son échelle.
	if _squelette:
		_attache = BoneAttachment3D.new()
		_attache.name = "SondeMain"
		_attache.bone_name = OS_MAIN
		_squelette.add_child(_attache)
		_mount = Node3D.new()
		_mount.name = "WeaponMount"
		_rig.add_child(_mount)
		_suivre_main()


## Seuil, en unités du modèle, au-delà duquel une dérive est considérée
## comme un déplacement racine et non comme du ballant. Le modèle mesure
## 190 unités de haut : 2 unités, c'est un centimètre à l'échelle du
## personnage, donc largement en dessous de tout mouvement voulu.
const DERIVE_MAX := 2.0


## Supprime le DÉPLACEMENT RACINE d'un clip qui boucle.
##
## POURQUOI : certaines animations de la bibliothèque translatent
## réellement le personnage. « Run_and_Shoot » avance de 158 unités —
## 1,58 m — en 0,70 s. Comme le code du jeu déplace DÉJÀ le corps, les
## deux s'additionnent ; puis la boucle repart de zéro et le personnage
## est ramené d'un coup en arrière. À l'écran : il avance, il recule, il
## avance, il recule.
##
## Mesuré sur les quatre clips, seul « course_tir » est concerné :
## « course » et « repos » dérivent de moins d'un millième d'unité.
##
## CE QU'ON ENLÈVE : la seule composante qui PROGRESSE au fil du clip, et
## uniquement à l'horizontale. Le balancement d'un pas reste intact, tout
## comme le rebond vertical du bassin — c'est lui qui donne son poids à
## la foulée, et l'écraser rendrait la course flottante.
##
## La correction est idempotente : après passage, la dérive vaut zéro,
## donc un second appel ne fait rien. C'est nécessaire, la ressource
## d'animation étant partagée entre tous les personnages.
func _fixer_sur_place(clip: Animation, nom: String) -> void:
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not str(clip.track_get_path(t)).ends_with(":Hips"):
			continue
		var n_cles := clip.track_get_key_count(t)
		if n_cles < 2:
			continue
		var depart: Vector3 = clip.track_get_key_value(t, 0)
		var arrivee: Vector3 = clip.track_get_key_value(t, n_cles - 1)
		var derive := arrivee - depart
		derive.y = 0.0
		if derive.length() < DERIVE_MAX:
			continue
		var duree := maxf(clip.length, 0.0001)
		for k in n_cles:
			var instant := clip.track_get_key_time(t, k)
			var v: Vector3 = clip.track_get_key_value(t, k)
			# On retranche la part de dérive déjà parcourue à cet instant.
			clip.track_set_key_value(t, k, v - derive * (instant / duree))
		print("[CharacterVisual] « %s » : déplacement racine neutralisé "
				% nom, derive)


## Force un clip, en court-circuitant la machine à états.
##
## RÉSERVÉ AU BANC DE RENDU : il faut pouvoir REGARDER une animation
## avant de décider comment la brancher, et la machine à états ne la
## choisirait pas encore.
##
## LE VERROU EST INDISPENSABLE. Sans lui, `update_visual` rechoisissait
## un clip à la trame suivante et ramenait le personnage au repos : la
## planche de contact montrait alors un fondu vers « repos » en croyant
## montrer le clip demandé. Deux candidats différents y paraissaient
## identiques — un banc qui ment est pire que pas de banc.
func forcer_clip(nom: String) -> void:
	if _anim == null or not _anim.has_animation(nom):
		push_warning("Clip « %s » absent." % nom)
		return
	_anim.get_animation(nom).loop_mode = Animation.LOOP_LINEAR
	_clip_verrouille = true
	_clip = nom
	_anim.play(nom, 0.0)
	_anim.speed_scale = 1.0


func _trouver(n: Node, classe: String) -> Node:
	if n.is_class(classe):
		return n
	for c in n.get_children():
		var r := _trouver(c, classe)
		if r:
			return r
	return null


func _mailles(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_mailles(c, out)
	return out


## Change de clip, sans relancer celui qui tourne déjà.
func _jouer(nom: String, fondu: float = FONDU) -> void:
	if _anim == null or _clip == nom or not _anim.has_animation(nom):
		return
	_clip = nom
	_anim.play(nom, fondu)


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
## tient jamais deux armes à la fois, même en image.
func attach_weapon(model: Node3D) -> void:
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = model
	if model == null or _mount == null:
		return
	model.scale = Vector3.ONE * ARME_ECHELLE
	_mount.add_child(model)


## Recopie la main sur le support d'arme, SANS son échelle.
##
## L'orientation est orthonormalisée : c'est précisément ce qui jette
## l'échelle du squelette, y compris la part que l'animation fait varier
## d'une trame à l'autre.
func _suivre_main() -> void:
	if _mount == null or _attache == null or not _attache.is_inside_tree():
		return
	var t := _attache.global_transform
	var base := t.basis.orthonormalized()
	# Le canon des armes pointe vers -Z, l'avant du modèle vers +Z.
	base = base.rotated(base.y.normalized(), PI)
	_mount.global_transform = Transform3D(base.scaled(Vector3.ONE * _facteur),
			t.origin)


## Vitesse et accélération dans le repère du personnage, normalisées.
func set_motion(vel: Vector3, acc: Vector3) -> void:
	_vel = vel
	_acc = acc


## Mise en joue. Appelé en continu avec l'intention de tir du joueur.
func set_aiming(actif: bool) -> void:
	_vise_cible = 1.0 if actif else 0.0


## Déformation ponctuelle qui revient d'elle-même. C'est l'ingrédient qui
## fait qu'un mouvement brutal se LIT au lieu d'être subi.
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


## Intensité du flash de dégâts.
##
## Calibrée pour un modèle TEXTURÉ. La valeur d'origine (2,6), pensée pour
## des aplats unis, noyait les textures de Kael : sa veste bleue virait au
## violet et ses cheveux à l'orange. Sur une texture, le flash doit
## TEINTER, pas remplacer.
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
	# On dispose désormais d'une VRAIE animation de mort. L'ancienne
	# bascule au sol par tween — le personnage entier pivoté et écrasé —
	# n'était qu'un pis-aller faute de squelette.
	if _anim and _anim.has_animation(A_MORT):
		_clip = A_MORT
		_anim.play(A_MORT, FONDU_MORT)
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rig, "rotation:x", -PI / 2.0, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "scale", Vector3(1.15, 0.55, 1.15), 0.32)
	tw.tween_property(self, "position:y", -0.25, 0.5)


## `speed_ratio` : 0 à l'arrêt, 1 à pleine course.
func update_visual(delta: float, speed_ratio: float) -> void:
	if _rig == null:
		return
	_time += delta

	_suivre_main()

	if _dead:
		return

	if _attack_t > 0.0:
		_attack_t -= delta
		if _attack_t <= 0.0 and state == State.ATTACK:
			state = State.RUN if speed_ratio > SEUIL_COURSE else State.IDLE
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0 and state == State.HIT:
			state = State.RUN if speed_ratio > SEUIL_COURSE else State.IDLE

	# CHOIX DU CLIP. L'hystérésis évite le clignotement entre repos et
	# course quand la vitesse oscille autour d'un seuil unique.
	var a := clampf(speed_ratio, 0.0, 1.0)
	if _court and a < SEUIL_ARRET:
		_court = false
	elif not _court and a > SEUIL_COURSE:
		_court = true

	if _clip_verrouille:
		pass
	elif _court:
		state = State.RUN
		_jouer(A_COURSE_TIR if _vise_cible > 0.5 else A_COURSE)
		# La cadence suit l'allure réelle : sans cela le personnage garde
		# la même foulée à toute vitesse, et ses pieds patinent.
		if _anim:
			_anim.speed_scale = lerpf(CADENCE_MIN, CADENCE_MAX, a)
	else:
		# À L'ARRÊT, la gâchette change la posture : garde si l'on tire,
		# repos sinon. C'est ce qui rendait le bouton de tir sans effet
		# visible quand on ne bougeait pas.
		state = State.ATTACK if _vise_cible > 0.5 else State.IDLE
		_jouer(A_GARDE if _vise_cible > 0.5 else A_REPOS)
		if _anim:
			_anim.speed_scale = 1.0

	# COUP ENCAISSÉ : recul du buste, très bref.
	if _hit_t > 0.0:
		_rig.position.z = (_hit_t / 0.18) * 0.14
	else:
		_rig.position.z = 0.0

	# INCLINAISON — le corps penche dans le sens de la marche et s'incline
	# dans les changements de direction. Sans elle, un personnage glisse à
	# plat, sans poids ni intention. Elle s'ajoute à l'animation plutôt
	# que de la remplacer : l'assiette générale vient de la vitesse, la
	# réaction vive de l'accélération.
	var target_lean := Vector2(
			clampf(_vel.z * 0.10 + _acc.z * 0.07, -0.20, 0.20),
			clampf(_vel.x * 0.13 + _acc.x * 0.09, -0.22, 0.22))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta / 0.09))
	_rig.rotation.x = -_lean.x
	_rig.rotation.z = -_lean.y

	# ÉCRASEMENT ponctuel, réservé aux impacts. La respiration d'antan a
	# disparu : le clip de repos en contient une vraie.
	_squash = _squash.lerp(_squash_target, 1.0 - exp(-delta / 0.055))
	_rig.scale = _squash


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
	_squash = Vector3.ONE
	_squash_target = Vector3.ONE
	_clip = ""
	_court = false
	if _anim:
		_anim.speed_scale = 1.0
		_jouer(A_REPOS, 0.0)
