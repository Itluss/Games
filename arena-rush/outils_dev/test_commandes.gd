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
	_isoler_le_banc()
	await _executer()
	_verifier_le_banc()
	print("=== %d échec(s) ===" % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


## LE BANC SE CONTRÔLE LUI-MÊME.
##
## Quand l'isolation a lâché, le joueur est mort en cours de route et
## QUATRE vérifications sont tombées d'affilée — toutes avec le même
## « obtenu=false », aucune ne disant la vraie raison. Il a fallu lire le
## diagnostic pour comprendre qu'il n'y avait qu'une cause.
##
## Cette vérification finale nomme la panne pour ce qu'elle est : un
## défaut du banc, pas quatre régressions du jeu. Elle est délibérément
## placée à la FIN, quand tout le temps de jeu du banc s'est écoulé.
func _verifier_le_banc() -> void:
	var j := _joueur()
	if j == null:
		_verifier("le banc a bien un joueur", false, true)
		return
	var elimine: bool = j.get(&"is_eliminated")
	if elimine:
		print("      Le sujet du test est MORT pendant le banc : les échecs "
				+ "ci-dessus n'en sont probablement qu'un seul.")
	_verifier("le joueur est resté vivant pendant tout le banc",
			not elimine, true)


## ISOLE LE BANC DE TOUT CE QUI N'EST PAS UNE COMMANDE.
##
## POURQUOI : ce test mesure des COMMANDES, et il le faisait au milieu
## d'une vraie partie — mobs qui chargent, zone qui se referme. Tant que
## les images défilent vite, cela ne se voit pas. Sur le runner
## d'intégration, où une image peut coûter une seconde, le moteur avance
## quand même le temps de jeu par paquets : plusieurs dizaines de secondes
## de partie s'écoulent pendant le test. Le joueur peut alors être blessé,
## repoussé, voire éliminé — et un joueur éliminé ne tire pas, quelle que
## soit la qualité du bouton.
##
## La publication a été bloquée par exactement ce genre d'échec, sur un jeu
## qui fonctionnait. Un test qui dépend de la survie de son sujet ne mesure
## pas ce qu'il annonce. On fige donc les menaces.
func _isoler_le_banc() -> void:
	# Le pondeur est cherché par son NOM et non par sa classe : `is_class`
	# ne connaît que les classes du moteur, jamais celles déclarées en
	# GDScript. Passer par « GameWorld » n'aurait jamais rien trouvé, et
	# l'isolation aurait échoué en silence — le pire des résultats.
	var pondeur := _main.find_child("MobSpawner", true, false)
	if pondeur != null:
		pondeur.set_process(false)
	for m in get_tree().get_nodes_in_group(&"mobs"):
		m.queue_free()

	# On fige le directeur de partie. Repousser seulement le rayon de zone
	# n'aurait servi à rien : il est ramené vers sa cible à chaque tick et
	# reviendrait aussitôt. Figer le nœud arrête d'un coup la fermeture de
	# la zone et la fin de partie.
	MatchDirector.set_process(false)
	MatchDirector.set_physics_process(false)
	MatchDirector.zone_radius = Cfg.ARENA_RADIUS

	# LES BOTS AUSSI. Première omission, et elle a coûté une publication :
	# j'avais gelé les mobs et la zone en croyant avoir figé « les
	# menaces ». Les autres joueurs sont des bots, ils tirent, et sur un
	# runner lent le banc dure assez de temps de jeu pour qu'ils tuent le
	# sujet du test. Le journal l'a dit sans ambiguïté :
	#
	#   DIAGNOSTIC tirs=15 éliminé=true pv=0.0
	#   clips vus pendant le martèlement : ["tir_debout", "mort"]
	#
	# Quatre vérifications sont alors tombées d'un coup, pour une seule et
	# même cause. Un cerveau de bot arrêté ne vise plus personne.
	var local := _joueur()
	var bots := 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if p == local:
			continue
		var cerveau := p.get_node_or_null("Brain")
		if cerveau != null:
			cerveau.set_process(false)
			cerveau.set_physics_process(false)
		p.set_physics_process(false)
		bots += 1

	if local != null:
		var pv = local.get(&"health")
		if pv != null:
			pv.reset()
	print("  Banc isolé : pondeur arrêté, mobs retirés, %d bot(s) neutralisé(s), "
			% bots + "zone et partie figées.")


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


## Presse une seule fois EN PLEINE RECHARGE et vérifie qu'un coup finit
## par partir, sans réappuyer.
func _verifier_tampon(j: Node, bouton: Control) -> void:
	var arme = j.get(&"weapon")
	if arme == null or arme.data == null:
		_verifier("arme équipée pour tester la mémoire d'appui", false, true)
		return
	# ON COMPTE LES COUPS PARTIS, PAS LES PROJECTILES VISIBLES.
	#
	# La version précédente regardait, à chaque trame, s'il y avait un
	# projectile de plus dans la scène : un ÉCHANTILLONNAGE, pour un tir qui
	# est un évènement instantané. Mesuré ici, le projectile reste visible
	# 80 trames — donc l'échantillonnage n'explique PAS l'échec constaté sur
	# le runner d'intégration, contrairement à ce que je supposais. Le
	# compteur reste néanmoins le bon instrument : il ne peut pas être
	# manqué, et il distingue « le coup n'est pas parti » de « le projectile
	# a disparu trop vite », ce que l'ancien test confondait.
	var avant: int = arme.tirs
	# On place l'arme presque au début de sa recharge : sans mémoire
	# d'appui, la demande serait purement ignorée.
	arme._cooldown = arme.data.cooldown() * 0.95
	await _clic(bouton.get_global_rect().get_center(), true)
	await get_tree().process_frame
	await _clic(bouton.get_global_rect().get_center(), false)
	var parti := false
	for i in 120:
		await get_tree().process_frame
		if arme.tirs > avant:
			parti = true
			break
	if not parti:
		# DIAGNOSTIC COMPLET. L'échec ne s'est produit que sur le runner
		# d'intégration, jamais ici : je ne peux donc l'observer que par ce
		# qu'il imprime là-bas. On relève tout ce qui peut interdire un tir,
		# pour que le prochain passage tranche en une seule fois plutôt
		# qu'en trois allers-retours.
		var pv = j.get(&"health")
		print("      DIAGNOSTIC recharge=%.3f  mémoire=%.3f  tirs=%d  "
				% [arme.temps_restant(), j.get(&"_tampon_tir"), arme.tirs]
				+ "munitions=%d  éliminé=%s  pv=%.1f  veut_tirer=%s  zone=%.1f"
				% [arme.ammo, str(j.get(&"is_eliminated")),
				(pv.current_health if pv != null else -1.0),
				str(j.get(&"want_fire")), MatchDirector.zone_radius])
	_verifier("appui pendant la recharge → le coup part quand même",
			parti, true)


## Les projectiles ne sont pas groupés : on les compte par leur classe.
func _compter_projectiles(n: Node = null) -> int:
	if n == null:
		n = get_tree().current_scene
	var total := 0
	if n is Projectile and (n as Node3D).visible:
		total += 1
	for c in n.get_children():
		total += _compter_projectiles(c)
	return total


## Simule un VRAI tactile à deux doigts : un sur le joystick, un sur le
## bouton de tir. On utilise des évènements d'écran indexés, et non un
## clic souris, car c'est précisément la différence qui compte.
func _doigt(index: int, pos: Vector2, appui: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = appui
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame


func _verifier_deux_doigts(j: Node, stick: Control, bouton: Control) -> void:
	# Doigt 0 : on tient le joystick de déplacement, comme en courant.
	await _doigt(0, stick.get_global_rect().get_center(), true)
	await get_tree().process_frame
	# Doigt 1 : on presse le bouton de tir SANS lâcher le joystick.
	await _doigt(1, bouton.get_global_rect().get_center(), true)
	for i in 6:
		await get_tree().process_frame
	var tire: bool = j.want_fire
	await _doigt(1, bouton.get_global_rect().get_center(), false)
	await _doigt(0, stick.get_global_rect().get_center(), false)
	for i in 4:
		await get_tree().process_frame
	_verifier("joystick tenu + appui sur TIR → le tir part", tire, true)


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
func _verifier_repetition(j: Node, visuel, bouton: Control) -> void:
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
			var a: String = visuel.posture()
			observees[a] = true
			# Les deux premiers cycles servent à installer la posture.
			if cycle >= 2 and a != "tir_debout":
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
	# AVEC UN AnimationTree, `AnimationPlayer.current_animation` est VIDE :
	# ce n'est plus lui qui décide. On interroge la posture logique du
	# visuel, qui est l'observable maintenu à cet effet.
	var visuel = j.get(&"visual")
	if visuel == null:
		print("  [ÉCHEC] visuel introuvable")
		_echecs += 1
	else:
		await _clic(bouton.get_global_rect().get_center(), true)
		for i in 30:
			await get_tree().process_frame
		_verifier_texte("à l'arrêt, gâchette pressée → posture de tir",
				visuel.posture(), "tir_debout")
		await _clic(bouton.get_global_rect().get_center(), false)
		for i in 30:
			await get_tree().process_frame
		_verifier_texte("gâchette relâchée → retour au repos",
				visuel.posture(), "repos")

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
	if visuel != null:
		await _verifier_repetition(j, visuel, bouton)

	# 3 quinquies bis. UN APPUI PENDANT LA RECHARGE EST-IL PERDU ?
	#
	# Retour de test : « quand j'appuie, ça ne tire pas immédiatement ».
	# La latence d'entrée était pourtant d'une trame — le tir partait bien
	# tout de suite QUAND l'arme était prête. Le reste du temps, l'appui
	# était JETÉ, et le bouton semblait mort. Il est désormais mémorisé.
	await _verifier_tampon(j, bouton)

	# 3 septies. DEUX DOIGTS À LA FOIS — le cas réel du jeu.
	#
	# Retour de test : « je cours, j'appuie sur tir, il ne se passe rien ».
	# Un doigt tient donc le joystick pendant que l'autre presse le
	# bouton. Tous mes tests précédents injectaient un clic ISOLÉ et ne
	# pouvaient pas voir ce cas.
	await _verifier_deux_doigts(j, stick, bouton)

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
