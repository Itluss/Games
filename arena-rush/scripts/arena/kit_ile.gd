extends RefCounted
class_name KitIle
## FOURNISSEUR DU KIT DE L'ÎLE — les assets Meshy générés depuis la
## planche, mesurés, remis à l'échelle, socle enterré, et livrés en
## MAILLE pour les lots MultiMesh.
##
## Descendant direct du KitWestern supprimé avec l'ancienne carte : la
## machinerie de mesure du socle est la sienne, éprouvée sur douze
## modèles. Ce qui change : au lieu de rendre un NŒUD prêt à poser, il
## rend la MAILLE et sa TRANSFORMÉE CORRECTIVE — échelle et enfouissement
## — pour que le bâtisseur garde son architecture en lots : un appel de
## dessin par modèle, quelle que soit la quantité posée.
##
## ─── LE PROBLÈME DU SOCLE ──────────────────────────────────────────────
##
## Le mode image de Meshy n'accepte qu'une image : impossible de lui
## interdire structurellement le socle de terrain, seulement de le lui
## déconseiller. Quand il vient quand même, il est PLAT et EN BAS :
## enfoncé sous le sol, il disparaît. On le mesure modèle par modèle —
## le socle se reconnaît à ce qu'il est BEAUCOUP PLUS LARGE que ce qui le
## surmonte — plutôt que de choisir un enfouissement au jugé.

## Les glb Meshy BRUTS (5 à 8 Mo pièce, quatre cartes 2048² chacun) ne
## sont plus chargés en jeu : l'atelier outils_dev/preparer_kit_ile.gd
## les presse une fois pour toutes en ressources compactes — la maille et
## un matériau couleur 512 px — et c'est CE dossier que le jeu lit. Les
## sources restent dans assets/models/, exclues de l'export.
const DOSSIER := "res://assets/kit_ile/"
## Dossier des glb sources, pour les outils d'atelier uniquement.
const DOSSIER_SOURCES := "res://assets/models/"

## ─── LA LISTE D'APPROBATION ────────────────────────────────────────────
##
## Un asset généré n'entre PAS dans la carte du seul fait qu'il existe :
## il entre quand il a passé le contrôle qualité — rendu individuel,
## inspection des bords, de la silhouette et de la texture. Consigne
## explicite : un asset aux bords coupés ou de mauvaise qualité ne se
## pose pas ; son module procédural le remplace en attendant une
## regénération. Cette liste est donc VIDE tant que le lot n'a pas été
## inspecté, et ne grandit qu'asset par asset, après examen.
## Lot n° 1, inspecté le 21/08 sur planche de contrôle : sept entrent,
## huit restent dehors — les trois cubes de mur sont revenus en DOUBLES
## 1×2 (posés sur des cellules de 2 m, ils déborderaient d'un mètre dans
## les rues), la cabane et le puits n'ont livré que leur toit, le
## palmier a perdu son tronc, la plateforme n'a rendu que l'étoile, le
## tonneau est un pot sombre.
## Lot n° 2 (reprises), même contrôle : seul le tonneau (mode texte)
## entre. Le bloc violet semblait enfin être UN cube — posé en
## situation, c'était un GOLEM PORTANT le cube, le porteur caché
## derrière le cube sous l'angle unique de l'aperçu : recalé, et
## leçon retenue — le contrôle se fait aussi EN SITUATION. Cubes rouge
## et vert encore doublés, cabane et puits encore réduits à leur toit,
## palmier encore sans tronc — tous repartis en mode TEXTE, la voie qui
## a réussi au tonneau.
const APPROUVES: Array[StringName] = [
	&"ile_barriere", &"ile_caisse", &"ile_cactus", &"ile_buisson",
	&"ile_fleurs", &"ile_tour", &"ile_bloc_jaune", &"ile_tonneau",
]
## Nombre de tranches horizontales pour l'analyse du socle.
const TRANCHES := 24
## Sous cette fraction de l'emprise maximale, on n'est plus dans le socle.
const SEUIL_SOCLE := 0.62

## nom → {"maille": Mesh, "transfo": Transform3D} ou null si absent.
static var _cache: Dictionary = {}


static func disponible(nom: StringName) -> bool:
	return ResourceLoader.exists(DOSSIER + String(nom) + ".res")


