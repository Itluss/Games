extends Node
## LA PRIME — la mécanique centrale du jeu, et la réponse à un constat
## brutal du test : « le joueur n'a aucun intérêt à rester en vie, il
## s'en fiche de mourir ».
##
## LA RÈGLE, EN TROIS PHRASES. Tout ce qu'un joueur accomplit sans mourir
## fait monter sa PRIME — un mob, un duel, le trône. Plus la prime est
## haute, plus elle rapporte (multiplicateur) et plus elle attire les
## convoitises : à la mort, la moitié va au tueur, le reste éclate en
## pièces d'or que n'importe qui ramasse. Le joueur vivant le plus riche
## porte LA COURONNE : visible de tous, marqué sur la carte, payé au
## goutte-à-goutte — l'objectif du jeu n'est pas un objet, c'est un
## joueur.
##
## POURQUOI LA PRIME NE DONNE AUCUNE PUISSANCE. Pas un point de dégâts,
## pas un point de vie : le riche est plus VISIBLE et plus RENTABLE à
## abattre, jamais plus fort. C'est l'équilibre qui empêche la spirale
## « le gros écrase les petits, les petits partent » — la puissance
## vient des armes ramassées, la prime ne mesure que l'audace.
##
## CE DIRECTEUR remplace l'ancien mode de l'étoile, jugé « trop
## abstrait » : un objet à ramasser ne racontait rien, un roi à détrôner
## raconte tout.
##
## LES VISUELS JOUENT PARTOUT, LES CRÉDITS SONT AU SERVEUR — la règle de
## tout le jeu. Le serveur calcule, rediffuse ; chaque pair voit les
## mêmes pièces aux mêmes endroits et la même couronne sur la même tête.
##
## Autoload : PrimeDirector

signal roi_change(ancien_id: int, nouveau_id: int)

## Prime minimale pour prétendre à la couronne : un roi à 2 pièces
## ridiculiserait le trône.
const ROI_MINI := 5
## Paliers du multiplicateur — et des tenues visuelles qui vont avec.
## Lisibles de loin : aura dorée au premier, flamme au second.
const PALIER_AURA := 10
const PALIER_FLAMME := 25
## Goutte-à-goutte du roi : une pièce toutes les deux secondes. C'est la
## récompense d'ÊTRE au sommet — et la raison pour les autres d'en finir.
const ROI_GOUTTE_PERIODE := 2.0
## Nombre maximal de pièces d'une pluie : au-delà, chaque pièce vaut
## plus cher au lieu d'encombrer le sol.
const PLUIE_MAX := 10
## Rayon de ramassage d'une pièce, en mètres.
const RAMASSAGE := 1.35
## Les pièces orphelines s'effacent au bout d'une minute : un champ de
## bataille qui scintille de vieilles pièces perd sa lisibilité.
const PIECE_DUREE := 60.0

## Identifiant du roi en titre, 0 = trône vacant.
var roi_id: int = 0
var _actif := false
var _goutte := 0.0
var _controle := 0.0
## Pièces au sol : id -> {noeud, valeur, age}.
var _pieces: Dictionary = {}
var _prochaine_piece_id: int = 1

## Maillage partagé des pièces — une seule ressource pour toutes.
var _maille_piece: CylinderMesh = null
var _matiere_piece: StandardMaterial3D = null


func demarrer() -> void:
	_actif = true
	roi_id = 0


func reset() -> void:
	_actif = false
	roi_id = 0
	for id in _pieces:
		var p: Dictionary = _pieces[id]
		if is_instance_valid(p["noeud"]):
			(p["noeud"] as Node).queue_free()
	_pieces.clear()


func est_actif() -> bool:
	return _actif


## Le multiplicateur d'un joueur, dérivé de sa prime. C'est LE moteur du
## système : rester en vie fait boule de neige.
static func multiplicateur(prime: int) -> int:
	if prime >= PALIER_FLAMME:
		return 3
	if prime >= PALIER_AURA:
		return 2
	return 1


func roi() -> Player:
	if roi_id == 0:
		return null
	var j := MatchDirector.players.get(roi_id) as Player
	return j if j != null and is_instance_valid(j) else null


func nom_roi() -> String:
	var j := roi()
	return j.display_name if j != null else ""


