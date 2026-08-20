extends Node3D
## SONDE D'ÉMISSION — est-ce que `emission` compte en mode NON ÉCLAIRÉ ?
##
## La question n'est pas théorique. Tous les matériaux d'effet du jeu
## (`noyau_mat`, `glow_mat`) sont en `SHADING_MODE_UNSHADED` ET comptent
## sur `emission_energy_multiplier` pour dépasser le seuil du halo. Si le
## mode non éclairé ignore l'émission, aucun effet de tir n'a jamais
## franchi ce seuil, et tout ce qu'on croit régler en montant l'énergie ne
## change rien du tout.
##
## Trois carrés, fond noir, caméra de face, et on lit les pixels :
##   A  non éclairé, albédo sombre, émission forte
##   B  par pixel,   albédo sombre, émission forte
##   C  non éclairé, albédo au-delà de 1
## Si A est sombre et B clair, l'émission est ignorée en non éclairé.

func _ready() -> void:
	# FENÊTRE CARRÉE ET CARRÉS BIEN ÉCARTÉS. En 600×200, le champ mesurait
	# dix-huit mètres de large : les trois carrés, posés à un mètre et demi
	# de l'axe, tombaient TOUS DANS LE TIERS CENTRAL. Le balayage lisait
	# alors le même carré trois fois et du vide deux fois.
	get_window().size = Vector2i(600, 600)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.ambient_light_energy = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	add_child(cam)
	cam.current = true

	_carre(-2.0, _mat(true, Color(0.05, 0.02, 0.0), Color(1, 0.7, 0.2), 3.0))
	_carre(0.0, _mat(false, Color(0.05, 0.02, 0.0), Color(1, 0.7, 0.2), 3.0))
	_carre(2.0, _mat(true, Color(3.0, 2.1, 0.6), Color(1, 0.7, 0.2), 3.0))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	# ON BALAYE L'IMAGE PAR TIERS AU LIEU DE PROJETER DES POINTS.
	#
	# Deux versions ont échoué avant celle-ci. La première lisait trois
	# abscisses écrites à la main : deux tombaient sur le fond noir, et la
	# sonde « prouvait » que le mode non éclairé rend du noir alors qu'elle
	# ne mesurait que du vide. La seconde appelait `unproject_position`, et
	# le processus ne rendait plus la main.
	#
	# Le balayage ne dépend d'aucune projection : on prend le pixel le plus
	# clair de chaque tiers de largeur, donc le carré, où qu'il soit tombé.
	var noms := ["A non-eclaire+emission", "B par-pixel+emission",
			"C non-eclaire+albedo>1"]
	var l := img.get_width() / 3
	for i in 3:
		var meilleur := Color.BLACK
		var somme := 0.0
		for x in range(i * l, (i + 1) * l, 2):
			for y in range(0, img.get_height(), 2):
				var c := img.get_pixel(x, y)
				var v := c.r + c.g + c.b
				somme = maxf(somme, v)
				if v > meilleur.r + meilleur.g + meilleur.b:
					meilleur = c
		print("%-26s max r=%.3f v=%.3f b=%.3f" % [
				noms[i], meilleur.r, meilleur.g, meilleur.b])
	get_tree().quit(0)


func _mat(non_eclaire: bool, albedo: Color, emis: Color,
		energie: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if non_eclaire \
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.emission_enabled = true
	m.emission = emis
	m.emission_energy_multiplier = energie
	return m


func _carre(x: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(x, 0, 0)
	add_child(mi)
