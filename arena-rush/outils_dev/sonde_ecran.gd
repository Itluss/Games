extends Node
## SONDE D'ÉCRAN — outil de développement, hors jeu.
##
## POURQUOI CELLE-CI APRÈS LES AUTRES. La sonde statique cherchait un trou
## dans la carte — il n'y en a pas. La sonde de session mesurait le retard
## de la caméra — deux dixièmes de seconde. La sonde d'occlusion, elle, a
## trouvé le défaut : au placement nominal, 5,2 % des positions du monde
## ont plus de 60 % du cadre bouché par du décor à moins de sept mètres.
## Mais elle raisonne en RAYONS, pas en pixels.
##
## Celle-ci lit les pixels, et c'est le seul instrument dont le résultat ne
## demande pas d'interprétation : soit l'image montre un décor, soit elle
## est d'une seule couleur.
##
## SA PREMIÈRE VERSION NE PROUVAIT RIEN, et c'est la leçon à retenir. Elle
## promenait le joueur sur une spirale de deux cents points : jamais elle ne
## tombait sur l'une des cinquante-six positions fautives. Elle rendait « 0
## image plate » AVEC et SANS le correctif — un instrument qui donne le même
## verdict dans les deux cas ne mesure pas ce qu'on croit.
##
## Elle cherche donc d'abord les positions suspectes AU RAYON — c'est
## exhaustif et cela coûte une seconde — et ne rend que celles-là.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_ecran.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 480
const HAUTEUR := 270
const PAS := 4.0
## Nombre de positions rendues PAR SECTEUR.
const PAR_SECTEUR := 4
## Un pixel est « de la même couleur » que le fond s'il en est plus proche
## que ce seuil. 0,06 laisse passer un dégradé de brume mais pas un rocher.
const SEUIL := 0.06
## Au-delà, l'image ne montre plus rien d'autre qu'un aplat.
const VIDE := 0.9

var _joueur: Node3D
var _cam: Camera3D
var _points: Array[Vector3] = []
var _i := 0
var _pire := 0.0
var _pire_pos := Vector3.ZERO
var _pire_teinte := Color.BLACK
var _vides := 0
var _somme := 0.0
var _prete := false

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id():
			_joueur = n
	if _joueur == null:
		push_error("Aucun joueur local : la sonde ne peut rien mesurer.")
		get_tree().quit(1)
		return
	_cam = get_viewport().get_camera_3d()
	_reperer()
	print("  %d positions suspectes retenues." % _points.size())
	_prete = true
	RenderingServer.frame_post_draw.connect(_analyser)


## Classe TOUTES les positions du monde par la part du cadre qu'un décor
## proche occuperait, caméra au placement nominal, et garde les pires
## SECTEUR PAR SECTEUR.
##
## Le classement global ne convient pas, et c'est une leçon payée : les
## seize pires positions du monde se trouvaient toutes dans la même bande
## de canyon, et la sonde n'a jamais rendu la fonderie — dont les toits de
## métal sont pourtant les seules surfaces du jeu capables de remplir un
## cadre d'un aplat parfaitement uni. Un échantillon concentré ne prouve
## rien sur le reste de la carte.
func _reperer() -> void:
	var espace := get_viewport().world_3d.direct_space_state
	var par_secteur: Dictionary = {}
	var n := int(PlanMonde.COTE / PAS)
	for ix in n:
		for iz in n:
			var p := Vector3(-PlanMonde.DEMI + float(ix) * PAS, 0.0,
					-PlanMonde.DEMI + float(iz) * PAS)
			var plan := Vector2(p.x, p.z)
			var cam := p + Vector3(0.0, 13.0, 10.0)
			var part := _part_bouchee(espace, cam, p)
			if part <= 0.2:
				continue
			var s := PlanMonde.secteur_de(plan)
			if not par_secteur.has(s):
				par_secteur[s] = [] as Array[Dictionary]
			(par_secteur[s] as Array).append({"pos": p, "part": part})
	for s in par_secteur:
		var liste: Array = par_secteur[s]
		liste.sort_custom(func(a, b): return a["part"] > b["part"])
		for e in liste.slice(0, PAR_SECTEUR):
			_points.append(e["pos"])
		print("      %s : %d suspectes, pire %.0f %%"
				% [s, liste.size(), float(liste[0]["part"]) * 100.0])