# --- CRÉDITS — SERVEUR UNIQUEMENT ----------------------------------------

## Un mob abattu : la route sûre et lente. Une pièce, fois le palier.
func crediter_mob(tueur: Player) -> void:
	if not Net.is_server() or tueur == null or not is_instance_valid(tueur):
		return
	tueur.crediter_prime(1 * multiplicateur(tueur.prime))


## Un joueur abattu : la route rapide — cinq pièces fois le palier, PLUS
## la moitié de la prime de la victime. C'est cette moitié qui fait des
## grosses primes des aimants à ennuis.
func crediter_duel(tueur: Player, victime: Player) -> int:
	if not Net.is_server() or tueur == null or not is_instance_valid(tueur):
		return 0
	var moitie: int = victime.prime / 2
	tueur.crediter_prime(5 * multiplicateur(tueur.prime) + moitie)
	return moitie


## À LA MORT : la moitié part au tueur (voir crediter_duel), le RESTE
## éclate en pièces au sol. Appelé par le mourant, côté serveur.
func pluie_de_pieces(centre: Vector3, montant: int) -> void:
	if not Net.is_server() or montant <= 0:
		return
	var n: int = clampi(montant, 1, PLUIE_MAX)
	var valeurs: Array = []
	var restant := montant
	for i in n:
		var v: int = restant / (n - i)
		valeurs.append(v)
		restant -= v
	var positions: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + randf() * 0.7
		var r := randf_range(0.7, 2.1)
		positions.append(Vector3(centre.x + cos(a) * r, 0.0,
				centre.z + sin(a) * r))
	var ids: Array = []
	for i in n:
		ids.append(_prochaine_piece_id)
		_prochaine_piece_id += 1
	Net.broadcast(self, &"net_pieces_poser", [ids, positions, valeurs])


# --- BOUCLE ---------------------------------------------------------------

func _process(delta: float) -> void:
	_animer_pieces(delta)
	if not _actif or not Net.is_server():
		return
	# Le goutte-à-goutte du roi.
	var r := roi()
	if r != null and not r.is_eliminated and not r.health.is_dead:
		_goutte += delta
		if _goutte >= ROI_GOUTTE_PERIODE:
			_goutte = 0.0
			r.crediter_prime(1)
	# Désignation du roi et ramassage, à cadence modérée : ni l'un ni
	# l'autre n'a besoin de la précision d'une image.
	_controle += delta
	if _controle < 0.2:
		return
	_controle = 0.0
	_designer_le_roi()
	_ramasser()


## LE TRÔNE SE PREND, NE SE GARDE PAS. À chaque contrôle, le joueur
## VIVANT à la plus haute prime (au moins ROI_MINI) est roi. Mort ou
## dépassé, la couronne change de tête à l'instant — c'est le drame
## permanent du mode.
func _designer_le_roi() -> void:
	var meilleur: Player = null
	for j in MatchDirector.players.values():
		var p := j as Player
		if p == null or not is_instance_valid(p):
			continue
		if p.is_eliminated or p.health == null or p.health.is_dead:
			continue
		if p.prime < ROI_MINI:
			continue
		if meilleur == null or p.prime > meilleur.prime:
			meilleur = p
	var nouveau: int = meilleur.peer_id if meilleur != null else 0
	if nouveau != roi_id:
		Net.broadcast(self, &"net_roi", [roi_id, nouveau])


func _ramasser() -> void:
	if _pieces.is_empty():
		return
	var pris: Array = []
	for id in _pieces:
		var piece: Dictionary = _pieces[id]
		for j in MatchDirector.players.values():
			var p := j as Player
			if p == null or not is_instance_valid(p) or p.is_eliminated \
					or p.health == null or p.health.is_dead:
				continue
			var noeud := piece["noeud"] as Node3D
			if not is_instance_valid(noeud):
				continue
			if PlanMonde.distance3(p.global_position,
					noeud.global_position) <= RAMASSAGE:
				pris.append([id, p.peer_id])
				break
	for paire in pris:
		Net.broadcast(self, &"net_piece_prise", [paire[0], paire[1]])


