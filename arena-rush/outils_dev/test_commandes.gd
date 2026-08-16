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

	# 4. CLIC DANS LE VIDE, hors interface → tir souris au bureau.
	await _clic(Vector2(640, 200), true)
	await get_tree().process_frame
	_verifier("clic hors interface (souris de bureau)", j.want_fire, true)
	await _clic(Vector2(640, 200), false)
