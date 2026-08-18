extends RefCounted
class_name KitDecor
## DÉCORS MODULAIRES — maillages low-poly générés, semés en MultiMesh.
##
## POURQUOI GÉNÉRER PLUTÔT QUE MODÉLISER. Le monde a besoin de rochers,
## d'arbres, de buissons et de palissades par centaines. Les faire produire
## par Meshy coûterait une heure d'attente, des crédits, et donnerait des
## maillages de 2 000 triangles là où 40 suffisent — pour des objets qui
## occupent trente pixels à l'écran sous une caméra en plongée. Des formes
## primitives assemblées donnent le même résultat visuel, instantanément,
## et se règlent par une constante.
##
## LE VRAI SUJET DE CE FICHIER EST LE COÛT DE DESSIN.
##
## À la densité de l'ancienne arène, un monde de 156 m de large demanderait
## près de huit cents maillages individuels, donc autant d'appels de dessin.
## Sur un téléphone, c'est injouable — et c'est le mur sur lequel butent la
## plupart des tentatives d'agrandir une carte.
##
## Un MultiMesh dessine N exemplaires d'un même maillage en UN SEUL appel.
## Toute la variété vient donc de la TRANSFORMATION de chaque exemplaire —
## rotation libre et mise à l'échelle non uniforme — et non de maillages
## différents. Vue de dessus, à trente pixels, personne ne verra jamais que
## tous les rochers sont le même rocher étiré différemment ; en revanche
## tout le monde verrait la différence entre 60 images par seconde et 20.
##
## FACETTES ASSUMÉES. Les primitives sont volontairement grossières — six
## côtés pour une sphère, trois anneaux — parce que le rendu cellulé du jeu
## a besoin de faces PLATES pour accrocher la lumière en aplats. Une sphère
## lisse rendrait un dégradé continu et jurerait avec les personnages.

# --- MAILLAGES -----------------------------------------------------------
#
# Chaque famille est construite une fois et mise en cache : un MultiMesh
# partage un maillage unique, le regénérer par semis serait absurde.
static var _cache: Dictionary = {}


static func maillage(famille: StringName) -> Mesh:
	if _cache.has(famille):
		return _cache[famille]
	var m: Mesh = null
	match famille:
		&"rocher": m = _rocher()
		&"caillou": m = _caillou()
		&"mesa": m = _mesa()
		&"arbre": m = _arbre()
		&"pin": m = _pin()
		&"buisson": m = _buisson()
		&"herbe": m = _touffe()
		&"caisse": m = _caisse()
		&"barricade": m = _barricade()
		&"pilier": m = _pilier()
		&"ruine": m = _ruine()
		&"cloture": m = _cloture()
		&"tente": m = _tente()
		&"tonneau": m = _tonneau()
		&"mur_bas": m = _mur_bas()
		&"bloc": m = _bloc_taille()
		&"cactus": m = _cactus()
		&"cristal": m = _cristal()
		_: m = _caillou()
	_cache[famille] = m
	return m


## Assemble des primitives en un seul maillage.
##
## `pieces` est une liste de { mesh, transform, materiau }. Les pièces qui
## partagent un matériau sont fusionnées en UNE surface : deux surfaces,
## c'est deux appels de dessin par exemplaire, ce qui annulerait tout le
## bénéfice du MultiMesh.
static func _assembler(pieces: Array) -> ArrayMesh:
	var par_materiau: Dictionary = {}
	for p: Dictionary in pieces:
		var mat: Material = p["materiau"]
		var cle := mat.get_instance_id()
		if not par_materiau.has(cle):
			par_materiau[cle] = {"materiau": mat, "pieces": []}
		(par_materiau[cle]["pieces"] as Array).append(p)

	var sortie := ArrayMesh.new()
	for cle in par_materiau:
		var groupe: Dictionary = par_materiau[cle]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p: Dictionary in groupe["pieces"]:
			st.append_from(p["mesh"], 0, p["transform"])
		# Normales RECALCULÉES à plat : les primitives arrivent lissées, et
		# c'est le facettage qui donne le style. Sans cela, un rocher
		# ressemble à un galet mouillé.
		st.generate_normals(false)
		st.set_material(groupe["materiau"])
		st.commit(sortie)
	return sortie


