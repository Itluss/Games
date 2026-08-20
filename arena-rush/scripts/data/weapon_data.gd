extends Resource
class_name WeaponData
## DÉFINITION D'UNE ARME — données pures, aucun comportement.
##
## Ajouter une arme au jeu ne doit demander AUCUNE ligne de code : on crée
## un .tres, on le déclare dans le Registry, et il est jouable. C'est la
## raison d'être de cette ressource.
##
## Chaque champ visuel (couleur, forme, traînée, secousse) existe parce
## qu'une arme doit se reconnaître à l'œil pendant qu'elle tire, pas
## seulement dans l'inventaire.

## Identifiant stable. C'est LUI qui circule sur le réseau, jamais le
## chemin de ressource : un id court reste valide si le fichier bouge.
@export var id: StringName = &""
@export var display_name: String = "Arme"

@export_group("Combat")
@export var damage: float = 10.0
## Tirs par seconde.
@export var fire_rate: float = 3.0
@export var range: float = 22.0
@export var projectile_speed: float = 34.0
## Projectiles émis par tir (le fusil à pompe en crache plusieurs).
@export var projectile_count: int = 1
## Dispersion totale du cône, en degrés.
@export var spread_degrees: float = 0.0
## Rayon de dégâts de zone. 0 = impact ponctuel.
@export var splash_radius: float = 0.0

@export_group("Trajectoire")
## Le lance-grenades décrit un arc : le projectile subit la gravité.
@export var gravity: float = 0.0
## Détonation automatique après ce délai (0 = jamais).
@export var fuse_time: float = 0.0
## Rebonds avant détonation.
@export var bounces: int = 0

@export_group("Identité visuelle")
@export var color: Color = Color.WHITE
## Taille du projectile — une grenade doit se voir venir, pas un plomb.
@export var projectile_radius: float = 0.18
@export var trail_length: float = 0.0
## Intensité de la secousse caméra au tir (0 = aucune).
@export var shake: float = 0.0
## Recul visuel de l'arme, en mètres.
@export var recoil: float = 0.0
## Forme du modèle d'arme, construite proceduralement.
@export_enum("pistol", "shotgun", "rifle", "launcher") var silhouette: String = "pistol"

@export_group("Identité de tir")
## LE PROFIL EST OPTIONNEL, ET C'EST VOULU.
##
## Les armes ramassées au sol gardent le comportement d'origine : sans
## profil, tout se passe comme avant cette passe. Seules les armes de poing
## signature des six héros en portent un. C'est ce qui permet d'ajouter une
## identité de tir sans rouvrir l'équilibrage de l'arsenal existant.
@export var profil: ProfilTir = null

@export_group("Munitions")
## -1 = illimité (l'arme de départ ne doit jamais laisser un joueur nu).
@export var max_ammo: int = -1

## Intervalle entre deux tirs, dérivé de la cadence.
func cooldown() -> float:
	return 1.0 / maxf(fire_rate, 0.01)

func is_infinite_ammo() -> bool:
	return max_ammo < 0

## Coups tirés par déclenchement — un pour une arme simple, davantage pour
## une rafale. Sert au calcul des dégâts par seconde et au banc.
func coups_par_declenchement() -> int:
	if profil == null or profil.mode == "simple":
		return 1
	return maxi(1, profil.rafale_coups)

## Dégâts théoriques par seconde. C'est la mesure qui garantit qu'ajouter
## une identité de tir n'a pas déplacé l'équilibrage.
func dps() -> float:
	return damage * float(projectile_count) \
			* float(coups_par_declenchement()) * fire_rate
