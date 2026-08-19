extends Node
## SONDE DE L'ÉCRAN VIOLET — la traque, épisode final.
##
## CE QUE LES SEPT SONDES PRÉCÉDENTES ONT ÉCARTÉ : aucun trou dans la
## carte, aucun décrochage durable de la caméra, aucune image plate même au
## bord du monde, aucune image trop sombre, aucun mur percé. Toutes
## mesuraient la GÉOMÉTRIE ou les PIXELS, et toutes rendaient un verdict
## rassurant sur un jeu qui, lui, montrait un écran vide.
##
## LA CAPTURE DE TROP a fini par trancher : la minicarte, sur le même
## écran, affichait le joueur entouré de décor et d'adversaires. Le monde
## existait donc, à sa place, avec des choses autour. Il n'était pas
## dessiné, voilà tout.
##
## OR LE DÉCOR EST REPOSITIONNÉ AUTOUR DE LA CAMÉRA À CHAQUE IMAGE. C'est
## le mécanisme qui rend le monde sans couture : chaque cellule vient se
## placer à celle de ses images qui est la plus proche de l'œil. Tant que
## ce mécanisme tourne, il est IMPOSSIBLE que la caméra se retrouve sans
## décor autour d'elle.
##
## D'où la seule question qui reste, et c'est celle que cette sonde pose :
## combien de cellules y a-t-il autour de la caméra, image par image ?
## Zéro cellule, c'est l'écran violet — et la réponse ne demande aucun
## rendu, donc elle est fiable même ici.
##
## Usage :
##   godot --headless --path arena-rush res://outils_dev/sonde_violet.tscn -- --solo

## Durée observée. Longue à dessein : le défaut est intermittent, et une
## mesure trop courte le rate puis le déclare absent.
const DUREE := 130.0

## Rayon dans lequel on attend du décor. La caméra ne montre qu'une
## trentaine de mètres de sol ; quarante laisse de la marge.
const PORTEE := 40.0

var _t := 0.0
var _arene: Node3D
var _joueur: Node3D
var _prete := false

var _sans_decor := 0
## Plus grand nombre de maillages visibles rencontré pendant la session.
var _pic_maillages := 0
var _sans_camera := 0
var _images := 0
var _pire := 999
var _pire_note := ""
var _morts := 0
var _alertes := 0
## ALTITUDE. Le décor est reposé à y = 0 autour de la caméra ; si celle-ci
## s'élève, le sol s'éloigne, et au-delà d'environ 110 m il passe derrière
## le plan lointain fixé à 140 m. Tout disparaît alors sauf le ciel — ce qui
## est exactement le symptôme signalé.
var _y_cam_max := -999.0
var _y_joueur_max := -999.0
var _haut := 0
## ACCUMULATION. Le défaut se déclenche vers la quatrième minute, deux fois
## de suite, quel que soit l'endroit : ce n'est pas un lieu, c'est un
## compteur qui monte. On regarde donc ce qui grossit.
var _releve: Array[Dictionary] = []
var _prochain := 0.0

func _ready() -> void:
	# LA SONDE MESURE EN DERNIER. Elle est la racine de la scène, donc son
	# `_process` s'exécuterait AVANT celui de tout ce qu'elle observe : elle
	# lirait l'état du monde avant que le monde ait fini de se mettre à jour.
	# Un instrument qui mesure trop tôt invente des défauts.
	process_priority = 200
	# CADENCE BASSE FORCÉE. C'est le régime dans lequel le défaut se
	# reproduit au navigateur — quatre à onze images par seconde — et c'est
	# le seul que les sondes précédentes n'avaient jamais essayé : elles
	# tournaient toutes à soixante, où tout va bien.
	#
	# Un pas de temps de deux dixièmes de seconde n'est pas un pas de temps
	# de seize millisecondes en plus lent : c'est un régime différent, où la
	# gravité intègre douze fois plus par pas et où le moteur physique cesse
	# de rattraper son retard.
	if "--lent" in OS.get_cmdline_user_args():
		Engine.max_fps = 5
		print("  [cadence forcée à 5 images par seconde]")
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	_arene = get_tree().get_first_node_in_group(&"arena") as Node3D
	if _arene == null:
		_arene = _chercher_arene(get_tree().current_scene)
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id() and not bool(n.get(&"is_bot")):
			_joueur = n
			if n.has_signal(&"died"):
				n.connect(&"died", func(): _morts += 1)
	if _arene == null or _joueur == null:
		push_error("Banc incomplet : arène=%s joueur=%s" % [_arene, _joueur])
		get_tree().quit(1)
		return
	_prete = true


