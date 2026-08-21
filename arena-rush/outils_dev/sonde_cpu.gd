extends Node
## SONDE CPU — le coût de la SIMULATION, rendu retiré de l'équation.
##
## POURQUOI ELLE EXISTE. La joueuse est tombée à 15 images par seconde
## APRÈS deux passes qui allégeaient le rendu, et son intuition — « ce ne
## sont pas les décors » — méritait mieux qu'une opinion en face. Les
## sondes existantes comptent ce que la carte DESSINE ; aucune ne mesurait
## ce que le jeu CALCULE. En headless, le serveur de rendu est un mannequin
## qui ne dessine rien : ce qui reste au chronomètre, c'est le code —
## scripts, physique, IA, interface.
##
## Elle mesure PAR IMAGE le temps de traitement et le temps de physique
## (moniteurs du moteur), et rend le verdict qui compte : la cadence
## maximale que le CPU seul autoriserait. Si ce plafond est déjà sous
## 60, aucune optimisation de rendu ne sauvera le téléphone.

const DUREE := 22.0

var _main: Node
var _t := 0.0
var _demarre := false
var _ech_process: Array[float] = []
var _ech_physique: Array[float] = []
var _ticks_physique := 0


func _ready() -> void:
	# Variantes de bissection, pour désigner le poste qui coûte :
	#   --phys60 : cadence de physique abaissée à 60 Hz ;
	#   --figer  : cerveaux des bots coupés après la chauffe — plus de
	#              déplacements ni de tirs, il ne reste que les corps
	#              immobiles, le monde et l'interface.
	if "--phys60" in OS.get_cmdline_user_args():
		Engine.physics_ticks_per_second = 60
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	# Cinq secondes de chauffe : apparitions, premiers échanges des bots.
	await get_tree().create_timer(5.0).timeout
	if "--figer" in OS.get_cmdline_user_args():
		var n := 0
		for j in get_tree().get_nodes_in_group(&"players"):
			for c in j.get_children():
				if c.get_script() != null \
						and String(c.get_script().resource_path).contains("bot_brain"):
					c.set_physics_process(false)
					c.set_process(false)
					n += 1
		print("[sonde_cpu] %d cerveaux figés" % n)
	_demarre = true
	print("[sonde_cpu] mesure lancée — physique à %d Hz" \
			% Engine.physics_ticks_per_second)


func _physics_process(_d: float) -> void:
	if _demarre:
		_ticks_physique += 1


func _process(delta: float) -> void:
	if not _demarre:
		return
	_t += delta
	# Les moniteurs rendent le temps de la DERNIÈRE image, en secondes.
	_ech_process.append(
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_ech_physique.append(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if _t >= DUREE:
		_rapport()
		get_tree().quit(0)


func _percentile(v: Array[float], p: float) -> float:
	var tri := v.duplicate()
	tri.sort()
	return tri[clampi(int(float(tri.size()) * p), 0, tri.size() - 1)]


func _rapport() -> void:
	var somme_p := 0.0
	for e in _ech_process:
		somme_p += e
	var somme_f := 0.0
	for e in _ech_physique:
		somme_f += e
	var n := maxi(_ech_process.size(), 1)
	var moy_p := somme_p / n
	var moy_f := somme_f / n
	# Le tick de physique moyen : le moniteur donne le temps de physique
	# par IMAGE ; en headless l'image suit la cadence maximale demandée,
	# et plusieurs ticks peuvent s'y entasser.
	var ticks_par_image := float(_ticks_physique) / float(n)
	var tick_ms := moy_f / maxf(ticks_par_image, 0.001)
	print("\n=== SONDE CPU (rendu mannequin, %d images sur %.0f s) ===\n"
			% [n, DUREE])
	print("  traitement par image      moyenne %6.2f ms   p95 %6.2f ms"
			% [moy_p, _percentile(_ech_process, 0.95)])
	print("  physique par image        moyenne %6.2f ms   p95 %6.2f ms"
			% [moy_f, _percentile(_ech_physique, 0.95)])
	print("  ticks de physique         %.2f par image   soit %6.2f ms le tick"
			% [ticks_par_image, tick_ms])
	print("  corps actifs %d · paires de collision %d · îlots %d"
			% [int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))])
	# À 60 images par seconde, chaque image paie son traitement plus
	# physique_Hz/60 ticks de physique. C'est le budget CPU réel.
	var cout_60 := moy_p + tick_ms * float(Engine.physics_ticks_per_second) / 60.0
	print("")
	print("  coût CPU d'une image à 60 FPS : %.2f ms  →  plafond CPU ≈ %d FPS"
			% [cout_60, int(1000.0 / maxf(cout_60, 0.001))])
	print("")
	print("=== 0 échec(s) ===")
