extends Node
class_name MobSpawner
## VAGUES DE MOBS — cadence, composition, plafond.
##
## SERVEUR UNIQUEMENT. Le spawner ne crée rien lui-même : il DEMANDE au
## monde de faire apparaître un mob, et le monde diffuse l'ordre à tous les
## pairs. Cette indirection garantit que les mobs existent avec le même
## identifiant partout, condition sine qua non pour que les RPC tombent
## sur le bon nœud.
##
## LA COMPOSITION ÉVOLUE avec la pression, et pas seulement la quantité :
## la partie commence avec des Chargers (simples à lire), puis introduit
## les Shooters (pression à distance), puis les Exploders (gestion de
## l'espace). C'est une courbe d'apprentissage, pas juste une montée de
## difficulté.

## PLAFOND SIMULTANÉ — garde-fou de performance ET de lisibilité.
##
## 34 au lieu de 14. Le monde fait cinq fois la surface de l'ancienne
## arène ; à plafond constant, chaque secteur en aurait eu deux ou trois et
## la carte aurait paru morte. Il ne monte pas pour autant à cinq fois : la
## plupart des mobs sont hors du champ de n'importe qui à un instant donné,
## et ce qui compte est la densité LÀ OÙ SE TROUVENT LES JOUEURS, pas le
## total.
const MAX_ALIVE := 34

## Distance au-delà de laquelle un mob n'intéresse plus personne.
##
## POURQUOI RECYCLER PLUTÔT QU'ACCUMULER : sur une grande carte, les mobs
## abandonnés derrière un joueur qui s'éloigne remplissent le plafond sans
## que personne ne les voie jamais. Le monde paraît alors vide là où l'on
## est — précisément l'inverse du but — parce que le budget est consommé
## ailleurs. On les retire, et le pondeur en remet près des joueurs.
const OUBLI := 62.0
const OUBLI_PERIODE := 4.0

var _oubli_timer: float = 0.0

var world: Node = null
var _timer: float = 0.0

## Nombre exact de mobs en arène de combat, et ils ne sont pondus qu'UNE
## fois. Le test demande dix mobs à des endroits voulus : une vague qui en
## rajoute, ou un recyclage qui en déplace, rendrait le test illisible —
## on ne saurait plus si une zone est déserte par conception ou parce que
## le pondeur a décidé autrement.
const MOBS_ARENE := 10
## Délai entre deux venues, en secondes.
##
## 2,5 s d'abord, et c'était trop lent : mesuré, l'effectif se maintenait
## à 0,8 mob en moyenne pour dix demandés. Dix bots abattent plus d'un mob
## par seconde à eux tous — un remplacement toutes les deux secondes et
## demie ne pouvait pas suivre, et l'arène restait vide de mobs pendant
## qu'on croyait en tester dix.
const DELAI_RETOUR := 0.5
## Venues par tour, tant qu'on est loin du compte : remplir dix places une
## par une prendrait cinq secondes au démarrage.
const PAR_TOUR := 2
var _recharge := 0.0
var _prochain := 0


func _process(delta: float) -> void:
	if not Net.is_server():
		return

	if Cfg.arene_test:
		_peupler_arene()
		return

	_recycler(delta)
	if MatchDirector.phase not in [MatchDirector.Phase.WARMUP,
			MatchDirector.Phase.ESCALATION, MatchDirector.Phase.CLOSING]:
		return

	_timer -= delta
	if _timer > 0.0:
		return

	var pressure := MatchDirector.pressure
	# CADENCE ACCÉLÉRÉE. Il faut peupler cinq fois plus de terrain : au
	# rythme d'origine, remplir la carte aurait demandé plus d'une minute,
	# et le joueur aurait traversé un monde vide pendant tout ce temps.
	_timer = lerpf(1.6, 0.5, pressure)

	var alive := get_tree().get_nodes_in_group(&"mobs").size()
	if alive >= MAX_ALIVE:
		return

	# Rafales croissantes : à la fin, les mobs arrivent par paquets, ce qui
	# force les joueurs à bouger au lieu de camper.
	var burst := 2 + int(pressure * 2.0)
	for i in mini(burst, MAX_ALIVE - alive):
		world.call(&"server_spawn_mob", _pick_type(pressure))

