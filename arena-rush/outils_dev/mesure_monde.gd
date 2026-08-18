extends Node3D
## MESURE DU MONDE — outil de développement, hors jeu.
##
## POURQUOI MESURER AVANT DE REGARDER : « ça a l'air grand » n'est pas une
## information. Le coût de dessin, lui, décide si le jeu tourne sur un
## téléphone — et il ne se voit sur aucune capture.

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var monde := Arena.new()
	add_child(monde)
	await get_tree().process_frame
	var montage := Time.get_ticks_msec() - t0

	var semis := 0
	var instances := 0
	var maillages := 0
	var formes := 0
	var triangles := 0
	_compter(monde, [semis, instances, maillages])
	var c := _relever(monde)

	var corps := monde.get_node_or_null("Obstacles")
	if corps:
		for n in corps.get_children():
			if n is CollisionShape3D:
				formes += 1

	print("=== MONDE ===")
	print("  Montage                 : %d ms" % montage)
	print("  Rayon                   : %.0f m (%.0f m de large)"
			% [PlanMonde.DEMI, PlanMonde.COTE])
	print("  Surface                 : %.0f m² (ancienne arène : %.0f m²)"
			% [PlanMonde.COTE * PlanMonde.COTE,
			PI * Cfg.ARENA_RADIUS * Cfg.ARENA_RADIUS])
	print("  Semis MultiMesh         : %d" % c["semis"])
	print("  Props semés             : %d" % c["instances"])
	print("  Maillages individuels   : %d" % c["maillages"])
	print("  Formes de collision     : %d" % formes)
	print("  APPELS DE DESSIN (pire) : %d" % (c["semis"] + c["maillages"]))
	print("  Points d'apparition     : %d joueur · %d mob"
			% [monde.player_spawn_points.size(), monde.mob_spawn_points.size()])
	print("  Secteurs                : %d · points d'intérêt : %d"
			% [PlanMonde.SECTEURS.size(), PlanMonde.POINTS_INTERET.size()])

	# Où tombent les apparitions ? Toutes dans le même secteur serait un
	# défaut de répartition invisible autrement.
	var par_secteur: Dictionary = {}
	for sp in monde.player_spawn_points:
		var s := PlanMonde.secteur_de(Vector2(sp.x, sp.z))
		par_secteur[s] = int(par_secteur.get(s, 0)) + 1
	print("  Répartition des apparitions : %s" % str(par_secteur))
	get_tree().quit()


func _compter(n: Node, _ignore: Array) -> void:
	pass


func _relever(racine: Node) -> Dictionary:
	var semis := 0
	var instances := 0
	var maillages := 0
	var pile: Array[Node] = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if n is MultiMeshInstance3D:
			semis += 1
			instances += (n as MultiMeshInstance3D).multimesh.instance_count
		elif n is MeshInstance3D:
			maillages += 1
		for e in n.get_children():
			pile.append(e)
	return {"semis": semis, "instances": instances, "maillages": maillages}
