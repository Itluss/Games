extends RefCounted
class_name KitBlocs
## KIT DE L'ARÈNE AUX BLOCS — vingt modules procéduraux, UN matériau.
##
## ─── POURQUOI PROCÉDURAL, ET PAS MESHY ─────────────────────────────────
##
## La référence est faite de volumes GÉOMÉTRIQUES : cubes biseautés,
## cylindres francs, prismes de palmes. C'est précisément ce qu'un
## générateur fait mieux qu'un sculpteur : arêtes exactes, couleurs par
## sommets sans texture (zéro lecture par pixel — leçon mesurée sur les
## décors précédents), aucun socle parasite à enterrer, aucun mégaoctet à
## télécharger. Meshy excelle sur l'organique ; ici l'organique n'existe
## pas. Chaque module sort déjà « propre et isolé », posable à même le sol,
## exactement ce que la consigne exige des assets.
##
## ─── LA RÈGLE DES COULEURS ─────────────────────────────────────────────
##
## Tout voyage dans les couleurs de sommets, écrites TELLES QUELLES :
## sonde à l'appui (trois plans côte à côte, pixel pipé), une couleur de
## sommet 0,5 s'affiche 0,498 dans le rendu web — identique à l'albédo.
## Chaque module prend une TEINTE DE BASE et en dérive son modelé : dessus
## éclairci, flancs pleins, bas assombri. C'est le modelé de la planche de
## référence — la lumière est déjà peinte dans le volume, l'éclairage
## temps réel ne fait que l'accompagner.
##
## ─── LA PALETTE DE LA RÉFÉRENCE ────────────────────────────────────────
##
## Huit familles, saturées et chaudes, pipées sur la planche. Les murs
## rouges, verts, jaunes et violets partagent LA MÊME géométrie : seule la
## teinte passée à `bloc()` change — c'est la consigne « variations par
## couleur plutôt que modèles uniques », au pied de la lettre.

const SOL        := Color("e2a047")
const SOL_CLAIR  := Color("efc06a")
const SOL_JOINT  := Color("c48c3c")
const CHEMIN     := Color("eeb862")
const ROUGE      := Color("d5543c")
const VERT       := Color("6aa844")
const JAUNE      := Color("e8c23f")
const VIOLET     := Color("8a5bb5")
const PIERRE     := Color("998e81")
const BOIS       := Color("a06334")
const BOIS_CLAIR := Color("c98a4b")
const FEUILLE    := Color("5da53e")
const FEUILLE_2  := Color("74c04f")
const TRONC      := Color("8a5a30")
const EAU_FOND   := Color("2ba69c")
const EAU_CLAIR  := Color("62d8c8")
const EAU_BORD   := Color("a8f0e2")
const TOIT       := Color("3fa8a0")
const OR_ETOILE  := Color("ffd24a")

## Mailles en cache : une par (module, teinte, gabarit).
static var _cache: Dictionary = {}
static var _materiau: StandardMaterial3D
static var _materiau_eau: ShaderMaterial


## LE matériau du décor — un seul pour toute l'arène, c'est lui qui rend
## les lots MultiMesh possibles sans état à changer entre deux appels.
static func materiau() -> StandardMaterial3D:
	if _materiau != null:
		return _materiau
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.metallic = 0.0
	# Diffuse LAMBERT et non toon : le modelé est déjà dans les sommets,
	# un second casse-lumière par-dessus doublerait les frontières.
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	_materiau = m
	return m


