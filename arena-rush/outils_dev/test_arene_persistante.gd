extends Node
## TEST DE LA BOUCLE PERSISTANTE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER : la boucle demandée est « mourir puis revenir, sans
## fin ». C'est précisément le genre de chose qu'on ne voit pas en jouant
## deux minutes, et qui casse de dix façons discrètes : un joueur qui revient
## sans pouvoir tirer, une partie qui se déclare gagnée dans le dos, des bots
## qui ne reviennent jamais et une arène qui se vide.
##
## Le banc tue donc pour de vrai, attend le retour, et VÉRIFIE l'état complet
## du ressuscité — pas seulement qu'il est vivant.

var _main: Node
var _echecs := 0
var _total := 0

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	await _executer()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-52s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _joueur_local() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"peer_id") == Net.local_id():
			return p
	return null


func _un_bot() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			return p
	return null


func _executer() -> void:
	print("=== ARÈNE PERSISTANTE ===")
	_verifier("le mode est persistant", MatchDirector.est_persistant(), true)

	var j := _joueur_local()
	var bot := _un_bot()
	_verifier("un joueur local existe", j != null, true)
	_verifier("au moins un bot existe", bot != null, true)
	if j == null or bot == null:
		return

	# --- 1. TUER UN JOUEUR CRÉDITE-T-IL LE KILL ? -----------------------
	Profil.effacer()
	var kills_avant: int = Profil.total_kills_joueurs
	var xp_avant: int = Profil.xp_compte
	# On abat le bot AU NOM du joueur local, comme le ferait un projectile.
	bot.server_take_damage(99999.0, bot.global_position,
			j.get(&"peer_id"), Cfg.Team.PLAYER)
	for i in 6:
		await get_tree().process_frame
	_verifier("le kill est compté", Profil.total_kills_joueurs, kills_avant + 1)
	_verifier("l'XP a été versée", Profil.xp_compte,
			xp_avant + ConfigProgression.XP_JOUEUR)
	_verifier("la série est à 1", Profil.serie_actuelle, 1)
	_verifier("le bot est bien éliminé", bot.get(&"is_eliminated"), true)

	# --- 2. LE BOT REVIENT-IL ? -----------------------------------------
	# Sans cela l'arène se viderait, et il n'y aurait plus personne à
	# affronter au bout de quelques minutes.
	var attente := 0.0
	while bot.get(&"is_eliminated") == true and attente < 8.0:
		await get_tree().process_frame
		attente += get_process_delta_time()
	_verifier("le bot est revenu", bot.get(&"is_eliminated"), false)
	print("      revenu après %.2f s (délai réglé : %.1f s)"
			% [attente, ConfigProgression.DELAI_RESPAWN])

	# --- 3. LE RESSUSCITÉ EST-IL VRAIMENT OPÉRATIONNEL ? ----------------
	# Le piège : rallumer cinq drapeaux sur six donne un joueur qui court
	# mais ne tire pas, ou qu'on traverse. Chacun est vérifié.
	var pv = bot.get(&"health")
	_verifier("il a retrouvé toute sa vie",
			is_equal_approx(pv.current_health, pv.max_health), true)
	_verifier("il n'est plus marqué mort", pv.is_dead, false)
	_verifier("sa physique est rallumée", bot.is_physics_processing(), true)
	_verifier("ses collisions sont rétablies",
			bot.collision_layer, Cfg.LAYER_PLAYER)
	_verifier("il porte de nouveau une arme",
			bot.get(&"weapon").data != null, true)

	# --- 4. L'INVULNÉRABILITÉ PROTÈGE-T-ELLE VRAIMENT ? -----------------
	_verifier("il est protégé au retour", bot.call(&"est_protege"), true)
	var pv_avant: float = pv.current_health
	bot.server_take_damage(40.0, bot.global_position, j.get(&"peer_id"),
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	_verifier("les dégâts sont annulés pendant la protection",
			is_equal_approx(pv.current_health, pv_avant), true)

	# La protection doit EXPIRER : une invulnérabilité qui dure serait pire
	# que pas de protection du tout.
	var t := 0.0
	while bot.call(&"est_protege") and t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_verifier("la protection expire", bot.call(&"est_protege"), false)

	# --- 5. LA PARTIE NE SE TERMINE JAMAIS ------------------------------
	# On élimine TOUS les bots : en Battle Royale, cela déclarerait le
	# joueur vainqueur. Ici, rien ne doit s'arrêter.
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			p.server_take_damage(99999.0, p.global_position,
					j.get(&"peer_id"), Cfg.Team.PLAYER)
	for i in 10:
		await get_tree().process_frame
	_verifier("aucune fin de partie déclarée",
			MatchDirector.phase != MatchDirector.Phase.ENDED, true)
	_verifier("le joueur local est toujours en jeu",
			j.get(&"is_eliminated"), false)

	# --- 6. MOURIR SOI-MÊME, PUIS REVENIR -------------------------------
	var morts_avant: int = Profil.total_morts
	var serie_avant: int = Profil.serie_actuelle
	_verifier("la série avait grimpé", serie_avant >= 3, true)
	j.server_take_damage(99999.0, j.global_position, bot.get(&"peer_id"),
			Cfg.Team.PLAYER)
	for i in 6:
		await get_tree().process_frame
	_verifier("le joueur local est mort", j.get(&"is_eliminated"), true)

	var attente2 := 0.0
	while j.get(&"is_eliminated") == true and attente2 < 8.0:
		await get_tree().process_frame
		attente2 += get_process_delta_time()
	_verifier("le joueur local est revenu", j.get(&"is_eliminated"), false)
	_verifier("il n'a pas été expulsé de la partie",
			MatchDirector.players.has(j.get(&"peer_id")), true)
