extends Node
## DIRECTEUR DE L'ÉTOILE WANTED — l'unique dépositaire de la règle.
##
## Autoload : EtoileDirector
##
## LA RÈGLE, EN UNE PHRASE : une étoile traîne dans la carte, on la ramasse,
## on la garde trente secondes sans mourir, on gagne une ★. Mourir avant
## la fait tomber sur place et remet le compteur à zéro — pour tout le
## monde, pas seulement pour celui qui vient de mourir.
##
## POURQUOI LE TEMPS N'EST JAMAIS TRANSMIS. C'est le cœur du mode et c'est
## ce qui le rend juste : si le suivant héritait de vingt-neuf secondes, la
## bonne stratégie serait d'attendre que quelqu'un fasse le travail et de
## le tuer à la fin. En repartant de zéro, tuer le porteur SUPPRIME de la
## valeur au lieu d'en voler — et il faut ensuite gagner soi-même ses
## trente secondes.
##
## AUTORITÉ SERVEUR, SANS EXCEPTION. Le serveur seul avance le compteur,
## désigne le porteur, décide du drop et crédite la victoire. Les clients
## reçoivent un état et l'affichent. Un client qui pourrait s'attribuer
## l'étoile n'aurait qu'à le faire en boucle.
##
## POURQUOI UN AUTOLOAD ET NON UN NŒUD DE L'ARÈNE. L'interface (barre
## WANTED, minicarte, classement) doit lire cet état à chaque image, et
## l'arène est reconstruite entre deux sessions. Un point fixe évite de
## rebrancher cinq abonnements à chaque changement de carte.

## Durée à tenir, en secondes.
const DUREE := 30.0
## Délai avant réapparition après une victoire.
const DELAI_VICTOIRE := 5.0
## Délai avant réapparition si l'étoile se retrouve orpheline (porteur parti
## de la partie sans mourir, par exemple).
const DELAI_ORPHELINE := 1.0
## Cadence de réplication du compteur, en hertz.
##
## QUATRE FOIS PAR SECONDE, PAS SOIXANTE. La barre affiche des secondes
## entières : répliquer plus finement enverrait du trafic pour des chiffres
## identiques. Entre deux paquets, le client fait avancer sa copie tout
## seul — voir `_process`.
const HZ_REPLICATION := 4.0

## Rayon minimal d'espace libre exigé autour d'un point d'apparition.
const DEGAGEMENT := 1.4
## Distance minimale entre l'étoile et un point d'apparition de joueur.
##
## Sans cette marge, l'étoile pouvait naître sur le tapis de réapparition :
## celui qui vient de mourir la ramassait en revenant, ce qui récompense
## exactement le mauvais geste.
const ECART_SPAWN := 9.0

signal etat_change()
signal ramassee(peer_id: int)
signal lachee(position: Vector3)
signal gagnee(peer_id: int, victoires: int)

## 0 = personne. Sinon le peer_id du porteur.
var porteur_id: int = 0
## Secondes déjà tenues par le porteur actuel. Toujours 0 quand il n'y en a
## pas — voir la règle du non-transfert.
var temps: float = 0.0
## L'étoile est-elle posée quelque part et ramassable ?
var au_sol: bool = false
## Où, si elle est au sol. Sert à la minicarte.
var position_sol: Vector3 = Vector3.ZERO

var arene: Node3D = null

var _corps: EtoileWanted = null
var _delai: float = 0.0
var _accum_replication: float = 0.0
## Points d'apparition candidats, calculés une fois par arène.
var _points: Array[Vector3] = []
## Index du dernier point utilisé : on ne réapparaît jamais deux fois de
## suite au même endroit, sinon le mode se joue sur une seule place.
var _dernier: int = -1


func _ready() -> void:
	set_process(true)


## Appelé quand une arène est prête. Remet tout à plat et sème l'étoile.
func demarrer(arena_node: Node3D) -> void:
	arene = arena_node
	reset()
	_calculer_points()
	if Net.is_server():
		_delai = 1.0


func reset() -> void:
	_liberer_corps()
	porteur_id = 0
	temps = 0.0
	au_sol = false
	position_sol = Vector3.ZERO
	_delai = 0.0
	_points = []
	_dernier = -1
	etat_change.emit()


