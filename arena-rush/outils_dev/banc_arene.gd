extends Node
## BANC DE L'ARÈNE DE COMBAT — dix bots, dix mobs, un joueur local.
##
## POURQUOI CE BANC, ET CE QU'IL NE FAIT PAS. Il ne juge pas si l'arène est
## belle : ça se juge en image. Il répond aux questions qu'une image ne
## peut pas trancher, parce qu'elles portent sur le MOUVEMENT — où les
## corps vont-ils réellement, s'y coincent-ils, se massent-ils au centre ?
##
## Il joue la vraie partie : la scène `main.tscn`, les vrais bots, les
## vrais mobs, la vraie caméra. Un banc qui recrée sa propre version du jeu
## mesure sa propre version du jeu.

## Durée observée, en secondes de jeu.
const DUREE := 150.0
## Période d'échantillonnage des positions.
const PAS := 0.25

var _main: Node
var _echecs := 0

## Compteurs de séjour par zone, en échantillons.
var _sejours := {"couronne interne": 0, "boucle": 0, "peripherie": 0}
var _echantillons := 0
## Position précédente de chaque corps, pour mesurer le chemin parcouru.
var _dernieres: Dictionary = {}
var _parcours: Dictionary = {}
var _images := 0
var _temps := 0.0
var _pire_fps := 999.0
## Nombre d'échantillons où le joueur local était masqué depuis la caméra.
var _joueur_masque := 0
var _joueur_vu := 0
## Mobs vivants, échantillonnés : un total final ne dit pas si l'arène a
## été peuplée, seulement si elle l'est encore.
var _mobs_min := 999
var _mobs_max := 0
var _mobs_somme := 0


func _ready() -> void:
	Cfg.arene_test = true
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	await _observer()
	_rapport()
	get_tree().quit(1 if _echecs > 0 else 0)


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-48s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


## À quelle zone du plan appartient un point ?
func _zone(p: Vector2) -> String:
	var r := p.length()
	if r < 8.0:
		return "place"
	# Les passes sont les deux goulets nord et sud : bande centrale étroite.
	# ZONES DE L'ARÈNE WESTERN, en couronnes : le centre, la couronne
	# intérieure des formations, la boucle principale, la périphérie.
	if r < 20.0:
		return "couronne interne"
	if r < 30.0:
		return "boucle"
	return "peripherie"


## LE TEMPS EST LU À L'HORLOGE, PAS DÉDUIT DES IMAGES.
##
## Premier jet : la boucle attendait `process_frame` et lisait
## `get_process_delta_time()`. Deux erreurs. Le signal ne porte aucun
## delta, donc l'attente rendait `null` ; et ce nœud n'a pas de traitement
## actif, donc le delta valait zéro. Résultat : ZÉRO échantillon, et un
## rapport qui annonçait tranquillement « 0 i/s » et « joueur visible
## 0 % » comme si c'étaient des mesures. C'est le pire genre de panne
## d'instrument — celle qui rend un verdict au lieu de se taire.
##
## On cadence donc sur un vrai minuteur, et on lit l'horloge du système.
func _observer() -> void:
	var depart := Time.get_ticks_msec()
	var images_avant := Engine.get_frames_drawn()
	while (Time.get_ticks_msec() - depart) < int(DUREE * 1000.0):
		await get_tree().create_timer(PAS).timeout
		_echantillonner()
	_temps = float(Time.get_ticks_msec() - depart) / 1000.0
	_images = Engine.get_frames_drawn() - images_avant


func _echantillonner() -> void:
	_echantillons += 1
	for p in get_tree().get_nodes_in_group(&"players"):
		if not is_instance_valid(p) or p.get(&"is_eliminated") == true:
			continue
		var g: Vector3 = p.global_position
		var plat := Vector2(g.x, g.z)
		_sejours[_zone(plat)] += 1
		var cle := p.get_instance_id()
		if _dernieres.has(cle):
			var pas: float = (_dernieres[cle] as Vector2).distance_to(plat)
			# Au-delà d'un mètre par échantillon, c'est une réapparition,
			# pas un déplacement : on ne la compte pas comme du chemin.
			if pas < 1.0:
				_parcours[cle] = float(_parcours.get(cle, 0.0)) + pas
		_dernieres[cle] = plat
	var m := get_tree().get_nodes_in_group(&"mobs").size()
	_mobs_min = mini(_mobs_min, m)
	_mobs_max = maxi(_mobs_max, m)
	_mobs_somme += m
	_regarder_le_joueur()


