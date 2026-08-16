extends Node
## CONFIGURATION GLOBALE — constantes partagées et réglages de qualité.
##
## Tout ce qui est « vrai partout » vit ici : couches physiques, palette,
## équilibrage de haut niveau. Aucun autre script ne doit redéfinir une
## couche de collision ou une couleur d'équipe dans son coin : une valeur
## dupliquée est une valeur qui finira par diverger.
##
## Autoload : Cfg

# --- COUCHES PHYSIQUES ---------------------------------------------------
# Masques de bits (couche 1 = 1, couche 2 = 2, couche 3 = 4, ...).
# Les projectiles n'ont volontairement PAS de couche commune avec leur
# tireur : c'est ce qui empêche de se blesser soi-même sans le moindre
# test à l'exécution.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MOB := 4
const LAYER_PROJECTILE := 8
const LAYER_PICKUP := 16

# --- ÉQUIPES -------------------------------------------------------------
enum Team { PLAYER, MOB }

# --- PALETTE -------------------------------------------------------------
# Direction artistique : cartoon premium, couleurs franches, ambiance
# chaude. Les teintes vives sont réservées au GAMEPLAY (projectiles, loot,
# télégraphes) ; le décor reste plus sourd pour ne jamais concurrencer la
# lisibilité du combat.
const COL_SAND := Color("e3b374")
const COL_SAND_DARK := Color("c08a45")
const COL_ROCK := Color("b0603a")
const COL_ROCK_DARK := Color("8a4526")
const COL_GRASS := Color("6cc24a")
const COL_SKY_TOP := Color("2f7fd6")
const COL_SKY_HORIZON := Color("ffdca8")
const COL_SUN := Color("fff2d6")

# Couleurs d'identité — une arme se reconnaît à sa couleur avant même
# qu'on lise son nom.
const COL_BASIC := Color("7fd4ff")
const COL_SHOTGUN := Color("ffb347")
const COL_ENERGY := Color("b06bff")
const COL_GRENADE := Color("6bff9e")

const COL_MOB_CHARGER := Color("ff6b5a")
const COL_MOB_SHOOTER := Color("5ad2ff")
const COL_MOB_EXPLODER := Color("ffd75a")

const COL_DANGER := Color("ff3b30")
const COL_HEAL := Color("4cd964")
const COL_LOCAL_PLAYER := Color("4ce0b3")
const COL_ENEMY_PLAYER := Color("ff5a8a")

# --- ARÈNE ---------------------------------------------------------------
const ARENA_RADIUS := 34.0

# --- QUALITÉ -------------------------------------------------------------
## Un seul curseur, lu par les systèmes coûteux (particules, ombres,
## décalcomanies). Baisser la qualité ne doit JAMAIS changer le gameplay,
## uniquement son habillage.
enum Quality { LOW, MEDIUM, HIGH }
var quality: Quality = Quality.HIGH

## Multiplicateur appliqué aux quantités de particules.
func fx_scale() -> float:
	match quality:
		Quality.LOW:
			return 0.35
		Quality.MEDIUM:
			return 0.7
		_:
			return 1.0

## Les ombres dynamiques sont le premier poste à sacrifier sur mobile.
func shadows_enabled() -> bool:
	return quality != Quality.LOW

## Détecte une plateforme tactile pour adapter l'interface sans deviner.
func is_touch_platform() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _ready() -> void:
	# Sur mobile, on part en qualité moyenne : mieux vaut 60 FPS stables
	# qu'un premier lancement à 30 dont le joueur ne reviendra pas.
	if OS.has_feature("mobile"):
		quality = Quality.MEDIUM
	Engine.max_fps = 60
