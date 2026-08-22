extends Node
## BANC DE LA PRIME — les situations qui décident du mode.
##
## ─── CE QU'IL VÉRIFIE, ET POURQUOI CELLES-LÀ ───────────────────────────
##
## La règle tient en trois phrases, et chacune de ses transitions peut se
## casser sans que rien ne plante :
##
##   1. un mob abattu POSE une pièce d'or AU SOL, fois le palier du
##      tueur — visible, jamais créditée en silence ;
##   2. le multiplicateur suit les paliers : ×1, ×2 à 10, ×3 à 25 ;
##   3. un joueur abattu : cinq pièces fois le palier, PLUS la moitié de
##      la prime de la victime — et la victime retombe à ZÉRO ;
##   4. le reste de la prime du mort ÉCLATE en pièces au sol ;
##   5. une pièce approchée est ramassée et créditée ;
##   6. le joueur vivant le plus riche est ROI ; mort, il perd le trône ;
##   7. même à prime NULLE, un mort lâche ses poches et paie le duel —
##      le correctif du tout premier retour de test du mode.
##
## Aucune de ces situations ne lève d'erreur quand elle est fausse. Une
## prime qui ne changerait pas de mains à la mort donnerait un jeu
## parfaitement fonctionnel et parfaitement plat — et seul un test le dit.
##
## ─── IL JOUE LA VRAIE PARTIE ───────────────────────────────────────────
##
## Le banc monte `main.tscn` en solo et passe par les mêmes chemins que le
## jeu : `crediter_mob`, `server_take_damage`, la boucle du directeur.
## Simuler l'état en écrivant directement dans les champs prouverait que
## les champs se laissent écrire, pas que la règle marche.

var _echecs := 0
var _main: Node


