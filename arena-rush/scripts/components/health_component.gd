extends Node
class_name HealthComponent
## POINTS DE VIE — composant réutilisable, AUTORITÉ SERVEUR.
##
## Règle non négociable du prototype : seul le serveur appelle
## `apply_damage()`. Un client qui croit avoir touché quelqu'un envoie une
## intention, jamais un résultat. Toute la triche « j'ai tué untel » meurt
## ici, parce que le client n'a tout simplement pas la méthode qui décide.
##
## Le composant ne connaît ni le joueur ni le mob qui le porte : il émet
## des signaux, et son propriétaire décide quoi en faire.

signal damaged(amount: float, from_position: Vector3)
signal healed(amount: float)
signal died(killer_id: int)
## Émis sur TOUS les pairs pour l'affichage (barres de vie, teinte).
signal health_changed(current: float, maximum: float)

@export var max_health: float = 100.0
## Invulnérabilité après un coup — empêche qu'une salve de plombs de
## fusil à pompe compte huit fois sur la même image.
@export var invulnerability: float = 0.05

var current_health: float
var is_dead: bool = false

var _invulnerable_until: float = 0.0

func _ready() -> void:
	current_health = max_health

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## SERVEUR UNIQUEMENT. Retourne true si le coup a effectivement porté.
func apply_damage(amount: float, from_position: Vector3 = Vector3.ZERO,
		killer_id: int = 0) -> bool:
	if is_dead or amount <= 0.0:
		return false
	if _now() < _invulnerable_until:
		return false
	_invulnerable_until = _now() + invulnerability

	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, from_position)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		is_dead = true
		died.emit(killer_id)
	return true

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)

## Réplique un état reçu du serveur (les clients ne calculent jamais les PV).
func set_replicated_health(value: float) -> void:
	if is_equal_approx(value, current_health):
		return
	current_health = clampf(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)

func ratio() -> float:
	return current_health / maxf(max_health, 0.01)

func reset() -> void:
	is_dead = false
	current_health = max_health
	_invulnerable_until = 0.0
	health_changed.emit(current_health, max_health)