## L'eau — le SEUL shader de la carte, et il tient en huit lignes : deux
## teintes turquoise balayées par une sinusoïde en coordonnées MONDE.
## Pas de normal map, pas de réflexion, pas de profondeur : la lecture
## « eau » vient de la couleur et du liseré clair du rivage, comme sur la
## planche. Non éclairée : l'eau de la référence est sa propre lumière.
static func materiau_eau() -> ShaderMaterial:
	if _materiau_eau != null:
		return _materiau_eau
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, specular_disabled;
void fragment() {
	vec3 monde = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float vague = sin(monde.x * 0.9 + TIME * 0.8)
			* sin(monde.z * 0.7 - TIME * 0.6);
	ALBEDO = mix(vec3(0.168, 0.651, 0.612), vec3(0.384, 0.847, 0.784),
			smoothstep(-0.2, 0.9, vague) * 0.5 + COLOR.r * 0.25);
}
"""
	_materiau_eau = ShaderMaterial.new()
	_materiau_eau.shader = sh
	return _materiau_eau


# --- GÉNÉRATEURS DE BASE -------------------------------------------------

## Boîte biseautée — LA forme du style. Le chanfrein attrape une facette
## de lumière sur chaque arête : c'est lui qui fait « chunky » au lieu de
## « cube gris de prototype ». Dessus éclairci, flancs pleins, chanfreins
## intermédiaires — le modelé peint de la référence.
static func _boite(st: SurfaceTool, t: Transform3D, sx: float, sy: float,
		sz: float, c: Color, biseau := 0.14) -> void:
	var b := minf(biseau, minf(sx, minf(sy, sz)) * 0.32)
	var x := sx * 0.5
	var y := sy * 0.5
	var z := sz * 0.5
	var haut := c.lightened(0.13)
	var flanc := c
	var flanc_o := c.darkened(0.06)
	var bas := c.darkened(0.15)
	var faces := [
		# [normale approx., 4 coins], du dessus vers le bas
		[Vector3.UP, [Vector3(-x + b, y, -z + b), Vector3(x - b, y, -z + b),
				Vector3(x - b, y, z - b), Vector3(-x + b, y, z - b)], haut],
		# Même leçon que le sol et les couvercles : la face avant est
		# celle dont les sommets tournent en sens horaire VUS DE DEHORS.
		# Les flancs tournaient à l'envers — le culling les mangeait et
		# chaque cube se rendait comme une table (le dessus, plus
		# l'intérieur sombre du flanc opposé).
		[Vector3.FORWARD, [Vector3(-x + b, -y, -z), Vector3(x - b, -y, -z),
				Vector3(x - b, y - b, -z), Vector3(-x + b, y - b, -z)], flanc],
		[Vector3.BACK, [Vector3(x - b, -y, z), Vector3(-x + b, -y, z),
				Vector3(-x + b, y - b, z), Vector3(x - b, y - b, z)], flanc],
		[Vector3.LEFT, [Vector3(-x, -y, z - b), Vector3(-x, -y, -z + b),
				Vector3(-x, y - b, -z + b), Vector3(-x, y - b, z - b)], flanc_o],
		[Vector3.RIGHT, [Vector3(x, -y, -z + b), Vector3(x, -y, z - b),
				Vector3(x, y - b, z - b), Vector3(x, y - b, -z + b)], flanc_o],
		# Chanfreins du dessus — quatre bandes à 45°.
		[Vector3(0, 1, -1).normalized(), [Vector3(-x + b, y, -z + b),
				Vector3(-x + b, y - b, -z), Vector3(x - b, y - b, -z),
				Vector3(x - b, y, -z + b)], haut.lerp(flanc, 0.5)],
		[Vector3(0, 1, 1).normalized(), [Vector3(x - b, y, z - b),
				Vector3(x - b, y - b, z), Vector3(-x + b, y - b, z),
				Vector3(-x + b, y, z - b)], haut.lerp(flanc, 0.5)],
		[Vector3(-1, 1, 0).normalized(), [Vector3(-x + b, y, z - b),
				Vector3(-x, y - b, z - b), Vector3(-x, y - b, -z + b),
				Vector3(-x + b, y, -z + b)], haut.lerp(flanc_o, 0.5)],
		[Vector3(1, 1, 0).normalized(), [Vector3(x - b, y, -z + b),
				Vector3(x, y - b, -z + b), Vector3(x, y - b, z - b),
				Vector3(x - b, y, z - b)], haut.lerp(flanc_o, 0.5)],
	]
	# Chanfreins des arêtes VERTICALES — les quatre coins. Les flancs
	# sont en retrait de b : sans ces bandes, chaque coin est une fente
	# ouverte sur l'intérieur (invisible tant que les flancs, enroulés à
	# l'envers, cachaient tout — révélée par leur correction).
	for coin: Vector2 in [Vector2(1, -1), Vector2(1, 1),
			Vector2(-1, 1), Vector2(-1, -1)]:
		var pa := Vector3(coin.x * (x - b), 0, coin.y * z)
		var pb := Vector3(coin.x * x, 0, coin.y * (z - b))
		var haut_a := Vector3(pa.x, y - b, pa.z)
		var haut_b := Vector3(pb.x, y - b, pb.z)
		var bas_a := Vector3(pa.x, -y, pa.z)
		var bas_b := Vector3(pb.x, -y, pb.z)
		var coin_haut := Vector3(coin.x * (x - b), y, coin.y * (z - b))
		var n_coin := Vector3(coin.x, 0, coin.y)
		if coin.x * coin.y < 0:
			faces.append([n_coin, [bas_a, bas_b, haut_b, haut_a],
					flanc.lerp(flanc_o, 0.5)])
			faces.append([Vector3(coin.x, 1.4, coin.y),
					[coin_haut, haut_a, haut_b, haut_b],
					haut.lerp(flanc, 0.5)])
		else:
			faces.append([n_coin, [bas_b, bas_a, haut_a, haut_b],
					flanc.lerp(flanc_o, 0.5)])
			faces.append([Vector3(coin.x, 1.4, coin.y),
					[coin_haut, haut_b, haut_a, haut_a],
					haut.lerp(flanc, 0.5)])
	for f: Array in faces:
		var n: Vector3 = t.basis * (f[0] as Vector3)
		var q: Array = f[1]
		var teinte: Color = f[2]
		# Le bas des faces verticales fonce : l'objet s'assoit.
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				var v: Vector3 = q[idx]
				var cc := teinte
				if absf((f[0] as Vector3).y) < 0.5 and v.y < 0.0:
					cc = bas
				st.set_color(cc)
				st.set_normal(n.normalized())
				st.add_vertex(t * v)
	# Le dessous n'est jamais vu : il n'existe pas. C'est autant de
	# triangles rendus en moins sur chaque exemplaire.


## Cylindre à pans — tonneaux, troncs, piliers. `pans` bas exprès : les
## facettes SONT le style.
static func _cylindre(st: SurfaceTool, t: Transform3D, r_bas: float,
		r_haut: float, h: float, c: Color, pans := 7,
		couvercle := true) -> void:
	var haut := c.lightened(0.20)
	for i in pans:
		var a0 := TAU * float(i) / pans
		var a1 := TAU * float(i + 1) / pans
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var p00 := Vector3(cos(a0) * r_bas, 0, sin(a0) * r_bas)
		var p01 := Vector3(cos(a1) * r_bas, 0, sin(a1) * r_bas)
		var p10 := Vector3(cos(a0) * r_haut, h, sin(a0) * r_haut)
		var p11 := Vector3(cos(a1) * r_haut, h, sin(a1) * r_haut)
		# Deux pans sur sept plus sombres : le tournage du volume.
		var teinte := c if i % 3 != 0 else c.darkened(0.10)
		for tri in [[p00, p10, p11], [p00, p11, p01]]:
			for v: Vector3 in tri:
				st.set_color(teinte if v.y > 0.01 or true else teinte)
				st.set_normal((t.basis * n).normalized())
				st.add_vertex(t * v)
		if couvercle:
			# Même leçon que le sol : l'ordre (centre, p10, p11) regarde le
			# ciel, l'inverse regardait la terre — et le couvercle de la
			# plateforme disparaissait dès que le culling est revenu.
			for v: Vector3 in [Vector3(0, h, 0), p10, p11]:
				st.set_color(haut)
				st.set_normal((t.basis * Vector3.UP).normalized())
				st.add_vertex(t * v)


## Prisme plat — palmes, ailes, planches inclinées.
static func _lame(st: SurfaceTool, t: Transform3D, long: float,
		large: float, c: Color) -> void:
	var q := [Vector3(0, 0, -large * 0.5), Vector3(long, 0, -large * 0.18),
			Vector3(long, 0, large * 0.18), Vector3(0, 0, large * 0.5)]
	var n := (t.basis * Vector3.UP).normalized()
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for idx in tri:
			st.set_color(c if idx < 2 else c.darkened(0.12))
			st.set_normal(n)
			st.add_vertex(t * (q[idx] as Vector3))
	for tri in [[2, 1, 0], [3, 2, 0]]:
		for idx in tri:
			st.set_color(c.darkened(0.2))
			st.set_normal(-n)
			st.add_vertex(t * (q[idx] as Vector3))


static func _fini(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


# --- LES MODULES ---------------------------------------------------------

## Bloc de mur coloré — LE module le plus posé de la carte. Trois gabarits
## (1 = cube 2 m, 0.5 = demi-hauteur, 2 = double hauteur), une teinte.
static func bloc(teinte: Color, gabarit := 1.0) -> ArrayMesh:
	var cle := "bloc_%s_%.2f" % [teinte.to_html(false), gabarit]
	if _cache.has(cle):
		return _cache[cle]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, gabarit, 0)),
			2.0, gabarit * 2.0, 2.0, teinte, 0.16)
	_cache[cle] = _fini(st)
	return _cache[cle]


## Caisse de bois — plus petite qu'un bloc, deux tons croisés.
static func caisse() -> ArrayMesh:
	if _cache.has("caisse"):
		return _cache["caisse"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)),
			1.1, 1.1, 1.1, BOIS_CLAIR, 0.10)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.0, 0)),
			Vector3(0, 0.55, 0)), 1.16, 0.24, 1.16, BOIS, 0.05)
	_cache["caisse"] = _fini(st)
	return _cache["caisse"]


static func tonneau() -> ArrayMesh:
	if _cache.has("tonneau"):
		return _cache["tonneau"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylindre(st, Transform3D.IDENTITY, 0.42, 0.36, 1.0, BOIS, 8)
	_cylindre(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.30, 0)),
			0.46, 0.46, 0.10, BOIS.darkened(0.3), 8, false)
	_cylindre(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0)),
			0.44, 0.44, 0.10, BOIS.darkened(0.3), 8, false)
	_cache["tonneau"] = _fini(st)
	return _cache["tonneau"]


## Barrière de bois — deux poteaux, deux lisses. Ajourée : on tire
## par-dessus, on ne passe pas au travers.
static func barriere() -> ArrayMesh:
	if _cache.has("barriere"):
		return _cache["barriere"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-1.1, 1.1]:
		_boite(st, Transform3D(Basis.IDENTITY, Vector3(x, 0.55, 0)),
				0.22, 1.1, 0.22, BOIS, 0.05)
	for y in [0.42, 0.86]:
		_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)),
				2.6, 0.16, 0.12, BOIS_CLAIR, 0.04)
	_cache["barriere"] = _fini(st)
	return _cache["barriere"]


## Palmier — tronc penché à trois segments, couronne de six palmes.
static func palmier() -> ArrayMesh:
	if _cache.has("palmier"):
		return _cache["palmier"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos := Vector3.ZERO
	var pente := Vector3(0.16, 1, 0).normalized()
	for s in 3:
		var h := 1.05 - float(s) * 0.12
		var t := Transform3D(Basis.IDENTITY, pos)
		_cylindre(st, t, 0.32 - float(s) * 0.05, 0.26 - float(s) * 0.05,
				h, TRONC if s % 2 == 0 else TRONC.lightened(0.12), 6, s == 2)
		pos += pente * h
	for i in 7:
		var a := TAU * float(i) / 7.0
		var t2 := Transform3D(
				Basis.from_euler(Vector3(0, -a, -0.62 - (0.2 if i % 2 == 0 else 0.0))),
				pos + Vector3(0, 0.05, 0))
		_lame(st, t2, 2.25, 0.95, FEUILLE if i % 2 == 0 else FEUILLE_2)
	# Le cœur de la couronne, pour que le sommet ne soit jamais troué.
	_boite(st, Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.12, 0)),
			0.6, 0.4, 0.6, FEUILLE_2, 0.16)
	_cache["palmier"] = _fini(st)
	return _cache["palmier"]


## Arbre rond — tronc court, deux boules de feuillage facettées.
static func arbre() -> ArrayMesh:
	if _cache.has("arbre"):
		return _cache["arbre"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylindre(st, Transform3D.IDENTITY, 0.3, 0.24, 1.1, TRONC, 6, false)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.4, 0)),
			Vector3(0, 1.9, 0)), 2.5, 1.9, 2.5, FEUILLE, 0.55)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.9, 0)),
			Vector3(0.2, 3.1, -0.15)), 1.6, 1.1, 1.6, FEUILLE_2, 0.42)
	_cache["arbre"] = _fini(st)
	return _cache["arbre"]


static func buisson() -> ArrayMesh:
	if _cache.has("buisson"):
		return _cache["buisson"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.5, 0)),
			Vector3(0, 0.34, 0)), 1.0, 0.7, 1.0, FEUILLE, 0.3)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 1.2, 0)),
			Vector3(0.4, 0.26, 0.3)), 0.7, 0.5, 0.7, FEUILLE_2, 0.24)
	_cache["buisson"] = _fini(st)
	return _cache["buisson"]


static func cactus() -> ArrayMesh:
	if _cache.has("cactus"):
		return _cache["cactus"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylindre(st, Transform3D.IDENTITY, 0.34, 0.30, 2.0, VERT.darkened(0.08), 7)
	for cote in [-1.0, 1.0]:
		_cylindre(st, Transform3D(Basis.IDENTITY,
				Vector3(cote * 0.52, 0.7 + (0.3 if cote > 0 else 0.0), 0)),
				0.17, 0.15, 0.8, VERT, 6)
		_boite(st, Transform3D(Basis.IDENTITY,
				Vector3(cote * 0.52, 0.75, 0)), 0.6, 0.3, 0.3,
				VERT.darkened(0.08), 0.1)
	_cache["cactus"] = _fini(st)
	return _cache["cactus"]


## Touffe fleurie — l'accent jaune du sol de la référence.
static func touffe() -> ArrayMesh:
	if _cache.has("touffe"):
		return _cache["touffe"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var t := Transform3D(Basis.from_euler(Vector3(0.5, -a, 0)),
				Vector3(cos(a) * 0.16, 0.02, sin(a) * 0.16))
		_lame(st, t, 0.5, 0.2, JAUNE if i % 2 == 0 else JAUNE.lightened(0.25))
	_cache["touffe"] = _fini(st)
	return _cache["touffe"]


## Cabane — un seul modèle, murs bois, toit turquoise à deux pans
## débordants. Le toit fait le quartier : on le voit de partout.
static func cabane() -> ArrayMesh:
	if _cache.has("cabane"):
		return _cache["cabane"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)),
			4.2, 2.6, 3.4, BOIS_CLAIR, 0.14)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 1.72)),
			1.2, 2.2, 0.14, BOIS.darkened(0.25), 0.04)
	for cote in [-1.0, 1.0]:
		var t := Transform3D(
				Basis.from_euler(Vector3(cote * 0.62, 0, 0)),
				Vector3(0, 3.15, cote * 0.95))
		_boite(st, t, 4.9, 0.22, 2.4, TOIT, 0.08)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 3.62, 0)),
			4.9, 0.2, 0.5, TOIT.lightened(0.15), 0.06)
	_cache["cabane"] = _fini(st)
	return _cache["cabane"]


## Machine du laboratoire — bloc violet + cuve + accent lumineux.
static func machine() -> ArrayMesh:
	if _cache.has("machine"):
		return _cache["machine"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)),
			2.4, 1.8, 1.8, VIOLET.darkened(0.12), 0.14)
	_cylindre(st, Transform3D(Basis.IDENTITY, Vector3(-0.5, 1.8, 0)),
			0.55, 0.5, 1.1, VIOLET.lightened(0.15), 8)
	_boite(st, Transform3D(Basis.IDENTITY, Vector3(0.7, 1.95, 0)),
			0.5, 0.5, 0.5, EAU_CLAIR, 0.12)
	_cache["machine"] = _fini(st)
	return _cache["machine"]


## Rocher gris — le neutre qui repose l'œil entre deux quartiers colorés.
static func rocher() -> ArrayMesh:
	if _cache.has("rocher"):
		return _cache["rocher"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.35, 0)),
			Vector3(0, 0.55, 0)), 1.8, 1.1, 1.5, PIERRE, 0.4)
	_boite(st, Transform3D(Basis.from_euler(Vector3(0, 0.9, 0)),
			Vector3(0.4, 1.05, -0.2)), 1.0, 0.7, 0.9, PIERRE.lightened(0.1), 0.3)
	_cache["rocher"] = _fini(st)
	return _cache["rocher"]


## Plateforme de l'étoile — disque de pierre à deux marches, huit plots.
static func plateforme() -> ArrayMesh:
	if _cache.has("plateforme"):
		return _cache["plateforme"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylindre(st, Transform3D.IDENTITY, 5.2, 5.0, 0.35, PIERRE, 16)
	_cylindre(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)),
			3.6, 3.4, 0.35, PIERRE.lightened(0.12), 14)
	for i in 8:
		var a := TAU * float(i) / 8.0
		_boite(st, Transform3D(Basis.from_euler(Vector3(0, -a, 0)),
				Vector3(cos(a) * 4.6, 0.85, sin(a) * 4.6)),
				0.5, 1.0, 0.5, BOIS, 0.08)
	_cache["plateforme"] = _fini(st)
	return _cache["plateforme"]


## Pont de planches — franchit l'eau de l'oasis, à plat.
static func pont() -> ArrayMesh:
	if _cache.has("pont"):
		return _cache["pont"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		_boite(st, Transform3D(Basis.IDENTITY,
				Vector3(-1.75 + float(i) * 0.7, 0.16, 0)),
				0.62, 0.14, 2.6, BOIS_CLAIR if i % 2 == 0 else BOIS, 0.04)
	for cote in [-1.0, 1.0]:
		_boite(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.28, cote * 1.2)),
				4.2, 0.12, 0.2, BOIS.darkened(0.15), 0.03)
	_cache["pont"] = _fini(st)
	return _cache["pont"]
