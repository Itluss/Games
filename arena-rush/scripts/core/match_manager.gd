extends Node
## DÉROULEMENT DE LA PARTIE — phases, pression, éliminations, victoire.
##
## AUTORITÉ SERVEUR intégrale : seul le serveur fait avancer les phases,
## décide qui est éliminé et déclare le vainqueur. Les clients reçoivent
## des annonces et se contentent de les afficher.
##
## LA COURBE DE TENSION est le cœur du prototype. Le jeu ne doit jamais
## laisser le joueur marcher dans le vide : la pression (0 → 1) monte en
## continu et pilote À LA FOIS le nombre de mobs, leur agressivité, la
## qualité du butin et la fermeture de la zone. Un seul curseur, donc un
## rythme cohérent plutôt que quatre réglages qui se contredisent.
##
## Autoload : MatchDirector

signal phase_changed(phase: int)
signal countdown_tick(value: int)          # 3, 2, 1, puis 0 pour « GO »
signal alive_count_changed(count: int)
signal player_eliminated(peer_id: int, name: String)
signal match_ended(winner_id: int, winner_name: String)
signal zone_updated(radius: float, next_radius: float, closing: bool)
signal announce(text: String, color: Color)

enum Phase { LOBBY, COUNTDOWN, WARMUP, ESCALATION, CLOSING, ENDED }
var phase: Phase = Phase.LOBBY

## MODES DE JEU.
##
## POURQUOI UN MODE PLUTÔT QU'UNE SUPPRESSION. Le Battle Royale marche, il
## est réglé, et il pourrait revenir comme événement ou comme playlist. Le
## découper au scalpel pour le réécrire dans six mois serait du gâchis. Il
## reste donc entier, simplement inactif : c'est UNE SEULE valeur qui
## décide, et tout ce qui en dépend interroge `est_persistant()` plutôt que
## de tester des phases une à une.
##
##   ARENE      — monde continu. Pas de zone, pas de vainqueur, pas de fin.
##                On y entre, on y reste, on en sort quand on veut.
##   ROYALE     — le mode d'origine : zone qui se referme, dernier survivant.
enum Mode { ARENE, ROYALE }
var mode: Mode = Mode.ARENE

## Vrai si la partie n'a pas de condition de fin. Toute logique de fin de
## partie DOIT passer par ici : c'est ce qui garantit qu'aucun chemin oublié
## ne viendra terminer une session censée durer des heures.
func est_persistant() -> bool:
	return mode == Mode.ARENE

## Durée visée d'une partie. Le prototype cible des sessions courtes :
## quelques minutes, tension immédiate, pas de temps mort.
## Le test automatisé montre qu'une partie se joue en ~110 s. Caler la
## durée de référence dessus fait que la pression atteint réellement son
## maximum avant la fin — avec 210 s, elle plafonnait à 0,5 et les mobs les
## plus intéressants n'apparaissaient jamais.
const MATCH_DURATION := 175.0
## La zone ne commence à se fermer qu'après ce délai, pour laisser le temps
## de looter une première arme.
const ZONE_START := 55.0
## Plateau de pression du mode arène. Assez haut pour que les mobs
## intéressants apparaissent, assez bas pour laisser de la marge à un futur
## réglage d'événements.
const PALIER_PRESSION := 0.75

var elapsed: float = 0.0
var pressure: float = 0.0

var arena: Node3D = null
var players: Dictionary = {}        # peer_id -> Node (joueur vivant ou mort)
var alive_ids: Array[int] = []

var zone_radius: float = Cfg.ARENA_RADIUS
var zone_target: float = Cfg.ARENA_RADIUS

var _countdown: float = 0.0
var _zone_tick: float = 0.0
## Nombre de participants au coup d'envoi — sert à ne pas déclarer une
## victoire dans une partie qui n'avait qu'un seul joueur.
var _initial_players: int = 0

func _ready() -> void:
	set_process(false)

## Appelé par l'arène une fois qu'elle est prête et peuplée.
func begin(arena_node: Node3D) -> void:
	arena = arena_node
	elapsed = 0.0
	pressure = 0.0
	zone_radius = Cfg.ARENA_RADIUS
	zone_target = Cfg.ARENA_RADIUS
	_countdown = 4.0
	_set_phase(Phase.COUNTDOWN)
	set_process(true)

func register_player(peer_id: int, node: Node) -> void:
	players[peer_id] = node
	if not alive_ids.has(peer_id):
		alive_ids.append(peer_id)
	_initial_players = maxi(_initial_players, alive_ids.size())
	alive_count_changed.emit(alive_ids.size())

func player_name(peer_id: int) -> String:
	var info: Dictionary = Net.peers.get(peer_id, {})
	return info.get("name", "Joueur %d" % peer_id)

func _set_phase(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)

