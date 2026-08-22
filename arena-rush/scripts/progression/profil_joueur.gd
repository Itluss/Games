extends Node
## PROFIL DU JOUEUR — progression permanente, séparée de la partie en cours.
##
## Autoload : Profil
##
## POURQUOI CE NŒUD N'EST PAS DANS LE PERSONNAGE. Un personnage naît et
## meurt vingt fois par session ; la progression, elle, doit survivre à sa
## mort, à la fin de la partie, et à la fermeture du jeu. Les coudre
## ensemble, c'est garantir de perdre l'une en nettoyant l'autre.
##
## POURQUOI IL NE DONNE AUCUN BONUS. Aucune valeur d'ici n'est lue par le
## calcul de dégâts ou de points de vie, et c'est un choix explicite : un
## joueur de niveau 50 ne doit pas écraser un débutant. La progression est
## HORIZONTALE — elle débloquera des personnages, des armes, des skins, des
## titres. Le talent reste ce qui décide d'un duel.
##
## POURQUOI LA SAUVEGARDE EST ISOLÉE DERRIÈRE DEUX FONCTIONS. `charger()`
## et `enregistrer()` sont les SEULS points de contact avec le stockage.
## Le jour où un serveur remplacera le fichier local, il n'y aura que ces
## deux corps à réécrire — rien dans le reste du jeu ne sait où vivent ces
## données.

signal xp_gagnee(montant: int, raison: StringName)
signal niveau_gagne(niveau: int)
signal statistiques_changees()

const FICHIER := "user://profil.json"
## VERSION DE FORMAT. Elle ne sert à rien aujourd'hui, et c'est exactement
## pourquoi il faut l'écrire maintenant : le jour où le format changera, les
## sauvegardes déjà sur les téléphones porteront leur numéro, et on saura
## quoi migrer. L'ajouter après coup est impossible.
const VERSION := 1

# --- COMPTE --------------------------------------------------------------
var xp_compte: int = 0
var niveau_compte: int = 1

# --- STATISTIQUES DE COMBAT ---------------------------------------------
var total_kills_joueurs: int = 0
var total_morts: int = 0
var total_kills_mobs: int = 0
var meilleure_serie: int = 0
var temps_de_jeu: float = 0.0
## LE TRÉSOR — l'or ramassé sur toutes les sessions, jamais perdu. C'est
## la brique de la progression durable : les pièces de la Prime meurent
## avec la vie, le trésor, lui, ne fait que grossir.
var or_total: int = 0

## Série EN COURS. Elle n'est pas sauvegardée : une série est un état de
## session, et la retrouver intacte après avoir quitté le jeu la viderait
## de son sens.
var serie_actuelle: int = 0

## Statistiques de la SESSION, remises à zéro à chaque lancement. Le HUD
## affiche celles-ci — « 7 kills » veut dire quelque chose maintenant,
## « 4 213 kills » ne veut plus rien dire.
var kills_session: int = 0
var morts_session: int = 0

# --- MAÎTRISES -----------------------------------------------------------
#
# Même structure pour les personnages et les armes, parce que c'est la même
# idée : une chose qu'on utilise progresse. Les fusionner en un seul
# dictionnaire aurait mélangé deux espaces de noms qui peuvent entrer en
# collision.
var personnages: Dictionary = {}   # id -> Dictionary
var armes: Dictionary = {}         # id -> Dictionary

# --- PRESTIGE ------------------------------------------------------------
#
# Ce que le joueur PORTE. Stocké et non recalculé : à terme il choisira
# parmi ce qu'il a débloqué, et un titre déduit du niveau ne le permettrait
# pas.
var titre_equipe: String = "ROOKIE"
var badge_equipe: StringName = &""
var cadre_equipe: StringName = &""
var effet_apparition: StringName = &""
var effet_elimination: StringName = &""

var _accumulateur_temps: float = 0.0


func _ready() -> void:
	charger()
	set_process(true)


func _process(delta: float) -> void:
	temps_de_jeu += delta
	# L'XP de temps est versée par MINUTE et non par image : mille
	# micro-gains rendraient le journal illisible et feraient clignoter le
	# HUD en permanence.
	_accumulateur_temps += delta
	if _accumulateur_temps >= 60.0:
		_accumulateur_temps -= 60.0
		ajouter_xp(ConfigProgression.XP_PAR_MINUTE, &"temps")


# --- ENTRÉES DE JEU ------------------------------------------------------

