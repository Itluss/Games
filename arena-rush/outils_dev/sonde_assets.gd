extends SceneTree
## Mesure chaque modèle Meshy : dimensions brutes et proportions.
func _init() -> void:
	var d := DirAccess.open("res://assets/models")
	var noms: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".glb"):
			noms.append(f.get_basename())
	noms.sort()
	print("%-20s %8s %8s %8s   %s" % ["modèle", "L(x)", "H(y)", "P(z)", "forme"])
	for n in noms:
		var sc := load("res://assets/models/%s.glb" % n) as PackedScene
		if sc == null:
			continue
		var r := sc.instantiate() as Node3D
		var boites: Array[AABB] = []
		_col(r, Transform3D.IDENTITY, boites)
		if boites.is_empty():
			r.free(); continue
		var t := boites[0]
		for i in range(1, boites.size()):
			t = t.merge(boites[i])
		var s := t.size
		# Ramené à 1 : ce qui compte est la PROPORTION, pas l'échelle Meshy.
		var m: float = maxf(maxf(s.x, s.y), s.z)
		var forme := "plat" if s.y / m < 0.35 else ("haut" if s.y / m > 0.75 else "trapu")
		print("%-20s %8.2f %8.2f %8.2f   %s  (y/max=%.2f)" % [n, s.x, s.y, s.z, forme, s.y / m])
		r.free()
	quit()

func _col(n: Node, t: Transform3D, out: Array[AABB]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(t * mi.get_aabb())
	for e in n.get_children():
		var s := t
		var e3 := e as Node3D
		if e3 != null:
			s = t * e3.transform
		_col(e, s, out)
