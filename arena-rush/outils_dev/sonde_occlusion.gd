extends Node3D
## SONDE D'OCCLUSION — outil de développement, hors jeu.
##
## POURQUOI CELLE-CI. Deux sondes avaient déjà cherché l'« écran violet » au
## mauvais endroit. La statique demandait « y a-t-il un trou dans la
## carte ? » — non. La sonde de session demandait « la caméra décroche-
## t-elle ? » — deux dixièmes de seconde, et une simulation du rattrapage
## après une réapparition de 150 m donne 0,37 s de ciel : un clignotement,
## pas une image figée dont on prend une photo.
##
## Restait la seule hypothèse compatible avec « à CERTAINS ENDROITS » : la
## caméra est reculée de 10 m derrière le joueur et surélevée de 13 m, et
## RIEN ne l'empêchait d'avoir une mesa, une tour ou un pilier entre l'œil
## et le joueur. Le monde a grandi de 68 m à 156 m et gagné des masses de
## 14 m de haut ; l'ancienne arène plate n'en avait aucune.
##
## Deux mesures, pas une :
##   • le joueur est-il visible depuis la caméra ?
##   • l'obstacle est-il assez proche pour REMPLIR le cadre — c'est ce
##     second point qui fait la différence entre « un rocher me cache » et
##     « mon écran est d'une seule couleur ».
##
## Chacune est prise DEUX FOIS : au placement nominal, puis avec le
## dégagement que la caméra applique désormais. Un correctif dont on ne
## mesure pas l'effet n'est qu'une intention.
##
## Usage : godot --headless --path arena-rush res://outils_dev/sonde_occlusion.tscn

const PAS := 4.0
const HAUTEUR := 13.0
const RECUL := 10.0
## Demi-ouverture verticale de la caméra de jeu (fov 58).
const DEMI_FOV := 29.0
## Un obstacle plus proche que cela occupe une part énorme du cadre.
const TRES_PRES := 7.0
## Seuil au-delà duquel on considère le cadre bouché.
const BOUCHE := 0.6

var _monde: Arena
var _espace: PhysicsDirectSpaceState3D
var _forme := SphereShape3D.new()
var _requete := PhysicsShapeQueryParameters3D.new()
var _echecs := 0

