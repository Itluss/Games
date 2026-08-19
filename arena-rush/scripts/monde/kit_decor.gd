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
		# LE VOCABULAIRE DE LA PLANCHE, ET RIEN D'AUTRE.
		#
		# Les familles d'avant venaient de cinq mondes qui se contredisaient :
		# pins et arbres du bosquet, tentes du camp, tonneaux de la fonderie,
		# mesas du canyon. Un seul biome veut un seul vocabulaire, et c'est
		# la planche qui le donne : pierre crème biseautée, métal cobalt,
		# cristaux d'énergie, végétation stylisée.
		&"dalle": m = _dalle()
		&"mur_bas": m = _mur_bas()
		&"pilier": m = _pilier_brise()
		&"bloc": m = _bloc_taille()
		&"caisse": m = _caisse_techno()
		&"cristal": m = _cristal()
		&"cristal_grand": m = _cristal_grand()
		&"plante": m = _plante_desert()
		&"cactus": m = _plante_desert()
		&"caillou": m = _caillou()
		&"rocher": m = _rocher()
		&"gravier": m = _gravier()
		&"arche_basse": m = _arche_basse()
		&"borne": m = _borne()
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

# --- LES FORMES DES RUINES SOLAIRES ---------------------------------------
#
# TROIS MATIÈRES, PAS UNE DE PLUS, et c'est ce qui fera l'unité de la carte.
#
#   PIERRE CRÈME    la maçonnerie ancienne, claire et chaude. Deux valeurs
#                   — pleine et ombrée — suffisent à faire lire un biseau.
#   MÉTAL COBALT    l'œuvre des anciens. Bleu profond, cerclé d'or. C'est
#                   lui qui empêche le désert de virer au monochrome sépia,
#                   et c'est le complémentaire du sable : posé dessus, il
#                   saute aux yeux sans effort.
#   ÉNERGIE         turquoise émissif. Jamais éclairant, toujours brillant.
#
# LE BISEAU EST LA SIGNATURE. La planche montre des arêtes cassées, pas des
# angles vifs : chaque volume porte donc un chapeau légèrement plus petit
# et une base légèrement plus large. Deux boîtes au lieu d'une, et la
# pierre cesse d'être un cube.

static func _pierre() -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_PIERRE_CREME, 0.0, 0.92)

static func _pierre_ombre() -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_PIERRE_OMBRE, 0.0, 0.93)

static func _cobalt() -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_COBALT, 0.0, 0.55)

static func _cobalt_clair() -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_COBALT_CLAIR, 0.0, 0.5)

static func _or() -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_OR, 0.25, 0.4)

static func _energie(force := 1.7) -> StandardMaterial3D:
	return VisualKit.mat(Cfg.COL_TURQUOISE, force, 0.3)


## DALLE DE SOL — le pavage des anciens, semé par plaques.
##
## Elle ne dépasse presque pas du sol : c'est un MOTIF, pas un obstacle.
## Semée en plaques autour des ruines, elle raconte qu'on marche sur
## quelque chose de bâti, et guide le pas sans jamais le gêner.
static func _dalle() -> ArrayMesh:
	return _assembler([
		{"mesh": _boite(Vector3(2.4, 0.12, 2.4)), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.06, 0))},
		{"mesh": _boite(Vector3(2.0, 0.14, 2.0)), "materiau": _pierre(),
			"transform": _t(Vector3(0, 0.05, 0))},
	])


