extends Node3D
## APERÇU DES SIX ARMES — trois images par héros, à la caméra de jeu.
##
## POURQUOI À LA CAMÉRA DE JEU ET NULLE PART AILLEURS. La consigne est
## explicite : « ne juge pas la lisibilité en gros plan ». Un départ jugé
## à deux mètres paraît toujours superbe et toujours trop gros ; c'est à
## dix mètres de haut, dans le cadre réel, qu'on voit s'il dit quelque
## chose ou s'il mange le personnage.
##
## Trois instants, parce que la signature se joue en trois temps :
##   DÉPART   le flash au canon — la première demi-seconde ;
##   VOL      le projectile et sa traînée — ce qu'on voit venir ;
##   IMPACT   la marque sur le mur — ce qui reste quand on a raté.

const LARGEUR := 1280
const HAUTEUR := 720
## Réglages COPIÉS de `arena_camera.gd`. S'ils y changent, ils doivent
## changer ici : un aperçu « caméra réelle » qui ne l'est plus mentirait.
const CAM_HAUTEUR := 10.4
const CAM_RECUL := 8.0
const CAM_FOV := 58.0

const HEROS: Array[StringName] = [&"milo", &"poppy", &"bruno", &"nox",
		&"ruby", &"gus"]
## Le mur est à cette distance : assez loin pour voir voler, assez près
## pour que l'impact tienne dans le même cadre que le départ.
const MUR := 9.0
## Facteur de ralentissement de l'horloge. Voir `_ready`.
const RALENTI := 1.0 / 12.0

var _dossier := ""
var _cam: Camera3D
var _arme: Weapon
var _visuel: CharacterVisual
var _i := 0
var _phase := 0
## Temps de JEU écoulé depuis le tir, en secondes.
##
## ON N'ATTEND PAS UN NOMBRE D'IMAGES, et c'est le correctif qui a rendu
## les projectiles visibles. Une image de ce banc dure entre cinquante et
## trois cents millisecondes selon la scène : compter les images revenait
## à attendre une durée inconnue, et le projectile était photographié
## tantôt collé au canon, tantôt déjà dans le mur. Le temps de jeu, lui,
## ne dépend ni de la machine ni du ralenti.
var _t := 0.0
var _prochain := 0.0


func _ready() -> void:
	_dossier = "user://apercu_armes"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dossier="):
			_dossier = a.substr(10)
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=%s" % ProjectSettings.globalize_path(_dossier))
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	# ─── LE TEMPS EST RALENTI, ET C'EST INDISPENSABLE ──────────────────
	#
	# Les départs durent de cinquante à cent millisecondes. Le rendu de ce
	# banc est logiciel : environ trois images par seconde, soit trois cents
	# millisecondes par image. Un flash naît et meurt ENTRE DEUX IMAGES, et
	# l'aperçu ne montrait que le projectile — sans qu'aucune erreur ne
	# soit signalée nulle part, ce qui est le pire des symptômes.
	#
	# On ralentit donc l'horloge d'un facteur douze : chaque image rendue
	# n'avance plus que de vingt-cinq millisecondes de jeu, et un flash de
	# soixante millisecondes tient sur deux ou trois images. Rien de ce qui
	# est mesuré ne change — seulement l'échantillonnage.
	Engine.time_scale = RALENTI

	_batir_decor()
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.far = 140.0
	add_child(_cam)
	_cam.position = Vector3(0, CAM_HAUTEUR, CAM_RECUL)
	_cam.look_at(Vector3(0, 1.0, -2.5), Vector3.UP)

	_arme = Weapon.new()
	add_child(_arme)
	_charger(0)


func _batir_decor() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a2016")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("6b5a44")
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-52, -34, 0)
	soleil.light_energy = 1.1
	add_child(soleil)

	var sol := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(40, 0.4, 40)
	sol.mesh = b
	sol.material_override = VisualKit.mat(Color("6b5643"), 0.0, 0.95)
	sol.position = Vector3(0, -0.2, 0)
	add_child(sol)

	# LE MUR SERT DE CIBLE, et il est SOMBRE ET NEUTRE exprès : un fond
	# coloré teinterait les impacts et fausserait la comparaison entre
	# deux armes dont on veut justement juger la forme.
	var mur := StaticBody3D.new()
	mur.collision_layer = Cfg.LAYER_WORLD
	add_child(mur)
	var forme := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(16, 6, 0.6)
	forme.shape = bs
	forme.position = Vector3(0, 3, -MUR)
	mur.add_child(forme)
	var mm := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(16, 6, 0.6)
	mm.mesh = mb
	mm.material_override = VisualKit.mat(Color("3b3128"), 0.0, 0.95)
	mm.position = Vector3(0, 3, -MUR)
	add_child(mm)


