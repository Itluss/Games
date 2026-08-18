extends Node
## SONDE DE PERFORMANCE — outil de développement, hors jeu.
##
## CE QU'ELLE MESURE, ET CE QU'ELLE REFUSE DE MESURER.
##
## Cette machine rend en logiciel, à quelques images par seconde. Le temps
## d'image qu'on y lit ne dit RIEN de ce que fera un téléphone : il est
## dominé par une rastérisation qui n'existe pas sur un vrai processeur
## graphique. Publier ce chiffre comme un résultat serait pire que ne rien
## mesurer, parce qu'on y croirait.
##
## Trois grandeurs, elles, sont PORTABLES — elles ne dépendent pas du
## matériel, et ce sont exactement celles qui décident sur mobile :
##
##   • LES APPELS DE DESSIN. Le premier plafond d'un téléphone. Chaque
##     appel coûte un aller-retour avec le pilote, quel que soit ce qu'il
##     dessine.
##   • LE TEMPS PASSÉ DANS LES SCRIPTS. `TIME_PROCESS` et
##     `TIME_PHYSICS_PROCESS` mesurent du GDScript, donc du CPU, donc
##     quelque chose qui se transpose.
##   • LE NOMBRE DE CORPS PHYSIQUES ACTIFS et de nœuds. Ce sont eux qui
##     font grimper les deux précédents.
##
## Le joueur MARCHE pendant la mesure : une sonde qui laisse le personnage
## immobile ne visite jamais les secteurs denses, c'est-à-dire précisément
## ceux qui coûtent cher.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/sonde_perf.tscn \
##       --rendering-driver opengl3 -- --solo [--mobile]

const LARGEUR := 640
const HAUTEUR := 360
## Durée observée, en secondes de jeu.
const DUREE := 60.0
## On ignore les premières secondes : la construction du monde et le
## préchauffage des effets ne représentent pas le régime de croisière.
const CHAUFFE := 6.0

var _t := 0.0
var _n := 0
var _joueur: Node3D
var _prete := false

var _dessins: Array[float] = []
var _objets: Array[float] = []
var _proc: Array[float] = []
var _phys: Array[float] = []

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().create_timer(2.5).timeout
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == Net.local_id():
			_joueur = n
	if _joueur == null:
		push_error("Aucun joueur local.")
		get_tree().quit(1)
		return
	_prete = true


func _process(delta: float) -> void:
	if not _prete:
		return
	_t += delta
	# Grande boucle traversant les six secteurs, en vraies commandes.
	if not bool(_joueur.get(&"is_eliminated")):
		var a := _t * 0.5
		var p := Vector2(cos(a * 0.19), sin(a * 0.19)) * 58.0
		var vers := p - Vector2(_joueur.global_position.x,
				_joueur.global_position.z)
		_joueur.set(&"move_input", vers.normalized())
		_joueur.set(&"aim_input", Vector3(vers.x, 0.0, vers.y).normalized())
		# ON TIRE. Les projectiles, les impacts et les gerbes de particules
		# sont une part importante du coût, et une mesure prise au repos les
		# laisserait tous de côté.
		_joueur.set(&"want_fire", true)

	if _t < CHAUFFE:
		return
	_dessins.append(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_objets.append(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_phys.append(Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_n += 1
	if _t > DUREE:
		_conclure()


func _stat(nom: String, v: Array[float], unite: String) -> void:
	if v.is_empty():
		print("  %-34s aucune mesure" % nom)
		return
	var tri := v.duplicate()
	tri.sort()
	var somme := 0.0
	for x in tri:
		somme += x
	# LA MÉDIANE ET LE CENTILE 95, pas la moyenne et le maximum. Une moyenne
	# masque les à-coups, et un maximum isolé accuse souvent une trame de
	# chargement. Le 95 est ce que le joueur ressent comme « ça rame ».
	var med: float = tri[tri.size() / 2]
	var p95: float = tri[mini(tri.size() - 1, int(float(tri.size()) * 0.95))]
	print("  %-34s médiane %8.1f %s · 95e %8.1f %s · pire %8.1f %s"
			% [nom, med, unite, p95, unite, tri[tri.size() - 1], unite])


func _conclure() -> void:
	_prete = false
	print("=== SONDE DE PERFORMANCE (%.0f s, %d images) ===" % [_t, _n])
	_stat("appels de dessin", _dessins, "")
	_stat("objets dessinés", _objets, "")
	_stat("temps des scripts (_process)", _proc, "ms")
	_stat("temps de la physique", _phys, "ms")
	print("  nœuds dans l'arbre                 %d"
			% [Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("  corps physiques actifs             %d"
			% [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
	print("  paires de collision                %d"
			% [Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	# LE NOMBRE DE RESSOURCES est la mesure du gaspillage d'allocation :
	# chaque matériau, maillage ou courbe construit en vol y apparaît. Une
	# valeur qui MONTE pendant la partie signale qu'on fabrique du neuf là
	# où l'on devrait recycler — c'est ce qui produit les à-coups.
	print("  ressources vivantes                %d"
			% [Performance.get_monitor(Performance.OBJECT_COUNT)])
	print("  mémoire vive                       %.1f Mo"
			% [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	print("  mobs vivants                       %d"
			% get_tree().get_nodes_in_group(&"mobs").size())
	get_tree().quit(0)
