extends SceneTree
## ATELIER DE PRÉPARATION DU KIT DE L'ÎLE — transforme chaque glb Meshy
## approuvé en UNE ressource `.res` compacte : la maille, plus un matériau
## jouet (couleur seule, 512 px, rugosité pleine). Les glb bruts pèsent
## 5 à 8 Mo pièce avec quatre cartes 2048² chacun — quarante mégaoctets
## et cinq secondes de chargement pour un style qui n'utilise ni normale,
## ni métal, ni rugosité. Après ce pressage : un fichier par asset,
## quelques centaines de kilo-octets, chargé en quelques millisecondes.
## Les sources restent dans assets/models/ mais sont EXCLUES de l'export.
## À relancer après chaque nouvel asset approuvé :
##   godot --headless --path . --script res://outils_dev/preparer_kit_ile.gd

const SORTIE := "res://assets/kit_ile/"
const COTE_TEXTURE := 512


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SORTIE)
	var rates := 0
	for nom: StringName in KitIle.APPROUVES:
		if not _presser(nom):
			rates += 1
	print("=== %d échec(s) ===" % rates)
	quit(1 if rates > 0 else 0)


func _presser(nom: StringName) -> bool:
	var chemin := "res://assets/models/" + String(nom) + ".glb"
	if not ResourceLoader.exists(chemin):
		print("✗ %s : source absente" % nom)
		return false
	var racine := (load(chemin) as PackedScene).instantiate() as Node3D
	var mi := KitIle._premiere_maille(racine)
	if mi == null:
		print("✗ %s : pas de maille" % nom)
		racine.free()
		return false
	# La transformée locale du nœud doit être CUITE dans la ressource :
	# le chargeur ne verra plus la scène, seulement la maille.
	var locale := KitIle._transfo_locale(mi, racine)
	var source := mi.mesh
	var maille := ArrayMesh.new()
	for s in source.get_surface_count():
		var arr := source.surface_get_arrays(s)
		if locale != Transform3D.IDENTITY:
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in vs.size():
				vs[i] = locale * vs[i]
			arr[Mesh.ARRAY_VERTEX] = vs
		# Normales et UV voyagent tels quels ; tangentes, couleurs et
		# autres canaux inutilisés sont abandonnés en route.
		var epure := []
		epure.resize(Mesh.ARRAY_MAX)
		epure[Mesh.ARRAY_VERTEX] = arr[Mesh.ARRAY_VERTEX]
		epure[Mesh.ARRAY_NORMAL] = arr[Mesh.ARRAY_NORMAL]
		epure[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
		epure[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
		maille.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, epure)
		maille.surface_set_material(s, _materiau_jouet(source, s, nom))
	racine.free()
	var sortie := SORTIE + String(nom) + ".res"
	var err := ResourceSaver.save(maille, sortie,
			ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	if err != OK:
		print("✗ %s : sauvegarde %d" % [nom, err])
		return false
	var octets := FileAccess.get_file_as_bytes(sortie).size()
	print("✓ %s : %d surfaces, %d Ko" % [nom, maille.get_surface_count(),
			octets / 1024])
	return true


## Le matériau du style : la couleur peinte, rien d'autre. Rugosité à 1
## comme le matériau partagé du kit procédural — même lumière, même toucher.
func _materiau_jouet(source: Mesh, s: int, nom: StringName) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.metallic = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var origine := source.surface_get_material(s) as BaseMaterial3D
	if origine != null and origine.albedo_texture != null:
		var im := origine.albedo_texture.get_image()
		im.decompress()
		if im.get_width() > COTE_TEXTURE:
			im.resize(COTE_TEXTURE, COTE_TEXTURE, Image.INTERPOLATE_LANCZOS)
		im.convert(Image.FORMAT_RGB8)
		im.generate_mipmaps()
		var tex := ImageTexture.create_from_image(im)
		m.albedo_texture = tex
	elif origine != null:
		m.albedo_color = origine.albedo_color
	else:
		print("  (%s : surface %d sans matériau, blanc)" % [nom, s])
	return m