func est_active() -> bool:
	return arene != null and is_instance_valid(arene)


## Nom affichable du porteur, ou chaîne vide.
func nom_porteur() -> String:
	var j := porteur()
	return j.display_name if j != null else ""


func porteur() -> Player:
	if porteur_id == 0:
		return null
	var j := MatchDirector.players.get(porteur_id) as Player
	return j if j != null and is_instance_valid(j) else null


# --- POINTS D'APPARITION -------------------------------------------------

## LES POINTS SONT DÉRIVÉS DU MONDE, PAS ÉCRITS À LA MAIN.
##
## Le brief propose des marqueurs `StarSpawn_01`, `StarSpawn_02`… posés dans
## la scène. Ici l'arène est BÂTIE PAR CODE et son plan change à chaque
## itération de level design : des marqueurs figés se retrouveraient dans un
## rocher à la première retouche de la carte, et personne ne le verrait
## avant de jouer.
##
## On part donc des apparitions de joueurs — déjà validées comme praticables
## par l'arène — et on s'en écarte : le résultat suit automatiquement le
## plan, quel qu'il devienne.
func _calculer_points() -> void:
	_points = []
	if arene == null:
		return
	var spawns: Array = arene.get(&"player_spawn_points")
	if spawns == null or spawns.is_empty():
		return
	# Huit directions autour de chaque apparition, à bonne distance : on
	# obtient une grille grossière qui couvre la carte sans la quadriller.
	for base: Vector3 in spawns:
		for k in 8:
			var a := TAU * float(k) / 8.0
			var essai := Vector3(base.x + cos(a) * ECART_SPAWN, base.y,
					base.z + sin(a) * ECART_SPAWN)
			essai = _corriger(essai)
			if essai == Vector3.INF:
				continue
			if _trop_pres_dun_spawn(essai, spawns):
				continue
			if _trop_pres_dun_point(essai):
				continue
			_points.append(essai)
	if _points.is_empty():
		# Filet de sécurité : mieux vaut une étoile au centre qu'un mode
		# qui ne démarre jamais.
		_points.append(_corriger(Vector3.ZERO))


func _trop_pres_dun_spawn(p: Vector3, spawns: Array) -> bool:
	for s: Vector3 in spawns:
		if PlanMonde.distance3(p, s) < ECART_SPAWN * 0.72:
			return true
	return false


func _trop_pres_dun_point(p: Vector3) -> bool:
	for q: Vector3 in _points:
		if PlanMonde.distance3(p, q) < 7.0:
			return true
	return false


## Ramène un point sur un sol praticable, ou `Vector3.INF` s'il n'y arrive
## pas. C'est l'arène qui sait où sont ses obstacles — on ne recopie pas sa
## carte ici.
func _corriger(p: Vector3) -> Vector3:
	if arene == null or not arene.has_method(&"position_degagee"):
		return p
	var enroule := PlanMonde.enrouler(Vector2(p.x, p.z))
	var degage: Vector3 = arene.call(&"position_degagee",
			Vector3(enroule.x, 0.0, enroule.y), DEGAGEMENT)
	if arene.has_method(&"position_libre") \
			and not arene.call(&"position_libre", degage, DEGAGEMENT):
		return Vector3.INF
	return Vector3(degage.x, 0.0, degage.z)


# --- BOUCLE SERVEUR ------------------------------------------------------

func _process(delta: float) -> void:
	if not est_active():
		return
	if not Net.is_server():
		# LE CLIENT FAIT AVANCER SA COPIE ENTRE DEUX PAQUETS. Sans cela, la
		# barre progresserait par saccades de 250 ms, ce qui se voit tout
		# de suite sur une jauge qui met trente secondes à se remplir. Le
		# prochain paquet la recale de toute façon.
		if porteur_id != 0:
			temps = minf(temps + delta, DUREE)
		return

	if _delai > 0.0:
		_delai -= delta
		if _delai <= 0.0:
			_semer()
		return

	if porteur_id == 0:
		return

	var j := porteur()
	if j == null or j.is_eliminated:
		# LE PORTEUR A DISPARU SANS PASSER PAR LA MORT — déconnexion, ou
		# retrait de la partie. L'étoile ne doit pas partir avec lui : on
		# la rend au monde là où il se trouvait, ou à un point neuf si on
		# ne sait plus où c'était.
		_orpheline()
		return

	temps = minf(temps + delta, DUREE)
	j.star_hold_time = temps
	if temps >= DUREE:
		_victoire(j)
		return

	_accum_replication += delta
	if _accum_replication >= 1.0 / HZ_REPLICATION:
		_accum_replication = 0.0
		Net.broadcast(self, &"net_etat", [porteur_id, temps, au_sol,
				position_sol])