## MUR BAS SCULPTÉ — l'abri de base, et le plus important de la carte.
##
## 1,10 m : il arrête les corps et les tirs, mais passe SOUS la ligne des
## yeux de la caméra. C'est toute la différence entre un abri et un mur qui
## cache le combat. Son liseré cobalt et son cabochon d'or disent d'un coup
## d'œil que ce n'est pas un caillou mais une ruine.
static func _mur_bas() -> ArrayMesh:
	# CORPS SOMBRE, CRÊTE CLAIRE — et l'inverse a été essayé d'abord.
	#
	# Le corps était en pierre crème. Mesuré en image, à la distance de la
	# caméra de jeu, le muret avait très exactement la valeur du sable
	# derrière lui : la masse disparaissait et il ne restait qu'un liseré
	# bleu flottant sur du beige. Un abri qu'on ne voit pas n'est pas un
	# abri. La masse prend donc la pierre d'ombre, et la crête claire, elle,
	# souligne le dessus — c'est ce qui dit où finit le couvert.
	return _assembler([
		{"mesh": _boite(Vector3(2.8, 1.0, 0.66)), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.5, 0))},
		{"mesh": _boite(Vector3(2.9, 0.14, 0.78)), "materiau": _pierre(),
			"transform": _t(Vector3(0, 1.05, 0))},
		# LE LISERÉ COBALT EST SUR LE DESSUS, PAS SUR LE FLANC.
		#
		# Il courait à mi-hauteur, ce qui est juste pour une élévation
		# d'architecte et faux pour CE jeu. La caméra plonge : d'un muret
		# de 1,1 m elle voit surtout la CRÊTE, et le flanc n'occupe que
		# quelques pixels en fuite. Vérifié en image — la bande bleue était
		# invisible sur les murets du premier plan, et ne se lisait que sur
		# les colonnes, plus hautes. Posée sur le dessus, elle est ce qui
		# fait repérer un abri d'un coup d'œil, à la distance où l'on
		# décide de courir vers lui.
		{"mesh": _boite(Vector3(2.3, 0.1, 0.26)), "materiau": _cobalt(),
			"transform": _t(Vector3(0, 1.14, 0))},
		# Le cabochon d'or au milieu de la crête : le seul point vraiment
		# chaud du prop, et ce qui l'empêche de n'être qu'une barre bleue.
		{"mesh": _boite(Vector3(0.3, 0.16, 0.4)), "materiau": _or(),
			"transform": _t(Vector3(0.55, 1.16, 0))},
		# Un bout écroulé : une ruine régulière se lit comme un muret neuf.
		{"mesh": _boite(Vector3(0.8, 0.5, 0.62)), "materiau": _pierre(),
			"transform": _t(Vector3(1.6, 0.25, 0.06), Vector3(0, 0.3, 0.16))},
	])


## PILIER BRISÉ — la verticale du décor, et son repère de proximité.
##
## Cassé net à mi-hauteur, jamais entier : une colonne intacte ferait
## bâtiment, une colonne brisée fait ruine. Deux mètres cinquante — assez
## pour se repérer, trop peu pour masquer un combat.
static func _pilier_brise() -> ArrayMesh:
	return _assembler([
		{"mesh": _cyl(0.52, 0.5, 0.22, 8), "materiau": _pierre(),
			"transform": _t(Vector3(0, 0.11, 0))},
		{"mesh": _cyl(0.4, 0.36, 2.3, 8), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 1.35, 0))},
		{"mesh": _cyl(0.42, 0.42, 0.16, 8), "materiau": _cobalt(),
			"transform": _t(Vector3(0, 1.0, 0))},
		# La cassure : une rondelle inclinée, plus sombre, au sommet.
		{"mesh": _cyl(0.36, 0.3, 0.2, 8), "materiau": _pierre(),
			"transform": _t(Vector3(0.05, 2.5, 0.03), Vector3(0.14, 0, 0.1))},
	])


## BLOC TAILLÉ — la pierre tombée, à hauteur de genou. Le remplissage.
static func _bloc_taille() -> ArrayMesh:
	return _assembler([
		{"mesh": _boite(Vector3(1.15, 0.58, 0.95)), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.29, 0), Vector3(0, 0.4, 0))},
		{"mesh": _boite(Vector3(1.0, 0.12, 0.82)), "materiau": _pierre(),
			"transform": _t(Vector3(0, 0.62, 0), Vector3(0, 0.4, 0))},
		{"mesh": _boite(Vector3(0.52, 0.34, 0.48)), "materiau": _pierre(),
			"transform": _t(Vector3(0.64, 0.17, 0.32), Vector3(0, -0.5, 0.1))},
	])


## CAISSE TECHNO — le seul objet franchement COBALT du semis.
##
## C'est le point bleu sur le sable, donc le repère qui attire. La planche
## lui donne ce rôle : « butin et intérêt combat ». Ses coins d'or et son
## hublot turquoise le distinguent d'un bloc de pierre à trente pixels.
static func _caisse_techno() -> ArrayMesh:
	return _assembler([
		{"mesh": _boite(Vector3(1.0, 0.9, 1.0)), "materiau": _cobalt(),
			"transform": _t(Vector3(0, 0.45, 0))},
		{"mesh": _boite(Vector3(1.06, 0.16, 1.06)), "materiau": _cobalt_clair(),
			"transform": _t(Vector3(0, 0.86, 0))},
		{"mesh": _boite(Vector3(1.1, 0.1, 0.14)), "materiau": _or(),
			"transform": _t(Vector3(0, 0.45, 0.5))},
		{"mesh": _boite(Vector3(0.14, 0.1, 1.1)), "materiau": _or(),
			"transform": _t(Vector3(0.5, 0.45, 0))},
		{"mesh": _cyl(0.17, 0.17, 0.08, 8), "materiau": _energie(2.2),
			"transform": _t(Vector3(0, 0.93, 0))},
	])


