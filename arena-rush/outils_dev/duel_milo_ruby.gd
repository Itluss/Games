extends Node3D
## COMPARAISON MILO / RUBY — la scène d'étalon de qualité.
##
## POURQUOI ELLE EXISTE. Deux tirs ne se comparent pas de mémoire, et
## surtout pas d'un aperçu à l'autre : entre deux passages, l'œil oublie.
## Ici les deux armes tirent DANS LA MÊME IMAGE, à la caméra de jeu, en
## boucle — Milo trois coups, une pause, Ruby cinq coups, une pause.
##
## DEUX MODES, ET LE SECOND EST CELUI QUI SERT À RÉGLER.
##
##   `--images=N`  boucle libre, N captures régulières. C'est la vue
##                 « à quoi ça ressemble en jouant ».
##   `--film`      pellicule SYNCHRONISÉE SUR LE COUP : une image de
##                 référence sans tir, puis une image par frame juste
##                 après le départ, pour Milo puis pour Ruby.
##
## Le premier mode a produit vingt-six images dont deux seulement
## contenaient un tir : à cadence réelle, un effet de cinquante
## millisecondes passe entre deux échantillons. Échantillonner au hasard
## d'un effet bref, c'est photographier surtout son absence. La pellicule
## règle le problème à la racine en déclenchant la capture sur le coup.
##
## LE FORMAT DE RENDU EST CELUI DU TÉLÉPHONE, doublé. 844×390 est la
## fenêtre réelle ; on rend 1688×780, soit exactement les pixels physiques
## d'un écran à densité 2. Juger un effet en 16/9 de bureau donnerait une
## image plus haute que celle du joueur, donc un effet plus généreux qu'il
## ne l'est vraiment.

## Pixels physiques d'un téléphone 844×390 à densité 2.
const LARGEUR := 1688
const HAUTEUR := 780
## Réglages COPIÉS de `arena_camera.gd`. S'ils y changent, ils doivent
## changer ici : une comparaison « caméra réelle » qui ne l'est plus ment.
const CAM_HAUTEUR := 10.4
const CAM_RECUL := 8.0
const CAM_FOV := 58.0
## Écartement des deux tireurs, en mètres.
const ECART := 3.4
## Distance du mur de réception.
const MUR := 10.0
## Le temps est ralenti : un départ dure cinquante millisecondes, contre
## trois cents par image en rendu logiciel. Voir `apercu_armes.gd`.
##
## LA PELLICULE RALENTIT VINGT-QUATRE FOIS, pas huit : à 1/8 chaque image
## avançait de 37 ms de temps de jeu, soit deux images pour tout l'effet
## de départ. À 1/24 on avance de 12,5 ms par image et la pellicule montre
## la naissance, le pic et l'extinction séparément.
const RALENTI := 1.0 / 8.0
const RALENTI_FILM := 1.0 / 24.0
## Nombre d'images de pellicule par tireur. 16 × 12,5 ms = 200 ms, soit
## largement de quoi couvrir flash, trainée et début d'impact.
const IMAGES_FILM := 16

var _cam: Camera3D
var _tireurs: Array = []
var _tour := 0
var _coups := 0
var _t := 0.0
var _prochain := 0.6
var _dossier := ""
var _images := 0
var _pris := 0
var _t_image := 0.0

## Pellicule.
var _film := false
var _macro := false
var _etape := 0
var _n := 0
var _attente := 0
var _sonde := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--images="):
			_images = int(a.substr(9))
		elif a.begins_with("--dossier="):
			_dossier = a.substr(10)
		elif a == "--film":
			_film = true
		elif a == "--sonde":
			_sonde = true
		elif a == "--macro":
			_macro = true
			_film = true
	Engine.time_scale = RALENTI_FILM if _film else RALENTI
	if _dossier == "":
		_dossier = "user://duel"
	DirAccess.make_dir_recursive_absolute(_dossier)
	get_window().size = Vector2i(LARGEUR, HAUTEUR)

	_decor()
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.far = 140.0
	add_child(_cam)
	if _macro:
		# ─── VUE DE CÔTÉ, COMME LA PLANCHE ──────────────────────────────
		#
		# La planche décrit chaque tir en « séquence visuelle vue de côté »
		# — départ, projectile, trail, impact — et c'est la seule vue où la
		# FORME se lit. À la caméra de jeu, un projectile de dix pixels ne
		# dit ni sa couleur ni son profil : on voit qu'il y a quelque
		# chose, pas quoi. Les deux vues sont donc nécessaires et servent à
		# des questions différentes : la caméra de jeu dit si ça se VOIT,
		# la vue de côté dit si c'est BEAU.
		#
		# On se place à hauteur de canon, légèrement en avant, en suivant
		# l'axe du tir de Milo.
		# LE CADRE COUVRE LE COULOIR, PAS LE PERSONNAGE. Premier réglage :
		# la caméra collée au tireur. On y voyait l'éclair de bouche en
		# gros plan, et RIEN du projectile — il quittait le cadre avant la
		# deuxième image. Or la moitié des reproches portent sur le
		# projectile et sa traînée.
		#
		# À 34° de champ vertical sur un cadre 1688×780, l'ouverture
		# horizontale vaut 66° ; à 3,8 m de l'axe, on embrasse cinq mètres
		# de trajectoire — du canon jusqu'à mi-chemin du mur.
		_cam.fov = 34.0
		_viser_couloir(-ECART * 0.5)
	else:
		_cam.position = Vector3(0, CAM_HAUTEUR, CAM_RECUL)
		_cam.look_at(Vector3(0, 1.0, -3.0), Vector3.UP)

	_tireurs.append(_poser(&"milo", -ECART * 0.5))
	_tireurs.append(_poser(&"ruby", ECART * 0.5))
	if _film:
		print("Duel : pellicule synchronisée sur le coup, %d images par tireur."
				% IMAGES_FILM)
	else:
		print("Duel Milo / Ruby — Milo 3 coups, pause, Ruby 5 coups, pause.")