# --- ÉVÉNEMENTS ----------------------------------------------------------

## SERVEUR — pose une étoile neuve à un point valide.
func _semer() -> void:
	if not Net.is_server() or not est_active():
		return
	if _points.is_empty():
		_calculer_points()
	if _points.is_empty():
		return
	var i := randi() % _points.size()
	# JAMAIS DEUX FOIS DE SUITE AU MÊME ENDROIT. Avec peu de points, le
	# tirage aléatoire répète, et le mode se met à se jouer sur une seule
	# place de la carte — ce qui est exactement ce qu'on cherche à éviter
	# en ayant plusieurs points.
	if _points.size() > 1 and i == _dernier:
		i = (i + 1) % _points.size()
	_dernier = i
	Net.broadcast(self, &"net_poser", [_points[i]])


## SERVEUR — un joueur touche l'étoile. Un seul peut gagner.
func tenter_ramassage(peer_id: int) -> void:
	if not Net.is_server():
		return
	# LA TRIPLE CONDITION EST L'EXCLUSION MUTUELLE. Deux joueurs qui
	# entrent dans la zone à la même image produisent deux appels ; le
	# premier met `porteur_id`, le second trouve `au_sol` déjà faux et
	# repart. Aucun verrou à tenir, aucune fenêtre entre les deux — les
	# appels sont traités l'un après l'autre sur le même fil.
	if not au_sol or porteur_id != 0:
		return
	var j := MatchDirector.players.get(peer_id) as Player
	if j == null or not is_instance_valid(j) or j.is_eliminated:
		return
	Net.broadcast(self, &"net_ramasser", [peer_id])


## SERVEUR — le porteur vient de mourir. Appelé par `Player`, AVANT que la
## réapparition n'efface sa position de mort.
func signaler_mort_porteur(peer_id: int, position: Vector3) -> void:
	if not Net.is_server() or porteur_id != peer_id:
		return
	# LA POSITION DE MORT EST CORRIGÉE AVANT D'ÊTRE DIFFUSÉE. On meurt
	# volontiers collé à un rocher, ou dans l'angle d'un muret ; l'étoile
	# lâchée telle quelle s'y retrouverait coincée, visible et
	# inatteignable. `position_degagee` la repousse jusqu'au premier
	# espace praticable.
	var pose := _corriger(position)
	if pose == Vector3.INF:
		pose = _corriger(Vector3.ZERO)
	Net.broadcast(self, &"net_lacher", [pose])


## SERVEUR — le porteur s'est volatilisé sans mourir.
func _orpheline() -> void:
	var pose := _corriger(position_sol if position_sol != Vector3.ZERO
			else Vector3.ZERO)
	if pose == Vector3.INF:
		pose = Vector3.ZERO
	porteur_id = 0
	temps = 0.0
	au_sol = false
	_delai = DELAI_ORPHELINE
	Net.broadcast(self, &"net_lacher", [pose])


## SERVEUR — trente secondes tenues.
func _victoire(j: Player) -> void:
	j.star_wins += 1
	j.star_hold_time = 0.0
	j.is_star_holder = false
	Net.broadcast(j, &"net_compteurs", [j.kills, j.star_wins])
	Net.broadcast(self, &"net_gagner", [j.peer_id, j.star_wins])
	_delai = DELAI_VICTOIRE


# --- RÉPLICATION ---------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func net_poser(position: Vector3) -> void:
	_liberer_corps()
	porteur_id = 0
	temps = 0.0
	au_sol = true
	position_sol = position
	_creer_corps(position)
	etat_change.emit()