# --- RÉPLICATION ----------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func net_roi(ancien: int, nouveau: int) -> void:
	roi_id = nouveau
	# La couronne change de tête chez TOUS les pairs.
	for j in MatchDirector.players.values():
		var p := j as Player
		if p != null and is_instance_valid(p):
			p.montrer_couronne(p.peer_id == nouveau)
	roi_change.emit(ancien, nouveau)


@rpc("authority", "call_local", "reliable")
func net_pieces_poser(ids: Array, positions: Array, valeurs: Array) -> void:
	for i in ids.size():
		var noeud := _fabriquer_piece(valeurs[i])
		var pos := positions[i] as Vector3
		noeud.position = Vector3(pos.x, 0.35, pos.z)
		var racine := get_tree().current_scene
		if racine == null:
			racine = get_parent()
		racine.add_child(noeud)
		_pieces[ids[i]] = {"noeud": noeud, "valeur": valeurs[i], "age": 0.0}


@rpc("authority", "call_local", "reliable")
func net_piece_prise(id: int, peer_id: int) -> void:
	var piece: Dictionary = _pieces.get(id, {})
	if piece.is_empty():
		return
	_pieces.erase(id)
	var noeud := piece["noeud"] as Node3D
	var valeur: int = piece["valeur"]
	var ramasseur := MatchDirector.players.get(peer_id) as Player
	if is_instance_valid(noeud):
		# La pièce SAUTE vers son ramasseur — le sol la donne, la main la
		# prend. C'est ce petit vol qui rend le ramassage délicieux.
		if ramasseur != null and is_instance_valid(ramasseur):
			var tw := noeud.create_tween()
			tw.tween_property(noeud, "global_position",
					ramasseur.global_position + Vector3.UP * 1.2, 0.16) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(noeud, "scale",
					Vector3.ONE * 0.2, 0.16)
			tw.tween_callback(noeud.queue_free)
		else:
			noeud.queue_free()
	if ramasseur == null or not is_instance_valid(ramasseur):
		return
	# Le crédit de prime est SERVEUR ; le trésor permanent est LOCAL — il
	# n'appartient qu'à la machine du ramasseur.
	if Net.is_server():
		ramasseur.crediter_prime(valeur)
	if peer_id == Net.local_id():
		Profil.ajouter_or(valeur)


# --- PIÈCES : FABRICATION ET VIE ------------------------------------------

## Une pièce d'or : un disque doré dressé qui tourne sur lui-même, avec
## son halo. Une seule maille et une seule matière pour toutes.
func _fabriquer_piece(valeur: int) -> Node3D:
	if _maille_piece == null:
		_maille_piece = CylinderMesh.new()
		_maille_piece.top_radius = 0.24
		_maille_piece.bottom_radius = 0.24
		_maille_piece.height = 0.07
		_maille_piece.radial_segments = 14
		_matiere_piece = StandardMaterial3D.new()
		_matiere_piece.albedo_color = Color("f5c542")
		_matiere_piece.metallic = 0.4
		_matiere_piece.roughness = 0.35
		_matiere_piece.emission_enabled = true
		_matiere_piece.emission = Color("d99a1e")
		_matiere_piece.emission_energy_multiplier = 0.6
	var racine := Node3D.new()
	racine.name = "PieceOr"
	var mi := MeshInstance3D.new()
	mi.mesh = _maille_piece
	mi.material_override = _matiere_piece
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dressée comme une pièce de dessin animé, pas posée à plat.
	mi.rotation.x = PI / 2.0
	racine.add_child(mi)
	# Une grosse pièce se voit : la valeur gonfle légèrement le disque.
	racine.scale = Vector3.ONE * clampf(1.0 + float(valeur) * 0.04, 1.0, 1.6)
	return racine


## Les pièces tournent et flottent chez tout le monde — pur affichage,
## aucun état de jeu.
func _animer_pieces(delta: float) -> void:
	var mortes: Array = []
	for id in _pieces:
		var piece: Dictionary = _pieces[id]
		var noeud := piece["noeud"] as Node3D
		if not is_instance_valid(noeud):
			mortes.append(id)
			continue
		piece["age"] += delta
		noeud.rotation.y += delta * 2.6
		noeud.position.y = 0.35 + 0.08 * sin(piece["age"] * 3.0 + float(id))
		if piece["age"] > PIECE_DUREE:
			mortes.append(id)
			noeud.queue_free()
	for id in mortes:
		_pieces.erase(id)
