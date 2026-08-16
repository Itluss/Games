extends RefCounted
class_name ProceduralRig
## RIGGING AUTOMATIQUE — greffe un squelette sur un maillage statique.
##
## POURQUOI CE FICHIER EXISTE : Meshy livre un maillage D'UN SEUL TENANT,
## sans os. Un tel modèle ne peut pas bouger un bras ni plier un genou :
## on ne peut que le déplacer, l'incliner ou l'écraser en entier. D'où
## l'impression, parfaitement juste, qu'il « sautille sur lui-même ».
##
## COMMENT : on pose un squelette aux proportions du personnage, puis on
## attribue à chaque sommet du maillage une influence pondérée des os les
## plus proches. C'est le principe de tout rigging automatique ; la qualité
## dépend entièrement de la fonction de poids.
##
## LE CHOIX DÉTERMINANT est la distance à un SEGMENT d'os, et non à son
## origine. Un bras est un segment, pas un point : mesurer la distance à
## l'épaule seule ferait suivre le coude par des sommets du torse, et la
## déformation partirait en charpie.
##
## LIMITES ASSUMÉES : les poids ne connaissent rien à la topologie. Une
## main proche d'une cuisse en pose A pourrait recevoir un peu d'influence
## de la jambe. Sur un personnage trapu aux membres bien écartés — ce qui
## est exactement le cas de Kael — l'approximation tient.

## Un os : nom, parent, et position de SA TÊTE dans le repère du maillage.
## La queue d'un os est la tête de son enfant, d'où l'ordre imposé.
const OSSATURE := [
	# nom,        parent,        position (repère d'origine du modèle)
	["hanches",   -1,            Vector3(0.00, -0.10, 0.00)],
	["buste",      0,            Vector3(0.00,  0.14, 0.00)],
	["torse",      1,            Vector3(0.00,  0.30, 0.00)],
	["tete",       2,            Vector3(0.00,  0.44, 0.00)],
	["epaule_g",   2,            Vector3(0.19,  0.33, 0.00)],
	["coude_g",    4,            Vector3(0.31,  0.13, 0.01)],
	["main_g",     5,            Vector3(0.40, -0.09, 0.06)],
	["epaule_d",   2,            Vector3(-0.19, 0.33, 0.00)],
	["coude_d",    7,            Vector3(-0.31, 0.13, 0.01)],
	["main_d",     8,            Vector3(-0.40, -0.09, 0.06)],
	["cuisse_g",   0,            Vector3(0.13, -0.16, 0.00)],
	["genou_g",   10,            Vector3(0.14, -0.52, 0.00)],
	["pied_g",    11,            Vector3(0.15, -0.88, 0.02)],
	["cuisse_d",   0,            Vector3(-0.13, -0.16, 0.00)],
	["genou_d",   13,            Vector3(-0.14, -0.52, 0.00)],
	["pied_d",    14,            Vector3(-0.15, -0.88, 0.02)],
]

## Index utiles, pour que l'animateur n'ait pas à compter.
const HANCHES := 0
const BUSTE := 1
const TORSE := 2
const TETE := 3
const EPAULE_G := 4
const COUDE_G := 5
const MAIN_G := 6
const EPAULE_D := 7
const COUDE_D := 8
const MAIN_D := 9
const CUISSE_G := 10
const GENOU_G := 11
const PIED_G := 12
const CUISSE_D := 13
const GENOU_D := 14
const PIED_D := 15

## Nombre d'os influençant un sommet. Quatre est la limite du format et
## largement assez : au-delà, les influences supplémentaires sont si
## faibles qu'elles ne font que brouiller la déformation.
const INFLUENCES := 4
## Exposant de la décroissance. Plus il est élevé, plus l'os le plus
## proche domine — donc plus les articulations sont nettes, au risque de
## paraître cassantes. 3,0 donne un bon compromis sur un personnage trapu.
const NETTETE := 3.0

## Le maillage habillé est calculé UNE FOIS et partagé par tous les
## personnages : le calcul des poids coûte cher, et il donnerait le même
## résultat pour chacun. Chaque joueur garde en revanche son propre
## squelette, sinon ils bougeraient tous à l'unisson.
static var _cache: ArrayMesh = null


## Construit un Skeleton3D aux proportions définies ci-dessus.
static func construire_squelette() -> Skeleton3D:
	var sq := Skeleton3D.new()
	sq.name = "Squelette"
	for i in OSSATURE.size():
		sq.add_bone(OSSATURE[i][0])
	for i in OSSATURE.size():
		var parent: int = OSSATURE[i][1]
		sq.set_bone_parent(i, parent)
		# Le repos d'un os est exprimé RELATIVEMENT à son parent : c'est
		# ce qui permet ensuite de faire tourner une cuisse sans toucher
		# au genou, qui suivra tout seul.
		var pos: Vector3 = OSSATURE[i][2]
		if parent >= 0:
			pos -= OSSATURE[parent][2]
		sq.set_bone_rest(i, Transform3D(Basis(), pos))
		sq.reset_bone_pose(i)
	return sq


## Distance d'un point au SEGMENT [a, b] — et non à l'un de ses bouts.
static func _distance_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var longueur2 := ab.length_squared()
	if longueur2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / longueur2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Segments d'os : de la tête d'un os à celle de son enfant. Un os sans
## enfant reçoit un segment court dans le prolongement de son parent,
## faute de quoi il serait réduit à un point et n'attirerait presque rien.
static func _segments() -> Array:
	var enfants := {}
	for i in OSSATURE.size():
		var p: int = OSSATURE[i][1]
		if p >= 0:
			enfants[p] = enfants.get(p, 0) + 1

	var segs := []
	for i in OSSATURE.size():
		var a: Vector3 = OSSATURE[i][2]
		var b := a
		var trouve := false
		for j in OSSATURE.size():
			if OSSATURE[j][1] == i:
				b = OSSATURE[j][2]
				trouve = true
				break
		if not trouve:
			var p: int = OSSATURE[i][1]
			var direction: Vector3 = Vector3.UP
			if p >= 0:
				direction = (a - OSSATURE[p][2]).normalized()
			b = a + direction * 0.12
		segs.append([a, b])
	return segs


## Reconstruit le maillage avec ses attaches osseuses.
static func habiller(source: Mesh) -> ArrayMesh:
	if _cache != null:
		return _cache

	var segs := _segments()
	var sortie := ArrayMesh.new()

	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var sommets: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var os := PackedInt32Array()
		var poids := PackedFloat32Array()
		os.resize(sommets.size() * INFLUENCES)
		poids.resize(sommets.size() * INFLUENCES)

		for v in sommets.size():
			var p := sommets[v]
			# Distances à tous les os, puis on ne garde que les plus
			# proches : un sommet influencé par tout le squelette ne se
			# déformerait plus du tout.
			var classement := []
			for b in segs.size():
				var d := _distance_segment(p, segs[b][0], segs[b][1])
				classement.append([d, b])
			classement.sort_custom(func(x, y): return x[0] < y[0])

			var total := 0.0
			var w := []
			for k in INFLUENCES:
				var d: float = maxf(classement[k][0], 0.0025)
				var val := pow(1.0 / d, NETTETE)
				w.append(val)
				total += val

			for k in INFLUENCES:
				os[v * INFLUENCES + k] = classement[k][1]
				poids[v * INFLUENCES + k] = w[k] / total

		arrays[Mesh.ARRAY_BONES] = os
		arrays[Mesh.ARRAY_WEIGHTS] = poids
		sortie.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := source.surface_get_material(s)
		if mat:
			sortie.surface_set_material(s, mat)

	_cache = sortie
	return sortie
