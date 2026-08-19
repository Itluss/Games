extends Node3D
## VISIBILITÉ DU JOUEUR DANS L'ARÈNE — balayage DÉTERMINISTE.
##
## POURQUOI CETTE SONDE EXISTE À CÔTÉ DU BANC VIVANT. Le banc mesurait la
## visibilité en téléportant le joueur sur un circuit pendant une vraie
## partie. Deux mesures successives ont rendu 93,8 % puis 81,2 % SANS
## qu'une ligne ne change entre les deux : la caméra est lissée, elle
## glisse ; le corps est physique, les bots le bousculent ; et le résultat
## dépendait de l'instant où l'on tirait le rayon. Un instrument qui rend
## deux verdicts différents pour le même niveau ne mesure pas le niveau.
##
## Ici, aucun corps et aucune caméra réelle : on parcourt une grille
## régulière, on place un point de vue AU DÉCALAGE EXACT de la caméra de
## jeu, et on tire un rayon vers la poitrine. Même arène, même résultat, à
## chaque exécution. C'est ce qui permet de dire qu'une correction a
## corrigé quelque chose.

## Décalage de la caméra de jeu, copié de arena_camera.gd.
const CAM_HAUTEUR := 10.4
const CAM_RECUL := 8.0
## Hauteur de poitrine visée.
const POITRINE := 1.1
## Pas de la grille, en mètres.
const PAS := 1.0
## Seuil d'acceptation.
const SEUIL := 0.96

func _ready() -> void:
	Cfg.arene_test = true
	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)
	await get_tree().process_frame
	await get_tree().physics_frame

	var espace := get_viewport().world_3d.direct_space_state
	var vus := 0
	var masques := 0
	var points_masques: Array[Vector2] = []
	var d := PlanAreneTest.DEMI - 1.0
	var y := -d
	while y <= d:
		var x := -d
		while x <= d:
			var sol := Vector3(x, 0.0, y)
			# On ne teste que les endroits où l'on peut SE TENIR : un point
			# à l'intérieur d'un conteneur n'intéresse personne.
			if not _libre(espace, sol):
				x += PAS
				continue
			var oeil := sol + Vector3(0.0, CAM_HAUTEUR, CAM_RECUL)
			var cible := sol + Vector3(0.0, POITRINE, 0.0)
			var q := PhysicsRayQueryParameters3D.create(oeil, cible)
			q.collision_mask = Cfg.LAYER_WORLD
			var hit := espace.intersect_ray(q)
			if hit.is_empty():
				vus += 1
			else:
				masques += 1
				points_masques.append(Vector2(x, y))
			x += PAS
		y += PAS

	var total: int = maxi(1, vus + masques)
	var taux := float(vus) / float(total)
	print("\n=== VISIBILITÉ DANS L'ARÈNE (balayage déterministe) ===\n")
	print("  %d positions praticables testées, pas de %.1f m" % [total, PAS])
	var ok := taux >= SEUIL
	print("  [%s] le joueur est visible depuis la caméra de jeu   %.1f %% (seuil %.0f %%)"
			% ["OK" if ok else "ÉCHEC", taux * 100.0, SEUIL * 100.0])
	if not points_masques.is_empty():
		# GROUPÉS PAR ZONE : une liste de deux cents coordonnées ne se lit
		# pas. Ce qu'on veut savoir, c'est OÙ ça coince.
		var par_zone: Dictionary = {}
		for p in points_masques:
			var k := "%s" % Vector2i(roundi(p.x / 6.0) * 6, roundi(p.y / 6.0) * 6)
			par_zone[k] = int(par_zone.get(k, 0)) + 1
		var cles := par_zone.keys()
		cles.sort_custom(func(a, b): return par_zone[a] > par_zone[b])
		print("  Foyers d'occultation (secteur → positions masquées) :")
		for k in cles.slice(0, 8):
			print("      %-12s %d" % [k, par_zone[k]])
	get_tree().quit(0 if ok else 1)


## Un point est-il praticable ? On teste un petit cylindre à hauteur de
## corps : c'est la question « puis-je me tenir là ? », pas « le sol
## est-il là ? ».
func _libre(espace: PhysicsDirectSpaceState3D, sol: Vector3) -> bool:
	var forme := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 1.6
	forme.shape = cyl
	forme.transform = Transform3D(Basis.IDENTITY, sol + Vector3(0, 0.85, 0))
	forme.collision_mask = Cfg.LAYER_WORLD
	return espace.intersect_shape(forme, 1).is_empty()