## La maille du modèle, remise à `hauteur` mètres UTILES (socle exclu),
## recentrée sur l'objet, socle sous le sol. Rend null si le fichier
## manque — l'appelant retombe alors sur le module procédural, et la
## carte reste jouable pendant que le lot Meshy se génère.
static func maille(nom: StringName, hauteur: float) -> Variant:
	if nom not in APPROUVES:
		return null
	var cle := "%s_%.2f" % [nom, hauteur]
	if _cache.has(cle):
		return _cache[cle]
	var chemin := DOSSIER + String(nom) + ".res"
	if not ResourceLoader.exists(chemin):
		_cache[cle] = null
		return null
	# La ressource pressée est la MAILLE elle-même, transformée locale
	# déjà cuite : plus de scène à instancier ni de nœuds à parcourir.
	var maille_mesh := load(chemin) as Mesh
	if maille_mesh == null:
		_cache[cle] = null
		return null

	# La mesure du socle parcourt les sommets : une milliseconde par
	# modèle — c'est le chargement des glb bruts qui coûtait cher, pas
	# elle. Sur la ressource pressée, elle reste à demeure.
	var mesure := _mesurer(maille_mesh, Transform3D.IDENTITY)
	var boite: AABB = mesure["boite"]
	var socle: float = mesure["socle"]
	var utile: AABB = mesure["utile"]

	var f: float = hauteur / maxf(utile.size.y, 0.0001)
	var centre := utile.get_center() * f
	# ON N'ENTERRE PAS À MOITIÉ : sous cinq centimètres, on remonte à
	# cinq — la leçon des tonneaux western, posés à un dixième de
	# millimètre du plan du sol.
	var enfoui := socle * f
	if enfoui > 0.0:
		enfoui = maxf(enfoui, 0.05)
	var transfo := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * f),
			Vector3(-centre.x,
					-boite.position.y * f - enfoui,
					-centre.z))
	var r := {"maille": maille_mesh, "transfo": transfo}
	_cache[cle] = r
	return r


static func _premiere_maille(n: Node) -> MeshInstance3D:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		return mi
	for e in n.get_children():
		var t := _premiere_maille(e)
		if t != null:
			return t
	return null


static func _transfo_locale(mi: Node3D, racine: Node3D) -> Transform3D:
	var t := mi.transform
	var p := mi.get_parent()
	while p != null and p != racine:
		var p3 := p as Node3D
		if p3 != null:
			t = p3.transform * t
		p = p.get_parent()
	return t


## Boîte englobante, épaisseur du socle et boîte UTILE (socle exclu),
## mesurées sur les sommets — la méthode éprouvée du KitWestern.
static func _mesurer(m: Mesh, locale: Transform3D) -> Dictionary:
	var sommets := PackedVector3Array()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in vs:
			sommets.append(locale * v)
	if sommets.is_empty():
		return {"boite": AABB(), "socle": 0.0, "utile": AABB()}

	var boite := AABB(sommets[0], Vector3.ZERO)
	for v in sommets:
		boite = boite.expand(v)

	var h := maxf(boite.size.y, 0.0001)
	var mnx := PackedFloat32Array()
	var mxx := PackedFloat32Array()
	var mnz := PackedFloat32Array()
	var mxz := PackedFloat32Array()
	for tab in [mnx, mnz]:
		tab.resize(TRANCHES)
		tab.fill(INF)
	for tab in [mxx, mxz]:
		tab.resize(TRANCHES)
		tab.fill(-INF)
	for v in sommets:
		var t := clampi(int((v.y - boite.position.y) / h * float(TRANCHES)),
				0, TRANCHES - 1)
		mnx[t] = minf(mnx[t], v.x)
		mxx[t] = maxf(mxx[t], v.x)
		mnz[t] = minf(mnz[t], v.z)
		mxz[t] = maxf(mxz[t], v.z)

	var plus_large := 0.0
	var emprises := PackedFloat32Array()
	emprises.resize(TRANCHES)
	for i in TRANCHES:
		var e := 0.0
		if mxx[i] > mnx[i]:
			e = maxf(mxx[i] - mnx[i], mxz[i] - mnz[i])
		emprises[i] = e
		plus_large = maxf(plus_large, e)

	# Le socle finit là où l'emprise s'effondre ; plus d'un tiers de la
	# hauteur, ce n'est plus un socle, c'est l'objet.
	var socle := 0.0
	for i in TRANCHES:
		if emprises[i] < plus_large * SEUIL_SOCLE:
			socle = float(i) / float(TRANCHES) * h
			break
	if socle > h * 0.34:
		socle = 0.0

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
	return {"boite": boite, "socle": socle, "utile": utile}
