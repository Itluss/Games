extends Node
## SONDE DE LA BALLE — le projectile du héros, vu de profil, en vol.
##
## LE RETOUR : « la balle du pirate n'est pas reconnaissable ». On ne
## règle pas un projectile sur une intuition : cette sonde fait tirer le
## joueur devant une caméra de profil et photographie la balle EN VOL,
## à la taille où le joueur la voit. La vignette de la planche est le
## juge : boule dorée, pointillés derrière.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_balle.tscn \
##       --rendering-driver opengl3 -- --solo

var _joueur: Node3D
var _cam: Camera3D
var _dossier := ""
var _photo := 0
var _attente := 8
var _prete := false

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_dossier = ProjectSettings.globalize_path("user://sonde_balle")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			p.queue_free()
		else:
			_joueur = p
	if _joueur == null:
		get_tree().quit(1)
		return
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(&"spawner"):
		n.set_process(false)
		n.set_physics_process(false)
	# Le contrôleur réécrit want_fire à chaque image depuis le HUD : on le
	# coupe, la sonde tient la gâchette elle-même. Il ne vit PAS sous le
	# joueur — c'est le monde de jeu qui le porte.
	var monde := get_tree().get_first_node_in_group(&"game_world")
	if monde != null:
		var ctrl = monde.get(&"controller")
		if ctrl != null:
			(ctrl as Node).set_process(false)
	# LA CAMÉRA DU JEU EST LE SEUL JUGE : c'est elle que le joueur a.
	# Les caméras de profil posées à la main se faisaient masquer par
	# les dunes — deux séries de photos vides avant de comprendre.
	_cam = get_viewport().get_camera_3d()
	Engine.time_scale = 0.2
	_prete = true
	RenderingServer.frame_post_draw.connect(_capturer)


func _capturer() -> void:
	if not _prete:
		return
	_joueur.set(&"want_fire", true)
	if _attente > 0:
		_attente -= 1
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dossier.path_join("balle_%02d.png" % _photo))
	var arme = _joueur.get(&"weapon")
	var trouves := []
	for c in get_tree().current_scene.get_children():
		if c is Projectile and (c as Node3D).visible:
			trouves.append(c)
	if trouves.is_empty():
		print("ETAT %02d aucun projectile visible" % _photo)
	else:
		var pr := trouves[0] as Node3D
		var ec := _cam.unproject_position(pr.global_position) \
				if _cam.is_position_in_frustum(pr.global_position) \
				else Vector2(-1, -1)
		for q in trouves:
			if q.get(&"_identite") == null:
				continue
			var mesh := q.get(&"_mesh") as MeshInstance3D
			var cont := q.get(&"_contour") as MeshInstance3D
			print("  p%02d pos=%s mesh_vis=%s mesh_pos=%s rayon=%.3f contour=%s racine_echelle=%s" % [
					_photo, str((q as Node3D).global_position),
					str(mesh.visible), str(mesh.global_position),
					(mesh.mesh as CapsuleMesh).radius,
					str(cont.visible) if cont != null else "nul",
					str((q as Node3D).scale)])
	_photo += 1
	if _photo >= 10:
		_prete = false
		Engine.time_scale = 1.0
		print("=== 0 échec(s) sur 1 vérification ===")
		get_tree().quit(0)