func _chercher_arene(n: Node) -> Node3D:
	if n == null:
		return null
	if n.get_script() != null \
			and (n.get_script() as Script).resource_path.ends_with("arena.gd"):
		return n as Node3D
	for e in n.get_children():
		var t := _chercher_arene(e)
		if t != null:
			return t
	return null


func _process(delta: float) -> void:
	if not _prete:
		return
	_t += delta
	# Le joueur PARCOURT la carte : le défaut est apparu « à certains
	# endroits », une sonde immobile ne visiterait jamais ces endroits-là.
	if not bool(_joueur.get(&"is_eliminated")):
		var a := _t * 0.42
		var p := Vector2(cos(a * 0.23), sin(a * 0.23)) * 62.0
		var vers := p - Vector2(_joueur.global_position.x,
				_joueur.global_position.z)
		_joueur.set(&"move_input", vers.normalized())

	var cam := get_viewport().get_camera_3d()
	_images += 1
	if cam == null:
		_sans_camera += 1
		if _sans_camera <= 3:
			print("      ! t=%.1f s : AUCUNE CAMÉRA ACTIVE dans la fenêtre" % _t)
		return

	# On compte les conteneurs de décor autour de l'œil.
	var proches := 0
	for e in _arene.get_children():
		if e is Node3D and e.get_class() == "Node3D":
			var d := (e as Node3D).global_position.distance_to(
					cam.global_position)
			if d < PORTEE:
				proches += 1
	if proches < _pire:
		_pire = proches
		_pire_note = "t=%.1f s · caméra %s · joueur %s · morts %d" % [
				_t, _bref(cam.global_position),
				_bref(_joueur.global_position), _morts]
	_pic_maillages = maxi(_pic_maillages, _compter_maillages())
	if _t >= _prochain:
		_prochain = _t + 10.0
		_releve.append({
			"t": _t,
			"noeuds": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"objets": Performance.get_monitor(Performance.OBJECT_COUNT),
			"orphelins": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"mem": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"mobs": get_tree().get_nodes_in_group(&"mobs").size(),
			"dessins": Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		})
	_y_cam_max = maxf(_y_cam_max, cam.global_position.y)
	_y_joueur_max = maxf(_y_joueur_max, _joueur.global_position.y)
	if cam.global_position.y > 60.0:
		_haut += 1
		if _alertes < 6:
			_alertes += 1
			print("      ! t=%.1f s : CAMÉRA À %.0f m — joueur à %.1f m"
					% [_t, cam.global_position.y, _joueur.global_position.y])
	if proches == 0:
		_sans_decor += 1
		if _alertes < 6:
			_alertes += 1
			print("      ! t=%.1f s : ZÉRO cellule autour de la caméra %s"
					% [_t, _bref(cam.global_position)])
	if _t > DUREE:
		_conclure()


