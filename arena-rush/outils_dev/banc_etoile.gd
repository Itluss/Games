extends Node
## BANC DE L'ÉTOILE WANTED — les six situations qui décident du mode.
##
## ─── CE QU'IL VÉRIFIE, ET POURQUOI CES SIX-LÀ ──────────────────────────
##
## La règle tient en trois phrases, et pourtant chacune de ses transitions
## peut se casser sans que rien ne plante :
##
##   1. le compteur démarre à ZÉRO au ramassage ;
##   2. mourir en cours de route rend l'étoile ET remet à zéro ;
##   3. trente secondes tenues valent une ★ et une réapparition ailleurs ;
##   4. deux joueurs qui la touchent ensemble : un seul l'obtient ;
##   5. le porteur qui QUITTE la partie ne l'emporte pas avec lui ;
##   6. lâchée contre un obstacle, elle reste attrapable.
##
## Aucune de ces situations ne lève d'erreur quand elle est fausse. Un
## compteur qui hériterait des vingt-neuf secondes du précédent porteur
## donnerait un jeu parfaitement fonctionnel et parfaitement injuste, et
## seul un test le dit.
##
## ─── IL JOUE LA VRAIE PARTIE ───────────────────────────────────────────
##
## Le banc monte `main.tscn` en solo et passe par les mêmes chemins que le
## jeu : `tenter_ramassage`, `server_take_damage`, la boucle du directeur.
## Simuler l'état en écrivant directement dans les champs prouverait que
## les champs se laissent écrire, pas que la règle marche.

var _echecs := 0
var _main: Node


