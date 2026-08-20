extends RefCounted
class_name KitWestern
## FOURNISSEUR DU KIT WESTERN — pose un modèle Meshy à la bonne taille,
## socle enterré, ou rend un volume de secours si le modèle manque.
##
## ─── LE PROBLÈME DU SOCLE, ET POURQUOI IL FALLAIT LE MESURER ───────────
##
## La planche de référence pose chaque objet sur un petit disque de sable.
## Le mode image de Meshy n'accepte qu'une image et une invite de TEXTURE,
## jamais une consigne de forme : impossible de lui interdire ce socle. Il
## est donc venu avec, et il DOMINE l'objet — mesuré : une botte de foin
## fait 3,50 m de large pour 0,95 de haut, une formation 10,60 m. Une botte
## de foin de trois mètres cinquante n'est pas une botte de foin.
##
## La bonne nouvelle est que le socle est PLAT et EN BAS. Enfoncé sous le
## sol, il disparaît, et sa largeur cesse de compter. Encore faut-il savoir
## de combien l'enfoncer : trop peu et une galette de sable dépasse autour
## de chaque caisse, trop et l'objet s'enterre.
##
## ON LE MESURE DONC, modèle par modèle, plutôt que de choisir un nombre au
## jugé. Le socle se reconnaît à une chose : il est BEAUCOUP PLUS LARGE que
## ce qui le surmonte. On découpe la hauteur en tranches, on mesure
## l'emprise au sol de chacune, et le socle finit là où l'emprise s'effondre.

const DOSSIER := "res://assets/models/"
## Nombre de tranches horizontales pour l'analyse du socle.
const TRANCHES := 24
## Sous cette fraction de l'emprise maximale, on n'est plus dans le socle.
const SEUIL_SOCLE := 0.62

static var _cache: Dictionary = {}


## Le modèle existe-t-il ?
## Largeur utile d'une pièce ramenée à `hauteur` — socle exclu. Sert aux
## bancs et au dimensionnement des collisions.
static func largeur_pour_hauteur(nom: StringName, hauteur: float) -> float:
	var chemin := DOSSIER + String(nom) + ".glb"
	if not ResourceLoader.exists(chemin):
		return 0.0
	var m := (load(chemin) as PackedScene).instantiate() as Node3D
	var r := _mesurer(nom, m)
	var u: AABB = r["utile"]
	m.free()
	return maxf(u.size.x, u.size.z) * (hauteur / maxf(u.size.y, 0.0001))


static func disponible(nom: StringName) -> bool:
	return ResourceLoader.exists(DOSSIER + String(nom) + ".glb")


## Instancie une pièce, ramenée à `hauteur` mètres AU-DESSUS DU SOCLE, et
## posée de sorte que le socle passe sous le sol.
##
## `hauteur` est donc la hauteur UTILE — celle qui compte pour le jeu, pas
## celle du fichier. C'est ce qui permet d'écrire « une caisse de 0,9 m »
## dans le plan et d'obtenir une caisse de 0,9 m à l'écran, quel que soit
## ce que Meshy a mis autour.
## `taille` est le VOLUME que la pièce doit occuper, en mètres. Le modèle
## y est ramené À L'INTÉRIEUR — jamais au-delà — par le plus petit des
## trois rapports, exactement comme le mobilier de l'Esplanade.
##
## POURQUOI PAR LE VOLUME ET NON PAR LA HAUTEUR. Ajuster sur la hauteur
## laissait l'emprise au sol libre de grandir : une botte de foin ramenée à
## 0,95 m de haut mesurait près de trois mètres de large, parce que le
## modèle est trapu. Or c'est l'EMPRISE qui décide de la circulation et de
## la collision — la contrainte doit donc porter là. Une pièce un peu plus
## basse que prévu ne gêne personne ; une pièce deux fois trop large ferme
## un passage validé au greybox.
static func instancier(nom: StringName, taille: Vector3) -> Node3D:
	var chemin := DOSSIER + String(nom) + ".glb"
	if not ResourceLoader.exists(chemin):
		return null
	var sc := load(chemin) as PackedScene
	if sc == null:
		return null
	var m := sc.instantiate() as Node3D
	if m == null:
		return null

	var mesure := _mesurer(nom, m)
	var boite: AABB = mesure["boite"]
	var socle: float = mesure["socle"]
	var utile: AABB = mesure["utile"]
	var f: float = minf(minf(taille.x / maxf(utile.size.x, 0.0001),
			taille.y / maxf(utile.size.y, 0.0001)),
			taille.z / maxf(utile.size.z, 0.0001))
	# ON ESSAIE AUSSI LE QUART DE TOUR. Meshy choisit librement
	# l'orientation : une barrière peut arriver en travers. Sans ce test,
	# le rapport le plus petit devient celui de la longueur contre la
	# largeur, et un élément long se réduit à un cube.
	var f_tourne: float = minf(minf(taille.x / maxf(utile.size.z, 0.0001),
			taille.y / maxf(utile.size.y, 0.0001)),
			taille.z / maxf(utile.size.x, 0.0001))
	var quart := f_tourne > f
	if quart:
		f = f_tourne
	m.scale = Vector3.ONE * f

	# ON CENTRE SUR L'OBJET, PAS SUR LE MODÈLE. Le disque de sable est
	# rarement centré sous ce qu'il porte ; se recaler dessus décalerait
	# chaque pièce de quelques dizaines de centimètres par rapport à sa
	# collision — et un joueur se cognerait à côté de la caisse.
	var centre := utile.get_center() * f
	m.position = Vector3(-centre.x, -(boite.position.y + socle) * f, -centre.z)

	var pivot := Node3D.new()
	var orienteur := Node3D.new()
	orienteur.rotation.y = PI * 0.5 if quart else 0.0
	pivot.add_child(orienteur)
	orienteur.add_child(m)
	return pivot