## LA SCÈNE NE DOIT PAS ENFLER.
##
## C'EST LA GARANTIE QUI MANQUAIT, ET SON ABSENCE A COÛTÉ QUATRE
## SIGNALEMENTS. Le butin abandonné s'accumulait sans fin : la scène passait
## de 2 446 à 4 611 nœuds en cinq minutes, la mémoire de 74 à 92 Mo, et la
## cadence s'effondrait jusqu'à ce que le monde cesse d'être dessiné.
##
## Aucun test ne pouvait le voir, parce qu'aucun ne REGARDAIT DANS LE TEMPS.
## Tous mesuraient un instant — un plan, une image, une distance — et un
## instant ne dit jamais qu'une courbe monte.
##
## ON MESURE DES PLAFONDS, PAS UNE PENTE. Comparer le début et la fin d'une
## fenêtre paraissait plus fin ; c'était l'inverse. Sur quatre-vingts
## secondes, la vraie fuite ne faisait que six pour cent — indétectable sans
## déclencher de fausses alertes — alors qu'elle dépassait toute limite
## raisonnable sur la durée. Deux plafonds absolus tranchent sans ambiguïté :
## le butin est borné par sa propre règle, et la scène entière par un nombre
## qu'un monde sain ne peut pas atteindre.
func _verifier_la_fuite() -> bool:
	var butins := get_tree().get_nodes_in_group(&"loot").size()
	var noeuds := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	# LE COMPTE D'INSTANCES VISIBLES, et c'est la barrière qui manquait.
	#
	# Un écran entièrement brun a été signalé depuis le téléphone : monde
	# intact, caméra juste, 60 images par seconde, et plus rien de dessiné.
	# Mesuré dans un vrai navigateur : au-delà d'un certain nombre de
	# maillages VISIBLES, le rendu compatibilité de WebGL cesse de soumettre
	# la géométrie 3D — sans une ligne d'erreur. La bascule s'est produite
	# entre 523 maillages (sain) et 782 (mort).
	#
	# Aucune des veilles existantes ne pouvait l'attraper : elles comptent
	# les nœuds, le butin, les cellules — jamais ce que le moteur doit
	# soumettre à chaque image.
	# LE MAXIMUM DE LA SESSION, PAS L'INSTANT FINAL.
	#
	# Le premier jet comptait à la dernière image : la publication a rendu
	# 750 là où j'avais mesuré 609, simplement parce qu'il y avait
	# vingt-six butins au sol chez elle contre cinq chez moi. Une barrière
	# qui dépend de ce qui traîne par terre à la seconde où elle regarde
	# n'est pas une barrière, c'est un tirage.
	var maillages := _pic_maillages
	var ok_maillages := maillages <= PLAFOND_MAILLAGES
	print("  [%s] les instances visibles restent bornées %d visibles (max %d)"
			% ["OK" if ok_maillages else "ÉCHEC", maillages, PLAFOND_MAILLAGES])
	var ok_butin := butins <= PLAFOND_BUTIN
	var ok_noeuds := noeuds <= PLAFOND_NOEUDS
	print("  [%s] le butin reste borné            %d au sol (max %d)"
			% ["OK" if ok_butin else "ÉCHEC", butins, PLAFOND_BUTIN])
	print("  [%s] la scène reste bornée           %d nœuds, %.0f Mo (max %d)"
			% ["OK" if ok_noeuds else "ÉCHEC", noeuds, mem, PLAFOND_NOEUDS])
	return not (ok_butin and ok_noeuds and ok_maillages)


## Plafonds. Le jeu efface le butin au bout de 45 s, avec un maximum de 26
## appliqué une fois par seconde.
##
## LA MARGE EST DE DIX, ET NON DE QUATRE. Mesuré : vingt-sept exemplaires au
## sol en fin de banc, pour un plafond à trente. Un test qui passe de si peu
## finit toujours par échouer un jour où plusieurs mobs meurent dans la même
## seconde — et un test qui échoue au hasard cesse d'être lu. Trente-six
## reste très loin de la quarantaine que montrait la vraie fuite au même
## instant du banc.
const PLAFOND_BUTIN := 36
## Une scène saine se stabilise autour de 3 500 nœuds ; celle qui fuyait
## dépassait 4 600 et continuait.
##
## C'EST LE FILET, PAS LE DÉTECTEUR. Sur les cent-trente secondes du banc,
## la fuite d'origine n'avait pas encore franchi ce plafond — c'est le
## compteur de BUTIN qui l'aurait attrapée, avec une quarantaine
## d'exemplaires au sol pour trente autorisés. Ce second plafond attrape
## tout le reste : la prochaine fuite ne sera pas dans le butin.
const PLAFOND_NOEUDS := 4100

## Maillages VISIBLES tolérés, en PROFIL TÉLÉPHONE uniquement.
##
## CE PLAFOND EST CALÉ SUR DES MESURES, PAS SUR UN CHIFFRE ROND — le
## premier essai à 560 refusait le jeu même sans le moindre contour, ce qui
## en disait plus long sur mon choix que sur le jeu.
##
##     572   plancher : aucun contour du tout
##     620   un contour par personnage — le réglage retenu
##     686   un contour par pièce au-dessus de 0,70 m — tient, mais en
##           zone grise
##     782   un contour par pièce — écran mort, définitif
##
## 720 est calé sur le PIRE CAS et non sur une partie tranquille : le pic
## mesuré est de 648 avec neuf butins au sol, et il monte d'environ trois
## instances par butin supplémentaire — vingt-six étant le maximum toléré,
## le pire cas approche 700. La publication a d'ailleurs rendu 750 avec le
## comptage à l'instant final et le butin d'origine, ce qui a justement
## fait échouer cette barrière sur sa propre livraison.
##
## LA MARGE EST MINCE, ET IL FAUT LE DIRE : entre ce plafond et le premier
## point mortel constaté (782) il ne reste qu'une soixantaine d'instances.
## Le prochain levier est identifié mais non vérifié — effacer à la
## distance les mobs éloignés, qui sont une trentaine dans le monde alors
## que la caméra n'en voit qu'une poignée.
##
## LA MARGE STRUCTURELLE EST MINCE, et c'est à retenir pour la suite : entre
## le plancher et la bascule il n'y a qu'environ deux cents instances pour
## TOUT — les contours, les futurs mobs, les futures armes. Chaque
## personnage à l'écran en coûte une dizaine. Cette barrière existe pour que
## la prochaine fois, ce soit la publication qui le dise, pas la joueuse.
##
## Sur ordinateur le compte est structurellement plus haut — toutes les
## mailles portent leur contour — et le rendu ne bronche pas : le plafond
## n'y a aucun sens, d'où le profil téléphone forcé dans la publication.
const PLAFOND_MAILLAGES := 720