func _ready() -> void:
	# ─── LE BANC JOUE L'ARÈNE WESTERN, PAS LE MONDE OUVERT ─────────────
	#
	# C'EST LA CORRECTION LA PLUS IMPORTANTE DE CE FICHIER, et elle vient
	# d'un bug signalé en jouant : l'étoile apparaissait DEHORS, derrière
	# la clôture. Le banc, lui, était vert.
	#
	# Il l'était pour une raison bête : `barriere.sh` lance `--solo`, ce
	# qui démarre le MONDE OUVERT. Or le monde ouvert est torique — il n'a
	# pas de dehors — donc « le point est-il dans le terrain ? » y répond
	# toujours oui. Toutes les vérifications de bord étaient vraies sans
	# rien mesurer. L'arène Western, elle, est BORNÉE à 36 m, et c'est
	# elle qu'on joue depuis le menu.
	#
	# Un banc doit tourner sur la carte du joueur, pas sur celle qui
	# l'arrange. Le drapeau est posé AVANT le montage : `Arena._ready` ne
	# le lit qu'une fois.
	Cfg.arene_test = true
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	# Le monde met un peu plus d'une seconde à se bâtir ; l'étoile est
	# semée une seconde après. On laisse la première apparition se faire.
	await get_tree().create_timer(3.5).timeout
	_figer_les_bots()
	print("\n=== BANC DE L'ÉTOILE WANTED ===\n")
	_test0_points_dans_larene()
	await _test1_ramassage()
	await _test2_mort_a_mi_course()
	await _test3_victoire()
	await _test4_double_ramassage()
	await _test5_porteur_parti()
	await _test6_drop_contre_obstacle()
	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh` : sans elle, un banc conforme est
	# compté comme non exécuté.
	print("=== %d échec(s) ===" % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


## ─── LES BOTS SONT FIGÉS PENDANT LA MESURE ───────────────────────────
##
## C'EST LA CORRECTION QUI REND CE BANC FIABLE, et elle vient de deux
## échecs intermittents qui ne se ressemblaient pas :
##
##   • « le porteur est bien mort — vie = 100 » : un bot avait tué le
##     joueur avant ma ligne, la réapparition l'avait rendu à cent points
##     de vie, et mes dégâts tombaient sur quelqu'un qui venait de naître ;
##   • « l'étoile est bien retombée — false » : un bot avait tout
##     simplement RAMASSÉ l'étoile entre deux lignes du test.
##
## Aucun des deux n'est un défaut du mode. Ce sont des courses entre le
## banc et une partie qui continue de tourner pendant qu'il mesure. Un
## banc qui perd ces courses une fois sur deux ne dit plus rien : vert, il
## ne prouve rien ; rouge, on ne sait pas quoi corriger.
##
## On coupe donc les cerveaux plutôt que de supprimer les bots : ils
## restent en scène — le classement et le marquage des porteurs ont besoin
## d'eux — mais ils ne bougent plus, ne tirent plus et ne ramassent plus.
func _figer_les_bots() -> void:
	var figes := 0
	for n in get_tree().get_nodes_in_group(&"players"):
		var j := n as Player
		if j == null or not j.is_bot:
			continue
		var cerveau := j.get_node_or_null("Brain")
		if cerveau != null:
			cerveau.set_physics_process(false)
			cerveau.set_process(false)
			figes += 1
		j.move_input = Vector2.ZERO
		j.want_fire = false
		j.want_tap = false
	print("  (banc : %d cerveau(x) de bot figé(s) pour la mesure)" % figes)


# --- OUTILLAGE -----------------------------------------------------------

func _joueurs() -> Array:
	var l := []
	for n in get_tree().get_nodes_in_group(&"players"):
		if n is Player and not n.is_eliminated:
			l.append(n)
	return l


## Remet le mode à plat entre deux tests : étoile au sol, personne dessus.
func _repartir() -> void:
	# RE-GEL À CHAQUE TEST. Le gel initial fige les bots présents — mais
	# un bot mort RÉAPPARAÎT avec un cerveau neuf, actif. Sur une machine
	# lente, les tests durent assez pour que ça arrive : une balle
	# parasite de 7 points tombait juste avant les 9 999 du banc et les
	# i-frames par coup les avalaient — « vie = 93 », huit échecs en
	# cascade, reproductibles sur conteneur neuf et verts sur machine
	# rapide.
	_figer_les_bots()
	EtoileDirector.porteur_id = 0
	EtoileDirector.temps = 0.0
	EtoileDirector._marquer_porteurs(0)
	EtoileDirector.net_poser(EtoileDirector._points[0]
			if not EtoileDirector._points.is_empty() else Vector3.ZERO)
	await get_tree().process_frame


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-46s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


func _titre(t: String) -> void:
	print("\n  ── %s ──" % t)


# --- LES SIX TESTS -------------------------------------------------------

## TEST 0 — TOUS LES POINTS D'APPARITION SONT DANS L'ARÈNE.
##
## CE TEST EXISTE PARCE QU'IL MANQUAIT. La première version du banc
## vérifiait qu'une étoile lâchée tombait sur un « sol praticable », et
## c'était vrai : il n'y a aucun obstacle derrière la clôture. Mais il n'y
## a pas de jeu non plus, et l'étoile est apparue DEHORS, hors de portée —
## signalé en jouant, pas ici.
##
## « Libre d'obstacle » et « dans le terrain » sont deux questions
## différentes. Le banc pose désormais les deux.
func _test0_points_dans_larene() -> void:
	_titre("Test 0 : les points d'apparition sont dans l'arène")
	var arene := MatchDirector.arena
	if arene == null or not arene.has_method(&"dans_terrain"):
		_ligne(false, "l'arène expose sa notion de terrain", "non")
		return
	# GARDE-FOU CONTRE UN BANC QUI SE MENT À LUI-MÊME. Si le drapeau n'a
	# pas pris, tout ce qui suit teste un monde sans bords et passe sans
	# rien prouver.
	_ligne(Cfg.arene_test, "le banc tourne bien dans l'arène bornée",
			"arene_test = %s" % Cfg.arene_test)
	var pts: Array = EtoileDirector._points
	_ligne(pts.size() >= 6, "assez de points pour varier les apparitions",
			"%d point(s)" % pts.size())
	var dehors := 0
	var pire := 0.0
	for p: Vector3 in pts:
		if not arene.call(&"dans_terrain", p, 0.0):
			dehors += 1
			pire = maxf(pire, Vector2(p.x, p.z).length())
	_ligne(dehors == 0, "aucun point hors de l'enceinte",
			"%d dehors%s" % [dehors,
					(", le pire à %.1f m" % pire) if dehors > 0 else ""])
	var colles := 0
	for p: Vector3 in pts:
		if not arene.call(&"dans_terrain", p, EtoileDirector.MARGE_TERRAIN):
			colles += 1
	_ligne(colles == 0, "aucun point collé au bord",
			"%d à moins de %.0f m du bord" % [colles,
					EtoileDirector.MARGE_TERRAIN])


## TEST 1 — un joueur ramasse : il devient porteur, le compteur part de 0.
func _test1_ramassage() -> void:
	_titre("Test 1 : ramassage")
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		_ligne(false, "au moins deux joueurs en scène", "%d" % js.size())
		return
	var a: Player = js[0]
	EtoileDirector.tenter_ramassage(a.peer_id)
	await get_tree().process_frame
	_ligne(EtoileDirector.porteur_id == a.peer_id,
			"le ramasseur devient porteur",
			"porteur = %d, attendu %d" % [EtoileDirector.porteur_id, a.peer_id])
	# LE SEUIL EST À 0,15 s ET NON À ZÉRO EXACT, et ce n'est pas une
	# tolérance de complaisance : entre le ramassage et la mesure il s'est
	# écoulé une image, que le directeur a comptée — c'est précisément son
	# travail. Ce que le test doit interdire, c'est l'HÉRITAGE des
	# secondes du porteur précédent, qui se compterait en dizaines.
	_ligne(EtoileDirector.temps < 0.15,
			"le compteur démarre à zéro", "%.2f s" % EtoileDirector.temps)
	_ligne(a.is_star_holder, "le drapeau du porteur est levé",
			str(a.is_star_holder))
	_ligne(not EtoileDirector.au_sol, "l'étoile n'est plus au sol",
			str(EtoileDirector.au_sol))


## TEST 2 — le porteur est tué à mi-course.
##
## C'EST LE TEST CENTRAL DU MODE. Si le temps se transmettait, la bonne
## stratégie serait d'attendre que quelqu'un fasse les vingt-neuf premières
## secondes. On vérifie donc les DEUX moitiés : le porteur retombe à zéro,
## et le suivant repart de zéro lui aussi.
func _test2_mort_a_mi_course() -> void:
	_titre("Test 2 : mort à 18 secondes sur 30")
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		_ligne(false, "au moins deux joueurs en scène", "%d" % js.size())
		return
	var a: Player = js[0]
	var b: Player = js[1]
	EtoileDirector.tenter_ramassage(a.peer_id)
	await get_tree().process_frame
	# On avance le compteur sans attendre dix-huit secondes réelles : c'est
	# la valeur du compteur qui est testée, pas l'horloge du moteur.
	EtoileDirector.temps = 18.0
	a.star_hold_time = 18.0
	await get_tree().process_frame

	# ON REND SA VIE AVANT DE FRAPPER. Le banc joue une vraie partie : dix
	# bots tirent pendant qu'il mesure, et le porteur pouvait être déjà
	# mort quand la ligne suivante s'exécutait. Les dégâts étaient alors
	# ignorés et le test accusait la règle d'un défaut qui n'était pas le
	# sien — vu une fois sur trois passes.
	a.health.current_health = a.health.max_health
	a.health.is_dead = false
	a.is_eliminated = false
	# ... ET SON INVULNÉRABILITÉ AVEC. La remise en vie ci-dessus était
	# incomplète : si le porteur venait de réapparaître — ce qui arrive
	# d'autant plus souvent que la machine est lente — la protection de
	# réapparition avalait les 9 999 points et le test accusait la règle.
	# Vu en rouge sur un conteneur neuf : « vie = 93 », six échecs en
	# cascade, reproductible — et le même banc vert sur machine rapide.
	a.set(&"_protection", 0.0)
	a.health.set(&"_invulnerable_until", 0.0)
	await get_tree().process_frame
	a.server_take_damage(9999.0, a.global_position, b.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	await get_tree().process_frame

	_ligne(a.health.is_dead, "le porteur est bien mort",
			"vie = %.0f" % a.health.current_health)
	_ligne(EtoileDirector.porteur_id == 0,
			"plus personne ne porte l'étoile",
			"porteur = %d" % EtoileDirector.porteur_id)
	_ligne(is_equal_approx(EtoileDirector.temps, 0.0),
			"le compteur est remis à zéro", "%.2f s" % EtoileDirector.temps)
	_ligne(is_equal_approx(a.star_hold_time, 0.0),
			"le compteur du mort est remis à zéro",
			"%.2f s" % a.star_hold_time)
	_ligne(EtoileDirector.au_sol, "l'étoile est retombée au sol",
			str(EtoileDirector.au_sol))
	var corps := get_tree().get_nodes_in_group(&"etoile_wanted")
	_ligne(corps.size() == 1, "un seul corps d'étoile dans la scène",
			"%d" % corps.size())

	EtoileDirector.tenter_ramassage(b.peer_id)
	await get_tree().process_frame
	_ligne(EtoileDirector.porteur_id == b.peer_id,
			"le suivant peut la reprendre",
			"porteur = %d, attendu %d" % [EtoileDirector.porteur_id, b.peer_id])
	_ligne(EtoileDirector.temps < 0.15,
			"le suivant repart de zéro, sans hériter",
			"%.2f s" % EtoileDirector.temps)


## TEST 3 — trente secondes tenues.
func _test3_victoire() -> void:
	_titre("Test 3 : trente secondes tenues")
	await _repartir()
	var js := _joueurs()
	if js.is_empty():
		_ligne(false, "au moins un joueur en scène", "0")
		return
	var a: Player = js[0]
	var avant := a.star_wins
	EtoileDirector.tenter_ramassage(a.peer_id)
	await get_tree().process_frame
	# Juste sous la barre : on laisse la boucle du directeur franchir les
	# trente secondes elle-même, pour tester le chemin réel de la victoire
	# et pas un appel direct à `_victoire`.
	# UN MILLIÈME SOUS LA BARRE, ET QUATRE IMAGES. À cinquante millièmes
	# et deux images, on arrivait à 29,99 s : le test échouait sur sa
	# propre arithmétique, pas sur le code. Une image de banc en rendu
	# logiciel vaut ce qu'elle veut — on ne parie donc pas sur sa durée.
	EtoileDirector.temps = EtoileDirector.DUREE - 0.001
	for _i in 4:
		await get_tree().process_frame

	_ligne(a.star_wins == avant + 1, "une victoire d'étoile de plus",
			"%d → %d" % [avant, a.star_wins])
	_ligne(EtoileDirector.porteur_id == 0, "l'étoile quitte le porteur",
			"porteur = %d" % EtoileDirector.porteur_id)
	_ligne(is_equal_approx(EtoileDirector.temps, 0.0),
			"le compteur est remis à zéro", "%.2f s" % EtoileDirector.temps)
	_ligne(not EtoileDirector.au_sol, "l'étoile disparaît de la carte",
			str(EtoileDirector.au_sol))
	_ligne(get_tree().get_nodes_in_group(&"etoile_wanted").is_empty(),
			"aucun corps d'étoile pendant le délai",
			"%d" % get_tree().get_nodes_in_group(&"etoile_wanted").size())

	# LA PARTIE NE S'ARRÊTE PAS. C'est écrit noir sur blanc dans la
	# consigne, et c'est le genre de chose qu'on casse en ajoutant un
	# écran de victoire « juste pour voir ».
	_ligne(MatchDirector.phase != MatchDirector.Phase.ENDED,
			"le deathmatch continue", "phase = %d" % MatchDirector.phase)

	# Réapparition après le délai.
	await get_tree().create_timer(EtoileDirector.DELAI_VICTOIRE + 0.6).timeout
	_ligne(EtoileDirector.au_sol, "elle réapparaît après le délai",
			str(EtoileDirector.au_sol))


## TEST 4 — deux joueurs la touchent dans la même image.
func _test4_double_ramassage() -> void:
	_titre("Test 4 : ramassage simultané")
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		_ligne(false, "au moins deux joueurs en scène", "%d" % js.size())
		return
	var a: Player = js[0]
	var b: Player = js[1]
	# Deux appels consécutifs SANS image entre les deux : c'est exactement
	# ce que produisent deux `body_entered` diffusés dans le même pas de
	# physique.
	EtoileDirector.tenter_ramassage(a.peer_id)
	EtoileDirector.tenter_ramassage(b.peer_id)
	await get_tree().process_frame
	_ligne(EtoileDirector.porteur_id == a.peer_id,
			"le premier arrivé garde l'étoile",
			"porteur = %d, attendu %d" % [EtoileDirector.porteur_id, a.peer_id])
	var porteurs := 0
	for j in _joueurs():
		if j.is_star_holder:
			porteurs += 1
	_ligne(porteurs == 1, "un seul joueur porte le drapeau",
			"%d porteur(s)" % porteurs)


## TEST 5 — le porteur quitte la partie sans mourir.
func _test5_porteur_parti() -> void:
	_titre("Test 5 : le porteur quitte la partie")
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		_ligne(false, "au moins deux joueurs en scène", "%d" % js.size())
		return
	# On prend un BOT : retirer le joueur local démonterait la caméra et
	# l'interface, et le test cesserait de mesurer ce qu'il croit mesurer.
	var partant: Player = null
	for j in js:
		if j.is_bot:
			partant = j
			break
	if partant == null:
		_ligne(false, "un bot disponible pour le test", "aucun")
		return
	var id := partant.peer_id
	EtoileDirector.tenter_ramassage(id)
	await get_tree().process_frame
	EtoileDirector.temps = 12.0
	# Départ brutal, comme une déconnexion : le nœud disparaît sans passer
	# par la mort.
	MatchDirector.players.erase(id)
	partant.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_ligne(EtoileDirector.porteur_id == 0,
			"l'étoile ne part pas avec lui",
			"porteur = %d" % EtoileDirector.porteur_id)
	_ligne(is_equal_approx(EtoileDirector.temps, 0.0),
			"son compteur est effacé", "%.2f s" % EtoileDirector.temps)
	await get_tree().create_timer(EtoileDirector.DELAI_ORPHELINE + 0.6).timeout
	_ligne(EtoileDirector.au_sol or EtoileDirector.porteur_id != 0,
			"elle redevient disponible", str(EtoileDirector.au_sol))


## TEST 6 — mort collée à un obstacle : l'étoile ne doit pas s'y enfermer.
func _test6_drop_contre_obstacle() -> void:
	_titre("Test 6 : chute contre un obstacle")
	var arene := MatchDirector.arena
	if arene == null or not arene.has_method(&"position_libre"):
		_ligne(false, "l'arène expose sa validation d'espace", "non")
		return
	# On cherche un point RÉELLEMENT bouché dans le monde, plutôt que d'en
	# inventer un : un test qui se déroule sur du terrain dégagé ne prouve
	# rien du cas qu'il prétend couvrir.
	var bouche := Vector3.INF
	for essai in 400:
		# ±34 ET NON ±38 : l'enceinte s'arrête à 36 m, et tirer au-delà
		# faisait échouer le test sur un point qui n'appartient tout
		# simplement pas au terrain — un faux défaut, qui masquait le vrai.
		var p := Vector3(randf_range(-34.0, 34.0), 0.0,
				randf_range(-34.0, 34.0))
		if not arene.call(&"position_libre", p, 1.4):
			bouche = p
			break
	if bouche == Vector3.INF:
		_ligne(false, "un point bouché trouvé dans l'arène", "aucun sur 400")
		return
	# ─── ON TESTE LA PAIRE, PAS L'ÉTAPE ────────────────────────────────
	#
	# La version précédente exigeait que `_corriger` rende toujours une
	# position. Elle échouait une fois sur deux, et elle avait tort : la
	# recherche d'espace libre explore en spirale sur dix-huit mètres, et
	# elle a parfaitement le droit de ne rien trouver au fond d'un recoin
	# dense. C'est précisément pour ce cas que `_pose_de_repli` existe.
	#
	# Ce qui doit être vrai, c'est que le SYSTÈME rende toujours une
	# position jouable — par dégagement ou par repli, peu importe.
	var resolu: Vector3 = EtoileDirector._corriger(bouche)
	var par_repli := resolu == Vector3.INF
	if par_repli:
		resolu = EtoileDirector._pose_de_repli(bouche)
	# TYPE EXPLICITE : `Node.call` rend un Variant, et l'inférence de type
	# de GDScript refuse alors la déclaration. Le banc ne compilait plus, et
	# comme `barriere.sh` signale ce cas par un message que mon filtre ne
	# retenait pas, deux passes sont sorties parfaitement muettes.
	var bonne: bool = resolu != Vector3.INF \
			and bool(arene.call(&"dans_terrain", resolu, 0.0)) \
			and bool(arene.call(&"position_libre", resolu, 1.4))
	_ligne(bonne, "un point bouché se résout en position jouable",
			"%s → %.1f, %.1f" % ["par repli" if par_repli else "par dégagement",
					resolu.x, resolu.z])

	# Et le chemin complet : on tue un porteur À CET ENDROIT-LÀ.
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		return
	var a: Player = js[0]
	var b: Player = js[1]
	EtoileDirector.tenter_ramassage(a.peer_id)
	await get_tree().process_frame
	a.global_position = Vector3(bouche.x, a.global_position.y, bouche.z)
	# MÊME PARADE QU'AU TEST 2 : on rend sa vie au porteur avant de le
	# frapper. Le banc joue une vraie partie, et ce test arrive après
	# plusieurs morts ; frapper quelqu'un de déjà mort ne déclenche rien et
	# le test accuse la règle d'un défaut qui n'est pas le sien.
	a.health.current_health = a.health.max_health
	a.health.is_dead = false
	a.is_eliminated = false
	a.set(&"_protection", 0.0)
	a.health.set(&"_invulnerable_until", 0.0)
	await get_tree().process_frame
	EtoileDirector.tenter_ramassage(a.peer_id)
	await get_tree().process_frame
	a.server_take_damage(9999.0, a.global_position, b.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	await get_tree().process_frame
	_ligne(EtoileDirector.au_sol, "l'étoile est bien retombée",
			str(EtoileDirector.au_sol))
	_ligne(arene.call(&"position_libre", EtoileDirector.position_sol, 1.4),
			"elle est tombée sur un sol praticable",
			"%.1f, %.1f" % [EtoileDirector.position_sol.x,
					EtoileDirector.position_sol.z])
	# ET DANS L'ARÈNE. C'est la vérification qui manquait : un point peut
	# être parfaitement dégagé ET parfaitement hors-jeu.
	_ligne(arene.call(&"dans_terrain", EtoileDirector.position_sol, 0.0),
			"elle est tombée DANS l'arène",
			"à %.1f m du centre"
					% Vector2(EtoileDirector.position_sol.x,
							EtoileDirector.position_sol.z).length())

	# ─── ET LE CAS EXTRÊME : UNE MORT HORS DE L'ENCEINTE ───────────────
	#
	# On ne devrait jamais y être, mais une projection, un rebond ou un
	# futur pouvoir de déplacement peuvent y mener. L'étoile ne doit pas
	# suivre.
	# ON TESTE LA PAIRE ICI AUSSI. Cette ligne interrogeait `_corriger`
	# seul, et elle est tombée dès que le plan de la carte a changé : le
	# point tiré vers le centre atterrit désormais sur une crête
	# diagonale, et la recherche d'espace libre n'a rien trouvé dans son
	# rayon. Ce n'est pas un défaut — c'est exactement le cas pour lequel
	# `_pose_de_repli` a été écrit. Ce qui doit être vrai, c'est que le
	# SYSTÈME rende une position jouable, pas qu'une étape particulière
	# réussisse toujours.
	var loin := Vector3(90.0, 0.0, 70.0)
	var ramene: Vector3 = EtoileDirector._corriger(loin)
	var repli := ramene == Vector3.INF
	if repli:
		ramene = EtoileDirector._pose_de_repli(loin)
	var bon: bool = ramene != Vector3.INF \
			and bool(arene.call(&"dans_terrain", ramene, 0.0)) \
			and bool(arene.call(&"position_libre", ramene, 1.4))
	_ligne(bon, "un point très hors-jeu est ramené dans l'arène",
			"%s → %.1f, %.1f" % ["par repli" if repli else "par dégagement",
					ramene.x, ramene.z] if ramene != Vector3.INF
					else "aucune position")
