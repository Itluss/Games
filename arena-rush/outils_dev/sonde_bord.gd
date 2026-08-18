extends Node
## SONDE DU BORD — outil de développement, hors jeu.
##
## POURQUOI CELLE-CI, APRÈS CINQ AUTRES. La joueuse a fini par donner
## l'information qui manquait : l'écran violet arrive « surtout quand je
## m'approche des bords de la map ». Les sondes précédentes balayaient le
## monde entier ou promenaient le joueur au hasard ; aucune ne longeait la
## limite, qui est pourtant l'endroit le plus singulier de la carte — c'est
## le seul où la caméra, reculée de 10 m sur l'axe Z du MONDE, se retrouve
## au-delà de tout ce qui est construit.
##
## Elle fait donc le tour complet en rasant le mur, et lit les pixels.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_bord.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 480
const HAUTEUR := 270
## Points visités sur le pourtour. 72 = un tous les cinq degrés.
const POINTS := 72
## Rayon de marche : au plus près du mur sans être dedans.
const RAYON := 76.0
const SEUIL := 0.06
const VIDE := 0.9

var _joueur: Node3D
var _cam: Camera3D
var _i := 0
var _vides := 0
var _pire := 0.0
var _pire_note := ""
var _pire_image: Image = null
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
	_cam = get_viewport().get_camera_3d()
	_prete = true
	RenderingServer.frame_post_draw.connect(_analyser)


func _point(i: int) -> Vector3:
	var a := TAU * float(i) / float(POINTS)
	return Vector3(cos(a) * RAYON, 0.0, sin(a) * RAYON)


func _analyser() -> void:
	if not _prete:
		return
	if _i > 0:
		var img := get_viewport().get_texture().get_image()
		var m := _mesurer(img)
		var plat: float = m["plat"]
		var ou := _point(_i - 1)
		var note := "angle %3.0f° · joueur (%.0f, %.0f) · caméra %s" % [
				360.0 * float(_i - 1) / float(POINTS), ou.x, ou.z,
				_bref(_cam.global_position) if _cam else "?"]
		if plat > _pire:
			_pire = plat
			_pire_note = "%s · teinte %s" % [note,
					(m["teinte"] as Color).to_html(false)]
			_pire_image = img
		if plat > VIDE:
			_vides += 1
			print("      ! %.0f %% d'aplat — %s (teinte %s)"
					% [plat * 100.0, note, (m["teinte"] as Color).to_html(false)])
	if _i >= POINTS:
		_conclure()
		return
	_joueur.global_position = _point(_i)
	if _cam and _cam.has_method(&"_snap"):
		_cam.call(&"_snap")
	_i += 1


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
	return {"plat": float(proches) / float(n), "teinte": moyenne}


func _conclure() -> void:
	_prete = false
	var dossier := ProjectSettings.globalize_path("user://sonde")
	DirAccess.make_dir_recursive_absolute(dossier)
	if _pire_image:
		_pire_image.save_png("%s/bord.png" % dossier)
	print("=== SONDE DU BORD (%d points au rayon %.0f m) ===" % [POINTS, RAYON])
	print("  images plates (> %.0f %%) : %d" % [VIDE * 100.0, _vides])
	print("  pire image : %.0f %% d'aplat" % (_pire * 100.0))
	print("      %s" % _pire_note)
	print("  capture : %s/bord.png" % dossier)
	print("=== %d échec(s) sur 1 vérification ===" % (1 if _vides > 0 else 0))
	get_tree().quit(1 if _vides > 0 else 0)
