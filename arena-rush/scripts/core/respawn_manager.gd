extends Node
## GESTIONNAIRE DE RÉAPPARITION — mort, attente, retour dans l'action.
##
## Autoload : Respawn
##
## POURQUOI UN NŒUD À PART. La mort touche quatre systèmes qui n'ont aucune
## raison de se connaître : le joueur (son état), le monde (où le remettre),
## la progression (qui a tué qui) et l'interface (ce qu'on affiche). Cousue
## dans `player.gd`, cette logique aurait rendu le personnage responsable de
## sa propre résurrection et du choix de sa position dans l'arène.
##
## AUTORITÉ SERVEUR. Seul le serveur décide qu'un joueur revient et où. Le
## client reçoit l'ordre et l'applique. Laisser le client choisir sa
## position de réapparition serait la porte ouverte à la téléportation.
##
## RÈGLE DE PERTE, ET POURQUOI ELLE EST ISOLÉE. Le joueur garde sa
## progression permanente et perd les armes ramassées. C'est un choix
## d'équilibrage qui changera — d'où une fonction dédiée plutôt qu'un `if`
## noyé dans la séquence de retour.

signal joueur_elimine(victime_id: int, tueur_id: int, tueur_nom: String)
signal compte_a_rebours(restant: float)
signal joueur_revenu(peer_id: int)

var monde: Node = null

## Réapparitions en attente : peer_id -> secondes restantes.
var _attentes: Dictionary = {}


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _attentes.is_empty():
		return
	# On itère sur une COPIE des clés : `faire_reapparaitre` retire de la
	# table, et modifier un dictionnaire pendant qu'on le parcourt est le
	# genre de bogue qui ne se manifeste qu'un jour sur dix.
	for id: int in _attentes.keys():
		var restant: float = float(_attentes[id]) - delta
		if restant > 0.0:
			_attentes[id] = restant
			continue
		_attentes.erase(id)
		if Net.is_server():
			faire_reapparaitre(id)


## SERVEUR — un joueur vient de mourir. Point d'entrée unique.
func signaler_mort(victime_id: int, tueur_id: int) -> void:
	if not Net.is_server():
		return
	if not MatchDirector.est_persistant():
		return
	if _attentes.has(victime_id):
		return
	_attentes[victime_id] = ConfigProgression.DELAI_RESPAWN
	var nom := MatchDirector.player_name(tueur_id) if tueur_id != 0 else "L'ARÈNE"
	Net.broadcast(self, &"_annoncer_mort", [victime_id, tueur_id, nom])


@rpc("authority", "call_local", "reliable")
func _annoncer_mort(victime_id: int, tueur_id: int, tueur_nom: String) -> void:
	joueur_elimine.emit(victime_id, tueur_id, tueur_nom)


## SERVEUR — remet le joueur en jeu, à une position qu'il choisit lui-même.
func faire_reapparaitre(peer_id: int) -> void:
	if not Net.is_server():
		return
	var joueur := MatchDirector.players.get(peer_id) as Node3D
	if joueur == null or not is_instance_valid(joueur):
		return
	var position := choisir_position(joueur)
	Net.broadcast(self, &"net_reapparaitre", [peer_id, position])
	MatchDirector.reintegrer(peer_id)


## OÙ REVIENT-ON ? La question n'est pas décorative : réapparaître sous le
## nez de son tueur transforme une mort en série de morts, et c'est la
## première raison pour laquelle on quitte un jeu de ce genre.
##
## On prend donc le point d'apparition le PLUS LOIN de tout joueur vivant.
## Simple, sans recherche de chemin, et suffisant sur une arène compacte —
## la finesse viendra quand la carte sera plus grande.
func choisir_position(mort: Node3D) -> Vector3:
	var arene := MatchDirector.arena as Arena
	if arene == null or arene.player_spawn_points.is_empty():
		return Vector3(0, 0.2, 0)

	var vivants: Array[Node3D] = []
	for n in mort.get_tree().get_nodes_in_group(&"players"):
		var p := n as Node3D
		if p == null or p == mort:
			continue
		if p.get(&"is_eliminated") == true:
			continue
		vivants.append(p)

	var meilleur := arene.player_spawn_points[0]
	var meilleure_distance := -INF
	for point: Vector3 in arene.player_spawn_points:
		var plus_proche := INF
		for v in vivants:
			plus_proche = minf(plus_proche,
					PlanMonde.distance3(point, v.global_position))
		# Sans personne en vue, tous les points se valent : on garde le
		# premier plutôt que de tirer au sort, pour que le comportement
		# reste reproductible en test.
		if plus_proche == INF:
			return point
		if plus_proche > meilleure_distance:
			meilleure_distance = plus_proche
			meilleur = point
	return meilleur


@rpc("authority", "call_local", "reliable")
func net_reapparaitre(peer_id: int, position: Vector3) -> void:
	var joueur := MatchDirector.players.get(peer_id) as Node
	if joueur == null or not is_instance_valid(joueur):
		return
	if joueur.has_method(&"revivre"):
		joueur.call(&"revivre", position)
	joueur_revenu.emit(peer_id)


## CE QUE L'ON PERD EN MOURANT — une seule fonction, pour que la règle se
## change en un endroit.
##
## Aujourd'hui : les armes ramassées dans l'arène sont perdues, l'arme de
## départ est rendue. On garde tout le reste, la progression en premier
## lieu. Demain on pourra vouloir garder une arme, en lâcher une au sol
## pour son tueur, ou ne rien perdre du tout — ce sera trois lignes ici et
## rien ailleurs.
func appliquer_perte_equipement(joueur: Node) -> void:
	if not Net.is_server():
		return
	if joueur.has_method(&"reinitialiser_equipement"):
		joueur.call(&"reinitialiser_equipement")


## Temps restant avant le retour d'un joueur, 0 s'il n'attend pas.
func attente_restante(peer_id: int) -> float:
	return float(_attentes.get(peer_id, 0.0))


func reset() -> void:
	_attentes.clear()