## CRISTAL TURQUOISE — l'accent lumineux, semé par grappes.
##
## ÉMISSIF ET NON ÉCLAIRANT : il brille sur lui-même sans ajouter la
## moindre lumière dynamique, donc sans rien coûter au rendu mobile. C'est
## ce qui permet d'avoir des points lumineux dans un jeu de téléphone.
static func _cristal() -> ArrayMesh:
	return _assembler([
		{"mesh": _cyl(0.0, 0.15, 0.9, 5), "materiau": _energie(),
			"transform": _t(Vector3(0, 0.45, 0), Vector3(0.09, 0.4, 0.05))},
		{"mesh": _cyl(0.0, 0.1, 0.58, 5), "materiau": _energie(1.4),
			"transform": _t(Vector3(0.19, 0.29, 0.11), Vector3(0.18, 1.0, 0.3))},
		{"mesh": _cyl(0.0, 0.08, 0.4, 5), "materiau": _energie(1.4),
			"transform": _t(Vector3(-0.16, 0.2, -0.1), Vector3(-0.2, 0.6, -0.26))},
		{"mesh": _cyl(0.26, 0.24, 0.1, 6), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.05, 0))},
	])


## GRAND CRISTAL — la version haute, réservée au champ de cristaux.
##
## Deux mètres quarante : c'est un REPÈRE, pas un caillou. On le sème rare,
## et sa lueur porte au-delà de la brume.
static func _cristal_grand() -> ArrayMesh:
	return _assembler([
		{"mesh": _cyl(0.0, 0.3, 2.4, 6), "materiau": _energie(1.9),
			"transform": _t(Vector3(0, 1.2, 0), Vector3(0.05, 0.3, 0.04))},
		{"mesh": _cyl(0.0, 0.19, 1.5, 5), "materiau": _energie(1.5),
			"transform": _t(Vector3(0.36, 0.75, 0.14), Vector3(0.16, 1.1, 0.24))},
		{"mesh": _cyl(0.0, 0.15, 1.05, 5), "materiau": _energie(1.5),
			"transform": _t(Vector3(-0.3, 0.53, -0.2), Vector3(-0.18, 0.5, -0.22))},
		{"mesh": _cyl(0.55, 0.5, 0.16, 6), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.08, 0))},
	])


## PLANTE DU DÉSERT — la note verte, et sa fleur magenta.
##
## Petite et étroite : elle colore sans encombrer. La fleur est un point de
## quelques pixels — c'est exactement le rôle qu'on lui demande, un accent,
## et le magenta est la teinte la plus rare de la carte.
static func _plante_desert() -> ArrayMesh:
	var vert := VisualKit.mat(Cfg.COL_VERT, 0.0, 0.9)
	var vert_clair := VisualKit.mat(Cfg.COL_VERT_CLAIR, 0.0, 0.9)
	var fleur := VisualKit.mat(Cfg.COL_MAGENTA, 0.4, 0.85)
	return _assembler([
		{"mesh": _cyl(0.2, 0.16, 1.25, 7), "materiau": vert,
			"transform": _t(Vector3(0, 0.63, 0))},
		{"mesh": _cyl(0.11, 0.09, 0.62, 6), "materiau": vert_clair,
			"transform": _t(Vector3(0.26, 0.8, 0), Vector3(0, 0, -0.5))},
		{"mesh": _cyl(0.1, 0.08, 0.5, 6), "materiau": vert_clair,
			"transform": _t(Vector3(-0.24, 0.62, 0.05), Vector3(0, 0, 0.55))},
		{"mesh": _sphere(0.11, 7, 5), "materiau": fleur,
			"transform": _t(Vector3(0, 1.3, 0))},
		{"mesh": _sphere(0.08, 6, 4), "materiau": fleur,
			"transform": _t(Vector3(0.3, 1.14, 0.02))},
	])


