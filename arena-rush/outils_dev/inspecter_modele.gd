extends Node3D
## Mesure du déplacement racine de TOUS les clips — outil de dev.

func _ready() -> void:
	var n: Node3D = load("res://assets/models/kael.glb").instantiate()
	add_child(n)
	var ap := _premier(n, "AnimationPlayer") as AnimationPlayer
	for nom in ap.get_animation_list():
		var a := ap.get_animation(nom)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			if not str(a.track_get_path(t)).ends_with(":Hips"):
				continue
			var k := a.track_get_key_count(t)
			var p0: Vector3 = a.track_get_key_value(t, 0)
			var pf: Vector3 = a.track_get_key_value(t, k - 1)
			var d := pf - p0
			print("%-12s %5.2f s  dérive horizontale = %8.2f   (x=%.2f z=%.2f)"
					% [nom, a.length, Vector2(d.x, d.z).length(), d.x, d.z])
	get_tree().quit()

func _premier(n: Node, c: String) -> Node:
	if n.is_class(c):
		return n
	for e in n.get_children():
		var r := _premier(e, c)
		if r:
			return r
	return null
