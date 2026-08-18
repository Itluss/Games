extends Node
## TEST DE LA PROGRESSION — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER : une sauvegarde qui ne survit pas au redémarrage est
## un défaut INVISIBLE en jouant — tout paraît fonctionner, et la perte ne
## se découvre qu'à la session suivante, quand il est trop tard pour la
## joueuse. C'est exactement le genre de chose qu'un test doit attraper.
##
## Le test s'exécute en DEUX PASSES, pilotées par un argument :
##   --ecrire  : profil neuf, on joue, on enregistre
##   --relire  : on relit et on vérifie que tout est là
## Deux processus distincts, donc une vraie preuve de persistance — vérifier
## dans le même processus ne prouverait que le contenu de la mémoire.

var _echecs := 0
var _total := 0

func _ready() -> void:
	var args := _arguments()
	if args.has("--ecrire"):
		_passe_ecriture()
	elif args.has("--relire"):
		_passe_relecture()
	else:
		_passe_calculs()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


## Godot sépare ses propres arguments de ceux placés après « -- » : lire les
## uns sans les autres avait déjà produit une validation faussement verte
## sur ce projet.
func _arguments() -> PackedStringArray:
	var a := OS.get_cmdline_args()
	a.append_array(OS.get_cmdline_user_args())
	return a


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-50s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _verifier_vrai(libelle: String, condition: bool) -> void:
	_verifier(libelle, condition, true)


# --- PASSE 1 : on joue, on enregistre -----------------------------------

func _passe_ecriture() -> void:
	print("=== PASSE ÉCRITURE ===")
	Profil.effacer()
	_verifier("profil neuf : niveau 1", Profil.niveau_compte, 1)
	_verifier("profil neuf : 0 kill", Profil.total_kills_joueurs, 0)

	# Trois éliminations de joueurs : la troisième doit déclencher un palier.
	var r1 := Profil.enregistrer_kill_joueur(&"basic_blaster")
	var r2 := Profil.enregistrer_kill_joueur(&"basic_blaster")
	var r3 := Profil.enregistrer_kill_joueur(&"shotgun")
	_verifier("kill 1 rapporte l'XP de base", int(r1["xp"]),
			ConfigProgression.XP_JOUEUR)
	_verifier("kill 2 : aucun palier", (r2["palier"] as Dictionary).is_empty(), true)
	_verifier("kill 3 : palier ON FIRE", String((r3["palier"] as Dictionary).get("texte", "")), "ON FIRE")
	_verifier("kill 3 : prime de série versée", int(r3["xp"]),
			ConfigProgression.XP_JOUEUR + ConfigProgression.XP_BONUS_SERIE)
	_verifier("série en cours", Profil.serie_actuelle, 3)

	Profil.enregistrer_kill_mob(&"commun")
	Profil.enregistrer_kill_mob(&"elite")
	_verifier("2 mobs comptés", Profil.total_kills_mobs, 2)

	# La mort casse la série mais ne retire aucune expérience.
	var xp_avant: int = Profil.xp_compte
	Profil.enregistrer_mort()
	_verifier("la mort remet la série à zéro", Profil.serie_actuelle, 0)
	_verifier("la mort ne coûte pas d'XP", Profil.xp_compte, xp_avant)
	_verifier("la meilleure série est retenue", Profil.meilleure_serie, 3)

	_verifier_vrai("la maîtrise de l'arme a monté",
			int(Profil.maitrise_arme(&"basic_blaster")["kills"]) == 2)

	Profil.enregistrer()
	print("  XP enregistrée : %d · niveau %d" % [Profil.xp_compte, Profil.niveau_compte])


# --- PASSE 2 : autre processus, on relit --------------------------------

func _passe_relecture() -> void:
	print("=== PASSE RELECTURE (nouveau processus) ===")
	# L'autoload a déjà chargé le fichier à son _ready.
	_verifier("kills joueurs conservés", Profil.total_kills_joueurs, 3)
	_verifier("morts conservées", Profil.total_morts, 1)
	_verifier("kills de mobs conservés", Profil.total_kills_mobs, 2)
	_verifier("meilleure série conservée", Profil.meilleure_serie, 3)
	_verifier_vrai("XP conservée", Profil.xp_compte > 0)
	_verifier_vrai("niveau recalculé depuis l'XP", Profil.niveau_compte >= 1)
	_verifier("maîtrise d'arme conservée",
			int(Profil.maitrise_arme(&"basic_blaster")["kills"]), 2)
	_verifier_vrai("maîtrise de personnage conservée",
			int(Profil.maitrise_personnage(&"kael")["kills"]) == 3)
	# La série EN COURS ne doit surtout pas survivre : c'est un état de
	# session, pas une statistique.
	_verifier("la série en cours ne survit pas", Profil.serie_actuelle, 0)
	_verifier("les kills de session repartent à zéro", Profil.kills_session, 0)
	print("  Relu : %d XP · niveau %d · titre %s"
			% [Profil.xp_compte, Profil.niveau_compte, Profil.titre_equipe])


# --- PASSE 0 : la courbe de niveaux -------------------------------------

func _passe_calculs() -> void:
	print("=== COURBE DE PROGRESSION ===")
	_verifier_vrai("le niveau 1 demande peu",
			ConfigProgression.xp_pour_passer_le_niveau(1) <= 200)
	_verifier_vrai("la courbe est croissante",
			ConfigProgression.xp_pour_passer_le_niveau(30)
			> ConfigProgression.xp_pour_passer_le_niveau(10))
	# Le plafond doit être ATTEIGNABLE : une courbe qui explose rend les
	# hauts niveaux décoratifs, donc inutiles.
	var total := ConfigProgression.xp_cumulee_pour_niveau(
			ConfigProgression.NIVEAU_MAX)
	var kills := total / ConfigProgression.XP_JOUEUR
	print("  Niveau %d : %d XP cumulés, soit ~%d éliminations."
			% [ConfigProgression.NIVEAU_MAX, total, kills])
	_verifier_vrai("le niveau 50 reste atteignable (< 25 000 kills)",
			kills < 25000)
	_verifier("aucun dépassement du plafond",
			int(ConfigProgression.niveau_pour_xp(total * 10)["niveau"]),
			ConfigProgression.NIVEAU_MAX)
	# Un aller-retour XP → niveau → XP doit être cohérent.
	for n in [2, 7, 20, 45]:
		var cumul := ConfigProgression.xp_cumulee_pour_niveau(n)
		_verifier("niveau retrouvé depuis %d XP cumulés" % cumul,
				int(ConfigProgression.niveau_pour_xp(cumul)["niveau"]), n)
	print("  Titre au niveau 1 : %s · au niveau 30 : %s"
			% [ConfigProgression.titre_pour_niveau(1)["titre"],
			ConfigProgression.titre_pour_niveau(30)["titre"]])
	_verifier("panier d'un débutant",
			ConfigProgression.panier_pour_niveau(1), &"rookie")
	_verifier("panier d'un vétéran",
			ConfigProgression.panier_pour_niveau(30), &"veteran")
