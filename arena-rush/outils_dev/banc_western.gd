extends Node3D
## BANC DE L'ARÈNE WESTERN — le level design tient-il ses promesses ?
##
## Il ne juge pas la beauté : ça se juge en image. Il répond aux quatre
## questions dont dépend la CHASSE, et qu'aucune capture ne tranche.
##
## POURQUOI IL MESURE LE PLAN ET NON LES MAILLAGES. La carte est bâtie en
## géométrie FUSIONNÉE — sept grandes masses, une par teinte, pour tenir la
## performance mobile. Une sonde qui inspecterait les maillages y verrait
## sept objets confondus et crierait au doublon : elle mesurerait la
## technique de rendu, pas la composition. On interroge donc les données
## du plan, et l'espace réellement libre par lancer de rayons.

## Rayon du corps d'un joueur, pour juger un passage praticable.
const RAYON_CORPS := 0.45
## Largeur minimale d'un passage pour qu'on s'y engage en courant.
const PASSAGE_MINI := 1.6
## Pas du balayage de praticabilité.
const PAS := 1.0

var _echecs := 0

func _ready() -> void:
	Cfg.arene_test = true
	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)
	await get_tree().process_frame
	await get_tree().physics_frame

	print("\n=== BANC DE L'ARÈNE WESTERN ===\n")
	_contournabilite()
	_apparitions()
	_lignes_de_vue()
	_connexite()

	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh`.
	#
	# Le lanceur refuse de croire un banc qui n'imprime pas cette ligne :
	# c'est ainsi qu'il distingue « tout est passé » de « le banc s'est
	# arrêté en route ». Sans elle, un banc pourtant conforme était
	# compté comme non exécuté.
	print("=== %d échec(s) ===" % _echecs)
	if _echecs == 0:
		print("Arène Western : conforme.")
	else:
		print("Arène Western : %d anomalie(s)." % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-46s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


## 1 — CHAQUE GROSSE MASSE EST-ELLE CONTOURNABLE À 360° ?
##
## On tourne autour de chacune, à la distance de dégagement voulue, et l'on
## teste si un corps peut s'y tenir. Une seule direction bouchée fait un
## cul-de-sac — et un cul-de-sac transforme une poursuite en exécution.
func _contournabilite() -> void:
	var espace := get_viewport().world_3d.direct_space_state
	var pires: Array[String] = []
	var pire_taux := 1.0
	var pire_nom := "—"
	for m: Dictionary in PlanAreneWestern.masses():
		var c: Vector2 = m["pos"]
		var r: float = float(m["rayon"]) + PlanAreneWestern.DEGAGEMENT * 0.5
		var libres := 0
		var n := 36
		for i in n:
			var a := TAU * float(i) / float(n)
			var p := c + Vector2(cos(a), sin(a)) * r
			if _tenable(espace, p):
				libres += 1
		var taux := float(libres) / float(n)
		if taux < pire_taux:
			pire_taux = taux
			pire_nom = "%s en %s" % [m["nom"], str(c)]
		# On tolère qu'un quart de l'anneau soit pris — un rocher peut
		# jouxter un muret. Au-delà, on ne contourne plus, on longe.
		if taux < 0.75:
			pires.append("%s en %s : %.0f %% de l'anneau libre"
					% [m["nom"], str(c), taux * 100.0])
	_ligne(pires.is_empty(), "toute grosse masse est contournable",
			"pire anneau %.0f %% libre chez %s (seuil 75 %%)"
			% [pire_taux * 100.0, pire_nom])
	for p in pires.slice(0, 6):
		print("        → %s" % p)


## 2 — LES DIX APPARITIONS SONT-ELLES SAINES ?
##
## Praticables, hors ligne de tir du centre, et suffisamment écartées.
func _apparitions() -> void:
	var espace := get_viewport().world_3d.direct_space_state
	var bloquees: Array[String] = []
	var exposees: Array[String] = []
	var mini := INF
	var pts := PlanAreneWestern.APPARITIONS
	for i in pts.size():
		var p: Vector2 = pts[i]
		if not _tenable(espace, p):
			bloquees.append("Spawn_%02d en %s" % [i + 1, str(p)])
		# Ligne de tir vers le centre : si le rayon passe, l'apparition est
		# à découvert face au point le plus fréquenté de la carte.
		var a := Vector3(p.x, 1.1, p.y)
		var b := Vector3(0, 1.1, 0)
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.collision_mask = Cfg.LAYER_WORLD
		if espace.intersect_ray(q).is_empty():
			exposees.append("Spawn_%02d" % (i + 1))
		for j in range(i + 1, pts.size()):
			mini = minf(mini, p.distance_to(pts[j]))
	_ligne(pts.size() == 10, "dix points d'apparition", "%d déclarés" % pts.size())
	_ligne(bloquees.is_empty(), "aucune apparition dans un obstacle",
			"%d bloquée(s)" % bloquees.size())
	for b in bloquees:
		print("        → %s" % b)
	_ligne(mini >= 12.0, "les apparitions sont écartées",
			"plus proche paire à %.1f m (seuil 12)" % mini)
	# Informatif : on veut PEU d'apparitions à découvert, pas zéro — une
	# carte où le centre n'est jamais visible depuis le bord serait un
	# labyrinthe.
	print("        · %d apparition(s) avec vue directe sur le centre : %s"
			% [exposees.size(), ", ".join(exposees) if exposees else "aucune"])
	_ligne(exposees.size() <= 3, "peu d'apparitions à découvert",
			"%d sur 10 (seuil 3)" % exposees.size())


## 3 — LES LIGNES DE TIR SONT-ELLES RÉGULIÈREMENT CASSÉES ?
##
## On tire cinq cents rayons entre paires de points praticables tirés au
## sort. Sur un shooter, une carte où l'on se voit d'un bord à l'autre
## donne des duels décidés avant qu'on ait pu bouger.
func _lignes_de_vue() -> void:
	var espace := get_viewport().world_3d.direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var longues := 0
	var total := 0
	var d := PlanAreneWestern.DEMI - 4.0
	while total < 500:
		var a := Vector2(rng.randf_range(-d, d), rng.randf_range(-d, d))
		var b := Vector2(rng.randf_range(-d, d), rng.randf_range(-d, d))
		if a.distance_to(b) < 28.0:
			continue
		if not _tenable(espace, a) or not _tenable(espace, b):
			continue
		total += 1
		var q := PhysicsRayQueryParameters3D.create(
				Vector3(a.x, 1.2, a.y), Vector3(b.x, 1.2, b.y))
		q.collision_mask = Cfg.LAYER_WORLD
		if espace.intersect_ray(q).is_empty():
			longues += 1
	var taux := float(longues) / float(maxi(total, 1))
	# Au-delà d'un quart de tirs longs dégagés, la carte est trop ouverte.
	_ligne(taux <= 0.25, "les tirs longs sont majoritairement coupés",
			"%.0f %% de vues dégagées au-delà de 28 m (seuil 25 %%)"
			% (taux * 100.0))


## 4 — LA CARTE EST-ELLE D'UN SEUL TENANT ?
##
## Un remplissage par diffusion depuis le centre. Toute poche praticable
## qu'on n'atteint pas est une zone morte, ou pire, une impasse fermée.
func _connexite() -> void:
	var espace := get_viewport().world_3d.direct_space_state
	var d := PlanAreneWestern.RAYON_CLOTURE - 1.0
	var n := int(d * 2.0 / PAS)
	var libre := {}
	for iz in n:
		for ix in n:
			var p := Vector2(-d + float(ix) * PAS, -d + float(iz) * PAS)
			if p.length() > d:
				continue
			if _tenable(espace, p):
				libre[Vector2i(ix, iz)] = true
	var depart := Vector2i(int(d / PAS), int(d / PAS))
	var vus := {}
	var file: Array[Vector2i] = [depart]
	if not libre.has(depart):
		_ligne(false, "le centre est praticable", "case centrale bloquée")
		return
	vus[depart] = true
	while not file.is_empty():
		var c: Vector2i = file.pop_back()
		for dd in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var v: Vector2i = c + dd
			if libre.has(v) and not vus.has(v):
				vus[v] = true
				file.append(v)
	var taux := float(vus.size()) / float(maxi(libre.size(), 1))
	_ligne(taux > 0.98, "toute la surface praticable est atteignable",
			"%.1f %% reliés au centre (%d cases isolées)"
			% [taux * 100.0, libre.size() - vus.size()])


## Un corps peut-il se tenir là ?
func _tenable(espace: PhysicsDirectSpaceState3D, p: Vector2) -> bool:
	var f := PhysicsShapeQueryParameters3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = RAYON_CORPS
	cy.height = 1.6
	f.shape = cy
	f.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.9, p.y))
	f.collision_mask = Cfg.LAYER_WORLD | Cfg.LAYER_BORDURE
	return espace.intersect_shape(f, 1).is_empty()
