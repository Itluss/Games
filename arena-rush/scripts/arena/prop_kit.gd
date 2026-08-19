extends RefCounted
class_name PropKit
## FOURNISSEUR DE MOBILIER D'ARÈNE — pose un modèle Meshy à la bonne taille,
## ou un volume de secours quand le modèle n'est pas encore là.
##
## POURQUOI CE FICHIER EXISTE — deux problèmes, une seule réponse.
##
## 1. MESHY NE CONNAÎT PAS LE MÈTRE. Un générateur 3D renvoie une échelle
##    arbitraire : le même prompt peut sortir un conteneur de 0,8 unité ou
##    de 240. Kael l'a déjà montré, son rig arrivait en centimètres. Écrire
##    un facteur d'échelle en dur pour chaque pièce, c'est signer pour le
##    réajuster à chaque regénération. On MESURE donc le modèle et on le
##    ramène à la taille déclarée par le plan de l'arène, en mètres.
##
## 2. LE JEU DOIT TOURNER AVANT QUE LES MODÈLES N'EXISTENT. Quinze
##    générations prennent des heures et peuvent échouer. Une arène qui ne
##    se monte pas sans elles serait injouable pendant tout ce temps, et
##    invérifiable. Chaque pièce absente est donc remplacée par un volume
##    aux dimensions exactes de la pièce attendue : le jeu reste jouable et
##    le placement reste vérifiable, seule la beauté manque.
##
## Conséquence heureuse : intégrer un modèle livré ne demande AUCUN code.
## Le fichier apparaît, la pièce s'embellit.

const DOSSIER := "res://assets/models/"


## Le plan déclare un volume en mètres. Le modèle est ramené À L'INTÉRIEUR
## de ce volume — jamais au-delà —, ce qui borne ce que l'art génératif
## peut faire au gameplay : un modèle inattendu peut être plus petit que
## prévu, jamais plus encombrant.
static func instancier(modele: StringName, taille: Vector3,
		teinte: Color) -> Dictionary:
	var chemin := DOSSIER + String(modele) + ".glb"
	if modele != &"" and ResourceLoader.exists(chemin):
		var noeud := _depuis_modele(chemin, taille, teinte)
		if not noeud.is_empty():
			return noeud
	return {"noeud": _volume_de_secours(taille, teinte), "taille": taille,
			"reel": false}


static func disponible(modele: StringName) -> bool:
	return modele != &"" \
			and ResourceLoader.exists(DOSSIER + String(modele) + ".glb")


# --- MODÈLE RÉEL ---------------------------------------------------------

static func _depuis_modele(chemin: String, taille: Vector3,
		teinte: Color) -> Dictionary:
	var scene := load(chemin) as PackedScene
	if scene == null:
		push_warning("Modèle illisible : %s" % chemin)
		return {}
	var modele := scene.instantiate() as Node3D
	if modele == null:
		push_warning("Modèle sans racine 3D : %s" % chemin)
		return {}

	var brut := _boite_englobante(modele)
	if brut.size.x <= 0.0001 or brut.size.y <= 0.0001 or brut.size.z <= 0.0001:
		push_warning("Modèle de volume nul : %s" % chemin)
		modele.queue_free()
		return {}

	# ÉCHELLE UNIFORME, et le rapport le PLUS PETIT des trois. Un facteur
	# par axe déformerait la pièce ; prendre le plus grand la ferait
	# déborder de son volume, donc traverser un autre abri ou dépasser de
	# sa collision. Le plus petit garantit qu'elle tient dedans.
	#
	# MAIS ON ESSAIE AUSSI LE QUART DE TOUR. Meshy choisit librement
	# l'orientation de ce qu'il produit : le conteneur est arrivé avec sa
	# longueur sur Z alors que le plan la déclare sur X. Sans ce test, le
	# rapport le plus petit devenait celui de la longueur contre la
	# largeur — un conteneur de 5,2 m sur 2,2 m se serait retrouvé réduit à
	# un cube de 1,3 m, et aurait cessé d'abriter qui que ce soit.
	#
	# Le volume déclaré exprime donc une INTENTION — « un abri long et
	# bas » — et non une orientation imposée. C'est ce qui rend le plan
	# indépendant des caprices du générateur.
	var f_droit: float = minf(minf(taille.x / brut.size.x,
			taille.y / brut.size.y), taille.z / brut.size.z)
	var f_tourne: float = minf(minf(taille.x / brut.size.z,
			taille.y / brut.size.y), taille.z / brut.size.x)
	var quart := f_tourne > f_droit
	var facteur: float = f_tourne if quart else f_droit
	modele.scale = Vector3.ONE * facteur

	_traiter_matieres(modele, teinte)

	# Trois niveaux, et chacun a une raison : le PIVOT porte la position et
	# la rotation voulues par le plan, l'ORIENTEUR le quart de tour éventuel
	# imposé par le modèle, et le modèle lui-même son recentrage. Les
	# mélanger rendrait impossible de régler l'un sans casser l'autre.
	var pivot := Node3D.new()
	var orienteur := Node3D.new()
	orienteur.rotation.y = PI * 0.5 if quart else 0.0
	pivot.add_child(orienteur)
	orienteur.add_child(modele)

	# On recentre en X/Z et on POSE la pièce sur le sol. Meshy centre ses
	# modèles sur leur barycentre, pas sur leurs pieds : sans ce décalage,
	# la moitié de chaque abri serait enterrée. Le recentrage a lieu AVANT
	# le quart de tour, dans l'espace du modèle — une rotation autour de Y
	# d'un objet déjà centré sur l'axe le laisse centré, et ne touche pas
	# à sa hauteur.
	var centre := brut.get_center() * facteur
	modele.position = Vector3(-centre.x, -brut.position.y * facteur, -centre.z)

	var reelle := brut.size * facteur
	if quart:
		reelle = Vector3(reelle.z, reelle.y, reelle.x)

	# Un abri sensiblement plus bas que prévu n'abrite plus : on le signale
	# plutôt que de le découvrir en jouant.
	if reelle.y < taille.y * 0.75:
		push_warning("%s : hauteur rendue %.2f m pour %.2f m attendus."
				% [chemin.get_file(), reelle.y, taille.y])

	return {"noeud": pivot, "taille": reelle, "reel": true}