func _part_bouchee(espace: PhysicsDirectSpaceState3D, cam: Vector3,
		cible: Vector3) -> float:
	var avant := (cible - cam).normalized()
	var droite := avant.cross(Vector3.UP).normalized()
	var haut := droite.cross(avant).normalized()
	var touches := 0
	for iy in range(-2, 3):
		for ix in range(-2, 3):
			var dir := (avant + haut * tan(deg_to_rad(14.5 * float(iy)))
					+ droite * tan(deg_to_rad(25.8 * float(ix)))).normalized()
			var q := PhysicsRayQueryParameters3D.create(cam, cam + dir * 7.0)
			q.collision_mask = Cfg.LAYER_WORLD
			var hit := espace.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > 0.25:
				touches += 1
	return float(touches) / 25.0


func _analyser() -> void:
	if not _prete or _i > _points.size():
		return
	# On lit l'image rendue à la position posée au tour précédent : celle-ci
	# n'aura été rendue qu'à la trame suivante.
	if _i > 0:
		var mesure := _mesurer(get_viewport().get_texture().get_image())
		var plat: float = mesure["plat"]
		_somme += plat
		var ou := _points[_i - 1]
		if plat > _pire:
			_pire = plat
			_pire_pos = ou
			_pire_teinte = mesure["teinte"]
		if plat > VIDE:
			_vides += 1
			print("      ! %.0f %% d'aplat en (%.0f, %.0f) — teinte %s"
					% [plat * 100.0, ou.x, ou.z,
					(mesure["teinte"] as Color).to_html(false)])
	if _i == _points.size():
		_conclure()
		return
	_joueur.global_position = _points[_i]
	# ON APPELLE LE RECALAGE DE LA VRAIE CAMÉRA, on ne la place pas à la
	# main : toute la question est de savoir si SON placement — dégagement
	# compris — donne une image.
	if _cam and _cam.has_method(&"_snap"):
		_cam.call(&"_snap")
	_i += 1


## Part de l'image occupée par la couleur dominante.
##
## Un pixel sur quatre suffit : à 480 × 270 cela laisse 8 100 points, et
## cela divise par seize le coût d'une lecture faite quarante fois.
func _mesurer(img: Image) -> Dictionary:
	var somme := Color(0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			somme += img.get_pixel(x, y)
			n += 1
	var moyenne := Color(somme.r / n, somme.g / n, somme.b / n)
	var proches := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if absf(c.r - moyenne.r) + absf(c.g - moyenne.g) \
					+ absf(c.b - moyenne.b) < SEUIL * 3.0:
				proches += 1
	return {"plat": float(proches) / float(n), "teinte": moyenne}


func _conclure() -> void:
	_prete = false
	print("=== SONDE D'ÉCRAN (%d positions les plus suspectes) ===" % _points.size())
	print("  images plates (> %.0f %% d'une seule couleur) : %d"
			% [VIDE * 100.0, _vides])
	print("  pire image : %.0f %% d'aplat en (%.0f, %.0f) — teinte %s"
			% [_pire * 100.0, _pire_pos.x, _pire_pos.z, _pire_teinte.to_html(false)])
	print("  aplat moyen : %.0f %%"
			% (_somme / maxf(1.0, float(_points.size())) * 100.0))
	print("=== %d échec(s) sur 1 vérification ===" % (1 if _vides > 0 else 0))
	get_tree().quit(1 if _vides > 0 else 0)