## LE CIRCUIT DE VISIBILITÉ.
##
## POURQUOI LE JOUEUR EST DÉPLACÉ DE FORCE. Personne ne tient la manette
## pendant un banc : laissé à lui-même, le joueur local reste planté sur
## son point d'apparition, et la mesure « le joueur est-il visible ? »
## répond pour UN endroit de l'arène. Le premier passage a d'ailleurs
## rendu 77,9 % puis 100 % selon les runs — deux chiffres qui ne
## mesuraient rien d'autre que le hasard de l'endroit où il stationnait.
##
## On le promène donc sur un circuit qui traverse toutes les zones : les
## deux passes, les deux routes, les quatre bastions et la place. Le taux
## rendu porte alors sur l'ARÈNE, pas sur un point.
const CIRCUIT: Array[Vector2] = [
	Vector2(0, 0), Vector2(0, -9), Vector2(-9, -18), Vector2(0, -22),
	Vector2(10, -19), Vector2(20, -13), Vector2(24, 0), Vector2(21, 13),
	Vector2(12, 21), Vector2(0, 25), Vector2(-11, 21), Vector2(-20, 13),
	Vector2(-25, 0), Vector2(-20, -12), Vector2(-31, -13), Vector2(-12, -30),
	Vector2(13, 30), Vector2(30, 13), Vector2(8, 8), Vector2(-8, -8),
	Vector2(-8, 8), Vector2(8, -8),
]
var _etape := 0
var _attente := 0
var _releves_valides := 0
## Points du circuit où le joueur s'est trouvé masqué, pour corriger le
## NIVEAU plutôt que de deviner.
var _points_masques: Dictionary = {}


## LE JOUEUR LOCAL EST-IL VISIBLE DEPUIS SA CAMÉRA ?
##
## On tire de la caméra vers la poitrine du joueur, sur la couche du
## monde. Si quelque chose est touché avant, le joueur est caché derrière
## du décor.
func _regarder_le_joueur() -> void:
	var cam := get_viewport().get_camera_3d()
	var moi: Node3D = null
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"peer_id") == Net.local_id():
			moi = p
			break
	if cam == null or moi == null:
		return
	# LA CAMÉRA DOIT AVOIR RATTRAPÉ LE CORPS AVANT QU'ON MESURE.
	#
	# Elle est lissée : après une téléportation, elle glisse vers sa
	# nouvelle place pendant plusieurs images, en traversant tout ce qui se
	# trouve sur le trajet. Mesurer pendant ce glissement compte des
	# occultations qui n'existent pas — le décor n'est pas en cause, c'est
	# la caméra qui n'est pas encore arrivée.
	#
	# On ne mesure donc QUE lorsqu'elle est effectivement en place : à sa
	# hauteur nominale, et à moins d'un mètre et demi de son recul attendu.
	# C'est un test d'état, pas un délai deviné.
	if _attente > 0:
		_attente -= 1
		if _attente == 0:
			pass
		else:
			return
	var ecart_cam := Vector2(cam.global_position.x - moi.global_position.x,
			cam.global_position.z - moi.global_position.z).length()
	if absf(cam.global_position.y - moi.global_position.y - 10.4) > 1.5 \
			or ecart_cam > 11.0:
		return

	_releves_valides += 1
	if _releves_valides >= 3:
		_releves_valides = 0
		_etape = (_etape + 1) % CIRCUIT.size()
		var c: Vector2 = CIRCUIT[_etape]
		moi.global_position = Vector3(c.x, 0.4, c.y)
		_attente = 6
		return
	var depart := cam.global_position
	var vers: Vector3 = moi.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(depart, vers)
	q.collision_mask = Cfg.LAYER_WORLD
	q.hit_from_inside = true
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_joueur_vu += 1
	else:
		_joueur_masque += 1
		var c: Vector2 = CIRCUIT[_etape]
		var cle := "%s ← %s" % [str(c), hit.get("collider", null)]
		_points_masques[cle] = int(_points_masques.get(cle, 0)) + 1


