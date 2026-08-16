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

## Plafond simultané — garde-fou de performance ET de lisibilité.
const MAX_ALIVE := 14

var world: Node = null
var _timer: float = 0.0

func _process(delta: float) -> void:
	if not Net.is_server():
		return
	if MatchDirector.phase not in [MatchDirector.Phase.WARMUP,
			MatchDirector.Phase.ESCALATION, MatchDirector.Phase.CLOSING]:
		return

	_timer -= delta
	if _timer > 0.0:
		return

	var pressure := MatchDirector.pressure
	# Intervalle décroissant : 2,6 s au début, 0,55 s à pleine pression.
	_timer = lerpf(3.4, 1.1, pressure)

	var alive := get_tree().get_nodes_in_group(&"mobs").size()
	if alive >= MAX_ALIVE:
		return

	# Rafales croissantes : à la fin, les mobs arrivent par paquets, ce qui
	# force les joueurs à bouger au lieu de camper.
	var burst := 1 + int(pressure * 1.5)
	for i in mini(burst, MAX_ALIVE - alive):
		world.call(&"server_spawn_mob", _pick_type(pressure))

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