## CAILLOU — le remplissage neutre, en gris doux. Il repose l'œil entre
## deux accents et ne concurrence jamais rien.
static func _caillou() -> ArrayMesh:
	var gris := VisualKit.mat(Cfg.COL_GRIS, 0.0, 0.95)
	return _assembler([
		{"mesh": _sphere(1.0, 5, 2), "materiau": gris,
			"transform": _t(Vector3(0, 0.24, 0), Vector3(0.2, 0.6, 0),
					Vector3(0.5, 0.3, 0.42))},
	])


## ROCHER — le caillou en grand, avec une facette claire pour l'échelle.
static func _rocher() -> ArrayMesh:
	var gris := VisualKit.mat(Cfg.COL_GRIS, 0.0, 0.95)
	var clair := VisualKit.mat(Cfg.COL_GRIS.lightened(0.18), 0.0, 0.95)
	return _assembler([
		{"mesh": _sphere(1.0, 6, 2), "materiau": gris,
			"transform": _t(Vector3(0, 0.6, 0), Vector3(0, 0.4, 0.12),
					Vector3(1.0, 0.7, 0.86))},
		{"mesh": _sphere(1.0, 5, 2), "materiau": clair,
			"transform": _t(Vector3(0.4, 0.34, -0.28), Vector3(0, 1.1, 0),
					Vector3(0.55, 0.42, 0.5))},
	])


## GRAVIER — trois éclats au ras du sol. Ce qui casse l'uniformité du sable
## sans rien ajouter à la silhouette.
static func _gravier() -> ArrayMesh:
	var gris := VisualKit.mat(Cfg.COL_GRIS.darkened(0.06), 0.0, 0.96)
	return _assembler([
		{"mesh": _sphere(1.0, 4, 2), "materiau": gris,
			"transform": _t(Vector3(0, 0.07, 0), Vector3(0, 0.5, 0),
					Vector3(0.3, 0.12, 0.26))},
		{"mesh": _sphere(1.0, 4, 2), "materiau": gris,
			"transform": _t(Vector3(0.38, 0.05, 0.22), Vector3(0, 1.2, 0),
					Vector3(0.2, 0.09, 0.18))},
		{"mesh": _sphere(1.0, 4, 2), "materiau": gris,
			"transform": _t(Vector3(-0.3, 0.05, 0.3), Vector3(0, 2.1, 0),
					Vector3(0.17, 0.08, 0.15))},
	])


## ARCHE BASSE — le fragment d'arcade, semé rare.
##
## Elle CADRE sans boucher : deux montants de 2,2 m et un linteau. On la
## traverse, et elle donne au regard une profondeur que cent murets bas ne
## donneraient pas.
static func _arche_basse() -> ArrayMesh:
	return _assembler([
		{"mesh": _boite(Vector3(0.5, 2.2, 0.62)), "materiau": _pierre(),
			"transform": _t(Vector3(-1.15, 1.1, 0))},
		{"mesh": _boite(Vector3(0.5, 2.2, 0.62)), "materiau": _pierre(),
			"transform": _t(Vector3(1.15, 1.1, 0))},
		{"mesh": _boite(Vector3(2.9, 0.46, 0.7)), "materiau": _pierre(),
			"transform": _t(Vector3(0, 2.42, 0))},
		{"mesh": _boite(Vector3(3.0, 0.14, 0.8)), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 2.68, 0))},
		{"mesh": _boite(Vector3(0.62, 0.24, 0.74)), "materiau": _cobalt(),
			"transform": _t(Vector3(0, 2.42, 0))},
	])


## BORNE — le petit obélisque cobalt à cabochon turquoise.
##
## Semée le long des axes, elle BALISE le parcours : trois bornes alignées
## se lisent comme un chemin, et l'œil suit un chemin sans qu'on le lui
## demande.
static func _borne() -> ArrayMesh:
	return _assembler([
		{"mesh": _boite(Vector3(0.5, 0.2, 0.5)), "materiau": _pierre_ombre(),
			"transform": _t(Vector3(0, 0.1, 0))},
		{"mesh": _boite(Vector3(0.34, 1.15, 0.34)), "materiau": _cobalt(),
			"transform": _t(Vector3(0, 0.75, 0))},
		{"mesh": _boite(Vector3(0.4, 0.12, 0.4)), "materiau": _or(),
			"transform": _t(Vector3(0, 1.28, 0))},
		{"mesh": _sphere(0.15, 6, 4), "materiau": _energie(2.4),
			"transform": _t(Vector3(0, 1.44, 0))},
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