func _poser(h: StringName, x: float) -> Dictionary:
	var v := CharacterVisual.new()
	add_child(v)
	v.build(Cfg.COL_LOCAL_PLAYER, Cfg.COL_KAEL_ACCENT, 1.9, h)
	v.position = Vector3(x, 0, 0)
	# ORIENTATION : le corps regarde LÀ OÙ PART LA BALLE, sinon on juge un
	# tir qui sort de côté. Le joueur pose `rotation.y = _facing + PI` avec
	# `_facing` mesuré depuis +Z ; tirer vers -Z donne `_facing = PI`, donc
	# un demi-tour complet, donc zéro. La première pellicule a été rendue
	# avec `PI` : le canon pointait à l'opposé du projectile et le départ
	# se déclenchait dans le dos du personnage.
	v.rotation.y = 0.0
	var a := Weapon.new()
	add_child(a)
	var data := Registry.arme_de_heros(h)
	# Comme le joueur : l'identité vient du HÉROS, la mécanique de l'arme.
	a.identite = data.profil if data else null
	a.equip(data)
	v.attach_weapon(a.take_model())
	var fiche := {"visuel": v, "arme": a, "heros": h}
	a.coup_parti.connect(func(canon: int):
		if is_instance_valid(v) and a.data:
			v.recul_de_tir(a.profil_visuel(), canon))
	return fiche


func _decor() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a2016")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Cfg.COL_AMBIANTE_JOUR
	# LES RÉGLAGES SONT CEUX DE L'ARÈNE, À LA VIRGULE PRÈS, et la première
	# pellicule a montré pourquoi ça compte. Avec un ambiant à 0,9 et une
	# exposition à 0,5 — des valeurs inventées pour cette scène —, le sable
	# montait à la limite du blanc. Or les tirs sont ADDITIFS : ajouter de
	# la lumière à une image déjà brûlée n'ajoute rien du tout. Les effets
	# étaient donc invisibles ici alors qu'ils ne le sont pas dans le jeu.
	# Un banc d'étalonnage qui éclaire mieux que le jeu ne mesure rien.
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.glow_intensity = 1.5
	e.glow_bloom = 0.28
	e.glow_hdr_threshold = 1.0
	e.glow_hdr_scale = 2.0
	e.glow_strength = 1.25
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 4.0
	e.tonemap_exposure = 0.45
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.32
	e.adjustment_contrast = 1.06
	env.environment = e
	add_child(env)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-52, -38, 0)
	soleil.light_energy = 1.0
	add_child(soleil)

	var sol := MeshInstance3D.new()
	sol.name = "SolDuel"
	var b := BoxMesh.new()
	b.size = Vector3(40, 0.4, 40)
	sol.mesh = b
	# LE SABLE DE L'ARÈNE, pas une teinte choisie ici. Un fond plus sombre
	# ferait ressortir les tirs sans qu'ils ressortent dans le jeu : c'est
	# exactement le fond clair qui est difficile, donc c'est celui-là qu'il
	# faut affronter.
	sol.material_override = VisualKit.mat(Cfg.COL_SABLE, 0.0, 0.95)
	sol.position = Vector3(0, -0.2, 0)
	add_child(sol)

	var mur := StaticBody3D.new()
	mur.collision_layer = Cfg.LAYER_WORLD
	add_child(mur)
	var forme := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 6, 0.6)
	forme.shape = bs
	forme.position = Vector3(0, 3, -MUR)
	mur.add_child(forme)
	var mm := MeshInstance3D.new()
	mm.name = "MurDuel"
	var mb := BoxMesh.new()
	mb.size = Vector3(20, 6, 0.6)
	mm.mesh = mb
	mm.material_override = VisualKit.mat(Color("8a5f3a"), 0.0, 0.95)
	mm.position = Vector3(0, 3, -MUR)
	add_child(mm)


