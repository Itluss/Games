extends Node3D
## BANC DE L'ARÈNE AUX BLOCS — la carte de la planche tient-elle ses
## promesses de JEU ?
##
## La fidélité visuelle se juge en capture, côte à côte avec la référence.
## Ici on répond aux questions qu'aucune image ne tranche : les huit
## quartiers existent-ils dans les données ; les apparitions sont-elles
## jouables ; l'eau arrête-t-elle vraiment ; le pont passe-t-il vraiment ;
## le labyrinthe est-il resté OUVERT — c'est la règle n° 1 du brief, et
## c'est celle qu'une retouche de plan casse le plus facilement.

## Rayon du corps d'un joueur, pour juger un passage praticable.
const RAYON_CORPS := 0.45

var _echecs := 0
var _arene: Node


func _ready() -> void:
	Cfg.arene_test = true
	_arene = Arena.new()
	_arene.name = "Arena"
	add_child(_arene)
	await get_tree().process_frame
	await get_tree().physics_frame

	print("\n=== BANC DE L'ARÈNE AUX BLOCS ===\n")
	_quartiers()
	_apparitions()
	_eau_et_pont()
	_ouverture()
	_enceinte()

	print("")
	print("=== %d échec(s) ===" % _echecs)
	if _echecs == 0:
		print("Arène aux blocs : conforme.")
	else:
		print("Arène aux blocs : %d anomalie(s)." % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


func _dire(nom: String, ok: bool, detail := "") -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-46s %s" % ["OK" if ok else "ÉCHEC", nom, detail])


## LES HUIT QUARTIERS EXISTENT — comptés dans le PLAN, pas devinés au
## pixel. Chaque zone de la planche a sa signature : une teinte, un
## module, un compte plancher. Si une retouche vide un quartier, ce banc
## le dit avant la capture.
func _quartiers() -> void:
	var comptes: Dictionary = {}
	for e: Dictionary in PlanAreneBlocs.PIECES:
		var cle := "%s_%s" % [e["m"], e.get("c", "")]
		comptes[cle] = int(comptes.get(cle, 0)) + 1
		var cm := String(e["m"])
		comptes[cm] = int(comptes.get(cm, 0)) + 1
	_dire("1 · la place : plateforme unique",
			int(comptes.get("plateforme", 0)) == 1)
	_dire("2 · les ruines et 5 · le canyon : blocs rouges",
			int(comptes.get("bloc_rouge", 0)) >= 40,
			str(comptes.get("bloc_rouge", 0)))
	_dire("3 · la jungle : haies vertes",
			int(comptes.get("bloc_vert", 0)) >= 20,
			str(comptes.get("bloc_vert", 0)))
	_dire("3 · la jungle : arbres et palmiers",
			int(comptes.get("arbre", 0)) + int(comptes.get("palmier", 0)) >= 20,
			str(int(comptes.get("arbre", 0)) + int(comptes.get("palmier", 0))))
	_dire("4 · le village : deux cabanes",
			int(comptes.get("cabane", 0)) == 2)
	_dire("6 · les champs : blocs jaunes",
			int(comptes.get("bloc_jaune", 0)) >= 10,
			str(comptes.get("bloc_jaune", 0)))
	_dire("7 · l'oasis : deux bassins et un pont",
			PlanAreneBlocs.BASSINS.size() == 2
			and int(comptes.get("pont", 0)) >= 1)
	_dire("8 · le laboratoire : blocs violets et machines",
			int(comptes.get("bloc_violet", 0)) >= 12
			and int(comptes.get("machine", 0)) >= 2,
			str(comptes.get("bloc_violet", 0)))
	_dire("toutes les pièces sont dans l'enceinte",
			_pieces_dedans(), "")


func _pieces_dedans() -> bool:
	for e: Dictionary in PlanAreneBlocs.PIECES:
		if not PlanAreneBlocs.dans_enceinte(e["pos"], 0.0):
			return false
	return true


## DIX APPARITIONS JOUABLES : dans l'enceinte, sur du sol libre, et
## jamais dans l'eau. Un joueur qui réapparaît coincé dans un bloc a
## perdu sans adversaire.
func _apparitions() -> void:
	# ON JUGE LA DONNÉE DU JEU, pas l'idéal du plan : l'arène dégage
	# elle-même ses apparitions à la construction, et c'est le résultat
	# de ce dégagement que les joueurs vivront.
	var points: Array = _arene.get(&"player_spawn_points")
	var n := points.size()
	_dire("dix apparitions", n == 10, str(n))
	var libres := 0
	for p: Vector3 in points:
		if bool(_arene.call(&"dans_terrain", p, 1.0)) \
				and bool(_arene.call(&"position_libre", p,
						RAYON_CORPS + 0.2)):
			libres += 1
	_dire("toutes dans l'enceinte et dégagées", libres == n,
			"%d/%d" % [libres, n])


## L'EAU ARRÊTE, LE PONT PASSE. Les deux propriétés se testent au même
## instrument (l'espace libre du monde) : si l'une ment, l'autre aussi.
func _eau_et_pont() -> void:
	var grand: Dictionary = PlanAreneBlocs.BASSINS[0]
	var c: Vector2 = grand["centre"]
	_dire("le cœur du grand bassin est infranchissable",
			not bool(_arene.call(&"position_libre",
					Vector3(c.x, 0.2, c.y), RAYON_CORPS)))
	# Le pont enjambe le détroit : son tablier doit être praticable.
	var pont := Vector2.ZERO
	for e: Dictionary in PlanAreneBlocs.PIECES:
		if e["m"] == "pont":
			pont = e["pos"]
			break
	_dire("le tablier du pont est praticable",
			bool(_arene.call(&"position_libre",
					Vector3(pont.x, 0.2, pont.y), RAYON_CORPS)),
			"%.0f, %.0f" % [pont.x, pont.y])


## LE LABYRINTHE RESTE OUVERT — la règle n° 1, mesurée sur ce que le
## plan PROMET désormais : des RUES. L'ancienne mesure balayait un anneau
## à seize mètres ; depuis que la carte est un réseau d'allées, cet
## anneau traverse légitimement des haies — l'instrument mesurait la
## promesse d'avant. Ici on parcourt le FIL de chaque rue déclarée par le
## plan, pas à pas : les deux axes, le rectangle des rues à ±12, et le
## tour de place entre la plateforme et son enclos. Une rue se doit
## d'être praticable de bout en bout — le seuil est à 90 %.
func _ouverture() -> void:
	var rues := [
		["axe nord",  Vector2(0, 13),   Vector2(0, 33)],
		["axe sud",   Vector2(0, -13),  Vector2(0, -33)],
		["axe est",   Vector2(13, 0),   Vector2(33, 0)],
		["axe ouest", Vector2(-13, 0),  Vector2(-33, 0)],
		["rue z=+12", Vector2(-30, 12), Vector2(30, 12)],
		["rue z=-12", Vector2(-30, -12), Vector2(30, -12)],
		["rue x=+12", Vector2(12, -30), Vector2(12, 30)],
		["rue x=-12", Vector2(-12, -30), Vector2(-12, 30)],
	]
	for r: Array in rues:
		var de: Vector2 = r[1]
		var vers: Vector2 = r[2]
		var n := int(de.distance_to(vers) / 1.0)
		var libres := 0
		for i in n + 1:
			var q := de.lerp(vers, float(i) / maxf(n, 1))
			if bool(_arene.call(&"position_libre",
					Vector3(q.x, 0.2, q.y), RAYON_CORPS)):
				libres += 1
		_dire("la rue « %s » circule" % r[0],
				libres >= (n + 1) * 9 / 10, "%d/%d" % [libres, n + 1])
	# Le tour de place, entre la plateforme et l'enclos en moulinet.
	var tour := 0
	for i in 16:
		var a := TAU * float(i) / 16.0
		if bool(_arene.call(&"position_libre",
				Vector3(cos(a) * 5.6, 0.2, sin(a) * 5.6), RAYON_CORPS)):
			tour += 1
	_dire("le tour de place circule", tour == 16, "%d/16" % tour)


## L'ENCEINTE TIENT : un point du large est dehors, et le rapatriement le
## ramène sur l'île.
func _enceinte() -> void:
	_dire("le large est hors enceinte",
			not bool(_arene.call(&"dans_terrain", Vector3(60, 0.2, 60), 0.0)))
	var r: Vector3 = _arene.call(&"ramener_dans_terrain",
			Vector3(60, 0.2, 60), 2.0)
	_dire("un point du large est ramené sur l'île",
			bool(_arene.call(&"dans_terrain", r, 0.0)),
			"%.1f, %.1f" % [r.x, r.z])