## Boîte englobante de TOUTES les mailles, exprimée dans l'espace du modèle.
##
## `MeshInstance3D.get_aabb()` ne parle que de la maille elle-même : il
## ignore la position du nœud dans la scène. Un modèle en plusieurs parties
## donnerait alors la taille d'une seule d'entre elles. On compose donc
## chaque boîte par la transformation qui mène de la racine à la maille.
##
## CETTE TRANSFORMATION EST COMPOSÉE À LA MAIN, et pas lue dans
## `global_transform` : la mesure a lieu AVANT que le modèle ne soit
## rattaché à la scène, et Godot refuse de donner une transformation
## globale à un nœud hors de l'arbre. On descend donc l'arborescence en
## accumulant les transformations locales, qui sont toujours lisibles.
static func _boite_englobante(racine: Node3D) -> AABB:
	var boites: Array[AABB] = []
	_collecter_boites(racine, Transform3D.IDENTITY, boites)
	if boites.is_empty():
		return AABB()
	var total := boites[0]
	for i in range(1, boites.size()):
		total = total.merge(boites[i])
	return total


static func _collecter_boites(n: Node, vers_racine: Transform3D,
		sortie: Array[AABB]) -> void:
	# La racine n'ajoute pas SA propre transformation : la mesure est
	# exprimée dans son espace à elle, pas dans celui de son parent. C'est
	# pourquoi l'accumulation part de l'identité et n'intègre la
	# transformation d'un nœud qu'en descendant vers ses enfants.
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		sortie.append(vers_racine * mi.get_aabb())
	for enfant in n.get_children():
		var suite := vers_racine
		var e3d := enfant as Node3D
		if e3d != null:
			suite = vers_racine * e3d.transform
		_collecter_boites(enfant, suite, sortie)


static func _toutes_les_mailles(n: Node, sortie: Array = []) -> Array:
	if n is MeshInstance3D:
		sortie.append(n)
	for enfant in n.get_children():
		_toutes_les_mailles(enfant, sortie)
	return sortie