@rpc("authority", "call_local", "reliable")
func net_ramasser(peer_id: int) -> void:
	porteur_id = peer_id
	# REMISE À ZÉRO EXPLICITE, et pas seulement parce que c'est propre :
	# c'est LA règle du mode. Elle est écrite ici, dans le chemin que tout
	# le monde emprunte, plutôt que laissée à la bonne volonté des
	# appelants.
	temps = 0.0
	au_sol = false
	if _corps != null and is_instance_valid(_corps):
		_corps.consommer()
	_corps = null
	var j := MatchDirector.players.get(peer_id) as Player
	if j != null and is_instance_valid(j):
		_marquer_porteurs(peer_id)
		Fx.pickup(j.global_position + Vector3(0, 1.6, 0), Color("ffc73a"))
	ramassee.emit(peer_id)
	etat_change.emit()


@rpc("authority", "call_local", "reliable")
func net_lacher(position: Vector3) -> void:
	porteur_id = 0
	temps = 0.0
	au_sol = true
	position_sol = position
	_marquer_porteurs(0)
	_creer_corps(position)
	# LE DROP DOIT SE VOIR. Une étoile qui réapparaît en silence au milieu
	# d'une fusillade passe inaperçue, et c'est précisément l'instant où
	# tout le monde doit la chercher des yeux.
	Fx.loot_spawn(position + Vector3(0, 1.0, 0), Color("ffc73a"))
	lachee.emit(position)
	etat_change.emit()


@rpc("authority", "call_local", "reliable")
func net_gagner(peer_id: int, victoires: int) -> void:
	porteur_id = 0
	temps = 0.0
	au_sol = false
	_marquer_porteurs(0)
	var j := MatchDirector.players.get(peer_id) as Player
	if j != null and is_instance_valid(j):
		Fx.impact(j.global_position + Vector3(0, 1.8, 0), Color("ffc73a"), 2.4)
	gagnee.emit(peer_id, victoires)
	etat_change.emit()


## Réplication périodique du compteur. `unreliable_ordered` : perdre un
## paquet sur quatre n'a aucune conséquence, le suivant recale tout, et on
## n'encombre pas le canal fiable réservé aux événements.
@rpc("authority", "call_local", "unreliable_ordered")
func net_etat(qui: int, t: float, sol: bool, pos: Vector3) -> void:
	porteur_id = qui
	temps = t
	au_sol = sol
	position_sol = pos


# --- CORPS ---------------------------------------------------------------

func _creer_corps(position: Vector3) -> void:
	if arene == null or not is_instance_valid(arene):
		return
	_liberer_corps()
	var e := EtoileWanted.new()
	e.position = Vector3(position.x, position.y, position.z)
	e.touchee.connect(tenter_ramassage)
	arene.add_child(e)
	_corps = e


func _liberer_corps() -> void:
	if _corps != null and is_instance_valid(_corps):
		# Même raison que dans `consommer` : hors du groupe tout de suite,
		# libéré en fin d'image.
		_corps.remove_from_group(&"etoile_wanted")
		_corps.queue_free()
	_corps = null


## Met à jour le drapeau `is_star_holder` de TOUS les joueurs.
##
## On repasse sur tout le monde plutôt que sur l'ancien et le nouveau : un
## joueur qui se déconnecte pendant qu'il porte l'étoile laisserait sinon
## un drapeau allumé sur un nœud qui reparaîtra peut-être plus tard.
func _marquer_porteurs(qui: int) -> void:
	for n in get_tree().get_nodes_in_group(&"players"):
		var j := n as Player
		# `is_instance_valid` EN PLUS DU TEST DE TYPE. Un joueur qui se
		# déconnecte est libéré en fin d'image ; d'ici là il reste dans le
		# groupe, et le toucher lève une erreur d'accès à un objet libéré.
		if j == null or not is_instance_valid(j):
			continue
		var porte := j.peer_id == qui and qui != 0
		j.is_star_holder = porte
		if not porte:
			j.star_hold_time = 0.0
		if j.has_method(&"montrer_etoile"):
			j.call(&"montrer_etoile", porte)