## Un joueur en a tué un autre. C'est l'évènement central du jeu.
func enregistrer_kill_joueur(arme_id: StringName,
		personnage_id: StringName = &"kael") -> Dictionary:
	total_kills_joueurs += 1
	kills_session += 1
	serie_actuelle += 1
	meilleure_serie = maxi(meilleure_serie, serie_actuelle)

	var gagne := ConfigProgression.XP_JOUEUR
	# Le palier de série se paie EN PLUS du kill, et une seule fois : c'est
	# une récompense d'exploit, pas une rente.
	var palier := palier_atteint(serie_actuelle)
	if not palier.is_empty():
		gagne += ConfigProgression.XP_BONUS_SERIE

	ajouter_xp(gagne, &"kill_joueur")
	_maitrise(armes, arme_id, gagne, true)
	_maitrise(personnages, personnage_id, gagne, true)
	statistiques_changees.emit()
	return {"xp": gagne, "serie": serie_actuelle, "palier": palier}


func enregistrer_kill_mob(categorie: StringName,
		arme_id: StringName = &"") -> int:
	total_kills_mobs += 1
	var gagne: int = ConfigProgression.XP_PAR_CATEGORIE.get(
			categorie, ConfigProgression.XP_MOB_COMMUN)
	ajouter_xp(gagne, &"kill_mob")
	if arme_id != &"":
		_maitrise(armes, arme_id, gagne, false)
	statistiques_changees.emit()
	return gagne


## La mort ne coûte pas d'XP — seulement la série. Retirer de l'expérience
## à quelqu'un qui vient de perdre un duel, c'est le punir deux fois.
func enregistrer_mort() -> void:
	total_morts += 1
	morts_session += 1
	serie_actuelle = 0
	statistiques_changees.emit()


func ajouter_xp(montant: int, raison: StringName) -> void:
	if montant <= 0:
		return
	var avant := niveau_compte
	xp_compte += montant
	var etat := ConfigProgression.niveau_pour_xp(xp_compte)
	niveau_compte = int(etat["niveau"])
	xp_gagnee.emit(montant, raison)
	if niveau_compte > avant:
		# Le titre suit le niveau TANT QUE le joueur n'en a pas choisi un :
		# le prototype n'offre pas encore ce choix, mais le champ existe
		# déjà, donc la bascule future ne cassera rien.
		titre_equipe = String(
				ConfigProgression.titre_pour_niveau(niveau_compte)["titre"])
		niveau_gagne.emit(niveau_compte)
		enregistrer()


## Progression dans le niveau courant, prête à afficher.
func etat_niveau() -> Dictionary:
	return ConfigProgression.niveau_pour_xp(xp_compte)


func panier_matchmaking() -> StringName:
	return ConfigProgression.panier_pour_niveau(niveau_compte)


## Le palier de série atteint EXACTEMENT à ce compte, sinon un dictionnaire
## vide. On teste l'égalité et non le dépassement : sans cela « ON FIRE »
## se réafficherait à chaque kill au-delà de trois.
func palier_atteint(serie: int) -> Dictionary:
	for p: Dictionary in ConfigProgression.PALIERS_SERIE:
		if int(p["seuil"]) == serie:
			return p
	return {}


# --- MAÎTRISES -----------------------------------------------------------

func _maitrise(table: Dictionary, id: StringName, xp: int,
		kill_joueur: bool) -> void:
	if id == &"":
		return
	var cle := String(id)
	if not table.has(cle):
		table[cle] = {"xp": 0, "niveau": 1, "kills": 0, "temps": 0.0,
				"meilleure_serie": 0}
	var e: Dictionary = table[cle]
	e["xp"] = int(e["xp"]) + xp
	e["niveau"] = ConfigProgression.niveau_de_maitrise(int(e["xp"]))
	if kill_joueur:
		e["kills"] = int(e["kills"]) + 1
		e["meilleure_serie"] = maxi(int(e["meilleure_serie"]), serie_actuelle)


func maitrise_personnage(id: StringName) -> Dictionary:
	return personnages.get(String(id),
			{"xp": 0, "niveau": 1, "kills": 0, "temps": 0.0,
			"meilleure_serie": 0})


func maitrise_arme(id: StringName) -> Dictionary:
	return armes.get(String(id),
			{"xp": 0, "niveau": 1, "kills": 0, "temps": 0.0,
			"meilleure_serie": 0})


# --- STOCKAGE ------------------------------------------------------------
#
# LES DEUX SEULES FONCTIONS QUI SAVENT OÙ VIVENT LES DONNÉES.