## Reprise du correctif déjà appliqué à Kael, et pour la même raison.
##
## Le glTF ne précise pas toujours `metallicFactor`, et la valeur par
## défaut de la spécification est 1.0 : un modèle Meshy importé tel quel
## arrive donc entièrement métallique. Sans carte d'environnement, un métal
## pur ne réfléchit rien — il rend NOIR. Kael est arrivé en silhouette
## noire pour cette exacte raison ; le mobilier arriverait de même.
##
## ─── POURQUOI LA TEXTURE D'ALBÉDO EST RETIRÉE ───────────────────────────
##
## CE QUI A ÉTÉ MESURÉ. Les quinze modèles ont été générés pour la CITÉ
## NÉON. Passé le monde aux Ruines Solaires, l'Esplanade est restée semée
## de masses anthracite au milieu d'un désert doré. Premier réflexe :
## pousser le mélange de teinte de 0,5 à 0,88. Sans effet — vérifié en
## image, puis expliqué en sondant les fichiers : l'`albedo_color` de ces
## matériaux vaut BLANC, et toute la couleur vit dans la TEXTURE. Or la
## texture MULTIPLIE la couleur. Blanc × texture sombre donne sombre ;
## cobalt × texture sombre donne sombre aussi. Aucune valeur de mélange
## n'aurait pu y changer quoi que ce soit — c'était l'idée qui était
## fausse, pas le réglage.
##
## On retire donc la texture et on pose la teinte de la famille en aplat.
##
## CE QU'ON PERD ET CE QU'ON GAGNE. On perd le détail peint par Meshy. On
## garde la SILHOUETTE — la seule chose qu'un générateur 3D fait mieux
## qu'une primitive, et la seule qui se lise à la distance de la caméra.
## Et l'on gagne l'unité : le mobilier de l'Esplanade parle enfin la même
## langue que le reste de la carte, qui est faite d'aplats facettés.
##
## LA VRAIE CORRECTION RESTE LA RETEXTURATION. Meshy sait retexturer sans
## regénérer la forme ; les bons de commande sont déposés dans
## art/requests/. Le jour où ces textures arrivent, il suffira de rendre
## ce retrait conditionnel. En attendant, la carte est cohérente sans
## dépendre d'une génération qui peut échouer.
##
## `teinte` : couleur de la FAMILLE à laquelle la pièce appartient.
static func _traiter_matieres(racine: Node3D, teinte: Color) -> void:
	for n in _toutes_les_mailles(racine):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			# BaseMaterial3D et non StandardMaterial3D : Meshy exporte en
			# ORMMaterial3D dès qu'il joint une carte occlusion/rugosité/
			# métal, et ces pièces-là auraient été sautées en silence.
			var source := mi.mesh.surface_get_material(i) as BaseMaterial3D
			var copie := (source.duplicate() if source != null
					else StandardMaterial3D.new()) as BaseMaterial3D
			copie.albedo_texture = null
			copie.albedo_color = teinte
			copie.metallic = 0.0
			copie.roughness = 0.68
			# Même éclairage cellulé que le reste du jeu : sans cela, le
			# décor serait rendu en dégradé continu et jurerait avec les
			# personnages, qui sont en aplats.
			copie.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			copie.specular_mode = BaseMaterial3D.SPECULAR_TOON
			copie.rim_enabled = true
			copie.rim = 0.35
			copie.rim_tint = 0.25
			# Les autres cartes suivent la texture d'albédo. Une carte de
			# rugosité ou de normales peinte pour un panneau de métal noir
			# creuserait des rayures et des rivets dans une pierre crème :
			# le détail resterait celui de la cité néon, sur une forme
			# repeinte en désert. C'est le contraire de ce qu'on cherche.
			copie.normal_enabled = false
			copie.roughness_texture = null
			copie.metallic_texture = null
			copie.ao_enabled = false
			# L'émissif de Meshy vaut souvent la couleur de base à pleine
			# puissance : la pièce s'éclairerait elle-même et perdrait tout
			# relief. Le néon du décor est ajouté séparément, où on le
			# veut, et pas partout.
			copie.emission_enabled = false
			mi.set_surface_override_material(i, copie)


# --- VOLUME DE SECOURS ---------------------------------------------------

## Ni un placeholder honteux ni un simple cube gris : un volume biseauté aux
## couleurs de la cité, pour que l'arène reste présentable tant que les
## modèles ne sont pas arrivés.
static func _volume_de_secours(taille: Vector3, teinte: Color) -> Node3D:
	var pivot := Node3D.new()

	var corps := MeshInstance3D.new()
	var boite := BoxMesh.new()
	boite.size = taille
	corps.mesh = boite
	corps.material_override = VisualKit.mat(teinte, 0.0, 0.7)
	corps.position = Vector3(0, taille.y * 0.5, 0)
	pivot.add_child(corps)

	# Couronnement plus clair : une arête éclairée détache le volume du sol
	# et donne du relief sans géométrie coûteuse.
	var chapeau := MeshInstance3D.new()
	var cboite := BoxMesh.new()
	cboite.size = Vector3(taille.x * 1.04, minf(0.18, taille.y * 0.14),
			taille.z * 1.04)
	chapeau.mesh = cboite
	chapeau.material_override = VisualKit.mat(teinte.lightened(0.22), 0.0, 0.7)
	chapeau.position = Vector3(0, taille.y - cboite.size.y * 0.5, 0)
	pivot.add_child(chapeau)

	return pivot
