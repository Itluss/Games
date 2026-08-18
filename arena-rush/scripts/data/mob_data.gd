extends Resource
class_name MobData
## DÉFINITION D'UN MOB — données pures.
##
## Le champ `behavior` sélectionne une stratégie d'IA déjà écrite ; il ne
## contient pas de logique. Ajouter une VARIANTE (un chargeur plus rapide,
## un tireur plus fragile) ne demande donc qu'un nouveau .tres.

@export var id: StringName = &""
@export var display_name: String = "Mob"

## Stratégie de comportement implémentée dans scripts/mobs/behaviors/.
@export_enum("charger", "shooter", "exploder") var behavior: String = "charger"

@export_group("Statistiques")
@export var health: float = 30.0
@export var speed: float = 4.0
@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var detection_range: float = 22.0
## Délai entre deux attaques, en secondes.
@export var attack_cooldown: float = 1.6
## Durée du télégraphe : le joueur DOIT avoir le temps de lire l'attaque
## et de réagir. C'est ce qui sépare un combat lisible d'un combat subi.
@export var telegraph_time: float = 0.6

@export_group("Comportement spécifique")
## Charger : vitesse pendant la ruée.
@export var charge_speed: float = 16.0
@export var charge_duration: float = 0.8
## Shooter : distance de maintien et caractéristiques du tir.
@export var preferred_distance: float = 12.0
@export var projectile_speed: float = 18.0
## Exploder : rayon de l'explosion.
@export var explosion_radius: float = 4.0

@export_group("Loot")
## Identifiant d'arme lâchée à la mort (vide = aucun loot).
@export var loot_weapon_id: StringName = &""
## Probabilité de lâcher cette arme, entre 0 et 1.
@export var loot_chance: float = 0.5

@export_group("Identité visuelle")
@export var color: Color = Color.WHITE
@export var scale: float = 1.0
## Score accordé au tueur — sert au classement de fin de partie.
@export var score: int = 10

## CATÉGORIE DE MENACE — commun, resistant, elite.
##
## Elle ne pilote AUCUNE statistique de combat : elle sert à la progression
## (combien vaut ce mob) et servira aux tables de butin (un élite lâche
## mieux). La séparer des statistiques permet de rendre un mob plus coriace
## sans le rendre plus rentable, et inversement — deux réglages distincts
## pour deux intentions distinctes.
@export_enum("commun", "resistant", "elite") var categorie: String = "commun"
