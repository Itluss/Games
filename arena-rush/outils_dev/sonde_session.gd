extends Node
## SONDE DE SESSION — outil de développement, hors jeu.
##
## POURQUOI : la sonde statique n'a trouvé aucun trou dans la carte. Le
## défaut « écran violet » vient donc de quelque chose qui BOUGE. On laisse
## donc tourner une vraie partie et on surveille, image par image, les trois
## grandeurs qui peuvent produire un écran vide :
##
##   • la hauteur des joueurs — tomber sous le sol donne exactement cette
##     image, puisque le sol est à face unique et disparaît vu de dessous ;
##   • leur distance au centre — sortir du monde le met hors de tout décor ;
##   • l'écart entre la caméra et sa cible — une caméra restée en arrière
##     regarderait le vide.

var _main: Node
var _y_min := INF
var _y_min_qui := ""
var _r_max := 0.0
var _r_max_qui := ""
var _ecart_max := 0.0
var _sous_le_sol := 0
var _hors_monde := 0
var _t := 0.0
var _frames_perdues := 0
var _duree_perdue := 0.0
var _episodes := 0
var _episode := 0.0
var _pire_angle := 0.0

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	for n in get_tree().get_nodes_in_group(&"players"):
		var p := n as Node3D
		if p == null:
			continue
		var nom := str(p.get(&"display_name"))
		if p.global_position.y < _y_min:
			_y_min = p.global_position.y
			_y_min_qui = nom
		# Sous -2 m, il n'y a plus de sol : le joueur tombe pour de bon.
		if p.global_position.y < -2.0:
			_sous_le_sol += 1
		var r := Vector2(p.global_position.x, p.global_position.z).length()
		if r > _r_max:
			_r_max = r
			_r_max_qui = nom
		if r > PlanMonde.DEMI * 1.5:
			_hors_monde += 1
		if cam != null and p.get(&"peer_id") == Net.local_id():
			var attendu := p.global_position + Vector3(0, 13.0, 10.0)
			var ecart := cam.global_position.distance_to(attendu)
			_ecart_max = maxf(_ecart_max, ecart)
			# COMBIEN DE TEMPS L'ÉCART DURE-T-IL ? Un pic d'un dixième de
			# seconde est un mouvement de caméra ; un écart qui tient
			# plusieurs secondes est un écran perdu.
			if ecart > 25.0:
				_frames_perdues += 1
				_duree_perdue += delta
				if _episode <= 0.0:
					_episodes += 1
					print("      t=%.1f s : la caméra décroche à %.0f m"
							% [_t, ecart])
				_episode = 0.6
			else:
				_episode = maxf(0.0, _episode - delta)
			# Que voit-on ? La caméra regarde-t-elle encore le joueur ?
			if ecart > 25.0:
				var vers := (p.global_position - cam.global_position).normalized()
				var regard := -cam.global_transform.basis.z
				_pire_angle = maxf(_pire_angle,
						rad_to_deg(acos(clampf(vers.dot(regard), -1.0, 1.0))))

	if _t > 55.0:
		_conclure()


func _conclure() -> void:
	set_process(false)
	print("=== SONDE DE SESSION (%.0f s) ===" % _t)
	print("  hauteur la plus basse atteinte : %.2f m (%s)" % [_y_min, _y_min_qui])
	print("  distance au centre maximale    : %.1f m (%s) — limite %.0f m"
			% [_r_max, _r_max_qui, PlanMonde.DEMI])
	print("  images passées sous le sol     : %d" % _sous_le_sol)
	print("  images passées hors du monde   : %d" % _hors_monde)
	print("  écart caméra/cible maximal     : %.1f m" % _ecart_max)
	print("  décrochages (> 25 m)           : %d épisode(s), %.1f s cumulées"
			% [_episodes, _duree_perdue])
	print("  angle max entre le regard et le joueur : %.0f°" % _pire_angle)
	var ok := _sous_le_sol == 0 and _hors_monde == 0 and _duree_perdue < 0.5
	# La ligne de verdict est aussi la MARQUE DE FIN lue par `barriere.sh`,
	# d'où sa forme : le lanceur cherche « échec(s) === » pour distinguer
	# un banc conforme d'un banc qui s'est arrêté en route.
	print("=== %d échec(s) ===" % (0 if ok else 1))
	print("Session : %s." % ("conforme" if ok else "anomalie trouvée"))
	get_tree().quit(0 if ok else 1)
