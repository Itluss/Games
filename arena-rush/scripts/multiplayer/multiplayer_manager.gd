extends Node
## RÉSEAU — hébergement, connexion, et mode solo hors-ligne.
##
## PARTAGE D'AUTORITÉ (c'est la décision structurante du prototype) :
##
##   • Le CLIENT est maître de SON déplacement. Un joystick qui attend un
##     aller-retour réseau donne un jeu mou ; sur mobile c'est rédhibitoire.
##     Chaque joueur simule donc son propre corps et diffuse sa position.
##
##   • Le SERVEUR est maître de TOUT le reste : dégâts, santé, mort, loot,
##     apparition des mobs, zone, victoire. Un client ne peut qu'ENVOYER
##     une intention de tir ; il ne décide jamais qu'un autre a été touché.
##     Les méthodes qui infligent des dégâts n'existent que côté serveur.
##
## Le mode SOLO passe par le même chemin de code : on crée simplement un
## pair hors-ligne où le joueur local EST le serveur. Aucun `if solo` ne
## pollue donc le reste du jeu, et tester à un seul exemplaire teste bien
## le vrai code réseau.
##
## Autoload : Net

signal peer_list_changed()
signal connection_failed()
signal server_disconnected()

const PORT := 8910
## DIX PARTICIPANTS AU LIEU DE QUATRE.
##
## Sur l'ancienne arène de 34 m, trois bots suffisaient à ce qu'on croise
## quelqu'un en permanence. Le monde fait maintenant cinq fois la surface :
## à effectif constant, on pourrait le traverser sans voir âme qui vive, et
## un monde vide n'est pas un monde ouvert, c'est un désert.
##
## Neuf bots pour cinq secteurs et six points d'intérêt : de quoi qu'il se
## passe toujours quelque chose quelque part, sans que la carte devienne
## une mêlée permanente.
const MAX_PLAYERS := 10

## PLAFOND RELEVÉ D'UN CRAN EN ARÈNE DE COMBAT, et d'un seul.
##
## Le banc demande onze corps : dix bots et le joueur local. Avec le
## plafond du jeu, `clampi(bots, 0, MAX_PLAYERS - 1)` ramenait
## silencieusement la commande de dix bots à neuf — on aurait cru tester
## la densité demandée en en testant une autre. Le plafond du JEU, lui, ne
## bouge pas : ce serait changer la taille des parties au prétexte d'un
## test.
const MAX_PLAYERS_ARENE := 11

static func plafond() -> int:
	return MAX_PLAYERS_ARENE if Cfg.arene_test else MAX_PLAYERS

enum Mode { NONE, SOLO, HOST, CLIENT }
var mode: Mode = Mode.NONE

## Nombre d'adversaires pilotés par l'IA à ajouter en solo, pour que le
## prototype soit jouable et testable sans deuxième appareil.
var bot_count: int = 9

## id de pair -> { "name": String, "bot": bool }
var peers: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func():
		mode = Mode.NONE
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		mode = Mode.NONE
		server_disconnected.emit())

# --- INTERROGATION -------------------------------------------------------

## Vrai si CE pair a le droit de trancher (dégâts, mort, spawn, victoire).
## En solo, le joueur local est le serveur : la réponse est vraie.
func is_server() -> bool:
	return mode == Mode.SOLO or multiplayer.is_server()

func local_id() -> int:
	if mode == Mode.SOLO:
		return 1
	return multiplayer.get_unique_id()

func is_networked() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT

## Identifiants humains uniquement (les bots ne sont pas des pairs réseau).
func human_ids() -> Array:
	var out: Array = []
	for id in peers:
		if not peers[id].get("bot", false):
			out.append(id)
	return out

func all_ids() -> Array:
	return peers.keys()

# --- DÉMARRAGE -----------------------------------------------------------

## Partie solo : pair hors-ligne, joueur local serveur, adversaires IA.
func start_solo(bots: int = 9) -> void:
	_reset_peer()
	mode = Mode.SOLO
	bot_count = clampi(bots, 0, plafond() - 1)
	peers = {1: {"name": "Vous", "bot": false}}
	# Les bots reçoivent des identifiants négatifs : impossible de les
	# confondre avec un vrai pair réseau, qui est toujours positif.
	for i in range(bot_count):
		var id := -(i + 1)
		peers[id] = {"name": "Bot %d" % (i + 1), "bot": true}
	peer_list_changed.emit()

## Hébergement d'une partie réseau.
func host() -> bool:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Impossible d'ouvrir le serveur sur le port %d (code %d)"
				% [PORT, err])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	peers = {1: {"name": "Hôte", "bot": false}}
	peer_list_changed.emit()
	return true

## Connexion à une partie existante.
func join(address: String = "127.0.0.1") -> bool:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Connexion impossible à %s:%d (code %d)" % [address, PORT, err])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return true

func leave() -> void:
	_reset_peer()
	mode = Mode.NONE
	peers.clear()
	peer_list_changed.emit()

func _reset_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

# --- ÉVÈNEMENTS DE PAIRS -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_server():
		return
	peers[id] = {"name": "Joueur %d" % id, "bot": false}
	# On informe le nouvel arrivant de la liste complète : il ne peut pas
	# la deviner, et le serveur est la seule source de vérité.
	_sync_peers.rpc(peers)
	peer_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	if is_server():
		_sync_peers.rpc(peers)
	peer_list_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_peers(list: Dictionary) -> void:
	peers = list
	peer_list_changed.emit()

# --- APPELS UNIFIÉS ------------------------------------------------------
#
# En solo il n'existe aucun pair réseau : un `rpc()` y serait ignoré en
# silence, et le jeu paraîtrait cassé sans la moindre erreur. Ces deux
# aides font que le MÊME code fonctionne en solo comme en ligne, ce qui
# évite de semer des `if solo` dans tout le projet.

## Exécute `method` sur tous les pairs, y compris soi-même.
func broadcast(node: Node, method: StringName, args: Array = []) -> void:
	if is_networked():
		node.callv(&"rpc", [method] + args)
	else:
		node.callv(method, args)

## Envoie une INTENTION au serveur. Sur le serveur (ou en solo), exécution
## directe. C'est le seul chemin par lequel un client demande une action
## à conséquence — il ne l'applique jamais lui-même.
func to_server(node: Node, method: StringName, args: Array = []) -> void:
	if is_networked() and not multiplayer.is_server():
		node.callv(&"rpc_id", [1, method] + args)
	else:
		node.callv(method, args)

# --- OUTIL DE TEST LOCAL -------------------------------------------------

## Ouvre une seconde instance du jeu sur cette machine pour tester une
## vraie partie réseau sans deuxième appareil.
##
## En éditeur, préférer Débogage → « Exécuter plusieurs instances » : c'est
## le chemin natif. Cette fonction sert aux builds exportés.
func spawn_test_instance() -> void:
	if OS.has_feature("editor"):
		push_warning("En éditeur, utiliser Débogage → Exécuter plusieurs instances.")
		return
	OS.create_instance(["--join"])