## Épaisseur du socle et boîte englobante, mesurées une fois par modèle.
static func _mesurer(nom: StringName, m: Node3D) -> Dictionary:
	if _cache.has(nom):
		return _cache[nom]

	var sommets := PackedVector3Array()
	_recolter(m, Transform3D.IDENTITY, sommets)
	if sommets.is_empty():
		var vide := {"boite": AABB(), "socle": 0.0}
		_cache[nom] = vide
		return vide

	var boite := AABB(sommets[0], Vector3.ZERO)
	for v in sommets:
		boite = boite.expand(v)

	# Emprise au sol de chaque tranche horizontale.
	var h := maxf(boite.size.y, 0.0001)
	var mini := PackedFloat32Array()
	var maxi := PackedFloat32Array()
	mini.resize(TRANCHES)
	maxi.resize(TRANCHES)
	for i in TRANCHES:
		mini[i] = INF
		maxi[i] = -INF
	var mnz := PackedFloat32Array()
	var mxz := PackedFloat32Array()
	mnz.resize(TRANCHES)
	mxz.resize(TRANCHES)
	for i in TRANCHES:
		mnz[i] = INF
		mxz[i] = -INF
	for v in sommets:
		var t := clampi(int((v.y - boite.position.y) / h * float(TRANCHES)),
				0, TRANCHES - 1)
		mini[t] = minf(mini[t], v.x)
		maxi[t] = maxf(maxi[t], v.x)
		mnz[t] = minf(mnz[t], v.z)
		mxz[t] = maxf(mxz[t], v.z)

	var emprises := PackedFloat32Array()
	emprises.resize(TRANCHES)
	var plus_large := 0.0
	for i in TRANCHES:
		var e := 0.0
		if maxi[i] > mini[i]:
			e = maxf(maxi[i] - mini[i], mxz[i] - mnz[i])
		emprises[i] = e
		plus_large = maxf(plus_large, e)

	# LE SOCLE FINIT LÀ OÙ L'EMPRISE S'EFFONDRE. On part du bas et l'on
	# monte tant que la tranche reste large. Si aucune ne s'effondre —
	# c'est le cas d'un rocher, large de haut en bas — il n'y a pas de
	# socle à enterrer, et la mesure rend zéro.
	var socle := 0.0
	for i in TRANCHES:
		if emprises[i] < plus_large * SEUIL_SOCLE:
			socle = float(i) / float(TRANCHES) * h
			break
	# GARDE-FOU : un socle de plus d'un tiers de la pièce n'est plus un
	# socle, c'est l'objet. Mieux vaut ne rien enterrer que de faire
	# disparaître la moitié d'un chariot.
	if socle > h * 0.34:
		socle = 0.0

	# LA BOÎTE DE L'OBJET, SOCLE EXCLU.
	#
	# La boîte englobante totale inclut le disque de sable, qui déborde de
	# tous les côtés : s'y fier donnait une botte de foin de trois mètres
	# cinquante de large. Ce qu'on veut connaître, c'est l'objet — donc la
	# boîte des seuls sommets qui SURMONTENT le socle.
	var seuil := boite.position.y + socle
	var utile := AABB()
	var premier := true
	for v in sommets:
		if v.y < seuil:
			continue
		if premier:
			utile = AABB(v, Vector3.ZERO)
			premier = false
		else:
			utile = utile.expand(v)
	if premier:
		utile = boite

	var r := {"boite": boite, "socle": socle, "utile": utile}
	_cache[nom] = r
	return r


static func _recolter(n: Node, t: Transform3D, out: PackedVector3Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				out.append(t * v)
	for e in n.get_children():
		var st := t
		var e3 := e as Node3D
		if e3 != null:
			st = t * e3.transform
		_recolter(e, st, out)
