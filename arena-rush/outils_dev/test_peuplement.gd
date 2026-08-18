extends Node
## TEST DU PEUPLEMENT — outil de développement, hors jeu.
##
## POURQUOI : « il y a plus de mobs » et « le monde semble habité » ne sont
## pas des mesures. Ce banc laisse tourner une vraie session et compte ce
## qui se passe RÉELLEMENT — combien de bots vivent, combien de mobs
## apparaissent, et surtout OÙ. Un monde peuplé uniquement au centre serait
## exactement le défaut qu'on cherche à éviter, et aucune capture d'écran
## ne le montrerait.

var _main: Node
var _echecs := 0
var _total := 0

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	# On laisse le monde se remplir : le pondeur travaille par rafales, et
	# juger au bout de trois secondes ne mesurerait que le démarrage.
	await get_tree().create_timer(25.0).timeout
	_mesurer()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-50s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _mesurer() -> void:
	print("=== PEUPLEMENT ===")
	var joueurs := get_tree().get_nodes_in_group(&"players")
	var bots := 0
	for p in joueurs:
		if p.get(&"is_bot") == true:
			bots += 1
	_verifier("neuf bots peuplent le monde", bots, 9)

	var mobs := get_tree().get_nodes_in_group(&"mobs")
	print("      %d mobs vivants (plafond %d)" % [mobs.size(), MobSpawner.MAX_ALIVE])
	_verifier("au moins 12 mobs vivants", mobs.size() >= 12, true)

	# RÉPARTITION — le vrai sujet. Tout au centre serait une arène déguisée.
	var par_zone: Dictionary = {}
	for m in mobs:
		var p := Vector2((m as Node3D).global_position.x,
				(m as Node3D).global_position.z)
		var z := &"noyau" if p.length() <= PlanMonde.RAYON_NOYAU \
				else PlanMonde.secteur_de(p)
		par_zone[z] = int(par_zone.get(z, 0)) + 1
	print("      mobs par zone : %s" % str(par_zone))
	_verifier("les mobs occupent au moins trois zones",
			par_zone.size() >= 3, true)

	var zones_bots: Dictionary = {}
	var loin := 0
	for p in joueurs:
		if p.get(&"is_bot") != true:
			continue
		var v := Vector2((p as Node3D).global_position.x,
				(p as Node3D).global_position.z)
		var z := &"noyau" if v.length() <= PlanMonde.RAYON_NOYAU \
				else PlanMonde.secteur_de(v)
		zones_bots[z] = int(zones_bots.get(z, 0)) + 1
		if v.length() > PlanMonde.RAYON_NOYAU:
			loin += 1
	print("      bots par zone : %s" % str(zones_bots))
	# Si tous les bots convergeaient vers le centre, quatre secteurs sur
	# cinq seraient déserts — le monde paraîtrait vide dès qu'on s'écarte.
	_verifier("les bots se répartissent hors du noyau", loin >= 4, true)
	_verifier("les bots occupent au moins trois zones",
			zones_bots.size() >= 3, true)

	# Distance parcourue : un bot qui patrouille s'éloigne de son point de
	# départ. Immobiles, ils ne feraient qu'habiter la carte en apparence.
	var etendue := 0.0
	for p in joueurs:
		for q in joueurs:
			etendue = maxf(etendue,
					(p as Node3D).global_position.distance_to(
					(q as Node3D).global_position))
	print("      étendue occupée par les joueurs : %.0f m" % etendue)
	_verifier("les participants s'étalent sur plus de 50 m",
			etendue > 50.0, true)
