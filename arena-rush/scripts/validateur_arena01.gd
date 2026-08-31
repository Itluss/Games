extends SceneTree
## VALIDATEUR AUTOMATIQUE — ARENA 01 : THE CONVERGENCE (V2, topologie de
## circulation corrigée). Non interactif, sans scène, sans rendu. Vérifie
## les données de `BlockoutPlan`, y compris son graphe de navigation.
##
## Lancer :
##   godot --headless --path arena-rush --script res://scripts/validateur_arena01.gd
##
## Code de sortie = nombre d'échecs (0 = tout est passé).

var _echecs := 0


func _initialize() -> void:
	print("=== VALIDATEUR ARENA 01 (V2) ===")
	_verifier_spawns()
	_verifier_sorties_secteur()
	_verifier_hubs()
	_verifier_pas_de_lien_direct_spawn_core()
	_verifier_chemins_spawn_core()
	_verifier_loot()
	_verifier_geometrie()
	_verifier_plateformes()
	_verifier_pas_de_cul_de_sac()
	print("")
	if _echecs == 0:
		print("VALIDATION OK — 0 échec")
	else:
		print("VALIDATION ÉCHOUÉE — %d échec(s)" % _echecs)
	quit(_echecs)


func _dire(nom: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[OK]   %s" % nom)
	else:
		_echecs += 1
		print("[FAIL] %s%s" % [nom, ("  — " + detail) if detail != "" else ""])


# --- 1. SPAWNS ------------------------------------------------------------

func _verifier_spawns() -> void:
	_dire("12 spawns exactement", BlockoutPlan.SPAWNS.size() == 12,
			"trouvé %d" % BlockoutPlan.SPAWNS.size())
	var noms := {}
	for s: Dictionary in BlockoutPlan.SPAWNS:
		noms[s["nom"]] = true
	for i in range(1, 13):
		_dire("spawn nommé S%02d présent" % i, noms.has("S%02d" % i))
	for s: Dictionary in BlockoutPlan.SPAWNS:
		var pos: Vector2 = s["pos"]
		_dire("%s à l'intérieur de l'enceinte" % s["nom"], pos.length() < BlockoutPlan.R_BORD,
				"r=%.1f" % pos.length())
	var min_dist := INF
	var pire := ""
	for i in BlockoutPlan.SPAWNS.size():
		for j in range(i + 1, BlockoutPlan.SPAWNS.size()):
			var a: Vector2 = BlockoutPlan.SPAWNS[i]["pos"]
			var b: Vector2 = BlockoutPlan.SPAWNS[j]["pos"]
			var d := a.distance_to(b)
			if d < min_dist:
				min_dist = d
				pire = "%s-%s" % [BlockoutPlan.SPAWNS[i]["nom"], BlockoutPlan.SPAWNS[j]["nom"]]
	_dire("≥18 m entre toute paire de spawns", min_dist >= 18.0,
			"min=%.1f (%s)" % [min_dist, pire])


# --- 2. DEUX SORTIES PAR SECTEUR --------------------------------------------

func _verifier_sorties_secteur() -> void:
	for secteur in BlockoutPlan.SECTEURS:
		var a := BlockoutPlan.NAV_NOEUDS.has("sortie_%s_cw" % secteur)
		var b := BlockoutPlan.NAV_NOEUDS.has("sortie_%s_ccw" % secteur)
		_dire("secteur %s a ses 2 sorties déclarées (horaire+antihoraire)" % secteur, a and b)
	_dire("chaque secteur atteint 2 hubs différents", _tous_secteurs_2_hubs_distincts())


func _tous_secteurs_2_hubs_distincts() -> bool:
	for secteur in BlockoutPlan.SECTEURS:
		var cw: String = BlockoutPlan.SECTEUR_HUBS[secteur]["cw"]
		var ccw: String = BlockoutPlan.SECTEUR_HUBS[secteur]["ccw"]
		if cw == ccw:
			return false
	return true


# --- 3-4. HUBS ---------------------------------------------------------------

func _verifier_hubs() -> void:
	_dire("4 hubs diagonaux présents", BlockoutPlan.HUBS.size() == 4,
			str(BlockoutPlan.HUBS.size()))
	for hub in BlockoutPlan.HUBS:
		_dire("hub %s : nœud central présent" % hub,
				BlockoutPlan.NAV_NOEUDS.has("hub_%s_centre" % hub))
		var secteurs: Array = BlockoutPlan.HUB_SECTEURS.get(hub, [])
		_dire("hub %s reçoit des routes d'exactement 2 secteurs voisins" % hub,
				secteurs.size() == 2, "trouvé %d (%s)" % [secteurs.size(), str(secteurs)])
		# Vérifie que les arêtes déclarées correspondent vraiment aux 2
		# secteurs annoncés (pas juste la métadonnée HUB_SECTEURS).
		var sources := {}
		for arete: Dictionary in BlockoutPlan.NAV_ARETES:
			var autre := ""
			if arete["b"] == "hub_%s_centre" % hub and arete["a"].begins_with("sortie_"):
				autre = arete["a"]
			elif arete["a"] == "hub_%s_centre" % hub and arete["b"].begins_with("sortie_"):
				autre = arete["b"]
			if autre != "":
				sources[autre] = true
		_dire("hub %s : 2 arêtes de sortie de secteur réellement déclarées" % hub,
				sources.size() == 2, "trouvé %d" % sources.size())


# --- 6. AUCUN LIEN DIRECT SPAWN → CORE --------------------------------------

func _verifier_pas_de_lien_direct_spawn_core() -> void:
	var viole := 0
	for arete: Dictionary in BlockoutPlan.NAV_ARETES:
		var a: String = arete["a"]
		var b: String = arete["b"]
		var touche_spawn := a.begins_with("spawn_") or b.begins_with("spawn_")
		var touche_core := a.begins_with("entree_core_") or b.begins_with("entree_core_") \
				or a == "core_centre" or b == "core_centre"
		if touche_spawn and touche_core:
			viole += 1
	_dire("aucun lien direct déclaré spawn → Core", viole == 0, "%d lien(s)" % viole)


# --- 7-9. CHEMINS SPAWN → CORE (via le graphe de navigation) --------------

func _verifier_chemins_spawn_core() -> void:
	for s: Dictionary in BlockoutPlan.SPAWNS:
		var depart := "spawn_%s" % s["nom"]
		var meilleur: Dictionary = {"distance": INF, "chemin": [], "hub": ""}
		for hub in BlockoutPlan.HUBS:
			var r: Dictionary = BlockoutPlan.chemin_le_plus_court(depart, "entree_core_%s" % hub)
			if r["distance"] < meilleur["distance"]:
				meilleur = {"distance": r["distance"], "chemin": r["chemin"], "hub": hub}

		var chemin: Array = meilleur["chemin"]
		var a_hub := false
		var a_anneau := false
		for n: String in chemin:
			if n.begins_with("hub_"):
				a_hub = true
			if n.contains("anneau"):
				a_anneau = true
		_dire("%s → Core passe par un hub puis par l'anneau" % s["nom"], a_hub and a_anneau,
				"chemin=%s" % str(chemin))
		_dire("%s → entrée Core la plus proche ≥ 75 m" % s["nom"], meilleur["distance"] >= 75.0,
				"%.1f m" % meilleur["distance"])
		var virages := _compter_virages_significatifs(chemin)
		_dire("%s → Core : ≥2 changements de direction significatifs" % s["nom"], virages >= 2,
				"%d viragе(s) > 20°" % virages)


## Compte les virages > 20° le long d'une suite de nœuds nommés.
func _compter_virages_significatifs(chemin: Array) -> int:
	if chemin.size() < 3:
		return 0
	var n := 0
	for i in range(1, chemin.size() - 1):
		var p0: Vector2 = BlockoutPlan.NAV_NOEUDS[chemin[i - 1]]
		var p1: Vector2 = BlockoutPlan.NAV_NOEUDS[chemin[i]]
		var p2: Vector2 = BlockoutPlan.NAV_NOEUDS[chemin[i + 1]]
		var d1 := (p1 - p0)
		var d2 := (p2 - p1)
		if d1.length() < 0.01 or d2.length() < 0.01:
			continue
		var angle := rad_to_deg(absf(d1.angle_to(d2)))
		if angle > 20.0:
			n += 1
	return n


# --- LOOT / SOINS / SOCKETS ---------------------------------------------

func _verifier_loot() -> void:
	_dire("6 loot haut-tier", BlockoutPlan.LOOT_HAUT.size() == 6,
			str(BlockoutPlan.LOOT_HAUT.size()))
	_dire("12 loot moyen-tier", BlockoutPlan.LOOT_MOYEN.size() == 12,
			str(BlockoutPlan.LOOT_MOYEN.size()))
	_dire("16 loot commun", BlockoutPlan.LOOT_COMMUN.size() == 16,
			str(BlockoutPlan.LOOT_COMMUN.size()))
	_dire("4 stations de soin", BlockoutPlan.SOINS.size() == 4,
			str(BlockoutPlan.SOINS.size()))
	_dire("≥5 sockets de zone finale", BlockoutPlan.SOCKETS_ZONE_FINALE.size() >= 5,
			str(BlockoutPlan.SOCKETS_ZONE_FINALE.size()))
	# Aucun loot élevé à proximité (< 25 m) d'un spawn.
	var viole := 0
	for p: Vector2 in BlockoutPlan.LOOT_HAUT:
		for s: Dictionary in BlockoutPlan.SPAWNS:
			if p.distance_to(s["pos"]) < 25.0:
				viole += 1
				break
	_dire("aucun loot haut-tier à proximité d'un spawn (< 25 m)", viole == 0,
			"%d violation(s)" % viole)


# --- GÉOMÉTRIE PRINCIPALE ------------------------------------------------

func _verifier_geometrie() -> void:
	var marge := 1.5
	var hors_limite := 0
	for m: Dictionary in BlockoutPlan.MURS:
		for p: Vector2 in m["points"]:
			if p.length() > BlockoutPlan.R_BORD + marge:
				hors_limite += 1
	_dire("aucune géométrie principale hors de l'enceinte (r=%.0f)" % BlockoutPlan.R_BORD,
			hors_limite == 0, "%d point(s) hors limite" % hors_limite)


# --- PLATEFORMES HAUTES (toujours des socles pleins en V2) --------------

func _verifier_plateformes() -> void:
	_dire("4 plateformes hautes (y=%.0f)" % BlockoutPlan.Y_SNIPER,
			BlockoutPlan.PLATEFORMES.size() == 4, str(BlockoutPlan.PLATEFORMES.size()))
	for p: Dictionary in BlockoutPlan.PLATEFORMES:
		_dire("plateforme %s : socle plein (y == Y_SNIPER, pas de dalle suspendue)" % p["nom"],
				p["y"] == BlockoutPlan.Y_SNIPER, "y=%.1f" % p["y"])
		var acces: Array = p.get("acces", [])
		_dire("plateforme %s a ≥2 accès déclarés" % p["nom"], acces.size() >= 2,
				str(acces.size()))


# --- CULS-DE-SAC (vérification partielle, cf. rapport) --------------------
## Vérifie que les amas de couverture (hubs, écrans) ne forment pas de
## polygone fermé (un mur dont le premier et le dernier point coïncident
## en dehors des anneaux qui DOIVENT être fermés) — un indice fort de
## poche sans issue. Ne remplace pas une vraie recherche géométrique de
## cul-de-sac (non implémentée, cf. limites dans le rapport final).
func _verifier_pas_de_cul_de_sac() -> void:
	var fermes := 0
	for m: Dictionary in BlockoutPlan.MURS:
		var nom: String = m["nom"]
		if nom.begins_with("enceinte_") or nom.begins_with("core_mur_"):
			continue  # anneaux : fermés par construction, c'est voulu
		var pts: PackedVector2Array = m["points"]
		if pts.size() >= 3 and pts[0].distance_to(pts[pts.size() - 1]) < 0.1:
			fermes += 1
	_dire("aucune couverture/écran ne forme un polygone fermé (indice de cul-de-sac)",
			fermes == 0, "%d fermé(s)" % fermes)