func _process(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.WARMUP, Phase.ESCALATION, Phase.CLOSING:
			_tick_match(delta)
		_:
			pass

func _tick_countdown(delta: float) -> void:
	var before := ceili(_countdown)
	_countdown -= delta
	var now := ceili(_countdown)
	if now != before:
		# 3, 2, 1 puis 0 → « GO ». Le HUD traduit 0 en mot.
		countdown_tick.emit(maxi(now, 0))
	if _countdown <= 0.0:
		_set_phase(Phase.WARMUP)
		announce.emit("GO", Cfg.COL_HEAL)

func _tick_match(delta: float) -> void:
	elapsed += delta
	# La pression pilote le nombre de mobs, leur agressivité et la qualité
	# du butin. En mode arène elle monte jusqu'à un PLATEAU et s'y tient :
	# une escalade sans fin dans un monde où l'on reste des heures finirait
	# par rendre l'arène inhabitable, alors que le plateau donne un rythme
	# de croisière soutenu et stable.
	if est_persistant():
		pressure = clampf(elapsed / (MATCH_DURATION * 0.6), 0.0, PALIER_PRESSION)
	else:
		pressure = clampf(elapsed / MATCH_DURATION, 0.0, 1.0)

	# Les phases ne sont que des SEUILS de la même courbe continue : le
	# joueur ressent une montée progressive, pas des paliers brutaux.
	if phase == Phase.WARMUP and elapsed >= 30.0:
		_set_phase(Phase.ESCALATION)
		announce.emit("LA PRESSION MONTE", Cfg.COL_SHOTGUN)
	elif phase == Phase.ESCALATION and elapsed >= ZONE_START \
			and not est_persistant():
		_set_phase(Phase.CLOSING)
		announce.emit("LA ZONE SE REFERME", Cfg.COL_DANGER)

	if phase == Phase.CLOSING:
		_tick_zone(delta)

	# EN MODE ARÈNE, PERSONNE NE GAGNE. La partie ne s'arrête pas parce
	# qu'il ne reste qu'un joueur debout : les autres reviennent.
	if Net.is_server() and not est_persistant():
		_check_victory()

func _tick_zone(delta: float) -> void:
	# Fermeture par PALIERS annoncés plutôt qu'en continu : le joueur peut
	# planifier son repli, ce qu'un rétrécissement lisse ne permet pas.
	_zone_tick -= delta
	if _zone_tick <= 0.0:
		_zone_tick = 26.0
		zone_target = maxf(7.0, zone_target * 0.62)
		announce.emit("ZONE — REPLIEZ-VOUS", Cfg.COL_DANGER)

	# Le rayon rattrape sa cible doucement : la limite bouge visiblement,
	# sans jamais téléporter un joueur hors de la zone d'un coup.
	zone_radius = move_toward(zone_radius, zone_target, delta * 1.6)
	zone_updated.emit(zone_radius, zone_target, zone_radius > zone_target + 0.05)

## Vrai si la position est hors de la zone sûre (donc soumise aux dégâts).
func is_outside_zone(pos: Vector3) -> bool:
	if phase != Phase.CLOSING:
		return false
	return Vector2(pos.x, pos.z).length() > zone_radius

## SERVEUR UNIQUEMENT — enregistre une élimination.
##
## En mode ARÈNE elle n'est plus DÉFINITIVE : le joueur sort de la liste des
## vivants le temps de sa réapparition, puis y revient par `reintegrer()`.
## C'est le gestionnaire de réapparition qui pilote ce va-et-vient.
func eliminate(peer_id: int) -> void:
	if not Net.is_server() or phase == Phase.ENDED:
		return
	if not alive_ids.has(peer_id):
		return
	# `Net.broadcast` plutôt qu'un `.rpc()` direct : en solo il n'existe
	# aucun pair réseau et un rpc y échouerait bruyamment. La diffusion
	# retombe alors sur un simple appel local, et le même code sert partout.
	Net.broadcast(self, &"_announce_elimination", [peer_id, player_name(peer_id)])
	_check_victory()

@rpc("authority", "call_local", "reliable")
func _announce_elimination(peer_id: int, name: String) -> void:
	# Chaque pair retire lui-même l'éliminé de SA liste : celle-ci est
	# identique partout, puisque les joueurs y sont enregistrés par le même
	# ordre de création diffusé par le serveur.
	alive_ids.erase(peer_id)
	player_eliminated.emit(peer_id, name)
	alive_count_changed.emit(alive_ids.size())

## SERVEUR UNIQUEMENT — remet un joueur parmi les vivants après sa
## réapparition. Symétrique d'`eliminate`, et diffusée de la même façon
## pour que tous les pairs tiennent la même liste.
func reintegrer(peer_id: int) -> void:
	if not Net.is_server():
		return
	Net.broadcast(self, &"_annoncer_retour", [peer_id])

@rpc("authority", "call_local", "reliable")
func _annoncer_retour(peer_id: int) -> void:
	if not alive_ids.has(peer_id):
		alive_ids.append(peer_id)
	alive_count_changed.emit(alive_ids.size())


func _check_victory() -> void:
	if phase == Phase.ENDED or not Net.is_server() or est_persistant():
		return
	# Une partie lancée avec un seul participant (test solo sans bots) ne
	# doit jamais se déclarer gagnée : il n'y avait rien à gagner.
	if _initial_players < 2:
		return
	if alive_ids.size() > 1:
		return
	var winner := alive_ids[0] if alive_ids.size() == 1 else 0
	Net.broadcast(self, &"_declare_winner",
			[winner, player_name(winner) if winner != 0 else "Personne"])

@rpc("authority", "call_local", "reliable")
func _declare_winner(winner_id: int, winner_name: String) -> void:
	if phase == Phase.ENDED:
		return
	_set_phase(Phase.ENDED)
	set_process(false)
	match_ended.emit(winner_id, winner_name)

## Remise à zéro complète entre deux parties.
func reset() -> void:
	set_process(false)
	phase = Phase.LOBBY
	elapsed = 0.0
	pressure = 0.0
	_countdown = 0.0
	_zone_tick = 0.0
	_initial_players = 0
	zone_radius = Cfg.ARENA_RADIUS
	zone_target = Cfg.ARENA_RADIUS
	players.clear()
	alive_ids.clear()
	arena = null