## Compte les maillages réellement visibles dans l'arbre.
func _compter_maillages() -> int:
	var n := 0
	var pile: Array[Node] = [get_tree().root]
	while not pile.is_empty():
		var e: Node = pile.pop_back()
		var mi := e as MeshInstance3D
		if mi != null and mi.is_visible_in_tree():
			n += 1
		for f in e.get_children():
			pile.append(f)
	return n


## QUI EST LÀ, À LA FIN ? Le compteur de nœuds dit QU'ÇA grossit ; il ne
## dit pas QUOI. On recense donc l'arbre par nature de nœud : ce qui fuit
## apparaît en tête, et le nom du coupable est le nom de sa classe.
func _inventaire() -> void:
	var par_type: Dictionary = {}
	var pile: Array[Node] = [get_tree().root]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		var cle := n.get_class()
		var sc: Script = n.get_script() as Script
		if sc != null:
			cle += " (%s)" % sc.resource_path.get_file()
		par_type[cle] = int(par_type.get(cle, 0)) + 1
		for e in n.get_children():
			pile.append(e)
	var liste: Array = []
	for k in par_type:
		liste.append([int(par_type[k]), k])
	liste.sort_custom(func(a, b): return a[0] > b[0])
	print("  --- inventaire de l'arbre ---")
	for e in liste.slice(0, 14):
		print("      %5d × %s" % [e[0], e[1]])


func _ligne(libelle: String, ok: bool, detail: String) -> void:
	print("  [%s] %-33s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


func _bref(v: Vector3) -> String:
	return "(%d, %d, %d)" % [roundi(v.x), roundi(v.y), roundi(v.z)]


func _conclure() -> void:
	_prete = false
	print("=== SONDE DE L'ÉCRAN VIOLET (%.0f s, %d images, %d morts) ==="
			% [_t, _images, _morts])
	print("  images sans caméra active         : %d" % _sans_camera)
	print("  images sans aucun décor autour    : %d" % _sans_decor)
	print("  minimum de cellules autour        : %d" % _pire)
	print("  altitude maximale de la caméra    : %.1f m" % _y_cam_max)
	print("  altitude maximale du joueur       : %.1f m" % _y_joueur_max)
	print("  images caméra au-dessus de 60 m   : %d" % _haut)
	print("  --- ce qui grossit avec le temps ---")
	print("      %5s %8s %8s %10s %8s %6s %8s"
			% ["t(s)", "nœuds", "objets", "orphelins", "Mo", "mobs", "dessins"])
	for r: Dictionary in _releve:
		print("      %5.0f %8d %8d %10d %8.1f %6d %8d"
				% [r["t"], r["noeuds"], r["objets"], r["orphelins"], r["mem"],
				r["mobs"], r["dessins"]])
	print("      %s" % _pire_note)
	_inventaire()
	var fuite := _verifier_la_fuite()
	# CHAQUE CONDITION S'ANNONCE, ET C'EST UNE CORRECTION DE L'INSTRUMENT.
	#
	# Trois de ces quatre conditions ne s'imprimaient nulle part : la
	# publication a rendu « régression » en n'affichant que deux lignes
	# marquées OK. Un banc qui échoue sans dire sur quoi oblige à relire
	# tout son journal, et fait perdre exactement le temps qu'il devait
	# faire gagner.
	_ligne("une caméra active à chaque image", _sans_camera == 0,
			"%d image(s) sans caméra" % _sans_camera)
	_ligne("du décor autour à chaque image", _sans_decor == 0,
			"%d image(s) sans décor · minimum %d cellules"
			% [_sans_decor, _pire])
	_ligne("la caméra reste à hauteur de jeu", _haut == 0,
			"%d image(s) au-dessus de 60 m · maximum %.1f m"
			% [_haut, _y_cam_max])
	var ok := _sans_camera == 0 and _sans_decor == 0 and _haut == 0 and not fuite
	print("=== %d échec(s) sur 1 vérification ===" % (0 if ok else 1))
	get_tree().quit(0 if ok else 1)
