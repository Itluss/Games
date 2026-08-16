extends Node
## TEST DE NON-RÉGRESSION DES COMMANDES — outil de développement.
##
## DÉFAUT VISÉ : l'action « attack » était liée au clic gauche, et Godot
## traduit tout appui tactile en clic. Poser le pouce sur le joystick de
## déplacement déclenchait donc une rafale — « il tire tout seul ».
##
## Ce test ne relit pas le code : il INJECTE de vrais évènements aux
## coordonnées réelles des commandes et observe `want_fire`. C'est la
## seule preuve qui vaille, la précédente validation ayant justement
## échoué faute de tester ce qu'elle prétendait tester.

var _main: Node
var _etapes := 0
var _echecs := 0

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	await _executer()
	print("=== %d échec(s) ===" % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


func _joueur() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			return p
	var tous := get_tree().get_nodes_in_group(&"players")
	return tous[0] if tous.size() > 0 else null


func _hud() -> Node:
	return get_tree().get_first_node_in_group(&"hud")


func _clic(pos: Vector2, appui: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = appui
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _verifier(libelle: String, obtenu: bool, attendu: bool) -> void:
	_etapes += 1
	var ok := obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-46s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _animateur(j: Node) -> AnimationPlayer:
	return _chercher(j, "AnimationPlayer") as AnimationPlayer


func _chercher(n: Node, classe: String) -> Node:
	if n.is_class(classe):
		return n
	for c in n.get_children():
		var r := _chercher(c, classe)
		if r:
			return r
	return null


func _verifier_texte(libelle: String, obtenu: String, attendu: String) -> void:
	_etapes += 1
	var ok := obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-46s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


## Taille minimale, en mètres, sous laquelle une arme est invisible.
const ARME_MIN := 0.08


func _verifier_arme(j: Node) -> void:
	var visuel = j.get(&"visual")
	var accroche: Node3D = visuel.get_weapon_mount() if visuel else null
	if accroche == null or accroche.get_child_count() == 0:
		_verifier("une arme est accrochée à la main", false, true)
		return
	# Le premier enfant est le nœud Weapon lui-même, pas sa silhouette :
	# on cherche le maillage, seul objet dont la taille se voie.
	var modele := _chercher(accroche, "MeshInstance3D") as Node3D
	if modele == null:
		_verifier("un maillage d'arme est accroché", false, true)
		return
	var taille := modele.global_transform.basis.get_scale().x
	_etapes += 1
	var ok := taille > ARME_MIN
	if not ok:
		_echecs += 1
	print("  [%s] %-46s échelle rendue=%.4f  minimum=%.2f"
			% ["OK" if ok else "ÉCHEC", "l'arme est à une taille visible",
			taille, ARME_MIN])


func _verifier_cadence(j: Node) -> void:
	var arme = j.get(&"weapon")
	if arme == null or arme.data == null:
		_verifier("arme équipée pour tester la cadence", false, true)
		return
	var cd: float = arme.data.cooldown()

	# À mi-délai : refusé si l'on maintient, accordé si l'on tapote.
	arme._cooldown = cd * 0.40
	_verifier("à 40 % du délai, gâchette MAINTENUE → refus",
			arme.can_fire(false), false)
	arme._cooldown = cd * 0.40
	_verifier("à 40 % du délai, appui NEUF → tir accordé",
			arme.can_fire(true), true)

	# Le gain est BORNÉ : tapoter n'autorise pas à tirer immédiatement,
	# sans quoi un client modifié tirerait en continu.
	arme._cooldown = cd * 0.90
	_verifier("à 90 % du délai, appui NEUF → refus (gain borné)",
			arme.can_fire(true), false)
	arme._cooldown = 0.0


## Écart maximal toléré, en degrés, entre le canon et l'avant du corps.
const CANON_ECART_MAX := 12.0


func _verifier_canon(j: Node) -> void:
	var visuel = j.get(&"visual")
	var accroche: Node3D = visuel.get_weapon_mount() if visuel else null
	if accroche == null:
		_verifier("un point d'accroche existe", false, true)
		return
	var canon := -accroche.global_transform.basis.z.normalized()
	# `j` est typé Node : sans transtypage explicite, GDScript ne sait pas
	# inférer le type de `global_transform` et refuse de compiler.
	var corps := j as Node3D
	var avant := -corps.global_transform.basis.z.normalized()
	var ecart := rad_to_deg(canon.angle_to(avant))
	_etapes += 1
	var ok := ecart < CANON_ECART_MAX
	if not ok:
		_echecs += 1
	print("  [%s] %-46s écart=%.1f°  maximum=%.0f°"
			% ["OK" if ok else "ÉCHEC", "le canon pointe vers l'avant du corps",
			ecart, CANON_ECART_MAX])


## Martèle le bouton et surveille l'animation entre les appuis.
func _verifier_repetition(j: Node, ap: AnimationPlayer, bouton: Control) -> void:
	var centre := bouton.get_global_rect().get_center()
	print("  … martèlement en cours", " ")
	var decroche := 0
	var observees := {}
	for cycle in 4:
		await _clic(centre, true)
		await get_tree().process_frame
		await _clic(centre, false)
		# Entre deux appuis : c'est LÀ que la posture décrochait.
		for i in 5:
			await get_tree().process_frame
			var a := ap.current_animation
			observees[a] = true
			# Les deux premiers cycles servent à installer la posture.
			if cycle >= 2 and a != "garde":
				decroche += 1
	print("      clips vus pendant le martèlement : ", observees.keys())
	_verifier("tir à répétition → la posture ne décroche pas",
			decroche == 0, true)


func _executer() -> void:
	var j := _joueur()
	var h := _hud()
	if j == null or h == null:
		print("ÉCHEC : joueur ou HUD introuvable (j=%s h=%s)" % [j, h])
		_echecs += 1
		return

	var stick: Control = h.get(&"_move_stick")
	var bouton: Control = h.get(&"_fire_button")
	print("joystick gauche : ", stick.get_global_rect())
	print("bouton de tir   : ", bouton.get_global_rect())

	_verifier("au repos, aucun tir", j.want_fire, false)

	# 1. APPUI SUR LE JOYSTICK DE DÉPLACEMENT → ne doit PAS tirer.
	await _clic(stick.get_global_rect().get_center(), true)
	await get_tree().process_frame
	_verifier("appui sur le joystick gauche", j.want_fire, false)
	await _clic(stick.get_global_rect().get_center(), false)

	# 2. APPUI SUR LE BOUTON DE TIR → doit tirer.
	await _clic(bouton.get_global_rect().get_center(), true)
	await get_tree().process_frame
	await get_tree().process_frame
	_verifier("appui sur le bouton de tir", j.want_fire, true)

	# 3. RELÂCHEMENT → doit cesser de tirer.
	await _clic(bouton.get_global_rect().get_center(), false)
	await get_tree().process_frame
	await get_tree().process_frame
	_verifier("relâchement du bouton de tir", j.want_fire, false)

	# 3 bis. CE QUE L'ON VOIT, et pas seulement ce que le jeu croit.
	#
	# Le retour de test était : « quand j'appuie sur tir, il ne prend pas
	# la position de tir ». `want_fire` passait pourtant bien à vrai — le
	# défaut était PLUS LOIN, dans le choix du clip, faute d'animation de
	# tir à l'arrêt. Vérifier l'intention ne suffit donc pas : on lit
	# l'animation réellement jouée.
	var ap := _animateur(j)
	if ap == null:
		print("  [ÉCHEC] AnimationPlayer introuvable")
		_echecs += 1
	else:
		await _clic(bouton.get_global_rect().get_center(), true)
		for i in 30:
			await get_tree().process_frame
		_verifier_texte("à l'arrêt, gâchette pressée → posture de garde",
				ap.current_animation, "garde")
		await _clic(bouton.get_global_rect().get_center(), false)
		for i in 30:
			await get_tree().process_frame
		_verifier_texte("gâchette relâchée → retour au repos",
				ap.current_animation, "repos")

	# 3 ter. L'ARME EST-ELLE VISIBLE DANS LA MAIN ?
	#
	# Retour de test : « il n'a pas l'arme entre les mains ». Elle y était
	# pourtant, et au bon endroit — mais rendue à 7 mm. Le rig Meshy est
	# exprimé en centimètres, et le point d'accroche héritait de son
	# échelle de 0,01. On mesure donc la TAILLE RENDUE, seule chose qui
	# décide si l'on voit l'arme ou non.
	_verifier_arme(j)

	# 3 quater. CADENCE. Maintenue, la gâchette tire au rythme de l'arme ;
	# un appui NEUF peut écourter une part du délai. Test direct sur
	# l'arme, donc déterministe — pas de dépendance à la vitesse du runner.
	_verifier_cadence(j)

	# 3 quinquies. TIR À RÉPÉTITION. C'est le cas qui n'allait pas : en
	# tapotant, l'intention de tir n'est vraie que quelques trames par
	# appui, si bien que l'orientation du corps ET l'animation
	# basculaient plusieurs fois par seconde. On simule un joueur qui
	# martèle le bouton et on vérifie que la posture NE DÉCROCHE PAS.
	if ap != null:
		await _verifier_repetition(j, ap, bouton)

	# 3 sexies. L'ARME POINTE-T-ELLE OÙ L'ON TIRE ?
	#
	# Elle était bien dans la main, mais son canon suivait les axes de
	# l'OS, à 150,6° de l'avant du personnage : elle pointait vers
	# l'arrière. Une arme qui vise ailleurs que la trajectoire ment sur
	# le jeu.
	_verifier_canon(j)

	# 4. CLIC DANS LE VIDE, hors interface → tir souris au bureau.
	await _clic(Vector2(640, 200), true)
	await get_tree().process_frame
	_verifier("clic hors interface (souris de bureau)", j.want_fire, true)
	await _clic(Vector2(640, 200), false)
