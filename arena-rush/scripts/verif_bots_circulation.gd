extends Node3D
## BANC DE CIRCULATION — 12 capsules debug (sans combat), une par spawn.
## Chacune choisit au hasard la sortie horaire ou antihoraire de son
## secteur, traverse le hub associé, l'anneau, puis rejoint l'entrée de
## Core de ce hub — en suivant le graphe de navigation de `BlockoutPlan`
## (le même que le validateur), donc en collision RÉELLE, pas en
## téléportation. Ne remplace pas le joueur contrôlable : uniquement un
## test de circulation.
##
## Les 12 capsules avancent dans UNE SEULE boucle physique partagée (pas
## 12 coroutines indépendantes) : Godot 4.3 exige `await` au point
## d'appel d'une coroutine, donc le schéma « lancer sans attendre, puis
## attendre plus tard » (utilisé dans une première version) ne compile
## pas (« Function is a coroutine, so it must be called with await »).
## Un pas-à-pas manuel, une image à la fois pour les 12 en même temps,
## évite complètement le problème.
##
## Usage : godot --headless --path arena-rush
##         res://scenes/verif_bots_circulation.tscn

const VITESSE := 3.0
## Certains sauts spawn→sortie dépassent 40 m (jusqu'à ~43 m) : à 3 m/s
## ça prend ~14,5 s (870 images), pas les 500 (8,3 s) prévus au départ —
## tous les bots échouaient exactement à ticks=501, aucun blocage réel
## (trouvé en ajoutant un print de diagnostic sur chaque échec).
const MAX_TICKS_PAR_ETAPE := 1000
const IMMOBILE_LIMITE := 90


func _ready() -> void:
	var arene := BlockoutBuilder.new()
	add_child(arene)
	await get_tree().process_frame
	await get_tree().physics_frame

	var bots: Array[Dictionary] = []
	for s: Dictionary in BlockoutPlan.SPAWNS:
		bots.append(_creer_bot(s))

	# --- Boucle partagée : chaque image, on avance TOUS les bots actifs --
	var actifs := bots.size()
	var garde := 0
	while actifs > 0 and garde < 6000:
		garde += 1
		actifs = 0
		for b in bots:
			if b["fini"]:
				continue
			actifs += 1
			_avancer_bot_dun_pas(b)
		await get_tree().physics_frame

	# --- Résultats ---------------------------------------------------
	var par_hub: Dictionary = {}
	for hub in BlockoutPlan.HUBS:
		par_hub[hub] = []
	var echecs := 0
	print("")
	for b in bots:
		var ok: bool = b["ok"]
		print("  %s (%s, sortie %s) -> hub %s : %s" % [
			b["nom"], b["secteur"], b["sens"], b["hub"], "OK" if ok else "FAIL"])
		if ok:
			(par_hub[b["hub"]] as Array).append(b["secteur"])
		else:
			echecs += 1
		b["corps"].queue_free()

	print("")
	var hubs_a_2_secteurs := 0
	for hub in BlockoutPlan.HUBS:
		var secteurs: Array = par_hub[hub]
		var distincts: Dictionary = {}
		for sec in secteurs:
			distincts[sec] = true
		print("Hub %s : %d capsule(s) arrivée(s), %d secteur(s) distinct(s) présent(s) (%s)" % [
			hub, secteurs.size(), distincts.size(), str(distincts.keys())])
		if distincts.size() >= 2:
			hubs_a_2_secteurs += 1
	print("")
	print(("Hubs avec ≥2 secteurs représentés CE TIRAGE : %d/4 (la garantie structurelle — "
			+ "chaque hub EST relié aux 2 secteurs voisins — est vérifiée à part par le "
			+ "validateur ; ceci ne mesure que le tirage aléatoire de cette exécution)")
			% hubs_a_2_secteurs)

	print("")
	print("BOTS DE CIRCULATION : %s (%d/12 réussis)" % [
		"OK" if echecs == 0 else "ÉCHEC", 12 - echecs])
	get_tree().quit(echecs)


func _creer_bot(s: Dictionary) -> Dictionary:
	var nom: String = s["nom"]
	var secteur: String = s["secteur"]
	var sens := "cw" if (randi() % 2 == 0) else "ccw"
	var hub: String = BlockoutPlan.SECTEUR_HUBS[secteur][sens]
	var r: Dictionary = BlockoutPlan.chemin_le_plus_court(
			"spawn_%s" % nom, "entree_core_%s" % hub)

	var corps := CharacterBody3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.8
	corps.add_child(col)
	# Couche 2, masque 1 : les bots restent bloqués par le monde statique
	# (couche 1) mais s'ignorent entre eux. Sans ça, plusieurs bots visant
	# le même centre de hub se coincent mutuellement (le trafic de 12
	# joueurs réels se répartirait naturellement) — ce n'est pas ce que ce
	# banc mesure (la circulation à travers la géométrie du monde), donc
	# ça fausserait le résultat sans révéler un vrai défaut de niveau
	# (trouvé en testant : tous les bots échouaient « immobile » pile
	# près d'un centre de hub, jamais ailleurs).
	corps.collision_layer = 2
	corps.collision_mask = 1
	var pos0: Vector2 = s["pos"]
	corps.position = Vector3(pos0.x, 1.0, pos0.y)
	add_child(corps)

	var points: Array[Vector3] = []
	for nom_noeud in (r["chemin"] as Array):
		if nom_noeud == "spawn_%s" % nom:
			continue
		var p: Vector2 = BlockoutPlan.NAV_NOEUDS[nom_noeud]
		points.append(Vector3(p.x, 0.0, p.y))

	return {
		"nom": nom, "secteur": secteur, "sens": sens, "hub": hub, "corps": corps,
		"points": points, "index": 0, "fini": points.is_empty(), "ok": not points.is_empty(),
		"immobile": 0, "derniere_pos": corps.global_position, "ticks_etape": 0,
	}


func _avancer_bot_dun_pas(b: Dictionary) -> void:
	var corps: CharacterBody3D = b["corps"]
	var points: Array = b["points"]
	var cible: Vector3 = points[b["index"]]
	var vers := Vector2(cible.x, cible.z) - Vector2(corps.global_position.x, corps.global_position.z)

	if vers.length() < 1.2:
		b["index"] += 1
		b["ticks_etape"] = 0
		b["immobile"] = 0
		if b["index"] >= points.size():
			b["fini"] = true
			b["ok"] = true
		return

	vers = vers.normalized() * VITESSE
	corps.velocity.x = vers.x
	corps.velocity.z = vers.y
	if not corps.is_on_floor():
		corps.velocity.y -= 20.0 * get_physics_process_delta_time()
	else:
		corps.velocity.y = 0.0
	corps.move_and_slide()

	if corps.global_position.distance_to(b["derniere_pos"]) < 0.005:
		b["immobile"] += 1
	else:
		b["immobile"] = 0
	b["derniere_pos"] = corps.global_position
	b["ticks_etape"] += 1

	if b["immobile"] > IMMOBILE_LIMITE or b["ticks_etape"] > MAX_TICKS_PAR_ETAPE:
		b["fini"] = true
		b["ok"] = false
		print("    DEBUG %s a échoué à l'étape %d/%d, pos=%s cible=%s immobile=%d ticks=%d" % [
			b["nom"], b["index"], points.size(), corps.global_position, cible,
			b["immobile"], b["ticks_etape"]])
