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

## Un os : nom, parent, position de SA TÊTE, et CÔTÉ (+1 gauche, -1
## droite, 0 axial).
##
## Les positions ne sont pas estimées à l'œil mais MESURÉES sur le
## maillage, par tranches horizontales :
##   • les jambes se séparent de y=-0,93 à y=-0,41 → entrejambe à -0,39 ;
##   • un renflement de largeur vers -0,52 → les genouillères ;
##   • les baskets s'arrêtent vers -0,70 → la cheville ;
##   • l'envergure est maximale vers -0,20 → les mains ;
##   • la largeur chute au-dessus de +0,42 → les épaules.
##
## L'erreur de la première version était de poser la tête des cuisses à
## -0,16, soit BIEN AU-DESSUS de l'entrejambe. Le bassin, masse unique,
## se retrouvait tiraillé entre deux os partant en sens opposés, et se
## déformait à chaque foulée.
const OSSATURE := [
	# nom,       parent, position                      côté
	["hanches",   -1,    Vector3(0.00, -0.20, 0.00),    0, "tronc"],
	["buste",      0,    Vector3(0.00,  0.02, 0.00),    0, "tronc"],
	["torse",      1,    Vector3(0.00,  0.24, 0.00),    0, "tronc"],
	["tete",       2,    Vector3(0.00,  0.47, 0.00),    0, "tronc"],
	["epaule_g",   2,    Vector3(0.17,  0.36, 0.00),    1, "bras"],
	["coude_g",    4,    Vector3(0.32,  0.09, 0.01),    1, "bras"],
	["main_g",     5,    Vector3(0.42, -0.17, 0.05),    1, "bras"],
	["epaule_d",   2,    Vector3(-0.17, 0.36, 0.00),   -1, "bras"],
	["coude_d",    7,    Vector3(-0.32, 0.09, 0.01),   -1, "bras"],
	["main_d",     8,    Vector3(-0.42, -0.17, 0.05),  -1, "bras"],
	# Tête de cuisse JUSTE au-dessus de l'entrejambe mesuré (-0,39).
	["cuisse_g",   0,    Vector3(0.14, -0.34, 0.00),    1, "jambe"],
	["genou_g",   10,    Vector3(0.145, -0.52, 0.00),   1, "jambe"],
	["cheville_g",11,    Vector3(0.15, -0.70, 0.00),    1, "jambe"],
	["pied_g",    12,    Vector3(0.15, -0.88, 0.04),    1, "jambe"],
	["cuisse_d",   0,    Vector3(-0.14, -0.34, 0.00),  -1, "jambe"],
	["genou_d",   14,    Vector3(-0.145, -0.52, 0.00), -1, "jambe"],
	["cheville_d",15,    Vector3(-0.15, -0.70, 0.00),  -1, "jambe"],
	["pied_d",    16,    Vector3(-0.15, -0.88, 0.04),  -1, "jambe"],
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
const CHEVILLE_G := 12
const PIED_G := 13
const CUISSE_D := 14
const GENOU_D := 15
const CHEVILLE_D := 16
const PIED_D := 17

## Nombre d'os influençant un sommet.
const INFLUENCES := 4
## Décroissance de l'influence avec la distance.
const NETTETE := 3.0

# --- APPARTENANCE ANATOMIQUE ---------------------------------------------
#
# La première version pondérait par la SEULE distance. C'était son défaut
# de fond : la distance ne sait pas à quoi un sommet APPARTIENT. Un mollet
# est près de la cuisse opposée, une main près d'une hanche — et
# l'influence fuyait d'un membre à l'autre. Il fallait alors brider les
# angles pour éviter que la géométrie ne s'effondre, donc brider la
# foulée elle-même.
#
# On pondère désormais la distance par une APPARTENANCE, calculée à partir
# du plan du corps : sous l'entrejambe et du bon côté, c'est une jambe ;
# assez latéral et à hauteur d'épaule, c'est un bras ; sinon c'est le
# tronc. La transition est progressive, sans quoi une couture apparaîtrait
# à chaque frontière.

## Repères mesurés sur le maillage.
const Y_ENTREJAMBE := -0.39
const Y_EPAULE := 0.36
const X_TRONC := 0.21

## Plancher d'appartenance : jamais zéro, sinon un sommet mal classé
## n'aurait plus aucune influence et partirait à l'origine.
const APPARTENANCE_MIN := 0.05

static func _lissage(bord0: float, bord1: float, x: float) -> float:
	var t := clampf((x - bord0) / (bord1 - bord0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## À quel point l'os `b` a vocation à emporter le sommet `p`.
static func _appartenance(p: Vector3, b: int) -> float:
	var cote: int = OSSATURE[b][3]
	var membre: String = OSSATURE[b][4]

	if membre == "jambe":
		# Sous l'entrejambe, et du bon côté.
		var bas := _lissage(Y_ENTREJAMBE + 0.12, Y_ENTREJAMBE - 0.08, p.y)
		var bon_cote := _lissage(-0.02, 0.07, p.x * float(cote))
		return maxf(bas * bon_cote, APPARTENANCE_MIN)

	if membre == "bras":
		# Latéral, et au-dessus de la ceinture.
		var lateral := _lissage(X_TRONC - 0.03, X_TRONC + 0.09, p.x * float(cote))
		var haut := _lissage(-0.45, -0.25, p.y)
		return maxf(lateral * haut, APPARTENANCE_MIN)

	# TRONC : il perd du terrain là où un membre le revendique, ce qui
	# évite qu'une épaule ou une cuisse reste happée par le buste.
	var pris_jambe := _lissage(Y_ENTREJAMBE + 0.12, Y_ENTREJAMBE - 0.08, p.y)
	var pris_bras := _lissage(X_TRONC - 0.03, X_TRONC + 0.12, absf(p.x))
	return maxf(1.0 - maxf(pris_jambe, pris_bras) * 0.92, APPARTENANCE_MIN)

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
				# La distance est divisée par l'appartenance : un os qui
				# n'a pas vocation à emporter ce sommet se retrouve
				# artificiellement éloigné.
				d /= maxf(_appartenance(p, b), 0.001)
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
