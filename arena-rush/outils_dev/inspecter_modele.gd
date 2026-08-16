extends Node3D
## Contrôle du déplacement racine APRÈS correction — outil de dev.

var _visuel: CharacterVisual

func _ready() -> void:
	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Color.WHITE, Color.WHITE, 1.7)
	var ap := _premier(_visuel, "AnimationPlayer") as AnimationPlayer
	for nom in ap.get_animation_list():
		var a := ap.get_animation(nom)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			if not str(a.track_get_path(t)).ends_with(":Hips"):
				continue
			var n := a.track_get_key_count(t)
			var p0: Vector3 = a.track_get_key_value(t, 0)
			var pf: Vector3 = a.track_get_key_value(t, n - 1)
			var d := pf - p0
			# Amplitude conservée : on veut avoir ôté la DÉRIVE, pas le
			# mouvement. Un clip aplati serait une régression silencieuse.
			var mn := p0
			var mx := p0
			for k in n:
				var v: Vector3 = a.track_get_key_value(t, k)
				mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
				mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
			print("%-12s boucle=%d  dérive horizontale=%.4f  amplitude X=%.2f Y=%.2f Z=%.2f"
					% [nom, a.loop_mode, Vector2(d.x, d.z).length(),
					mx.x - mn.x, mx.y - mn.y, mx.z - mn.z])
	get_tree().quit()

func _premier(n: Node, classe: String) -> Node:
	if n.is_class(classe):
		return n
	for c in n.get_children():
		var r := _premier(c, classe)
		if r:
			return r
	return null