## RETIRE LES MOBS QUE PLUS PERSONNE NE PEUT RENCONTRER.
##
## Sans ce ménage, le plafond se remplit de mobs abandonnés aux quatre
## coins de la carte : ils coûtent leur simulation, occupent la place, et
## personne ne les voit jamais. Le monde paraît vide là où l'on joue.
##
## On ne touche évidemment pas à ceux qui se battent : seule l'ABSENCE de
## tout joueur à portée compte.
func _recycler(delta: float) -> void:
	_oubli_timer -= delta
	if _oubli_timer > 0.0:
		return
	_oubli_timer = OUBLI_PERIODE
	var joueurs := get_tree().get_nodes_in_group(&"players")
	if joueurs.is_empty():
		return
	for node in get_tree().get_nodes_in_group(&"mobs"):
		var m := node as Node3D
		if m == null:
			continue
		var plus_proche := INF
		for j in joueurs:
			if is_instance_valid(j) and j.get(&"is_eliminated") != true:
				plus_proche = minf(plus_proche,
						PlanMonde.distance3(m.global_position, j.global_position))
		if plus_proche > OUBLI:
			m.queue_free()


## Seuils calés sur des parties MESURÉES, pas estimés : le test automatisé
## montre qu'une partie se conclut vers 60-110 s, donc autour d'une pression
## de 0,45 à 0,85. Des seuils fixés plus haut faisaient que l'Exploder
## n'apparaissait jamais — un des trois mobs du jeu restait invisible.
func _pick_type(pressure: float) -> StringName:
	var roll := randf()
	# Ouverture : uniquement des Chargers, le comportement le plus simple
	# à lire. Le joueur apprend une menace à la fois.
	if pressure < 0.10:
		return &"charger"
	# Le Shooter entre tôt : c'est lui qui oblige à bouger et à utiliser
	# les obstacles, donc à comprendre l'arène.
	if pressure < 0.26:
		return &"shooter" if roll < 0.45 else &"charger"
	# L'Exploder arrive au tiers de la partie, une fois qu'on a une arme.
	if pressure < 0.6:
		if roll < 0.34:
			return &"shooter"
		return &"exploder" if roll < 0.60 else &"charger"
	# Fin de partie : composition complète, Exploders bien présents pour
	# empêcher tout campement défensif.
	if roll < 0.36:
		return &"exploder"
	return &"shooter" if roll < 0.68 else &"charger"

func reset() -> void:
	_timer = 0.0


## PEUPLE L'ARÈNE DE COMBAT — dix mobs, une seule fois.
##
## Pas de cadence, pas de rafales, pas d'oubli à distance : rien de ce qui
## fait vivre un monde ouvert n'a de sens sur quarante mètres, où tout est
## à portée de marche. On pose la composition et on la laisse tranquille.
##
## LES TROIS FAMILLES SONT REPRÉSENTÉES, en alternance sur les foyers :
## un test de combat qui n'affronterait qu'un seul type de mob ne dirait
## rien de la lisibilité des autres.
func _peupler_arene() -> void:
	if MatchDirector.phase not in [MatchDirector.Phase.WARMUP,
			MatchDirector.Phase.ESCALATION, MatchDirector.Phase.CLOSING]:
		return
	# L'EFFECTIF EST MAINTENU, PAS POSÉ UNE FOIS.
	#
	# Premier jet : dix mobs pondus au démarrage, plus jamais rien. Mesuré
	# sur 150 s de partie avec dix bots — il n'en restait ZÉRO à la fin.
	# Les bots les avaient tous tués dans la première minute, et le reste
	# du banc observait une arène sans mobs en croyant en observer dix.
	#
	# Ce n'est pas une vague pour autant : on ne dépasse jamais dix, et
	# chacun revient au foyer que le plan lui a assigné. La composition
	# reste celle qu'on a voulue, elle ne s'épuise simplement plus.
	_recharge -= get_process_delta_time()
	if _recharge > 0.0:
		return
	var vivants := get_tree().get_nodes_in_group(&"mobs").size()
	if vivants >= MOBS_ARENE:
		return
	# Un délai entre deux venues : sans lui, un mob tué réapparaît dans
	# l'image suivante, au même endroit, sous le nez de celui qui vient de
	# l'abattre. On ne teste plus un combat, on teste un tapis roulant.
	_recharge = DELAI_RETOUR
	var familles: Array[StringName] = [&"charger", &"shooter", &"exploder"]
	for i in mini(PAR_TOUR, MOBS_ARENE - vivants):
		world.call(&"server_spawn_mob", familles[_prochain % familles.size()])
		_prochain += 1
