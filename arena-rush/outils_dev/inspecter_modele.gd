extends Node3D
## Mesure de l'orientation RÉELLE, animation en cours — outil de dev.
##
## La pose de repos ne suffit pas : un clip peut faire pivoter le bassin
## et retourner le personnage sans qu'aucune donnée statique ne le dise.
## On mesure donc le regard À TRAVERS toute la chaîne — nœud, squelette,
## animation — exactement comme le moteur le rendra.

var _visuel: CharacterVisual

func _ready() -> void:
	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Color.WHITE, Color.WHITE, 1.7)
	_visuel.set_motion(Vector3(0, 0, -5.6), Vector3.ZERO)
	# Le personnage n'est pas tourné : on mesure l'orientation NUE.
	for i in 40:
		_visuel.update_visual(0.02, 1.0)
		await get_tree().process_frame
	_mesurer("course")
	get_tree().quit()

func _mesurer(libelle: String) -> void:
	var sq := _premier(_visuel, "Skeleton3D") as Skeleton3D
	var i_tete := sq.find_bone("Head")
	var i_front := sq.find_bone("headfront")
	# get_bone_global_pose tient compte de l'ANIMATION, à la différence
	# de get_bone_global_rest.
	var a := sq.get_bone_global_pose(i_tete).origin
	var b := sq.get_bone_global_pose(i_front).origin
	# Puis on remonte dans l'espace monde, ce qui intègre le demi-tour.
	var m := sq.global_transform
	var regard := (m * b - m * a).normalized()
	print("[%s] regard monde = %s" % [libelle, regard])
	print("  z=%.3f → %s" % [regard.z,
			"AVANT Godot (-Z) : correct" if regard.z < -0.5
			else ("ARRIÈRE (+Z) : INVERSÉ" if regard.z > 0.5 else "de côté")])

func _premier(n: Node, classe: String) -> Node:
	if n.is_class(classe):
		return n
	for c in n.get_children():
		var r := _premier(c, classe)
		if r:
			return r
	return null
