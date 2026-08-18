extends Node
## TEST DU MONDE ENROULÉ — la limite ne doit couper AUCUNE interaction.
##
## POURQUOI CE TEST EXISTE. La carte a été rendue sans bord, et le décor
## se recolle : mesuré, zéro rupture, zéro traversée visible. Mais un monde
## qui s'enroule ne tient pas qu'à son décor. Tout ce qui mesure une
## distance ou une direction doit s'enrouler AUSSI, et il suffit d'un seul
## calcul « à plat » oublié pour rouvrir la limite :
##
##   • un mob qui poursuit à travers la limite part droit dans le vide ;
##   • un projectile la franchit et ne touche plus rien ;
##   • la visée automatique ignore une cible à deux mètres ;
##   • un adversaire proche est calculé à cent quarante mètres, donc
##     invisible et intouchable.
##
## Aucun de ces défauts ne se voit sur une capture d'écran, et aucun ne se
## produit ailleurs que sur une bande étroite de la carte. C'est exactement
## le genre de chose qu'un test doit tenir, parce que personne ne pensera à
## aller la vérifier à la main.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/test_enroulement.tscn \
##       --rendering-driver opengl3 -- --solo

var _echecs := 0
var _total := 0
var _joueur: Node3D
var _cible: Node3D

func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	if not _preparer():
		get_tree().quit(1)
		return
	print("=== MONDE ENROULÉ ===")
	await _garantie_voisinage()
	await _garantie_repli_des_corps()
	await _garantie_visee_automatique()
	await _garantie_tir_traversant()
	await _garantie_projectile_replie()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-52s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


## Isole le banc : sans cela, un mob de passage fausserait chaque mesure.
func _preparer() -> bool:
	# LE PONDEUR N'EST DANS AUCUN GROUPE. Le premier jet croyait l'éteindre
	# en cherchant un groupe « spawner » qui n'existe pas : il a continué à
	# peupler la carte pendant toutes les mesures, et la visée automatique
	# se verrouillait sur un mob de passage plutôt que sur l'adversaire.
	# On passe donc par le monde, qui le référence nommément.
	var monde0 := _trouver_monde()
	if monde0 != null and monde0.get(&"spawner") != null:
		var pondeur: Node = monde0.get(&"spawner")
		pondeur.set_process(false)
		pondeur.set_physics_process(false)
	else:
		push_error("Pondeur de mobs introuvable : le banc ne serait pas isolé.")
		return false
	_vider_les_mobs()
	var bots: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id() and not bool(n.get(&"is_bot")):
			_joueur = n
		elif bool(n.get(&"is_bot")):
			bots.append(n)
	if _joueur == null or bots.is_empty():
		push_error("Banc incomplet : joueur=%s bots=%d" % [_joueur, bots.size()])
		return false
	# On garde UN seul adversaire, et on l'éteint : un bot qui se déplace ou
	# qui riposte rendrait chaque mesure irreproductible.
	_cible = bots[0]
	for i in range(1, bots.size()):
		bots[i].queue_free()
	var cerveau := _cible.get_node_or_null("Brain")
	if cerveau:
		cerveau.queue_free()
	_cible.set(&"move_input", Vector2.ZERO)
	_cible.set(&"want_fire", false)

	# ON DÉBRANCHE LE CONTRÔLEUR HUMAIN. Il réécrit `want_fire` à chaque
	# image depuis l'état des boutons : sans cela, l'intention posée par le
	# banc était effacée avant d'avoir servi, et le premier jet mesurait un
	# joueur qui ne tirait tout simplement jamais.
	var monde := _trouver_monde()
	if monde != null and monde.get(&"controller") != null:
		var ctrl: Node = monde.get(&"controller")
		ctrl.set_physics_process(false)
		ctrl.set_process(false)
	else:
		push_error("Contrôleur introuvable : le banc ne peut pas tirer.")
		return false
	return true


## Retire tous les mobs. Appelé avant chaque mesure : même éteint, le
## pondeur laisse derrière lui ce qu'il a déjà semé.
func _vider_les_mobs() -> void:
	for n in get_tree().get_nodes_in_group(&"mobs"):
		n.queue_free()


func _trouver_monde() -> Node:
	var principal := get_tree().get_first_node_in_group(&"main")
	if principal == null:
		return null
	for n in principal.get_children():
		if n.get(&"controller") != null:
			return n
	return null