## Sonde de diagnostic : où sont réellement les projectiles à l'image N.
## Une pellicule où l'on ne voit aucune balle pose deux questions — « pas
## visible » ou « pas là » — et seule la position tranche.
func _sonder(qui: String, n: int) -> void:
	if not _sonde:
		return
	var l := []
	for p in _trouver_projectiles(self):
		l.append("%s v=%s pos=%.2f,%.2f,%.2f" % [
				p.name, p.visible, p.global_position.x,
				p.global_position.y, p.global_position.z])
	print("[%s %02d] %d projectile(s) : %s" % [qui, n, l.size(), ", ".join(l)])


func _trouver_projectiles(n: Node) -> Array:
	var r := []
	for e in n.get_children():
		if e is Projectile:
			r.append(e)
		r.append_array(_trouver_projectiles(e))
	return r


## Place la caméra macro en face du couloir de tir d'abscisse `x`.
## Les deux tireurs n'ont pas le même axe : filmer Ruby depuis l'axe de
## Milo revenait à photographier du sable — c'est ce qu'a donné la
## première pellicule macro.
func _viser_couloir(x: float) -> void:
	_cam.position = Vector3(x + 3.8, 0.95, -2.5)
	_cam.look_at(Vector3(x, 0.74, -2.5), Vector3.UP)


func _capture(nom: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [_dossier, nom])


func _tirer(i: int) -> void:
	var a: Weapon = _tireurs[i]["arme"]
	a.fire(a.muzzle_position(), Vector3.FORWARD, Cfg.Team.PLAYER, 1, true)


## Pellicule : référence à vide, puis une image par frame après le départ.
## Chaque étape est un cran d'un automate simple, pour que l'ordre des
## captures soit lisible d'un coup d'œil.
func _process_film() -> void:
	match _etape:
		0:
			# Laisser le rendu se stabiliser avant la référence.
			_attente += 1
			if _attente >= 4:
				_capture("macro_ref" if _macro else "ref")
				_attente = 0
				_etape = 1
		1:
			_tirer(0)
			_n = 0
			_etape = 2
		2:
			_n += 1
			_sonder("milo", _n)
			_capture("%smilo_%02d" % ["macro_" if _macro else "", _n])
			if _n >= IMAGES_FILM:
				_n = 0
				_etape = 3
		3:
			# Laisser retomber Milo avant de juger Ruby sur fond propre.
			_attente += 1
			if _attente >= 10:
				_attente = 0
				_etape = 4
		4:
			if _macro:
				_viser_couloir(ECART * 0.5)
			_tirer(1)
			_n = 0
			_etape = 5
		5:
			_n += 1
			_sonder("ruby", _n)
			_capture("%sruby_%02d" % ["macro_" if _macro else "", _n])
			if _n >= IMAGES_FILM:
				print("Duel : pellicule dans %s"
						% ProjectSettings.globalize_path(_dossier))
				get_tree().quit(0)


func _process(d: float) -> void:
	for f in _tireurs:
		var v: CharacterVisual = f["visuel"]
		if is_instance_valid(v):
			v.update_visual(d, 0.0)
	if _film:
		_process_film()
		return
	_t += d
	if _images > 0:
		_t_image += d
		if _t_image >= 0.055 and _pris < _images:
			_t_image = 0.0
			_pris += 1
			_capture("duel_%02d" % _pris)
			if _pris >= _images:
				print("Duel : %d images dans %s" % [_pris,
						ProjectSettings.globalize_path(_dossier)])
				get_tree().quit(0)
	if _t < _prochain:
		return
	_t = 0.0
	# Phase 0 : Milo tire trois fois. Phase 1 : pause. Phase 2 : Ruby tire
	# cinq fois. Phase 3 : pause. Puis on recommence.
	var qui := 0 if _tour % 4 == 0 else (1 if _tour % 4 == 2 else -1)
	if qui < 0:
		_prochain = 0.55
		_tour += 1
		return
	var f: Dictionary = _tireurs[qui]
	var a: Weapon = f["arme"]
	a.fire(a.muzzle_position(), Vector3.FORWARD, Cfg.Team.PLAYER, 1, true)
	_coups += 1
	var vise := 3 if qui == 0 else 5
	_prochain = 1.0 / maxf(a.data.fire_rate, 0.1)
	if _coups >= vise:
		_coups = 0
		_tour += 1
		_prochain = 0.15
