extends Node3D
## VÉRIFICATION DE COLLISION (V2) — déplace une capsule (dimensions de
## Milo) le long de trajets RÉELS à travers la géométrie construite, pour
## confirmer qu'aucun mur/rampe/plateforme ne bloque ni ne laisse passer
## le joueur. Réutilise le graphe de navigation de `BlockoutPlan` (déjà
## validé par `validateur_arena01.gd`) comme suite de points de passage —
## la même donnée sert donc à la fois la preuve topologique (le
## validateur) et la preuve physique (ce script), au lieu de deux
## trajectoires devinées indépendamment qui pourraient diverger.
##
## Usage : godot --headless --path arena-rush
##         res://scenes/verif_deplacement.tscn

const VITESSE := 3.0


func _ready() -> void:
	var arene := BlockoutBuilder.new()
	add_child(arene)
	await get_tree().process_frame
	await get_tree().physics_frame

	var corps := CharacterBody3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	corps.add_child(col)
	add_child(corps)

	var tout_ok := true

	# --- 1) Trajets réels spawn → Core, via le graphe de navigation -----
	# Un spawn par secteur, en variant cw/ccw, pour couvrir les 4 hubs.
	var essais_spawns := ["S01", "S05", "S07", "S11"]
	for nom_spawn in essais_spawns:
		var spawn_pos := _pos_spawn(nom_spawn)
		var meilleur_hub := ""
		var meilleure_dist := INF
		var meilleur_chemin: Array = []
		for hub in BlockoutPlan.HUBS:
			var r: Dictionary = BlockoutPlan.chemin_le_plus_court(
					"spawn_%s" % nom_spawn, "entree_core_%s" % hub)
			if r["distance"] < meilleure_dist:
				meilleure_dist = r["distance"]
				meilleur_hub = hub
				meilleur_chemin = r["chemin"]
		corps.position = Vector3(spawn_pos.x, 1.0, spawn_pos.y)
		corps.velocity = Vector3.ZERO
		await get_tree().physics_frame
		var ok := await _suivre_chemin(corps, meilleur_chemin,
				"%s → Core (via %s)" % [nom_spawn, meilleur_hub])
		if not ok:
			tout_ok = false

	# --- 2) Confirme que la sortie centrale directe est bien bloquée ----
	# Vise le Core en ligne droite depuis un spawn central (sur l'axe
	# cardinal) : le gros bloqueur doit empêcher d'y arriver.
	var s02 := _pos_spawn("S02")
	corps.position = Vector3(s02.x, 1.0, s02.y)
	corps.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var bloque := await _tenter_ligne_droite(corps, Vector3.ZERO, "S02 → Core (ligne droite)")
	_dire("la sortie centrale directe de Sanctuary est bien bloquée", bloque)
	if not bloque:
		tout_ok = false

	# --- 3) Chaque plateforme haute (socle plein, 2 rampes) -------------
	# Vise D'ABORD le point d'attache de la rampe (son « haut »), PAS
	# directement le centre du socle : viser le centre en continu fait
	# dériver la capsule hors de la rampe (large de 3 m seulement) avant
	# le sommet, elle tombe alors sur le côté et se coince contre le
	# socle — trouvé en testant : elle s'arrêtait systématiquement à mi-
	# hauteur (y≈4,6 sur 6), jamais plus haut ni en chute.
	for p: Dictionary in BlockoutPlan.PLATEFORMES:
		var nom: String = p["nom"]
		var acces: Array = p["acces"]
		for i in acces.size():
			var depart: Vector2 = acces[i]
			corps.position = Vector3(depart.x, 0.5, depart.y)
			corps.velocity = Vector3.ZERO
			await get_tree().physics_frame
			var rect: Rect2 = p["rect"]
			var sommet := rect.position + rect.size * 0.5
			var haut_rampe := _trouver_haut_rampe(depart)
			# Critère de réussite = la HAUTEUR atteinte (monter sur la
			# plateforme), pas la distance XZ au centre géométrique exact
			# du socle : viser le centre pile après avoir grimpé revient à
			# marcher en diagonale sur un toit plat de 7×7 m, ce qui
			# n'a rien à voir avec « la plateforme est-elle praticable ».
			await _suivre_points(corps,
					[Vector3(haut_rampe.x, p["y"], haut_rampe.y), Vector3(sommet.x, p["y"], sommet.y)],
					"", true)
			var ok: bool = corps.global_position.y > p["y"] - 0.5
			_dire("%s : accès %d → sommet (y=%.0f)" % [nom, i + 1, p["y"]], ok,
					"hauteur atteinte=%.2f" % corps.global_position.y)
			if not ok:
				tout_ok = false

	print("")
	print("VERIF DEPLACEMENT : %s" % ("OK" if tout_ok else "ÉCHEC"))
	get_tree().quit(0 if tout_ok else 1)