func _charger(i: int) -> void:
	# ─── ON FAIT LE MÉNAGE ENTRE DEUX HÉROS ────────────────────────────
	#
	# Sans cela, le projectile de Bruno — lent, et rendu douze fois plus
	# lent encore par le ralenti — traversait encore l'image pendant qu'on
	# photographiait Nox. La planche montrait un personnage vert tirant des
	# boules rouges, et j'ai d'abord cru à un défaut de recyclage des
	# projectiles. Ce n'en était pas un : c'était le décor qui n'était pas
	# vide.
	_vider(self)
	if _visuel and is_instance_valid(_visuel):
		_visuel.queue_free()
	var h := HEROS[i]
	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Cfg.COL_LOCAL_PLAYER, Cfg.COL_KAEL_ACCENT, 1.9, h)
	_visuel.position = Vector3(0, 0, 0)
	_visuel.rotation.y = PI
	var data := Registry.arme_de_heros(h)
	_arme.equip(data)
	_visuel.attach_weapon(_arme.take_model())
	if not _arme.coup_parti.is_connected(_sur_coup):
		_arme.coup_parti.connect(_sur_coup)
	_phase = 0
	_t = 0.0
	_prochain = 0.25


## Retire tout ce qui vole ou brille encore : projectiles et effets.
func _vider(n: Node) -> void:
	for c in n.get_children():
		if c is Projectile:
			Pool.release(c)
		elif c is GPUParticles3D or c is OmniLight3D \
				or String(c.name).begins_with("EtoileFx"):
			# LE MÉNAGE NE DOIT EMPORTER QUE LES EFFETS. La première
			# version reconnaissait les nœuds à leur nom généré par Godot
			# — or le sol et le mur du banc n'étaient pas nommés non plus,
			# et elle les effaçait. La planche est sortie sur fond noir, et
			# j'ai cru un instant à un défaut d'éclairage.
			c.queue_free()
		else:
			_vider(c)


func _sur_coup(canon: int) -> void:
	if _visuel and is_instance_valid(_visuel) and _arme.data:
		_visuel.recul_de_tir(_arme.data.profil, canon)


func _process(d: float) -> void:
	if _i >= HEROS.size():
		return
	# ─── LE VISUEL DOIT ÊTRE MIS À JOUR, MÊME DANS UN BANC ─────────────
	#
	# C'est `update_visual` qui recale le support d'arme sur l'os de la
	# main, chaque trame. Sans cet appel, le support reste à l'origine et
	# `muzzle_position()` rend un point à un centimètre du sol. J'ai cru
	# une bonne demi-heure avoir trouvé un défaut du jeu — les projectiles
	# seraient partis des pieds — avant de voir que le jeu, lui, appelle
	# bien cette fonction à chaque trame depuis `player.gd`. Le défaut
	# était dans le banc.
	if _visuel and is_instance_valid(_visuel):
		_visuel.update_visual(d, 0.0)
	_t += d
	if _t < _prochain:
		return
	var h := HEROS[_i]
	var vol := MUR / maxf(_arme.data.projectile_speed, 1.0)
	match _phase:
		0:
			# ON TIRE DU VRAI CANON, pas d'un point choisi à la main. Un
			# aperçu qui place le départ ailleurs que le jeu ne dit rien
			# de ce que le joueur verra — et c'est le seul but de cet outil.
			_arme.fire(_arme.muzzle_position(), Vector3.FORWARD,
					Cfg.Team.PLAYER, 1, true)
			_t = 0.0
			_prochain = 0.035
			_phase = 1
		1:
			_capturer("%s_1_depart" % h)
			_prochain = vol * 0.5
			_phase = 2
		2:
			_capturer("%s_2_vol" % h)
			_prochain = vol + 0.04
			_phase = 3
		3:
			_capturer("%s_3_impact" % h)
			_prochain = vol + 0.6
			_phase = 4
		_:
			_i += 1
			if _i < HEROS.size():
				_charger(_i)
			else:
				print("Aperçu des armes : %d héros, 3 images chacun."
						% HEROS.size())
				get_tree().quit(0)


func _capturer(nom: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var chemin := "%s/arme_%s.png" % [_dossier, nom]
	img.save_png(chemin)
	print("→ %s" % ProjectSettings.globalize_path(chemin))
