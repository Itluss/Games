extends Node
## SONDE DE PARTIE EN PIXELS — outil de développement, hors jeu.
##
## POURQUOI UNE QUATRIÈME. Les trois précédentes ont chacune écarté une
## piste sans reproduire le symptôme signalé : un écran ENTIÈREMENT violet.
##   • sonde_camera  — aucun trou dans la carte ;
##   • sonde_session — la caméra décroche 0,2 s après une réapparition ;
##   • sonde_ecran   — même aux positions que les rayons disent « bouchées
##                     à 100 % », l'image rendue n'est plate qu'à 56 %.
##
## Cette dernière mesure est la plus instructive : une paroi de roche vue de
## près N'EST PAS un aplat, elle a des facettes, une ombre, un dégradé. Le
## symptôme vient donc d'autre chose, et rien de ce qu'on peut poser à la
## main ne le déclenche.
##
## On laisse donc jouer une VRAIE partie — le joueur local reste immobile,
## les bots et les mobs le tuent, il réapparaît — et on lit chaque image.
## Aucune position n'est forcée : c'est le jeu qui choisit ce qu'il montre.
## La pire image est enregistrée en PNG : une capture vaut mieux qu'un
## chiffre quand il faudra comprendre ce qu'on regarde.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_flash.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 480
const HAUTEUR := 270
## Durée observée, en secondes de jeu.
const DUREE := 70.0
const SEUIL := 0.06
## Au-delà, l'image ne montre plus rien d'autre qu'un aplat.
const VIDE := 0.9
## En dessous de cette luminance moyenne, l'image est trop sombre pour
## qu'on y distingue quoi que ce soit. « L'écran ne restitue plus rien »
## peut aussi vouloir dire cela : pas un aplat, une image éteinte.
const NOIR := 0.13

var _t := 0.0
var _images := 0
var _vides := 0
var _pire := 0.0
var _pire_teinte := Color.BLACK
var _pire_note := ""
var _pire_image: Image = null
var _morts := 0
## Luminance moyenne la plus basse rencontrée, et son image.
var _noir := 1.0
var _noir_note := ""
var _noir_image: Image = null
var _sombres := 0
var _joueur: Node3D
var _prete := false

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id():
			_joueur = n
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	if _joueur.has_signal(&"died"):
		_joueur.connect(&"died", func(): _morts += 1)
	_prete = true
	RenderingServer.frame_post_draw.connect(_analyser)


func _process(delta: float) -> void:
	if _prete:
		_t += delta


func _analyser() -> void:
	if not _prete:
		return
	if _t > DUREE:
		_conclure()
		return
	var img := get_viewport().get_texture().get_image()
	var mesure := _mesurer(img)
	var plat: float = mesure["plat"]
	_images += 1
	var cam := get_viewport().get_camera_3d()
	var note := "t=%.1f s · joueur %s · caméra %s · morts %d" % [
			_t, _bref(_joueur.global_position),
			_bref(cam.global_position) if cam else "?", _morts]
	if plat > _pire:
		_pire = plat
		_pire_teinte = mesure["teinte"]
		_pire_note = note
		_pire_image = img
	if plat > VIDE:
		_vides += 1
		print("      ! %.0f %% d'aplat — %s (teinte %s)"
				% [plat * 100.0, note, (mesure["teinte"] as Color).to_html(false)])
	var lum: float = mesure["lum"]
	if lum < _noir:
		_noir = lum
		_noir_note = note
		_noir_image = img
	if lum < NOIR:
		_sombres += 1


func _bref(v: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [v.x, v.y, v.z]


func _mesurer(img: Image) -> Dictionary:
	var somme := Color(0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			somme += img.get_pixel(x, y)
			n += 1
	var moyenne := Color(somme.r / n, somme.g / n, somme.b / n)
	var proches := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if absf(c.r - moyenne.r) + absf(c.g - moyenne.g) \
					+ absf(c.b - moyenne.b) < SEUIL * 3.0:
				proches += 1
	# Luminance perçue, pas moyenne des canaux : l'œil ne pèse pas le bleu
	# comme le vert, et une image « violette » peut être objectivement
	# claire en bleu tout en paraissant éteinte.
	var lum := 0.2126 * moyenne.r + 0.7152 * moyenne.g + 0.0722 * moyenne.b
	return {"plat": float(proches) / float(n), "teinte": moyenne, "lum": lum}


func _conclure() -> void:
	_prete = false
	var dossier := ProjectSettings.globalize_path("user://sonde")
	DirAccess.make_dir_recursive_absolute(dossier)
	if _pire_image:
		_pire_image.save_png("%s/pire.png" % dossier)
	if _noir_image:
		_noir_image.save_png("%s/plus_sombre.png" % dossier)
	print("=== SONDE DE PARTIE (%.0f s, %d images, %d morts) ==="
			% [_t, _images, _morts])
	print("  images plates (> %.0f %%) : %d" % [VIDE * 100.0, _vides])
	print("  pire image : %.0f %% d'aplat — teinte %s"
			% [_pire * 100.0, _pire_teinte.to_html(false)])
	print("      %s" % _pire_note)
	print("  images trop sombres (luminance < %.2f) : %d sur %d"
			% [NOIR, _sombres, _images])
	print("  image la plus sombre : luminance %.3f" % _noir)
	print("      %s" % _noir_note)
	print("  captures : %s/pire.png et %s/plus_sombre.png" % [dossier, dossier])
	print("=== %d échec(s) sur 1 vérification ===" % (1 if _vides > 0 else 0))
	get_tree().quit(1 if _vides > 0 else 0)