func _ready() -> void:
	_monde = Arena.new()
	add_child(_monde)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_espace = get_world_3d().direct_space_state
	_forme.radius = ArenaCamera.RAYON_SONDE
	_requete.shape = _forme
	_requete.collision_mask = Cfg.LAYER_WORLD

	print("=== SONDE D'OCCLUSION ===")
	var nominal := _balayer(false)
	var degage := _balayer(true)
	print("  placement nominal  : joueur caché %5.1f %% · cadre bouché %5.1f %%"
			% [nominal["caches"], nominal["remplis"]])
	print("  avec dégagement    : joueur caché %5.1f %% · cadre bouché %5.1f %%"
			% [degage["caches"], degage["remplis"]])
	print("      (%d positions testées, pas de %.0f m)"
			% [int(nominal["testes"]), PAS])
	for e: Dictionary in degage["pires"]:
		var pos: Vector3 = e["pos"]
		print("      reste %3.0f %% bouché en (%.0f, %.0f) — secteur %s"
				% [float(e["part"]) * 100.0, pos.x, pos.z,
				PlanMonde.secteur_de(Vector2(pos.x, pos.z))])

	# Le dégagement ne peut pas tout : un joueur adossé à une paroi aura
	# toujours de la roche dans le cadre, et c'est normal. Ce qui ne doit
	# plus exister, c'est l'écran ENTIÈREMENT bouché.
	_verifier("aucune position ne bouche plus de 90 % du cadre",
			float(degage["pire"]) <= 0.9, true)
	_verifier("moins de 1 % des positions ont le cadre bouché",
			float(degage["remplis"]) < 1.0, true)
	# CE SEUIL EST LARGE, ET C'EST ASSUMÉ. Un joueur masqué par un tronc
	# pendant qu'il court derrière n'est pas un défaut : c'est le décor que
	# la joueuse a demandé pour pouvoir se cacher. Le placement nominal
	# masquait le joueur 14,7 % du temps, le dégagement descend à 9,0 % ; le
	# seuil garde la porte contre une famille de props qui noierait la carte,
	# pas contre l'existence même des abris.
	_verifier("le joueur est visible sur plus de 88 % de la carte",
			float(degage["caches"]) < 12.0, true)
	print("=== %d échec(s) sur 3 vérifications ===" % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-54s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _balayer(degager: bool) -> Dictionary:
	var testes := 0
	var caches := 0
	var remplis := 0
	var pire := 0.0
	var pires: Array[Dictionary] = []
	# LE MONDE EST UN CARRÉ SANS BORD : on le balaye en entier, il n'y a
	# plus de « dehors » à écarter.
	var n := int(PlanMonde.COTE / PAS)
	for ix in n:
		for iz in n:
			var p := Vector3(-PlanMonde.DEMI + float(ix) * PAS, 0.0,
					-PlanMonde.DEMI + float(iz) * PAS)
			testes += 1
			var oeil := p + Vector3(0.0, ArenaCamera.YEUX, 0.0)
			var but := p + Vector3(0.0, HAUTEUR, RECUL)
			var cam := but
			if degager:
				cam = oeil + ArenaCamera.placer(but - oeil,
						_fraction(oeil, but - oeil))
			if _bloque(cam, oeil):
				caches += 1
			var part := _part_bouchee(cam, p)
			pire = maxf(pire, part)
			if part > BOUCHE:
				remplis += 1
				pires.append({"pos": p, "part": part})
	pires.sort_custom(func(a, b): return a["part"] > b["part"])
	return {
		"testes": testes,
		"caches": 100.0 * float(caches) / maxf(1.0, float(testes)),
		"remplis": 100.0 * float(remplis) / maxf(1.0, float(testes)),
		"pire": pire,
		"pires": pires.slice(0, 8),
	}


## Reproduction EXACTE du dégagement appliqué par la caméra. Recopier la
## règle plutôt que d'appeler la caméra est un choix : la sonde doit
## échouer si la règle change sans qu'on y pense.
func _fraction(oeil: Vector3, course: Vector3) -> float:
	# La caméra ne bouge QUE si le joueur est masqué. Tant qu'on le voit,
	# elle reste au placement nominal quoi qu'il y ait autour — c'est ce qui
	# a supprimé le zoom continuel signalé en jeu.
	var vue := PhysicsRayQueryParameters3D.create(oeil + course, oeil)
	vue.collision_mask = Cfg.LAYER_WORLD
	if _espace.intersect_ray(vue).is_empty():
		return 1.0
	_requete.transform = Transform3D(Basis(), oeil)
	_requete.motion = course
	var bornes := _espace.cast_motion(_requete)
	if bornes.size() < 1:
		return 1.0
	var sur: float = bornes[0]
	return clampf(sur - 0.04, ArenaCamera.DEGAGEMENT_MINI, 1.0)


func _bloque(de: Vector3, vers: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(de, vers)
	q.collision_mask = Cfg.LAYER_WORLD
	var hit := _espace.intersect_ray(q)
	if hit.is_empty():
		return false
	# Le sol est un obstacle légitime : il est SOUS le segment, jamais entre
	# l'œil et le joueur. On ne retient que ce qui se dresse.
	return (hit["position"] as Vector3).y > 0.25


## Part du cadre bouchée par quelque chose de très proche.
##
## On tire une grille de rayons dans le tronc de vision et on compte ceux
## qui heurtent un obstacle DEBOUT à moins de sept mètres. Le sol ne compte
## pas : il est censé remplir le cadre, c'est son rôle.
func _part_bouchee(cam: Vector3, cible: Vector3) -> float:
	var avant := (cible - cam).normalized()
	var droite := avant.cross(Vector3.UP).normalized()
	var haut := droite.cross(avant).normalized()
	var touches := 0
	var total := 0
	for iy in range(-2, 3):
		for ix in range(-2, 3):
			var ay := deg_to_rad(DEMI_FOV * float(iy) / 2.0)
			var ax := deg_to_rad(DEMI_FOV * 1.78 * float(ix) / 2.0)
			var dir := (avant + haut * tan(ay) + droite * tan(ax)).normalized()
			total += 1
			var q := PhysicsRayQueryParameters3D.create(cam, cam + dir * TRES_PRES)
			q.collision_mask = Cfg.LAYER_WORLD
			var hit := _espace.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > 0.25:
				touches += 1
	return float(touches) / float(total)
