extends Node
## LE LOD SERT-IL VRAIMENT ? — question à trancher avant d'optimiser.
##
## Godot génère des niveaux de détail à l'import (« generate_lods »). Mais
## la version web tourne en rendu Compatibility, et rien ne garantit qu'il
## s'en serve. Si le LOD est inerte, chaque rocher coûte son plein tarif
## même à cent mètres — et alléger passe alors forcément par la source.
##
## On pose UN rocher, on regarde la caméra de près puis de très loin, et
## on compte les primitives réellement dessinées. Si le chiffre ne bouge
## pas, le LOD ne fait rien.

const MODELE := "res://assets/models/west_rock_formation_a.glb"
const DISTANCES := [6.0, 25.0, 60.0, 150.0, 400.0]

var _cam: Camera3D


func _ready() -> void:
	var scene: PackedScene = load(MODELE)
	var inst := scene.instantiate()
	add_child(inst)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	add_child(_cam)
	_cam.current = true
	var lum := DirectionalLight3D.new()
	add_child(lum)
	await get_tree().process_frame
	print("\n=== LE LOD EST-IL ACTIF EN RENDU COMPATIBILITY ? ===\n")
	print("  rendu : %s" % RenderingServer.get_video_adapter_name())
	print("")
	print("  %-12s %14s %14s" % ["distance", "primitives", "objets"])
	for d in DISTANCES:
		_cam.global_position = Vector3(0, float(d) * 0.35, float(d))
		_cam.look_at(Vector3.ZERO)
		for _i in 8:
			await get_tree().process_frame
		var prim := RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var obj := RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		print("  %-12s %14d %14d" % ["%.0f m" % d, prim, obj])
	print("")
	print("  Un chiffre constant = LOD inerte : alléger doit se faire à la source.")
	print("")
	print("=== 0 échec(s) ===")
	get_tree().quit(0)
