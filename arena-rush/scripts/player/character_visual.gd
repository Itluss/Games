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
## Identifiant du héros porté par ce visuel. Vide = Kael.
var _heros: StringName = &""

## Chemin du modèle à monter. Un héros inconnu ou absent retombe sur Kael
## plutôt que de ne rien afficher : mieux vaut le mauvais personnage qu'un
## joueur invisible.
func _chemin_modele() -> String:
	if _heros != &"":
		# LES MASCOTTES DU ROSTER « 30 PREMIERS HÉROS » PRIMENT : c'est le
		# nouveau visage du jeu. Les anciens hero_* restent en repli, le
		# temps que le roster se remplisse asset par asset, après contrôle.
		var m := "res://assets/models/mascotte_%s.glb" % _heros
		if ResourceLoader.exists(m):
			return m
		var c := "res://assets/models/hero_%s.glb" % _heros
		if ResourceLoader.exists(c):
			return c
	return MODELE
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
## Os du HAUT DU CORPS, sur lesquels la posture de tir est plaquée.
##
## Le bassin et les jambes en sont EXCLUS : ce sont eux qui doivent
## rester au repos quand on tire sans bouger, faute de quoi le
## personnage courrait sur place.
const HAUT_DU_CORPS := [
	"Spine", "Spine01", "Spine02", "neck", "Head", "head_end", "headfront",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
## Durée du fondu du haut du corps vers la posture de tir.
const FONDU_BUSTE := 0.14
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
## Nœud INTERCALAIRE qui porte la démarche.
##
## POURQUOI UN NŒUD DE PLUS PLUTÔT QUE POSER SUR `_rig`. `_rig` porte
## déjà l'orientation du corps, le support d'arme et le gabarit de repli,
## et son `rotation.y` est écrit par le joueur. Y ajouter le tangage et le
## roulis de la marche rendrait impossible de régler l'un sans casser
## l'autre — et une remise à zéro faite ailleurs effacerait la démarche
## sans qu'on comprenne pourquoi. Le nœud de démarche s'insère AU-DESSUS :
## il ne touche qu'à ce qui lui appartient.
## ─── ÉTAT DU RECUL DE TIR ──────────────────────────────────────────────
##
## Quatre nombres, pas un clip d'animation. Un clip par héros aurait coûté
## six exports Meshy et n'aurait pas pu se mêler à l'inclinaison ni au coup
## encaissé — or ces trois réactions arrivent souvent ensemble.
var _recul_t: float = 0.0
var _recul_duree: float = 0.15
var _recul_ampl: float = 0.05
var _recul_type: String = "sec"
var _recul_canon: int = 0

var _demarche: Node3D
var _loco: Locomotion
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
var _arbre: AnimationTree = null
var _n_base: AnimationNodeAnimation = null
var _melange: float = 0.0
## Posture logique en cours. Avec un AnimationTree, `current_animation`
## de l'AnimationPlayer ne veut plus rien dire : c'est cette valeur qui
## fait foi, et que les tests observent.
var _posture: String = "repos"
## Verrou du banc de rendu : empêche la machine à états de rechoisir.
var _clip_verrouille: bool = false
var _court: bool = false
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _dead: bool = false


## `heros` choisit le modèle et le profil de démarche. Vide = Kael, le
## comportement d'avant : aucun appelant existant n'a à changer.
func build(color: Color, accent: Color, height: float = 1.7,
		heros: StringName = &"") -> void:
	_heros = heros
	_demarche = Node3D.new()
	_demarche.name = "Demarche"
	add_child(_demarche)

	_loco = Locomotion.new()
	_loco.name = "Locomotion"
	_loco.profil = ProfilDemarche.profil(heros)
	add_child(_loco)

	_rig = Node3D.new()
	_rig.name = "Rig"
	_demarche.add_child(_rig)
	# Repli si l'asset manque : le jeu doit rester lançable sur une
	# branche où le modèle n'a pas encore été déposé.
	if ResourceLoader.exists(_chemin_modele()):
		_monter_modele(height)
	else:
		push_warning("Modèle %s absent — repli sur le gabarit primitif." % MODELE)
		_monter_primitives(color, accent, height)


# --- MONTAGE DU MODÈLE ANIMÉ --------------------------------------------

func _monter_modele(height: float) -> void:
	var scene: PackedScene = load(_chemin_modele())
	_modele = scene.instantiate()
	# LA HAUTEUR NATIVE SE MESURE, elle ne se suppose pas. Kael arrive à
	# 1,9 ; les six héros sortent de Meshy à des tailles quelconques, et
	# leur imposer le facteur de Kael les rendrait tous faux.
	_facteur = height / maxf(_hauteur_native(), 0.0001)
	_modele.scale = Vector3.ONE * _facteur
	_modele.rotation.y = MODELE_DEMI_TOUR
	_rig.add_child(_modele)

	_anim = _trouver(_modele, "AnimationPlayer") as AnimationPlayer
	_normaliser_clips()
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
		_monter_arbre()

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
	# UN MODÈLE SANS OS DOIT QUAND MÊME PORTER SON ARME.
	#
	# Les six héros sortent d'un image-to-3d : un seul nœud, aucun
	# squelette. Sans repli, `_mount` restait nul et l'arme n'était
	# jamais greffée — vérifié par la barrière des commandes, qui a
	# signalé « un point d'accroche existe : faux » dès le branchement.
	#
	# Le support est alors posé À LA MAIN, en fraction de la taille du
	# personnage : hauteur d'épaule, écarté du côté de la main droite,
	# légèrement en avant. C'est approximatif et c'est assumé — un
	# placement approximatif rend l'arme visible et le jeu jouable, un
	# support absent ne rend rien du tout. Le jour où les squelettes
	# arrivent, la branche du dessus reprend la main sans rien changer
	# ici.
	if _squelette == null:
		_mount = Node3D.new()
		_mount.name = "WeaponMount"
		_mount.position = Vector3(0.26, height * 0.60, 0.20)
		_rig.add_child(_mount)
	elif _squelette:
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
	_posture = nom
	_anim.speed_scale = 1.0
	if _arbre:
		_n_base.animation = nom
		_melange = 0.0
		_appliquer_melange(0.0)
	else:
		_anim.play(nom, 0.0)


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


## Monte l'arbre d'animation : LOCOMOTION + POSTURE DE TIR SUPERPOSÉE.
##
## POURQUOI UN ARBRE plutôt qu'un simple clip à la fois.
##
## La posture de tir jugée bonne est celle de « Run_and_Shoot » — bras et
## buste d'un personnage qui tire. Mais ce clip contient AUSSI une
## foulée : le jouer à l'arrêt ferait courir sur place.
##
## On superpose donc les deux étages du corps : le HAUT vient du clip de
## tir, le BAS de la locomotion réelle — repos si l'on ne bouge pas,
## course si l'on court. Le personnage garde ainsi la même attitude de
## tir, qu'il soit lancé ou immobile, ce qui est exactement ce qu'on
## attend d'un jeu de tir.
##
## Le filtre porte sur les os, et le bassin en est EXCLU : c'est lui qui
## porte le rebond de la foulée, et l'inclure ramènerait le sautillement
## qu'on cherche justement à éviter.
func _monter_arbre() -> void:
	if _anim == null or not _anim.has_animation(A_COURSE_TIR):
		_jouer(A_REPOS, 0.0)
		return

	var melange := AnimationNodeBlend2.new()
	melange.filter_enabled = true
	# Les chemins de piste sont ceux du clip lui-même : on les relève
	# plutôt que de les reconstruire, pour ne pas dépendre du nom exact
	# du nœud Skeleton3D dans le modèle importé.
	var reference := _anim.get_animation(A_COURSE_TIR)
	for t in reference.get_track_count():
		var chemin := reference.track_get_path(t)
		var os := str(chemin).get_slice(":", 1)
		if os in HAUT_DU_CORPS:
			melange.set_filter_path(chemin, true)

	_n_base = AnimationNodeAnimation.new()
	_n_base.animation = A_REPOS
	var haut := AnimationNodeAnimation.new()
	haut.animation = A_COURSE_TIR

	var racine := AnimationNodeBlendTree.new()
	racine.add_node("base", _n_base)
	racine.add_node("haut", haut)
	racine.add_node("melange", melange)
	racine.connect_node("melange", 0, "base")
	racine.connect_node("melange", 1, "haut")
	racine.connect_node("output", 0, "melange")

	_arbre = AnimationTree.new()
	_arbre.name = "ArbreAnim"
	_modele.add_child(_arbre)
	_arbre.anim_player = _arbre.get_path_to(_anim)
	_arbre.tree_root = racine
	_arbre.active = true
	_appliquer_melange(0.0)


func _appliquer_melange(valeur: float) -> void:
	if _arbre:
		_arbre.set("parameters/melange/blend_amount", valeur)


## Posture logique en cours — « repos », « course », « course_tir »,
## « tir_debout » ou « mort ». C'est l'observable des tests : avec un
## AnimationTree, `AnimationPlayer.current_animation` est vide.
func posture() -> String:
	return _posture


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


## DÉCLENCHE LA RÉACTION DU CORPS AU TIR.
##
## Appelée à CHAQUE coup, y compris les coups d'une rafale : c'est ce qui
## fait que la rafale de Poppy secoue trois fois et non une.
func recul_de_tir(profil: ProfilTir, canon: int) -> void:
	if profil == null or _dead:
		return
	_recul_type = profil.recul_corps
	_recul_ampl = profil.recul_amplitude
	_recul_duree = maxf(profil.recul_duree, 0.02)
	_recul_canon = canon
	_recul_t = 1.0


## Place l'arme dans la main : POSITION de l'os, ORIENTATION du corps.
##
## DEUX DÉFAUTS DISTINCTS, corrigés ici, et il a fallu les mesurer pour
## les séparer.
##
## 1. L'ÉCHELLE. Le rig Meshy est exprimé en centimètres — la hanche est
##    à y=93,9 pour un maillage haut de 1,9 — et l'armature porte donc une
##    échelle voisine de 0,01. Tout ce qu'on greffe sous un
##    BoneAttachment3D en hérite : l'arme était rendue à SEPT MILLIMÈTRES,
##    donc invisible. Et la compenser une fois ne suffit pas, les clips
##    animant aussi la taille des os.
##
## 2. L'ORIENTATION. Reprendre les axes de l'os de la main donnait un
##    canon à 150,6° de l'avant du personnage : l'arme pointait vers
##    l'arrière. Les axes d'un os n'ont aucune raison d'être alignés sur
##    le corps — celui de la main suit l'avant-bras.
##
## On ne retient donc de l'os que sa POSITION, et l'on prend
## l'orientation du personnage. C'est d'ailleurs la seule cohérente avec
## le jeu : les projectiles partent dans l'axe du personnage, et une arme
## qui viserait ailleurs mentirait sur la trajectoire.
##
## Le prix à payer est que l'arme ne pivote plus avec le poignet pendant
## l'animation. Sur une vue de dessus, personne ne le remarquera ; une
## arme qui tire de travers, si.
func _suivre_main() -> void:
	if _mount == null or _attache == null or not _attache.is_inside_tree():
		return
	if not _mount.is_inside_tree():
		return
	_mount.global_position = _attache.global_position
	# Le support vit sous `_rig`, dont l'orientation est celle du corps :
	# une base identité suffit donc à aligner le canon sur l'avant.
	_mount.rotation = Vector3.ZERO
	_mount.scale = Vector3.ONE * _facteur


## Vitesse et accélération dans le repère du personnage, normalisées.
## Vitesse RÉELLE en m/s, non normalisée. `set_motion` reçoit une valeur
## locale et divisée par la vitesse de pointe — utile au penché, inutile à
## la cadence, qui a besoin de mètres par seconde pour cadencer les appuis
## sur la distance parcourue.
var _vel_monde: Vector3 = Vector3.ZERO

func set_world_velocity(v: Vector3) -> void:
	_vel_monde = Vector3(v.x, 0.0, v.z)


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
	if _arbre and _anim and _anim.has_animation(A_MORT):
		# Avec un arbre actif, `AnimationPlayer.play()` est ignoré : c'est
		# le nœud de base qu'il faut changer.
		_posture = A_MORT
		_n_base.animation = A_MORT
		_melange = 0.0
		_appliquer_melange(0.0)
		_anim.speed_scale = 1.0
		return
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
## Hauteur réelle du modèle monté, en unités du fichier.
## LES NOMS DE MESHY NE SONT PAS LES NÔTRES.
##
## L'auto-riggeur livre ses clips sous les étiquettes de sa bibliothèque —
## « Idle », « RunFast » — là où tout le jeu demande « repos » et
## « course ». Kael avait été renommé à la fusion ; les six héros non,
## parce que leurs noms sources diffèrent d'un fichier à l'autre et que le
## renommage a glissé sans bruit.
##
## On traduit donc À L'ARRIVÉE plutôt qu'à la génération. C'est le bon
## endroit : la correspondance vit là où les noms sont utilisés, elle
## survit à une regénération, et un clip inconnu n'empêche rien — il reste
## simplement inutilisé au lieu de faire disparaître le personnage.
const TRADUCTION_CLIPS := {
	"Idle": A_REPOS, "idle": A_REPOS,
	"RunFast": A_COURSE, "Run": A_COURSE, "run": A_COURSE,
	"Walk": A_COURSE, "walk": A_COURSE,
}

func _normaliser_clips() -> void:
	if _anim == null:
		return
	var bib := _anim.get_animation_library("")
	if bib == null:
		return
	for source in TRADUCTION_CLIPS:
		var cible: String = TRADUCTION_CLIPS[source]
		if bib.has_animation(source) and not bib.has_animation(cible):
			bib.add_animation(cible, bib.get_animation(source))


func _hauteur_native() -> float:
	if _heros == &"":
		return MODELE_HAUTEUR
	# ─── NE JAMAIS MESURER UN MAILLAGE PEAUFINÉ ────────────────────────
	#
	# `get_aabb()` d'un MeshInstance3D peaufiné à un squelette rend la
	# boîte de sa POSE DE LIAISON, exprimée dans le repère de l'armature
	# — laquelle est en centimètres chez Meshy. Mesuré : Kael comme Milo
	# y répondent 0,02, quand ils font 1,9 m à l'écran. Diviser par 0,02
	# au lieu de 1,9 donnait un facteur QUATRE-VINGT-CINQ FOIS trop grand.
	#
	# Le défaut est resté invisible tant que les héros n'avaient pas d'os :
	# Kael passait par le raccourci du dessus, et les six étaient des blocs
	# statiques dont la boîte est juste. C'est le riggage qui l'a réveillé,
	# et c'est la barrière de l'enroulement qui l'a signalé — son témoin ne
	# touchait plus, et soixante-quatre projectiles partaient à l'autre
	# bout du monde, tirés par un personnage géant.
	#
	# LA RÈGLE : on ne mesure QUE ce dont la taille est inconnue. Un modèle
	# riggé sort de cette chaîne, donc de sa convention — 1,9 m. Un
	# maillage statique arrive à une échelle arbitraire et doit être
	# mesuré.
	if _trouver(_modele, "Skeleton3D") != null:
		return MODELE_HAUTEUR
	var boites: Array[AABB] = []
	_boites(_modele, Transform3D.IDENTITY, boites)
	if boites.is_empty():
		return MODELE_HAUTEUR
	var t := boites[0]
	for i in range(1, boites.size()):
		t = t.merge(boites[i])
	return t.size.y


func _boites(n: Node, t: Transform3D, out: Array[AABB]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(t * mi.get_aabb())
	for e in n.get_children():
		var s2 := t
		var e3 := e as Node3D
		if e3 != null:
			s2 = t * e3.transform
		_boites(e, s2, out)


## APPLIQUE LA DÉMARCHE. Rien ici ne touche au corps physique : le
## personnage reste exactement là où le gameplay l'a mis, seule son
## apparence bouge. C'est ce qui rend la couche inoffensive pour la
## collision, la visée et le réseau.
func _appliquer_demarche(delta: float) -> void:
	if _demarche == null or _loco == null or _dead:
		return
	_loco.set_velocity(_vel_monde)
	_loco.avancer(delta)
	var inc := _loco.inclinaison()
	_demarche.position = Vector3(_loco.derive_laterale(), _loco.hauteur(), 0.0)
	_demarche.rotation = Vector3(inc.x, 0.0, inc.z)


func update_visual(delta: float, speed_ratio: float) -> void:
	if _rig == null:
		return
	_time += delta

	_appliquer_demarche(delta)
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

	var tire := _vise_cible > 0.5
	if _clip_verrouille:
		pass
	elif _arbre:
		# LOCOMOTION en bas, POSTURE DE TIR en haut.
		#
		# En courant, la locomotion est déjà le clip de tir : le corps
		# entier est cohérent, et la superposition n'a rien à ajouter. À
		# l'arrêt, on garde les jambes au repos et l'on plaque le buste du
		# tir par-dessus — c'est ce qui donne la MÊME attitude debout
		# qu'en course, sans courir sur place.
		if _court:
			state = State.RUN
			_n_base.animation = A_COURSE_TIR if tire else A_COURSE
			_posture = A_COURSE_TIR if tire else A_COURSE
			_melange = lerpf(_melange, 0.0, 1.0 - exp(-delta / FONDU_BUSTE))
			_anim.speed_scale = lerpf(CADENCE_MIN, CADENCE_MAX, a)
		else:
			state = State.ATTACK if tire else State.IDLE
			_n_base.animation = A_REPOS
			_posture = "tir_debout" if tire else A_REPOS
			_melange = lerpf(_melange, 1.0 if tire else 0.0,
					1.0 - exp(-delta / FONDU_BUSTE))
			_anim.speed_scale = 1.0
		_appliquer_melange(_melange)
	elif _anim == null:
		# ─── AUCUNE ANIMATION : LA POSTURE RESTE UNE INFORMATION ────────
		#
		# `_posture` est une valeur LOGIQUE — l'intention du personnage —
		# et non le nom du clip en cours. Un modèle sans squelette ne peut
		# rien jouer, mais il tire, il court et il vise exactement comme
		# les autres : le reste du jeu, et les bancs, ont le droit de le
		# savoir. La laisser bloquée sur « repos » revenait à mentir sur
		# l'état du joueur parce qu'il manque un fichier.
		if _court:
			state = State.RUN
			_posture = A_COURSE_TIR if tire else A_COURSE
		else:
			state = State.ATTACK if tire else State.IDLE
			_posture = "tir_debout" if tire else A_REPOS
	elif _court:
		state = State.RUN
		_jouer(A_COURSE_TIR if tire else A_COURSE)
		# LA POSTURE EST UNE INTENTION, PAS UN NOM DE CLIP.
		#
		# Ce chemin sert aux modèles qui n'ont PAS de clip de tir en
		# course — c'est le cas des six héros, que l'auto-riggeur livre
		# avec un repos et une course, rien de plus. `_jouer` retombe
		# alors silencieusement sur la course simple, ce qui est le bon
		# comportement visuel ; mais laisser `_posture` suivre le clip
		# revenait à déclarer « ce joueur ne tire pas » parce qu'il lui
		# manque un fichier. Le reste du jeu, et les bancs, lisent cette
		# valeur pour savoir ce que le personnage FAIT.
		_posture = A_COURSE_TIR if tire else A_COURSE
		if _anim:
			_anim.speed_scale = lerpf(CADENCE_MIN, CADENCE_MAX, a)
	else:
		state = State.ATTACK if tire else State.IDLE
		_jouer(A_GARDE if tire else A_REPOS)
		_posture = "tir_debout" if tire else A_REPOS
		if _anim:
			_anim.speed_scale = 1.0

	# COUP ENCAISSÉ : recul du buste, très bref.
	var recul_z := 0.0
	var recul_x := 0.0
	var recul_y := 0.0
	var recul_roul := 0.0
	if _hit_t > 0.0:
		recul_z += (_hit_t / 0.18) * 0.14

	# ─── RECUL DE TIR — LA MOITIÉ CORPORELLE DE L'IDENTITÉ ──────────────
	#
	# La consigne interdit « la même animation sur les six personnages avec
	# seulement une vitesse différente ». Ce n'est donc pas un clip : c'est
	# une réaction PROCÉDURALE, différente en NATURE d'un héros à l'autre.
	# Milo encaisse dans le bras et le buste ne bouge presque pas ; Bruno
	# part en arrière et revient lentement ; Gus tourne l'épaule qui tire.
	#
	# Elle s'AJOUTE à l'inclinaison et au coup encaissé au lieu de les
	# remplacer : un personnage touché pendant qu'il tire doit montrer les
	# deux.
	if _recul_t > 0.0:
		_recul_t = maxf(_recul_t - delta / maxf(_recul_duree, 0.01), 0.0)
		var r := _recul_t
		match _recul_type:
			"lourd":
				# Poppy : l'arme est trop grosse pour elle. Le buste part
				# franchement et revient d'un coup.
				recul_z += r * _recul_ampl * 3.4
				recul_x += r * 0.13
			"massif":
				# Bruno : tout le corps encaisse, et le retour traîne —
				# c'est la lenteur du retour qui dit le poids.
				recul_z += r * r * _recul_ampl * 3.0
				recul_x += r * r * 0.18
			"minimal":
				# Nox : presque rien. Il faut regarder pour le voir.
				recul_z += r * _recul_ampl * 1.6
				recul_x += r * 0.02
			"vif":
				# Ruby : un contrecoup qui rebondit, jamais un recul lourd.
				# Le sinus lui donne son petit sursaut de retour.
				recul_z += sin(r * PI) * _recul_ampl * 2.6
				recul_x += r * 0.05
				recul_roul += sin(r * PI * 2.0) * 0.05
			"alterne":
				# Gus : l'épaule qui tire recule, l'autre reste. C'est cette
				# torsion qui fait le balancement à deux temps, et elle est
				# lisible même sans voir les revolvers.
				recul_z += r * _recul_ampl * 2.0
				recul_y += r * (0.13 if _recul_canon == 0 else -0.13)
				recul_roul += r * (-0.06 if _recul_canon == 0 else 0.06)
			_:
				# Milo, et le défaut : sec, contrôlé, retour immédiat.
				recul_z += r * _recul_ampl * 2.2
				recul_x += r * 0.05
	_rig.position.z = recul_z

	# INCLINAISON — le corps penche dans le sens de la marche et s'incline
	# dans les changements de direction. Sans elle, un personnage glisse à
	# plat, sans poids ni intention. Elle s'ajoute à l'animation plutôt
	# que de la remplacer : l'assiette générale vient de la vitesse, la
	# réaction vive de l'accélération.
	var target_lean := Vector2(
			clampf(_vel.z * 0.10 + _acc.z * 0.07, -0.20, 0.20),
			clampf(_vel.x * 0.13 + _acc.x * 0.09, -0.22, 0.22))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta / 0.09))
	_rig.rotation.x = -_lean.x + recul_x
	_rig.rotation.z = -_lean.y + recul_roul
	_rig.rotation.y = recul_y

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
	_melange = 0.0
	_posture = A_REPOS
	if _anim:
		_anim.speed_scale = 1.0
	if _arbre:
		_n_base.animation = A_REPOS
		_appliquer_melange(0.0)
	elif _anim:
		_jouer(A_REPOS, 0.0)
