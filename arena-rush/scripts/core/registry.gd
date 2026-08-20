extends Node
## CATALOGUE DE CONTENU — résout un identifiant vers sa ressource.
##
## POURQUOI CETTE INDIRECTION : sur le réseau on ne transmet jamais un
## objet ni un chemin de fichier, seulement un `StringName` court. Le
## serveur dit « arme shotgun » et chaque client résout localement. Cela
## rend les messages minuscules et empêche un client de faire charger un
## chemin arbitraire au moteur.
##
## Autoload : Registry

const WEAPON_DIR := "res://resources/weapons/"
const MOB_DIR := "res://resources/mobs/"

var weapons: Dictionary = {}   # StringName -> WeaponData
var mobs: Dictionary = {}      # StringName -> MobData

## Ordre de puissance croissante — utilisé par les vagues pour distribuer
## un butin de plus en plus fort à mesure que la partie monte en tension.
var weapon_tiers: Array[StringName] = []

func _ready() -> void:
	_load_dir(WEAPON_DIR, weapons)
	_load_dir(MOB_DIR, mobs)
	_build_tiers()

func _load_dir(path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Registry : dossier introuvable — " + path)
		return
	for file in dir.get_files():
		# À l'export, les .tres sont convertis en .remap : on normalise.
		var clean := file.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := ResourceLoader.load(path + clean)
		if res == null or not (&"id" in res):
			push_error("Registry : ressource illisible — " + clean)
			continue
		if String(res.id).is_empty():
			push_error("Registry : id vide dans " + clean)
			continue
		into[res.id] = res

## LES ARMES DE POING SIGNATURE NE TOMBENT JAMAIS AU SOL.
##
## Elles appartiennent à un héros et le suivent. Les laisser entrer dans
## la table du butin donnerait le revolver de Milo à Bruno — et l'identité
## de tir, qui est tout l'objet de cette passe, ne voudrait plus rien dire.
func _est_signature(id: StringName) -> bool:
	return String(id).begins_with("arme_")


func _build_tiers() -> void:
	var ids := weapons.keys().filter(func(id): return not _est_signature(id))
	ids.sort_custom(func(a, b):
		var wa: WeaponData = weapons[a]
		var wb: WeaponData = weapons[b]
		# Le DPS brut suffit à ordonner un prototype ; l'ordre ne sert
		# qu'à doser la montée en puissance, pas à équilibrer finement.
		return wa.damage * wa.fire_rate * wa.projectile_count \
				< wb.damage * wb.fire_rate * wb.projectile_count)
	weapon_tiers.clear()
	for id in ids:
		weapon_tiers.append(id)

func weapon(id: StringName) -> WeaponData:
	return weapons.get(id)

func mob(id: StringName) -> MobData:
	return mobs.get(id)

## L'ARME DE DÉPART DÉPEND DU HÉROS.
##
## C'est le seul point de branchement dont l'identité de tir avait besoin :
## avant, `starting_weapon()` rendait la même arme aux six personnages, et
## le tir de Milo était donc exactement celui de Bruno. Le butin, lui, ne
## change pas — un héros qui ramasse un fusil à pompe tire au fusil à
## pompe, et c'est très bien : il a fait un choix.
func arme_de_heros(heros: StringName) -> WeaponData:
	var trouvee := weapon(StringName("arme_%s" % heros))
	return trouvee if trouvee != null else starting_weapon()


func starting_weapon() -> WeaponData:
	return weapon(&"basic_blaster")

## Arme aléatoire dont la puissance suit l'avancée de la partie.
## `pressure` va de 0 (début) à 1 (fin de partie).
func weapon_for_pressure(pressure: float) -> StringName:
	if weapon_tiers.is_empty():
		return &""
	var top := int(round(lerpf(1.0, float(weapon_tiers.size() - 1),
			clampf(pressure, 0.0, 1.0))))
	return weapon_tiers[randi_range(1, maxi(1, top))] if weapon_tiers.size() > 1 \
			else weapon_tiers[0]
