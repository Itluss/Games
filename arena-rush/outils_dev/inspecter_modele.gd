extends Node
## POURQUOI LE TIR NE PART PAS EN DÉBUT DE PARTIE — outil de dev.
##
## On maintient le bouton de tir dès la toute première trame et on relève
## à chaque instant TOUT ce qui pourrait bloquer : présence du joueur,
## arme équipée, munitions, recharge, phase de partie, élimination.
## La colonne qui reste bloquante quand rien ne part est la réponse.

var _presse := false
var _dernier_rect := Rect2()

func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())
	await _observer()
	get_tree().quit()

func _projectiles(n: Node = null) -> int:
	if n == null:
		n = get_tree().current_scene
	var t := 0
	if n is Projectile and (n as Node3D).visible:
		t += 1
	for c in n.get_children():
		t += _projectiles(c)
	return t

func _observer() -> void:
	var t0 := Time.get_ticks_msec()
	var dernier := ""
	var premier_tir := -1.0
	for i in 260:
		await get_tree().process_frame
		var s := (Time.get_ticks_msec() - t0) / 1000.0
		var hud := get_tree().get_first_node_in_group(&"hud")
		var j: Node = null
		for p in get_tree().get_nodes_in_group(&"players"):
			j = p
			break
		# Dès que le bouton existe, on APPUIE et on ne relâche plus.
		# LE BANC MENT-IL ? Si le rectangle du bouton n'est pas encore
		# calculé, mon clic tombe à côté et « l'appui perdu » que je
		# mesure est mon propre défaut, pas celui du jeu.
		if hud:
			var bb: Control = hud.get(&"_fire_button")
			if bb:
				var r := bb.get_global_rect()
				if r != _dernier_rect:
					print("[%5.2f s] rectangle du bouton = %s" % [s, r])
					_dernier_rect = r
		if hud and not _presse:
			var b: Control = hud.get(&"_fire_button")
			if b:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = true
				e.position = b.get_global_rect().get_center()
				e.global_position = e.position
				Input.parse_input_event(e)
				_presse = true
				print("[%5.2f s] appui MAINTENU sur le bouton de tir" % s)
		# On sépare les trois maillons de la chaîne : le HUD a-t-il
		# ENREGISTRÉ l'appui ? le contrôleur TOURNE-t-il ? le joueur
		# a-t-il reçu l'intention ?
		var tenu := "?"
		if hud:
			tenu = str(hud.get(&"_fire_held"))
		var ctrl: Node = null
		for n in get_tree().get_nodes_in_group(&"players"):
			for c in n.get_children():
				if c is PlayerController:
					ctrl = c
		if ctrl == null:
			for c in get_tree().current_scene.get_children():
				if c is PlayerController:
					ctrl = c
		var etat := "boutonTenu=%s ctrl=%s ctrlActif=%s ctrlJoueur=%s" % [
			tenu,
			ctrl != null,
			str(ctrl.is_processing()) if ctrl else "-",
			str(ctrl.player != null) if ctrl else "-"]
		if j != null:
			var arme = j.get(&"weapon")
			etat += " arme=%s munitions=%s recharge=%.2f elimine=%s want_fire=%s" % [
				"OUI" if (arme and arme.data) else "NON",
				str(arme.ammo) if arme else "?",
				arme.temps_restant() if arme else -1.0,
				j.get(&"is_eliminated"), j.get(&"want_fire")]
		etat += " phase=%d" % MatchDirector.phase
		if etat != dernier:
			print("[%5.2f s] %s" % [s, etat])
			dernier = etat
		if premier_tir < 0.0 and _projectiles() > 0:
			premier_tir = s
			print("[%5.2f s] >>> PREMIER PROJECTILE <<<" % s)
	print("premier tir à %.2f s après le lancement" % premier_tir)
