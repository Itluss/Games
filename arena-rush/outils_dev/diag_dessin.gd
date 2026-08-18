extends Node3D
func _ready() -> void:
	var m := Arena.new()
	add_child(m)
	await get_tree().process_frame
	var par_materiau: Dictionary = {}
	var total := 0
	var semis := 0
	var pile: Array[Node] = [m]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if n is MultiMeshInstance3D:
			semis += 1
		elif n is MeshInstance3D:
			total += 1
			var mi := n as MeshInstance3D
			var cle := "?"
			if mi.mesh:
				cle = mi.mesh.get_class()
			var mat := mi.material_override
			if mat is StandardMaterial3D:
				cle += " " + (mat as StandardMaterial3D).albedo_color.to_html(false)
			par_materiau[cle] = int(par_materiau.get(cle, 0)) + 1
		for e in n.get_children():
			pile.append(e)
	print("=== MAILLAGES INDIVIDUELS : %d (et %d semis) ===" % [total, semis])
	var liste: Array = []
	for k in par_materiau:
		liste.append([int(par_materiau[k]), k])
	liste.sort_custom(func(a, b): return a[0] > b[0])
	for e in liste.slice(0, 22):
		print("  %4d × %s" % [e[0], e[1]])
	get_tree().quit()