## Retrouve, pour un point de départ de rampe donné, son point d'arrivée
## (« haut ») dans `BlockoutPlan.RAMPES`.
func _trouver_haut_rampe(bas: Vector2) -> Vector2:
	for r: Dictionary in BlockoutPlan.RAMPES:
		if (r["bas"] as Vector2).distance_to(bas) < 0.01:
			return r["haut"]
	return bas


func _pos_spawn(nom: String) -> Vector2:
	for s: Dictionary in BlockoutPlan.SPAWNS:
		if s["nom"] == nom:
			return s["pos"]
	return Vector2.ZERO


## Suit une liste de noms de nœuds du graphe de navigation, en 3D (y du
## nœud = 0 sauf pour les entrées de plateforme, gérées séparément).
func _suivre_chemin(corps: CharacterBody3D, chemin: Array, etiquette: String) -> bool:
	var points: Array[Vector3] = []
	for nom in chemin:
		var p: Vector2 = BlockoutPlan.NAV_NOEUDS[nom]
		points.append(Vector3(p.x, 0.0, p.y))
	return await _suivre_points(corps, points, etiquette)


## Avance vers chaque point de la liste, dans l'ordre, en pilotant la
## vélocité directement (pas de clavier simulé : on teste la collision).
## `silencieux` : ne pas juger/annoncer le résultat ici (l'appelant a son
## propre critère de réussite, ex. la hauteur atteinte pour les rampes).
func _suivre_points(corps: CharacterBody3D, points: Array, etiquette: String,
		silencieux := false) -> bool:
	var tout_ok := true
	for cible in points:
		var depart := corps.global_position
		var distance_depart := Vector2(depart.x, depart.z).distance_to(Vector2(cible.x, cible.z))
		var bloque_immobile := 0
		var derniere_pos := depart
		for i in 600:  # jusqu'à 10 s à 60 Hz
			var vers := Vector2(cible.x, cible.z) - Vector2(corps.global_position.x, corps.global_position.z)
			if vers.length() < 1.0:
				break
			vers = vers.normalized() * VITESSE
			corps.velocity.x = vers.x
			corps.velocity.z = vers.y
			if not corps.is_on_floor():
				corps.velocity.y -= 20.0 * get_physics_process_delta_time()
			else:
				corps.velocity.y = 0.0
			corps.move_and_slide()
			await get_tree().physics_frame
			if corps.global_position.distance_to(derniere_pos) < 0.005:
				bloque_immobile += 1
			else:
				bloque_immobile = 0
			derniere_pos = corps.global_position
			if bloque_immobile > 90:
				break
		var arrivee := corps.global_position
		var distance_restante := Vector2(arrivee.x, arrivee.z).distance_to(Vector2(cible.x, cible.z))
		var chute := arrivee.y < -2.0
		# Seuil STRICT sur la distance restante — pas de clause « 60% du
		# trajet parcouru » : ce genre de seuil relatif a déjà laissé
		# passer un vrai bug (une capsule bloquée à 4-7 m d'une cible
		# après en avoir parcouru 30-40 m affichait quand même >60% de
		# progrès, alors qu'elle n'était jamais arrivée).
		var ok := not chute and distance_restante < 3.0
		if not ok:
			tout_ok = false
			if not silencieux:
				print("    (distance_depart=%.1f distance_restante=%.1f)" % [distance_depart, distance_restante])
	if not silencieux:
		_dire(etiquette, tout_ok, "arrivée finale=%s" % corps.global_position)
	return tout_ok


## Fonce en ligne droite vers `cible` et retourne VRAI si la capsule reste
## bloquée avant d'y arriver (utilisé pour prouver qu'un blocage marche).
func _tenter_ligne_droite(corps: CharacterBody3D, cible: Vector3, etiquette: String) -> bool:
	var bloque_immobile := 0
	var derniere_pos := corps.global_position
	for i in 600:
		var vers := Vector2(cible.x, cible.z) - Vector2(corps.global_position.x, corps.global_position.z)
		if vers.length() < 1.0:
			return false  # est arrivé — PAS bloqué, donc échec du test
		vers = vers.normalized() * VITESSE
		corps.velocity.x = vers.x
		corps.velocity.z = vers.y
		if not corps.is_on_floor():
			corps.velocity.y -= 20.0 * get_physics_process_delta_time()
		else:
			corps.velocity.y = 0.0
		corps.move_and_slide()
		await get_tree().physics_frame
		if corps.global_position.distance_to(derniere_pos) < 0.005:
			bloque_immobile += 1
		else:
			bloque_immobile = 0
		derniere_pos = corps.global_position
		if bloque_immobile > 60:
			return true  # coincé avant d'arriver = bloqueur efficace
	return corps.global_position.distance_to(cible) > 5.0


func _dire(nom: String, ok: bool, detail: String = "") -> void:
	print("[%s] %s%s" % ["OK" if ok else "FAIL", nom, ("  — " + detail) if detail != "" else ""])