func _vers_dictionnaire() -> Dictionary:
	return {
		"version": VERSION,
		"account_xp": xp_compte,
		"account_level": niveau_compte,
		"total_player_kills": total_kills_joueurs,
		"total_deaths": total_morts,
		"total_mob_kills": total_kills_mobs,
		"best_kill_streak": meilleure_serie,
		"total_play_time": temps_de_jeu,
		"gold_total": or_total,
		"title": titre_equipe,
		"badge": String(badge_equipe),
		"frame": String(cadre_equipe),
		"spawn_fx": String(effet_apparition),
		"kill_fx": String(effet_elimination),
		"characters": personnages,
		"weapons": armes,
	}


## Une pièce d'or ramassée entre dans le trésor — et y reste. La
## sauvegarde est immédiate : sur le web, l'onglet peut se fermer sans
## préavis, et un trésor perdu est la pire trahison d'un jeu de
## collection.
func ajouter_or(montant: int) -> void:
	if montant <= 0:
		return
	or_total += montant
	enregistrer()


func enregistrer() -> void:
	var f := FileAccess.open(FICHIER, FileAccess.WRITE)
	if f == null:
		push_warning("Profil non enregistré : %s inaccessible." % FICHIER)
		return
	f.store_string(JSON.stringify(_vers_dictionnaire(), "  "))
	# FERMETURE EXPLICITE, et non par ramassage de la référence. Sur l'export
	# web, `user://` vit dans IndexedDB et n'est réellement écrit qu'à la
	# fermeture du fichier : sans elle, une sauvegarde peut ne jamais
	# atteindre le disque, et le joueur perdrait sa session en fermant
	# l'onglet.
	f.close()


func charger() -> void:
	if not FileAccess.file_exists(FICHIER):
		return
	var f := FileAccess.open(FICHIER, FileAccess.READ)
	if f == null:
		return
	var brut := f.get_as_text()
	f.close()
	var donnees = JSON.parse_string(brut)
	if typeof(donnees) != TYPE_DICTIONARY:
		# Un fichier corrompu ne doit pas empêcher de jouer : on repart d'un
		# profil neuf plutôt que de planter au lancement.
		push_warning("Profil illisible — un profil neuf est utilisé.")
		return
	var d: Dictionary = donnees
	var version := int(d.get("version", 0))
	if version > VERSION:
		# Un profil venu d'une version PLUS RÉCENTE du jeu : on n'y touche
		# pas, on l'ignore. L'écraser détruirait la progression du joueur
		# s'il repasse ensuite sur la version récente.
		push_warning("Profil en version %d, plus récente que %d — ignoré."
				% [version, VERSION])
		return

	xp_compte = int(d.get("account_xp", 0))
	total_kills_joueurs = int(d.get("total_player_kills", 0))
	total_morts = int(d.get("total_deaths", 0))
	total_kills_mobs = int(d.get("total_mob_kills", 0))
	meilleure_serie = int(d.get("best_kill_streak", 0))
	temps_de_jeu = float(d.get("total_play_time", 0.0))
	or_total = int(d.get("gold_total", 0))
	titre_equipe = String(d.get("title", "ROOKIE"))
	badge_equipe = StringName(d.get("badge", ""))
	cadre_equipe = StringName(d.get("frame", ""))
	effet_apparition = StringName(d.get("spawn_fx", ""))
	effet_elimination = StringName(d.get("kill_fx", ""))
	personnages = d.get("characters", {})
	armes = d.get("weapons", {})
	# Le niveau est RECALCULÉ depuis l'XP plutôt que relu : si la courbe
	# change entre deux versions, le niveau enregistré serait faux, et
	# l'XP, elle, reste vraie.
	niveau_compte = int(ConfigProgression.niveau_pour_xp(xp_compte)["niveau"])


## Efface le profil. Réservé au développement et à un futur bouton de
## réinitialisation ; jamais appelé par le jeu.
func effacer() -> void:
	if FileAccess.file_exists(FICHIER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FICHIER))
	xp_compte = 0
	niveau_compte = 1
	total_kills_joueurs = 0
	total_morts = 0
	total_kills_mobs = 0
	meilleure_serie = 0
	temps_de_jeu = 0.0
	serie_actuelle = 0
	kills_session = 0
	morts_session = 0
	personnages.clear()
	armes.clear()
	titre_equipe = "ROOKIE"
	statistiques_changees.emit()