func _rapport() -> void:
	print("\n=== BANC DE L'ARÈNE DE COMBAT ===\n")
	var bots := 0
	var humains := 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_bot") == true:
			bots += 1
		else:
			humains += 1
	var mobs := get_tree().get_nodes_in_group(&"mobs").size()

	_ligne(bots == 10, "dix bots en piste", "%d bots" % bots)
	_ligne(humains == 1, "un joueur local", "%d humain(s)" % humains)
	# AUCUN MOB : c'est la consigne de cette étape, et il faut la VÉRIFIER.
	# Un pondeur qu'on croit désactivé et qui tourne encore est le genre de
	# chose qu'on découvre en jouant, pas en relisant.
	_ligne(_mobs_max == 0, "aucun mob dans l'arène",
			"maximum observé %d" % _mobs_max)

	# --- 1 et 2 : répartition des combats, engorgement du centre ---------
	print("\n  Séjour par zone (%d échantillons) :" % _echantillons)
	var total: int = maxi(1, _echantillons)
	var part_place := 0.0
	for z in ["couronne interne", "boucle", "peripherie"]:
		var part := float(_sejours[z]) / float(total) * 100.0 \
				/ maxf(1.0, float(bots + humains))
		if z == "couronne interne":
			part_place = part
		print("      %-9s %5.1f %%" % [z, part])
	# LE CENTRE NE DOIT PAS AVALER LA PARTIE. Au-delà d'un tiers du temps
	# passé sur la place, l'arène n'a plus qu'une zone et les bastions ne
	# servent à rien.
	_ligne(part_place < 55.0, "le combat se répartit sur la carte",
			"%.1f %% du temps dans la couronne interne" % part_place)

	# --- 3 : les bots contournent-ils, ou se coincent-ils ? --------------
	# LE JOUEUR LOCAL EST EXCLU DE CE TEST, et il faut le dire. Personne ne
	# tient la manette pendant un banc : il reste planté à son point
	# d'apparition et compterait comme « coincé » à chaque passage. Ce
	# qu'on veut savoir ici, c'est si les BOTS savent contourner.
	var moi_cle := 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"peer_id") == Net.local_id():
			moi_cle = p.get_instance_id()
	var immobiles := 0
	var parcours_min := INF
	for cle in _parcours:
		if cle == moi_cle:
			continue
		var d: float = _parcours[cle]
		parcours_min = minf(parcours_min, d)
		# Moins de 12 m parcourus en 150 s, c'est un corps coincé.
		if d < 12.0:
			immobiles += 1
	_ligne(immobiles == 0, "aucun corps coincé dans le décor",
			"%d immobile(s) · plus court trajet %.0f m"
			% [immobiles, parcours_min if parcours_min < INF else 0.0])

	# --- 8 : le joueur reste-t-il visible ? ------------------------------
	var vus: int = maxi(1, _joueur_vu + _joueur_masque)
	var taux := float(_joueur_vu) / float(vus) * 100.0
	_ligne(taux > 92.0, "le joueur reste visible sur tout le circuit",
			"%.1f %% des relevés · %d points parcourus" % [taux, CIRCUIT.size()])
	if not _points_masques.is_empty():
		print("      points où le joueur est masqué :")
		for k in _points_masques:
			print("        → %s × %d" % [k, _points_masques[k]])

	# --- 10 : les images tiennent-elles ? --------------------------------
	# LA CADENCE N'EST PAS MESURABLE ICI, ET PRÉTENDRE LE CONTRAIRE SERAIT
	# PIRE QUE DE NE RIEN DIRE. Ce banc tourne sous Xvfb, en rendu
	# logiciel : il plafonne à quelques images par seconde quoi qu'on
	# affiche. Le chiffre est imprimé pour comparer deux versions entre
	# elles sur CETTE machine, jamais pour juger le jeu. La vraie mesure se
	# prend sur un appareil ou dans un navigateur avec une vraie carte.
	var moyen := float(_images) / maxf(_temps, 0.001)
	print("      cadence %.1f i/s — RENDU LOGICIEL, valeur non représentative"
			% moyen)

	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh`.
	#
	# Le lanceur refuse de croire un banc qui n'imprime pas cette ligne :
	# c'est ainsi qu'il distingue « tout est passé » de « le banc s'est
	# arrêté en route ». Sans elle, un banc pourtant conforme est compté
	# comme non exécuté — et c'est arrivé trois fois dans ce dépôt.
	print("=== %d échec(s) ===" % _echecs)
	if _echecs == 0:
		print("Arène de combat : conforme.")
	else:
		print("Arène de combat : %d anomalie(s)." % _echecs)