func _ready() -> void:
	# L'arène bornée, comme le banc de l'étoile avant lui : c'est la carte
	# du joueur, pas celle qui arrange le banc.
	Cfg.arene_test = true
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.5).timeout
	_figer_les_bots()
	print("\n=== BANC DE LA PRIME ===\n")
	await _test1_credit_mob()
	await _test2_multiplicateur()
	await _test3_duel()
	await _test4_pluie_et_ramassage()
	await _test5_le_roi()
	await _test6_poches_du_mort()
	print("")
	print("=== %d échec(s) ===" % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


## LES BOTS SONT FIGÉS PENDANT LA MESURE — et RE-FIGÉS entre chaque
## test : un bot mort réapparaît avec un cerveau neuf, actif, et sa balle
## parasite fausserait les comptes (leçon du banc de l'étoile, apprise
## sur un conteneur lent).
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


## Remet le mode à plat entre deux tests : primes à zéro, pièces
## balayées, bots re-figés, joueurs remis en vie.
func _repartir() -> void:
	_figer_les_bots()
	for n in _joueurs():
		var j := n as Player
		j.prime = 0
		j.health.current_health = j.health.max_health
		j.health.is_dead = false
		j.set(&"_protection", 0.0)
		j.health.set(&"_invulnerable_until", 0.0)
	PrimeDirector.reset()
	PrimeDirector.demarrer()
	await get_tree().process_frame


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-46s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


func _titre(t: String) -> void:
	print("\n  ── %s ──" % t)


# --- LES TESTS -----------------------------------------------------------

func _test1_credit_mob() -> void:
	_titre("Test 1 : un mob pose une pièce au sol")
	await _repartir()
	var js := _joueurs()
	if js.is_empty():
		_ligne(false, "au moins un joueur en scène", "0")
		return
	var a: Player = js[0]
	# Le directeur est suspendu le temps d'INSPECTER la pièce posée :
	# actif, il la ferait ramasser avant la mesure.
	PrimeDirector._actif = false
	PrimeDirector.crediter_mob(a, a.global_position)
	await get_tree().process_frame
	var posees := PrimeDirector._pieces.size()
	_ligne(posees == 1, "une pièce est posée au sol",
			"%d pièce(s)" % posees)
	var valeur := 0
	for id in PrimeDirector._pieces:
		valeur += PrimeDirector._pieces[id]["valeur"]
	_ligne(valeur == 1, "elle vaut une pièce", "valeur = %d" % valeur)
	# Puis le directeur reprend : la pièce est à portée du tueur, elle
	# doit lui revenir — c'est le chemin complet mob → sol → prime.
	PrimeDirector._actif = true
	await get_tree().create_timer(0.5).timeout
	_ligne(a.prime == 1, "ramassée, elle crédite la prime",
			"prime = %d" % a.prime)


func _test2_multiplicateur() -> void:
	_titre("Test 2 : les paliers multiplient")
	await _repartir()
	var a: Player = _joueurs()[0]
	_ligne(PrimeDirector.multiplicateur(0) == 1, "×1 sous 10", "")
	_ligne(PrimeDirector.multiplicateur(10) == 2, "×2 à 10", "")
	_ligne(PrimeDirector.multiplicateur(25) == 3, "×3 à 25", "")
	a.crediter_prime(10)
	await get_tree().process_frame
	PrimeDirector._actif = false
	PrimeDirector.crediter_mob(a, a.global_position)
	await get_tree().process_frame
	var valeur := 0
	for id in PrimeDirector._pieces:
		valeur += PrimeDirector._pieces[id]["valeur"]
	_ligne(valeur == 2, "un mob au palier ×2 lâche 2 pièces d'or",
			"valeur au sol = %d, attendu 2" % valeur)
	PrimeDirector._actif = true


func _test3_duel() -> void:
	_titre("Test 3 : un duel transfère la moitié")
	await _repartir()
	var js := _joueurs()
	if js.size() < 2:
		_ligne(false, "au moins deux joueurs en scène", "%d" % js.size())
		return
	var a: Player = js[0]
	var b: Player = js[1]
	b.crediter_prime(20)
	await get_tree().process_frame
	# A tue B par les vrais chemins : 9999 points signés de son arme.
	a.prime = 0
	b.server_take_damage(9999.0, b.global_position, a.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	await get_tree().process_frame
	_ligne(b.health.is_dead, "la victime est morte",
			"vie = %.0f" % b.health.current_health)
	# Le tueur touche 5 × son palier (×1) + la moitié de 20 = 15.
	_ligne(a.prime == 15, "le tueur touche 5 + la moitié (10)",
			"prime = %d, attendu 15" % a.prime)
	_ligne(b.prime == 0, "la victime retombe à zéro",
			"prime = %d" % b.prime)


func _test4_pluie_et_ramassage() -> void:
	_titre("Test 4 : le reste éclate au sol et se ramasse")
	await _repartir()
	var js := _joueurs()
	var a: Player = js[0]
	var b: Player = js[1]
	b.crediter_prime(20)
	await get_tree().process_frame
	var avant: int = PrimeDirector._pieces.size()
	b.server_take_damage(9999.0, b.global_position, a.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	await get_tree().process_frame
	var posees: int = PrimeDirector._pieces.size() - avant
	_ligne(posees > 0, "des pièces sont posées au sol",
			"%d pièce(s)" % posees)
	# La somme au sol vaut le reste : 20 − 10 (moitié au tueur) = 10.
	var somme := 0
	for id in PrimeDirector._pieces:
		somme += PrimeDirector._pieces[id]["valeur"]
	_ligne(somme == 10, "la somme au sol vaut le reste (10)",
			"somme = %d" % somme)
	# Le tueur marche sur une pièce : elle est créditée et disparaît.
	var id0: int = PrimeDirector._pieces.keys()[0]
	var piece: Dictionary = PrimeDirector._pieces[id0]
	var valeur: int = piece["valeur"]
	var prime_avant: int = a.prime
	a.global_position = (piece["noeud"] as Node3D).global_position
	# Le ramassage tourne à cadence de contrôle : on lui laisse le temps.
	await get_tree().create_timer(0.5).timeout
	_ligne(not PrimeDirector._pieces.has(id0), "la pièce est ramassée",
			"restantes = %d" % PrimeDirector._pieces.size())
	# Les pièces éclatent en cercle serré : marcher sur l'une en ramasse
	# souvent plusieurs. On vérifie donc que le crédit couvre AU MOINS la
	# pièce visée et EXACTEMENT ce qui a disparu du sol.
	var restant := 0
	for id in PrimeDirector._pieces:
		restant += PrimeDirector._pieces[id]["valeur"]
	_ligne(a.prime == prime_avant + (10 - restant),
			"le crédit égale ce qui a quitté le sol",
			"prime = %d, ramassé = %d" % [a.prime, 10 - restant])
	_ligne(a.prime >= prime_avant + valeur,
			"la pièce visée est bien créditée",
			"prime = %d" % a.prime)


func _test5_le_roi() -> void:
	_titre("Test 5 : le trône suit la plus haute prime vivante")
	await _repartir()
	var js := _joueurs()
	var a: Player = js[0]
	var b: Player = js[1]
	a.crediter_prime(8)
	b.crediter_prime(12)
	await get_tree().create_timer(0.5).timeout
	_ligne(PrimeDirector.roi_id == b.peer_id, "le plus riche est roi",
			"roi = %d, attendu %d" % [PrimeDirector.roi_id, b.peer_id])
	# Le roi meurt : la couronne bascule sur le survivant le plus riche.
	b.set(&"_protection", 0.0)
	b.health.set(&"_invulnerable_until", 0.0)
	b.server_take_damage(9999.0, b.global_position, a.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().create_timer(0.5).timeout
	_ligne(PrimeDirector.roi_id != b.peer_id, "le roi mort perd le trône",
			"roi = %d" % PrimeDirector.roi_id)


func _test6_poches_du_mort() -> void:
	_titre("Test 6 : même à prime nulle, un mort paie")
	await _repartir()
	var js := _joueurs()
	var a: Player = js[0]
	var b: Player = js[1]
	# B n'a RIEN — le cas de tous les bots en début de partie, celui du
	# tout premier retour de test : « je ne vois aucune pièce tombée à
	# terre quand je tue un ennemi ».
	PrimeDirector._actif = false
	b.server_take_damage(9999.0, b.global_position, a.peer_id,
			Cfg.Team.PLAYER)
	await get_tree().process_frame
	await get_tree().process_frame
	_ligne(a.prime == 5, "le duel paie ses 5 pièces au tueur",
			"prime = %d, attendu 5" % a.prime)
	var somme := 0
	for id in PrimeDirector._pieces:
		somme += PrimeDirector._pieces[id]["valeur"]
	_ligne(somme == PrimeDirector.POCHES_DU_MORT,
			"le mort lâche ses poches (%d)" % PrimeDirector.POCHES_DU_MORT,
			"somme au sol = %d" % somme)
	PrimeDirector._actif = true
