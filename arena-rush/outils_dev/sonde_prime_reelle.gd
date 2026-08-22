extends Node
## SONDE DE LA PRIME EN CONDITIONS RÉELLES — le chemin complet, pas les
## fonctions appelées à la main : un VRAI mob abattu par le joueur, un
## VRAI bot abattu, et la photo de ce que le joueur VOIT.

var _joueur: Node3D

func _ready() -> void:
	print("SONDE: demarrage")
	get_window().size = Vector2i(1280, 720)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(3.0).timeout
	print("SONDE: monde charge")
	var bots: Array = []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			bots.append(p)
		else:
			_joueur = p
	for b in bots:
		var cerveau = (b as Node).get_node_or_null("Brain")
		if cerveau:
			cerveau.set_physics_process(false)
			cerveau.set_process(false)
	# ─── 1. UN VRAI MOB, TUÉ PAR LE VRAI CHEMIN ───────────────────────
	# Les mobs arrivent par vagues après le départ : on les ATTEND.
	var mobs: Array = []
	for essai in 50:
		mobs = get_tree().get_nodes_in_group(&"mobs")
		if not mobs.is_empty():
			break
		await get_tree().create_timer(0.5).timeout
	print("mobs en scène : %d" % mobs.size())
	var avant: int = _joueur.get(&"prime")
	if not mobs.is_empty():
		var m := mobs[0] as Node3D
		# Tout près : la pièce lâchée doit tomber dans le rayon de
		# ramassage du tueur (0,25–0,60 m autour du mob).
		m.global_position = _joueur.global_position + Vector3(0.6, 0, 0)
		m.call(&"server_take_damage", 9999.0, m.global_position,
				_joueur.get(&"peer_id"), Cfg.Team.PLAYER)
		await get_tree().create_timer(0.1).timeout
		print("pieces posees par le mob : %d" % PrimeDirector._pieces.size())
		await get_tree().create_timer(0.7).timeout
	print("VERIF mob : prime %d -> %d (attendu +1, via la pièce au sol)"
			% [avant, _joueur.get(&"prime")])
	# ─── 2. UN BOT À PRIME NULLE — les poches du mort ─────────────────
	var b0 := bots[0] as Node3D
	b0.global_position = _joueur.global_position + Vector3(5, 0, 0)
	b0.set(&"_protection", 0.0)
	(b0.get(&"health") as Node).set(&"_invulnerable_until", 0.0)
	avant = _joueur.get(&"prime")
	var pieces_avant: int = PrimeDirector._pieces.size()
	b0.call(&"server_take_damage", 9999.0, b0.global_position,
			_joueur.get(&"peer_id"), Cfg.Team.PLAYER)
	await get_tree().create_timer(0.5).timeout
	print("VERIF duel prime 0 : prime %d -> %d (attendu +5)"
			% [avant, _joueur.get(&"prime")])
	print("VERIF poches du mort : %d piece(s) au sol (attendu >= 3)"
			% (PrimeDirector._pieces.size() - pieces_avant))
	# ─── 3. UN BOT AVEC PRIME, TUÉ PAR LE VRAI CHEMIN ─────────────────
	var b1 := bots[1] as Node3D
	b1.global_position = _joueur.global_position + Vector3(-5, 0, 0)
	b1.call(&"crediter_prime", 8)
	await get_tree().process_frame
	b1.set(&"_protection", 0.0)
	(b1.get(&"health") as Node).set(&"_invulnerable_until", 0.0)
	avant = _joueur.get(&"prime")
	b1.call(&"server_take_damage", 9999.0, b1.global_position,
			_joueur.get(&"peer_id"), Cfg.Team.PLAYER)
	await get_tree().create_timer(0.5).timeout
	print("VERIF duel : prime %d -> %d (attendu +5 + 4 = +9)"
			% [avant, _joueur.get(&"prime")])
	print("VERIF pieces au sol : %d" % PrimeDirector._pieces.size())
	# ─── 4. LA PHOTO DE CE QUE LE JOUEUR VOIT ─────────────────────────
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/claude-0/-home-user-IronWolf/88b88d81-1808-586a-930b-2f060879b0e8/scratchpad/prime_reelle.png")
	print("SONDE: terminee")
	get_tree().quit(0)