## LA SITUATION DE RÉFÉRENCE : de part et d'autre de la limite, à un mètre.
## Bande de la limite retenue pour toutes les poses, choisie DÉGAGÉE.
##
## POURQUOI CE N'EST PLUS z = 0. Le banc posait les deux corps sur la
## limite à z = 0, quoi qu'il y ait à cet endroit. Le jour où le secteur
## des ruines a reçu des murets bas, un muret s'est trouvé là : la physique
## a repoussé l'adversaire de près de deux mètres en six images, et le banc
## a conclu que le repli ne fonctionnait plus. Il mesurait en réalité une
## collision parfaitement normale.
##
## Un banc qui teste l'enroulement ne doit rien tester d'autre. On réutilise
## donc le couloir dégagé déjà calculé pour les tirs — et on le calcule une
## seule fois, il coûte 144 rayons.
var _z_pose := NAN

func _poser_de_part_et_dautre(ecart: float = 1.0) -> void:
	if is_nan(_z_pose):
		_z_pose = _couloir_libre()
		if is_nan(_z_pose):
			_z_pose = 0.0
	var z := _z_pose
	_joueur.global_position = Vector3(PlanMonde.DEMI - ecart * 0.5, 0.6, z)
	_cible.global_position = Vector3(-PlanMonde.DEMI + ecart * 0.5, 0.6, z)
	_cible.set(&"_target_pos", _cible.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _garantie_voisinage() -> void:
	await _poser_de_part_et_dautre(1.0)
	var d := PlanMonde.distance3(_joueur.global_position,
			_cible.global_position)
	print("      distance mesurée sur le tore : %.2f m" % d)
	_verifier("deux corps séparés par la limite sont voisins", d < 2.0, true)


## Le corps de l'adversaire doit être RAMENÉ près du joueur, pas laissé à
## cent quarante mètres. C'est cette translation qui le rend visible à
## l'écran et atteignable par la physique.
func _garantie_repli_des_corps() -> void:
	await _poser_de_part_et_dautre(1.0)
	for i in 6:
		await get_tree().physics_frame
	var brut := _joueur.global_position.distance_to(_cible.global_position)
	print("      distance BRUTE après repli : %.2f m" % brut)
	_verifier("l'adversaire est replié auprès du joueur", brut < 3.0, true)


## LA VISÉE AUTOMATIQUE, interrogée sur le contrôleur réel.
##
## On le rebranche le temps de la mesure : c'est LUI qui cherche la cible,
## et tester le calcul ailleurs ne dirait rien de ce que fait le jeu.
func _garantie_visee_automatique() -> void:
	_vider_les_mobs()
	await _poser_de_part_et_dautre(4.0)
	var monde := _trouver_monde()
	var ctrl: Node = monde.get(&"controller") if monde else null
	if ctrl == null:
		_verifier("la visée automatique voit à travers la limite",
				false, true)
		return
	# LE CONTRÔLEUR TOURNE DANS `_process`, PAS DANS `_physics_process`.
	# Le premier jet le réactivait sur la mauvaise horloge : il restait
	# muet, et le banc concluait que la visée automatique était aveugle
	# alors qu'elle n'avait jamais été appelée.
	#
	# ET IL FAUT LUI DONNER UN INDICE DE DIRECTION. La visée automatique ne
	# retient que les cibles dans un cône de 55° autour de l'intention du
	# joueur — sinon elle accrocherait n'importe qui dans le dos. Sur
	# bureau, cette intention vient du CURSEUR. Sans le poser, le banc
	# mesurait un cône orienté au hasard et concluait à tort que la limite
	# du monde rendait la cible invisible.
	# ON NEUTRALISE L'INDICE DE VISÉE AU LIEU D'ESSAYER DE LE POSER.
	#
	# Le banc déplaçait le curseur sur la cible avec `Input.warp_mouse`.
	# Sans affichage, ce déplacement N'A AUCUN EFFET : le curseur restait à
	# (0, 0), donc dans le coin supérieur gauche, et `_aim_hint()` en
	# déduisait une intention pointant vers le haut à gauche. La cible
	# tombait hors du cône de 55°, et le banc annonçait « la visée est
	# aveugle au-delà de la limite » alors qu'il lui avait lui-même désigné
	# une autre direction. Mesuré : indice = (-0,70 ; 0 ; -0,71).
	#
	# Ce que ce test doit prouver, c'est que la SÉLECTION de cible mesure la
	# distance sur le tore et non à plat. Le cône d'accrochage est une autre
	# question, qui se teste sans limite du monde. On retire donc la caméra
	# le temps de la mesure : sans caméra, `_aim_hint()` ne renvoie aucune
	# intention, aucun cône ne s'applique, et il ne reste que la question
	# posée — l'ennemi d'en face est-il vu à cinq mètres ou à cent quarante ?
	var cam_gardee: Camera3D = Fx.camera
	Fx.camera = null
	ctrl.set_process(true)
	for i in 14:
		await get_tree().process_frame
	Fx.camera = cam_gardee
	var verrou = _joueur.get(&"locked_target")
	# DIAGNOSTIC IMPRIMÉ, PAS DÉDUIT. Cet échec a déjà coûté du temps une
	# fois parce que le banc disait « aveugle » sans dire de quoi : cible
	# hors groupe, hors portée, éliminée, ou cône mal orienté produisent le
	# même verdict. On imprime donc les quatre.
	print("      DIAG verrou=%s cible=%s ecart=%.1f m portee=%.1f m groupes=%s elim=%s"
			% [verrou, _cible,
			PlanMonde.distance3(_joueur.global_position, _cible.global_position),
			(_joueur.weapon.data.range if _joueur.weapon and _joueur.weapon.data
					else -1.0),
			_cible.get_groups(), _cible.get(&"is_eliminated")])
	ctrl.set_process(false)
	_joueur.set(&"want_fire", false)
	_verifier("la visée automatique voit à travers la limite",
			verrou == _cible, true)


## LE TEST QUI COMPTE : un tir par-dessus la limite doit faire mal.
##
## AVEC SON TÉMOIN. Le même tir est d'abord joué EN PLEINE CARTE, loin de
## toute limite. S'il ne touche pas là non plus, ce n'est pas le monde
## enroulé qui est en cause mais le banc — et un test qui accuse le jeu
## d'un défaut qui lui appartient fait perdre plus de temps qu'il n'en
## fait gagner. Le témoin est donc vérifié en premier, et son échec est
## annoncé comme tel.
func _garantie_tir_traversant() -> void:
	var temoin := await _tirer_et_mesurer(
			Vector3(10.0, 0.6, 0.0), Vector3(15.0, 0.6, 0.0))
	print("      témoin en pleine carte : %.0f points de dégâts" % temoin)
	_verifier("le banc sait faire toucher un tir (témoin)", temoin > 0.0, true)
	if temoin <= 0.0:
		print("      ! témoin en échec : la mesure suivante ne prouverait rien.")
		return

	# ON CHOISIT UN ENDROIT DÉGAGÉ SUR LA LIMITE. Elle traverse tout le
	# monde, décor compris : planter le duel devant un rocher mesurerait la
	# solidité du rocher, pas celle de l'enroulement. On longe donc la
	# limite jusqu'à trouver une ligne de tir libre.
	var z := _couloir_libre()
	if is_nan(z):
		print("      ! aucune ligne de tir libre trouvée sur la limite.")
		_verifier("un tir traverse la limite et touche", false, true)
		return
	print("      couloir dégagé trouvé à z = %.0f m" % z)
	# CE QUE LA BISECTION A APPRIS, et qui vaut d'être gardé : le premier
	# duel joué à un endroit neuf ratait, le second touchait. Ce n'était pas
	# la limite du monde, c'était le temps de pivot du personnage. Une
	# mesure qui dépend de l'ordre des mesures ne mesure rien.
	var traversant := await _tirer_et_mesurer(
			Vector3(PlanMonde.DEMI - 2.5, 0.6, z),
			Vector3(-PlanMonde.DEMI + 2.5, 0.6, z))
	print("      à travers la limite : %.0f points de dégâts" % traversant)
	_verifier("un tir traverse la limite et touche", traversant > 0.0, true)


## Cherche une abscisse le long de la limite où le tir ne rencontre aucun
## décor. Rend NAN si le monde est bouché sur toute sa longueur.
func _couloir_libre() -> float:
	var espace := _joueur.get_world_3d().direct_space_state
	# ON ÉVITE LES COINS. Le premier jet retenait z = -72, c'est-à-dire
	# l'intersection des DEUX limites : un cas doublement particulier, le
	# pire endroit où chercher à isoler une cause.
	#
	# ET ON SONDE À LA HAUTEUR DU PROJECTILE, pas à hauteur de poitrine. Le
	# tir sort du canon vers 2,4 m ; un couloir dégagé à un mètre ne dit
	# rien de ce qu'il rencontre là-haut.
	for i in 48:
		var z := -50.0 + 100.0 * float(i) / 48.0
		var libre := true
		for h: float in [1.0, 2.0, 2.6]:
			var q := PhysicsRayQueryParameters3D.create(
					Vector3(PlanMonde.DEMI - 4.0, h, z),
					Vector3(PlanMonde.DEMI + 4.0, h, z))
			q.collision_mask = Cfg.LAYER_WORLD
			if not espace.intersect_ray(q).is_empty():
				libre = false
				break
		if libre:
			return z
	return NAN


## Place les deux corps, tire, et rend les dégâts infligés.
func _tirer_et_mesurer(ou_joueur: Vector3, ou_cible: Vector3) -> float:
	_joueur.global_position = ou_joueur
	_cible.global_position = ou_cible
	_cible.set(&"_target_pos", ou_cible)
	_cible.set(&"move_input", Vector2.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sante = _cible.get(&"health")
	sante.reset()
	var avant: float = sante.current_health
	# MISE EN JOUE AVANT DE TIRER. Le personnage PIVOTE vers sa visée : le
	# canon ne pointe la cible qu'au bout de quelques dixièmes de seconde.
	# Sans ce délai, la première rafale part de travers et le banc rendait
	# des résultats qui dépendaient de l'ordre des mesures — le même duel
	# ratait en premier et touchait en second.
	for i in 24:
		_joueur.set(&"aim_input", PlanMonde.ecart3(_joueur.global_position,
				_cible.global_position).normalized())
		await get_tree().physics_frame
	sante.reset()
	avant = sante.current_health
	for i in 90:
		# LA VISÉE EST REPOSÉE À CHAQUE IMAGE. Les deux corps bougent — le
		# repli les translate, la gravité les tasse — et une direction
		# calculée une seule fois rate la cible au bout d'une seconde.
		_joueur.set(&"aim_input", PlanMonde.ecart3(_joueur.global_position,
				_cible.global_position).normalized())
		_joueur.set(&"want_fire", true)
		await get_tree().physics_frame
	_joueur.set(&"want_fire", false)
	return avant - float(sante.current_health)


## Un projectile ne doit jamais s'éloigner indéfiniment : replié, il reste
## dans le voisinage du joueur tant qu'il vit.
## Les projectiles ne sont pas dans un groupe : on les reconnaît à leur
## script. Un groupe serait plus propre, mais l'ajouter pour un test
## reviendrait à modifier le jeu pour qu'il se laisse mesurer.
func _bref(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _projectiles() -> Array[Node3D]:
	# ON NE PARCOURT QUE LA SCÈNE COURANTE, pas la racine. Le premier jet
	# repartait de `get_tree().root` à chaque image : deux mille trois cents
	# nœuds visités quarante fois, et le banc n'a jamais fini.
	var sortie: Array[Node3D] = []
	var racine := get_tree().current_scene
	if racine == null:
		return sortie
	var pile: Array[Node] = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		# TYPE EXPLICITE. `get_script()` rend un Variant, et l'inférence sur
		# un Variant est traitée comme une ERREUR par ce projet : le script
		# ne se charge alors pas, la scène s'ouvre sans lui, plus personne
		# n'appelle `quit()` — et le banc tourne indéfiniment au lieu
		# d'échouer bruyamment. C'est le troisième blocage de cette forme.
		var sc: Script = n.get_script() as Script
		if sc != null and sc.resource_path.ends_with("projectile.gd") \
				and n is Node3D and (n as Node3D).visible:
			sortie.append(n as Node3D)
			continue
		for e in n.get_children():
			pile.append(e)
	return sortie


func _garantie_projectile_replie() -> void:
	await _poser_de_part_et_dautre(6.0)
	_joueur.set(&"aim_input", Vector3(1, 0, 0))
	_joueur.set(&"want_fire", true)
	for i in 10:
		await get_tree().physics_frame
	_joueur.set(&"want_fire", false)
	var loin := 0
	var vus := 0
	for i in 16:
		await get_tree().physics_frame
		for p in _projectiles():
			vus += 1
			if p.global_position.distance_to(_joueur.global_position) > 90.0:
				loin += 1
	print("      %d observations de projectile, %d au-delà de 90 m"
			% [vus, loin])
	_verifier("aucun projectile ne part à l'autre bout du monde", loin, 0)
