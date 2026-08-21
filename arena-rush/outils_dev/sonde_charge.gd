extends Node
## SONDE DE CHARGE — ce que le moteur doit dessiner, et ce qui le lui coûte.
##
## ─── POURQUOI ELLE EXISTE ──────────────────────────────────────────────
##
## « Je ne dépasse plus les 30 images par seconde, le jeu est difficilement
## jouable. » Une chute de cadence ne se diagnostique pas en lisant du
## code : on peut passer une journée à optimiser ce qui ne coûtait rien.
##
## Cette machine rend en LOGICIEL, à une ou deux images par seconde : y
## mesurer des FPS n'aurait aucun sens et ce banc n'en mesure pas. Il
## mesure ce qui, lui, ne dépend pas de la carte graphique :
##
##   · le nombre d'OBJETS soumis au rendu à chaque image ;
##   · le nombre de PRIMITIVES (triangles) de ces objets ;
##   · le nombre d'APPELS DE DESSIN — le poste qui tue le mobile ;
##   · le nombre de projectiles vivants et de nœuds de la scène.
##
## Ces quatre nombres sont les mêmes sur un téléphone et ici. S'ils ont
## doublé, on sait où chercher ; s'ils n'ont pas bougé, la cause est
## ailleurs et l'on aura évité d'optimiser à l'aveugle.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_charge.tscn \
##       --rendering-driver opengl3 -- --solo --arene-test [--mobile]

## Durée d'observation, en secondes. Assez longue pour que les bots se
## trouvent, s'engagent et tirent : c'est le pire cas qu'on veut voir, pas
## la carte au repos.
const DUREE := 22.0
## Période d'échantillonnage.
const PAS := 0.25

var _main: Node
var _t := 0.0
var _prochain := 0.0
var _demarre := false

var _pic_objets := 0
var _pic_prims := 0
var _pic_appels := 0
var _pic_proj := 0
var _pic_noeuds := 0
var _somme_objets := 0
var _somme_appels := 0
## LA MOYENNE DES PRIMITIVES, pas seulement le pic. Un pic est un seul
## échantillon : il suffit que la caméra se tourne une fois vers un amas
## de rochers pour qu'il double, sans que la partie soit plus lourde.
## Comparer deux versions sur des pics, c'est comparer deux hasards.
var _somme_prims := 0
var _echantillons := 0


func _ready() -> void:
	get_window().size = Vector2i(1688, 780)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# On laisse le monde se bâtir et les bots se mettre en marche avant de
	# compter : le pic du chargement n'a rien à voir avec le jeu.
	if not _demarre:
		if _t < 4.0:
			return
		_demarre = true
		_t = 0.0
		_prochain = 0.0
		return
	if _t >= DUREE:
		_rapport()
		get_tree().quit(0)
		return
	if _t < _prochain:
		return
	_prochain = _t + PAS
	_echantillon()


func _echantillon() -> void:
	var objets := int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var appels := int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	# ON COMPTE DEPUIS LA RACINE DE L'ARBRE, pas depuis la scène montée.
	# Les projectiles sont pris dans une réserve et rattachés à l'ARÈNE,
	# qui n'est pas sous `_main` : cherchés au mauvais endroit, ils
	# rendaient zéro et donnaient à croire que personne ne tirait.
	var proj := _compter_projectiles(get_tree().root)
	var noeuds := _compter(get_tree().root)

	_pic_objets = maxi(_pic_objets, objets)
	_pic_prims = maxi(_pic_prims, prims)
	_pic_appels = maxi(_pic_appels, appels)
	_pic_proj = maxi(_pic_proj, proj)
	_pic_noeuds = maxi(_pic_noeuds, noeuds)
	_somme_objets += objets
	_somme_appels += appels
	_somme_prims += prims
	_echantillons += 1


func _compter(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _compter(c)
	return t


func _compter_projectiles(n: Node) -> int:
	var t := 0
	if n is Projectile and (n as Projectile).visible:
		t += 1
	for c in n.get_children():
		t += _compter_projectiles(c)
	return t


func _rapport() -> void:
	print("\n=== SONDE DE CHARGE ===\n")
	print("  profil : %s · qualité %d · %d échantillons sur %.0f s"
			% ["téléphone" if Cfg.est_mobile() else "bureau",
			Cfg.quality, _echantillons, DUREE])
	print("")
	print("  objets soumis au rendu    pic %6d   moyenne %6d"
			% [_pic_objets, _somme_objets / maxi(_echantillons, 1)])
	print("  appels de dessin          pic %6d   moyenne %6d"
			% [_pic_appels, _somme_appels / maxi(_echantillons, 1)])
	print("  primitives                pic %6d   moyenne %6d"
			% [_pic_prims, _somme_prims / maxi(_echantillons, 1)])
	print("  projectiles vivants       pic %6d" % _pic_proj)
	print("  nœuds de la scène         pic %6d" % _pic_noeuds)
	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh`.
	print("=== 0 échec(s) ===")