static func _sphere(rayon: float, cotes: int, anneaux: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = rayon
	s.height = rayon * 2.0
	s.radial_segments = cotes
	s.rings = anneaux
	return s


static func _cyl(bas: float, haut: float, hauteur: float, cotes: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bas
	c.top_radius = haut
	c.height = hauteur
	c.radial_segments = cotes
	c.rings = 1
	return c


static func _boite(taille: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = taille
	return b


static func _t(pos: Vector3, rot := Vector3.ZERO,
		echelle := Vector3.ONE) -> Transform3D:
	var base := Basis.from_euler(rot).scaled(echelle)
	return Transform3D(base, pos)


# --- FAMILLES ------------------------------------------------------------
#
# Toutes sont construites À L'ORIGINE ET POSÉES SUR LE SOL (y = 0 au pied) :
# le semis n'a alors qu'à donner une position au sol, sans corriger de
# décalage vertical famille par famille.

static func _rocher() -> ArrayMesh:
	var mat := VisualKit.mat(Cfg.COL_ROCHE, 0.0, 0.95)
	var mat_clair := VisualKit.mat(Cfg.COL_ROCHE.lightened(0.16), 0.0, 0.95)
	return _assembler([
		{"mesh": _sphere(1.0, 6, 2), "materiau": mat,
			"transform": _t(Vector3(0, 0.62, 0), Vector3(0, 0.4, 0.12),
					Vector3(1.0, 0.72, 0.86))},
		{"mesh": _sphere(1.0, 5, 2), "materiau": mat_clair,
			"transform": _t(Vector3(0.42, 0.34, -0.3), Vector3(0, 1.1, 0),
					Vector3(0.52, 0.44, 0.5))},
	])


static func _caillou() -> ArrayMesh:
	var mat := VisualKit.mat(Cfg.COL_ROCHE.darkened(0.08), 0.0, 0.95)
	return _assembler([
		{"mesh": _sphere(1.0, 5, 2), "materiau": mat,
			"transform": _t(Vector3(0, 0.26, 0), Vector3(0.2, 0.6, 0),
					Vector3(0.5, 0.3, 0.42))},
	])


## MESA — la falaise du canyon. Un tronc de cône à six côtés : la légère
## conicité suffit à lire « érodé » là où un prisme droit lirait « boîte ».
static func _mesa() -> ArrayMesh:
	var mat := VisualKit.mat(Cfg.COL_ROCHE_CHAUDE, 0.0, 0.96)
	var mat_haut := VisualKit.mat(Cfg.COL_ROCHE_CHAUDE.lightened(0.2), 0.0, 0.96)
	return _assembler([
		{"mesh": _cyl(1.15, 0.9, 4.0, 6), "materiau": mat,
			"transform": _t(Vector3(0, 2.0, 0))},
		# Strate plus claire : une seule bande horizontale suffit à donner
		# une échelle à la roche, donc à dire au joueur qu'elle est haute.
		{"mesh": _cyl(1.02, 0.98, 0.42, 6), "materiau": mat_haut,
			"transform": _t(Vector3(0, 2.7, 0))},
	])


static func _arbre() -> ArrayMesh:
	var bois := VisualKit.mat(Cfg.COL_BOIS, 0.0, 0.9)
	var feuille := VisualKit.mat(Cfg.COL_FEUILLAGE, 0.0, 0.88)
	return _assembler([
		{"mesh": _cyl(0.22, 0.16, 1.9, 5), "materiau": bois,
			"transform": _t(Vector3(0, 0.95, 0))},
		{"mesh": _sphere(1.0, 6, 3), "materiau": feuille,
			"transform": _t(Vector3(0, 2.5, 0), Vector3.ZERO,
					Vector3(1.25, 0.95, 1.25))},
		{"mesh": _sphere(1.0, 5, 2), "materiau": feuille,
			"transform": _t(Vector3(0.5, 2.0, 0.25), Vector3.ZERO,
					Vector3(0.7, 0.6, 0.7))},
	])


static func _pin() -> ArrayMesh:
	var bois := VisualKit.mat(Cfg.COL_BOIS.darkened(0.12), 0.0, 0.9)
	var feuille := VisualKit.mat(Cfg.COL_FEUILLAGE.darkened(0.14), 0.0, 0.88)
	# Trois cônes empilés : la silhouette la plus reconnaissable du monde
	# pour une dizaine de triangles.
	return _assembler([
		{"mesh": _cyl(0.2, 0.14, 1.2, 5), "materiau": bois,
			"transform": _t(Vector3(0, 0.6, 0))},
		{"mesh": _cyl(1.1, 0.0, 1.5, 6), "materiau": feuille,
			"transform": _t(Vector3(0, 1.7, 0))},
		{"mesh": _cyl(0.85, 0.0, 1.3, 6), "materiau": feuille,
			"transform": _t(Vector3(0, 2.6, 0))},
		{"mesh": _cyl(0.55, 0.0, 1.1, 6), "materiau": feuille,
			"transform": _t(Vector3(0, 3.4, 0))},
	])


static func _buisson() -> ArrayMesh:
	var feuille := VisualKit.mat(Cfg.COL_FEUILLAGE.lightened(0.08), 0.0, 0.9)
	return _assembler([
		{"mesh": _sphere(1.0, 6, 2), "materiau": feuille,
			"transform": _t(Vector3(0, 0.42, 0), Vector3.ZERO,
					Vector3(0.8, 0.5, 0.8))},
		{"mesh": _sphere(1.0, 5, 2), "materiau": feuille,
			"transform": _t(Vector3(0.42, 0.3, 0.16), Vector3.ZERO,
					Vector3(0.5, 0.36, 0.5))},
	])


static func _touffe() -> ArrayMesh:
	var h := VisualKit.mat(Cfg.COL_FEUILLAGE.lightened(0.22), 0.0, 0.95)
	var pieces: Array = []
	for i in 3:
		var a := TAU * float(i) / 3.0
		pieces.append({"mesh": _cyl(0.09, 0.0, 0.5, 3), "materiau": h,
			"transform": _t(Vector3(cos(a) * 0.14, 0.25, sin(a) * 0.14),
					Vector3(0.2 * cos(a), a, 0.2 * sin(a)))})
	return _assembler(pieces)


static func _caisse() -> ArrayMesh:
	var bois := VisualKit.mat(Cfg.COL_BOIS.lightened(0.1), 0.0, 0.85)
	var cercle := VisualKit.mat(Cfg.COL_METAL, 0.0, 0.7)
	return _assembler([
		{"mesh": _boite(Vector3(0.9, 0.9, 0.9)), "materiau": bois,
			"transform": _t(Vector3(0, 0.45, 0))},
		{"mesh": _boite(Vector3(0.96, 0.12, 0.96)), "materiau": cercle,
			"transform": _t(Vector3(0, 0.72, 0))},
	])


static func _barricade() -> ArrayMesh:
	var bois := VisualKit.mat(Cfg.COL_BOIS, 0.0, 0.9)
	return _assembler([
		{"mesh": _boite(Vector3(2.4, 0.22, 0.18)), "materiau": bois,
			"transform": _t(Vector3(0, 0.85, 0), Vector3(0, 0, 0.14))},
		{"mesh": _boite(Vector3(2.4, 0.22, 0.18)), "materiau": bois,
			"transform": _t(Vector3(0, 0.45, 0), Vector3(0, 0, -0.1))},
		{"mesh": _boite(Vector3(0.2, 1.2, 0.2)), "materiau": bois,
			"transform": _t(Vector3(-1.0, 0.6, 0))},
		{"mesh": _boite(Vector3(0.2, 1.2, 0.2)), "materiau": bois,
			"transform": _t(Vector3(1.0, 0.6, 0))},
	])


static func _pilier() -> ArrayMesh:
	var pierre := VisualKit.mat(Cfg.COL_PIERRE, 0.0, 0.94)
	return _assembler([
		{"mesh": _cyl(0.45, 0.45, 0.3, 8), "materiau": pierre,
			"transform": _t(Vector3(0, 0.15, 0))},
		{"mesh": _cyl(0.33, 0.3, 3.2, 8), "materiau": pierre,
			"transform": _t(Vector3(0, 1.75, 0))},
		{"mesh": _cyl(0.44, 0.44, 0.28, 8), "materiau": pierre,
			"transform": _t(Vector3(0, 3.45, 0))},
	])


## RUINE — un pan de mur ébréché. L'entaille est faite par un bloc DÉCALÉ
## plutôt que par une soustraction : le résultat se lit pareil de loin, et
## coûte deux boîtes au lieu d'une géométrie booléenne.
static func _ruine() -> ArrayMesh:
	var pierre := VisualKit.mat(Cfg.COL_PIERRE.darkened(0.06), 0.0, 0.94)
	return _assembler([
		{"mesh": _boite(Vector3(3.2, 1.9, 0.5)), "materiau": pierre,
			"transform": _t(Vector3(0, 0.95, 0))},
		{"mesh": _boite(Vector3(1.3, 1.0, 0.5)), "materiau": pierre,
			"transform": _t(Vector3(-0.9, 2.3, 0))},
		{"mesh": _boite(Vector3(0.7, 0.6, 0.5)), "materiau": pierre,
			"transform": _t(Vector3(1.2, 2.1, 0), Vector3(0, 0, 0.18))},
	])


static func _cloture() -> ArrayMesh:
	var bois := VisualKit.mat(Cfg.COL_BOIS.darkened(0.1), 0.0, 0.9)
	var pieces: Array = []
	for i in 3:
		pieces.append({"mesh": _boite(Vector3(0.14, 1.1, 0.14)),
			"materiau": bois,
			"transform": _t(Vector3(-1.2 + 1.2 * float(i), 0.55, 0))})
	pieces.append({"mesh": _boite(Vector3(2.7, 0.14, 0.1)), "materiau": bois,
		"transform": _t(Vector3(0, 0.9, 0))})
	pieces.append({"mesh": _boite(Vector3(2.7, 0.14, 0.1)), "materiau": bois,
		"transform": _t(Vector3(0, 0.5, 0))})
	return _assembler(pieces)


static func _tente() -> ArrayMesh:
	var toile := VisualKit.mat(Cfg.COL_TOILE, 0.0, 0.92)
	var bois := VisualKit.mat(Cfg.COL_BOIS, 0.0, 0.9)
	return _assembler([
		{"mesh": _cyl(1.5, 0.0, 1.9, 4), "materiau": toile,
			"transform": _t(Vector3(0, 0.95, 0), Vector3(0, PI * 0.25, 0))},
		{"mesh": _boite(Vector3(0.12, 2.3, 0.12)), "materiau": bois,
			"transform": _t(Vector3(0, 1.15, 0))},
	])


static func _tonneau() -> ArrayMesh:
	var metal := VisualKit.mat(Cfg.COL_METAL.lightened(0.1), 0.0, 0.62)
	var bande := VisualKit.mat(Cfg.COL_KAEL_ACCENT, 0.0, 0.6)
	return _assembler([
		{"mesh": _cyl(0.4, 0.4, 1.1, 8), "materiau": metal,
			"transform": _t(Vector3(0, 0.55, 0))},
		{"mesh": _cyl(0.42, 0.42, 0.16, 8), "materiau": bande,
			"transform": _t(Vector3(0, 0.78, 0))},
	])


# --- SEMIS ---------------------------------------------------------------

## Crée un MultiMesh peuplé. UN SEUL APPEL DE DESSIN pour tout le tas.
##
## `transformations` porte déjà la position, la rotation et l'échelle de
## chaque exemplaire : c'est là que vit toute la variété visuelle.
##
## `portee` active l'atténuation par la distance. C'est la « gestion simple
## des distances » : une propriété native de Godot, aucun gestionnaire à
## écrire, aucune liste à tenir à jour. Les props de garniture disparaissent
## au loin ; les repères, eux, ne doivent JAMAIS s'effacer — c'est
## précisément à distance qu'ils servent.
static func semer(famille: StringName, transformations: Array[Transform3D],
		portee: float = 0.0, ombres: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = maillage(famille)
	mm.instance_count = transformations.size()
	for i in transformations.size():
		mm.set_instance_transform(i, transformations[i])

	var noeud := MultiMeshInstance3D.new()
	noeud.multimesh = mm
	noeud.name = "Semis_%s" % famille
	noeud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if ombres else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if portee > 0.0:
		noeud.visibility_range_end = portee
		noeud.visibility_range_end_margin = portee * 0.15
		noeud.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return noeud


# --- ZONE D'ESSAI : LES RUINES ENSOLEILLÉES ------------------------------
#
# QUATRE FAMILLES AJOUTÉES, ET LE CHOIX EST UN CHOIX DE LISIBILITÉ.
#
# Les ruines étaient une forêt de colonnes pâles de trois mètres et demi,
# toutes de la même teinte que le sol — vérifié en capture. Elles
# attiraient l'œil davantage que le personnage, et masquaient les combats.
#
# Ce qui les remplace est BAS : un pan de mur à hauteur de poitrine, un
# bloc tombé, quelques cactus. On peut se mettre à couvert derrière, on ne
# perd jamais l'action de vue par-dessus. Les colonnes restent, mais rares :
# elles ne servent plus qu'à s'orienter.


## MUR BAS — le couvert principal des ruines.
##
## Il monte à 1,2 m : assez pour cacher un personnage accroupi et arrêter
## un tir tendu, jamais assez pour boucher la vue depuis la caméra. La
## crête claire est ce qui le détache du sable qui l'entoure — sans elle,
## une pierre chaude sur un sol chaud disparaît.
static func _mur_bas() -> ArrayMesh:
	var pierre := VisualKit.mat(Cfg.COL_PIERRE_CHAUDE, 0.0, 0.93)
	var crete := VisualKit.mat(Cfg.COL_PIERRE_CRETE, 0.0, 0.92)
	return _assembler([
		{"mesh": _boite(Vector3(2.6, 1.1, 0.62)), "materiau": pierre,
			"transform": _t(Vector3(0, 0.55, 0))},
		{"mesh": _boite(Vector3(2.7, 0.16, 0.72)), "materiau": crete,
			"transform": _t(Vector3(0, 1.14, 0))},
		# Un bout écroulé à une extrémité : une ruine régulière se lit
		# comme un muret de jardin.
		{"mesh": _boite(Vector3(0.7, 0.55, 0.6)), "materiau": pierre,
			"transform": _t(Vector3(1.5, 0.28, 0.05), Vector3(0, 0.3, 0.14))},
	])


## BLOC TAILLÉ — une pierre tombée, à hauteur de genou.
static func _bloc_taille() -> ArrayMesh:
	var pierre := VisualKit.mat(Cfg.COL_PIERRE_CHAUDE.darkened(0.07), 0.0, 0.94)
	var crete := VisualKit.mat(Cfg.COL_PIERRE_CRETE, 0.0, 0.93)
	return _assembler([
		{"mesh": _boite(Vector3(1.1, 0.62, 0.9)), "materiau": pierre,
			"transform": _t(Vector3(0, 0.31, 0), Vector3(0, 0.4, 0))},
		{"mesh": _boite(Vector3(0.95, 0.12, 0.78)), "materiau": crete,
			"transform": _t(Vector3(0, 0.66, 0), Vector3(0, 0.4, 0))},
		{"mesh": _boite(Vector3(0.5, 0.34, 0.46)), "materiau": pierre,
			"transform": _t(Vector3(0.62, 0.17, 0.3), Vector3(0, -0.5, 0.1))},
	])


## CACTUS — la note verte du secteur, et sa seule verticale vivante.
##
## Petit et étroit : il colore sans encombrer. La fleur au sommet est un
## point rose de quelques pixels — c'est exactement le rôle qu'on lui
## demande, un accent, pas une masse.
static func _cactus() -> ArrayMesh:
	var vert := VisualKit.mat(Cfg.COL_CACTUS, 0.0, 0.9)
	var vert_clair := VisualKit.mat(Cfg.COL_CACTUS_CLAIR, 0.0, 0.9)
	var fleur := VisualKit.mat(Cfg.COL_FLEUR, 0.35, 0.85)
	return _assembler([
		{"mesh": _cyl(0.19, 0.15, 1.35, 7), "materiau": vert,
			"transform": _t(Vector3(0, 0.68, 0))},
		{"mesh": _cyl(0.11, 0.09, 0.6, 6), "materiau": vert_clair,
			"transform": _t(Vector3(0.26, 0.85, 0), Vector3(0, 0, -0.5))},
		{"mesh": _cyl(0.1, 0.08, 0.5, 6), "materiau": vert_clair,
			"transform": _t(Vector3(-0.24, 0.66, 0.05), Vector3(0, 0, 0.55))},
		{"mesh": _sphere(0.11, 7, 5), "materiau": fleur,
			"transform": _t(Vector3(0, 1.4, 0))},
	])


## CRISTAL — l'accent froid et lumineux, posé à la douzaine sur tout le
## secteur.
##
## Il est ÉMISSIF et non éclairant : il brille sur lui-même sans ajouter la
## moindre lumière dynamique, donc sans rien coûter au rendu mobile. C'est
## ce qui permet d'avoir des points lumineux dans un jeu qui doit tenir sur
## un téléphone.
static func _cristal() -> ArrayMesh:
	var vif := VisualKit.mat(Cfg.COL_CRISTAL, 1.6, 0.35)
	var sombre := VisualKit.mat(Cfg.COL_CRISTAL.darkened(0.45), 0.5, 0.5)
	return _assembler([
		{"mesh": _cyl(0.0, 0.16, 0.82, 5), "materiau": vif,
			"transform": _t(Vector3(0, 0.41, 0), Vector3(0.1, 0.4, 0.06))},
		{"mesh": _cyl(0.0, 0.1, 0.5, 5), "materiau": vif,
			"transform": _t(Vector3(0.18, 0.25, 0.1), Vector3(0.2, 1.0, 0.35))},
		{"mesh": _cyl(0.22, 0.22, 0.12, 6), "materiau": sombre,
			"transform": _t(Vector3(0, 0.06, 0))},
	])
