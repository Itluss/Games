extends Node
## APERÇU DE L'INTERFACE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER EXISTE : une interface ne se juge pas au code. Les
## réglages qui la font vivre — épaisseur d'un anneau, force d'une ombre,
## inclinaison d'une lettre — n'ont aucun sens lus dans un fichier, et
## chacun d'eux peut ruiner l'ensemble sans qu'aucun test ne bronche.
##
## Le banc lance une vraie partie, la met dans un état DIGNE D'ÊTRE
## REGARDÉ — vie entamée, deux armes en main, une annonce à l'écran — et
## capture. Une capture d'interface au repos ne montrerait ni la barre
## partiellement vidée, ni la plaque d'élimination, c'est-à-dire
## précisément les pièces les plus délicates à régler.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/apercu_interface.tscn \
##       --rendering-driver opengl3 -- --solo

const LARGEUR := 1280
const HAUTEUR := 720

var _main: Node
var _large := LARGEUR
var _haut := HAUTEUR
var _suffixe := ""
var _propre := false

func _ready() -> void:
	# FORMAT RÉGLABLE, PARCE QUE LA CIBLE N'EST PAS UN ÉCRAN DE BUREAU.
	# La consigne demande de vérifier en 844×390 ET sur tablette. Juger
	# une composition en 16/9 de bureau donne une image plus haute et plus
	# large que celle du joueur : tout y tient, et rien ne prouve que ça
	# tienne ailleurs.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--large="):
			_large = int(a.substr(8))
		elif a.begins_with("--haut="):
			_haut = int(a.substr(7))
		elif a.begins_with("--nom="):
			_suffixe = a.substr(6)
		elif a == "--propre":
			_propre = true
	get_window().size = Vector2i(_large, _haut)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	await _mettre_en_scene()
	await _capturer()
	get_tree().quit()


func _joueur() -> Node:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			return p
	return null


## Compose la situation à photographier. Rien ici ne doit ressembler à un
## état de repos : c'est en plein combat que l'interface doit tenir.
func _mettre_en_scene() -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	var j := _joueur()
	if j == null or hud == null:
		push_error("Ni joueur ni interface : la scène n'est pas montée.")
		return

	# Une deuxième arme, pour que les deux cartes soient remplies et qu'on
	# voie la différence entre la carte active et l'autre.
	j.server_pickup(&"shotgun")
	await get_tree().process_frame

	# DES GERBES DE PARTICULES, et plusieurs de suite : c'est le RECYCLAGE
	# qu'on vérifie. Un nœud de particules réutilisé sans être correctement
	# relancé n'émet rien du tout, et le défaut ne se voit que sur la
	# deuxième gerbe — jamais sur la première.
	for k in 5:
		Fx.hit(j.global_position + Vector3(2.0 + float(k) * 1.1, 0.8, -1.0),
				Cfg.COL_SHOTGUN, 1.0)
	Fx.death(j.global_position + Vector3(-3.0, 0.2, -2.5), Cfg.COL_MOB_CHARGER)
	await get_tree().process_frame
	await get_tree().process_frame

	# DEUX GAINS D'XP FLOTTANTS, à deux distances. Un chiffre posé dans le
	# monde n'a pas de taille fixe à l'écran : celui qui est lisible à trois
	# mètres peut être illisible à douze, et seule une capture le dit.
	Fx.gain_xp(j.global_position + Vector3(3.0, 1.5, -1.5), 5)
	Fx.gain_xp(j.global_position + Vector3(-4.5, 1.5, -5.5), 20)
	await get_tree().process_frame

	# Vie entamée : une barre pleine ne dit rien de la jauge ni du dégradé.
	var pv = j.get(&"health")
	if pv != null:
		pv.apply_damage(31.0, j.global_position)
	await get_tree().process_frame

	# Une session déjà entamée : sept kills, une série de trois. C'est
	# l'état dans lequel le joueur passe l'essentiel de son temps, donc
	# celui qu'il faut juger.
	Profil.effacer()
	for i in 7:
		Profil.enregistrer_kill_joueur(&"basic_blaster")
	Profil.serie_actuelle = 3
	var bilan := {"xp": 150, "serie": 3,
			"palier": ConfigProgression.PALIERS_SERIE[0]}
	if hud.has_method(&"_rafraichir_progression"):
		hud.call(&"_rafraichir_progression")
	# LA CÉLÉBRATION EST OPTIONNELLE. Elle occupe le centre de l'écran et
	# masque exactement la zone où l'on veut juger l'étoile et les plaques
	# de nom. `--propre` la coupe.
	if hud.has_method(&"_on_elimination_reussie") and not _propre:
		hud.call(&"_on_elimination_reussie", "BOT 3", bilan)
	# On laisse la plaque finir son arrivée : capturée en cours
	# d'animation, elle paraîtrait mal centrée ou trop petite.
	await get_tree().create_timer(0.45).timeout

	# ─── L'ÉTOILE EST DANS LES MAINS D'UN ADVERSAIRE ──────────────────
	#
	# C'est l'état B de la barre WANTED, et c'est celui qui a le plus de
	# choses à rater : nom du porteur dans sa couleur, jauge à mi-course,
	# chiffre, étoile au-dessus de sa tête, repère sur la carte. L'état A
	# — « ÉTOILE DISPONIBLE » — n'a rien à afficher, donc rien à vérifier.
	_mettre_en_scene_etoile()
	await get_tree().process_frame

	# Bouton de tir MAINTENU : l'état enfoncé est celui que le joueur voit
	# la moitié du temps, et c'est celui qu'on oublie de vérifier.
	if hud.has_method(&"_marquer_tir"):
		hud.call(&"_marquer_tir", true)
	for i in 3:
		await get_tree().process_frame


func _capturer() -> void:
	var dossier := ProjectSettings.globalize_path("user://apercu")
	DirAccess.make_dir_recursive_absolute(dossier)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nom := dossier + "/interface%s.png" % _suffixe
	img.save_png(nom)
	print("→ ", nom)


## Donne l'étoile à un adversaire proche et garnit le classement.
##
## ON PASSE PAR LE DIRECTEUR, pas par les champs des joueurs : c'est le
## chemin réel du jeu, et l'aperçu doit photographier ce que le jeu produit,
## pas une mise en scène qui lui ressemble.
func _mettre_en_scene_etoile() -> void:
	await get_tree().process_frame
	var moi := _joueur()
	var cible: Node = null
	for p in get_tree().get_nodes_in_group(&"players"):
		if p != moi:
			cible = p
			break
	if cible == null:
		return
	# LE PORTEUR EST AMENÉ DANS LE CADRE. Un bot parti à trente mètres ne
	# montre ni son étoile ni sa plaque de nom, et c'est précisément ce
	# qu'on veut juger.
	if moi != null:
		cible.global_position = moi.global_position + Vector3(-3.8, 0.0, 0.6)
	# Des scores plausibles, pour que le classement ait quatre lignes
	# remplies et des chiffres de largeurs différentes.
	var scores := [12, 7, 4, 2]
	var etoiles := [2, 1, 0, 0]
	var i := 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if i >= scores.size():
			break
		p.set(&"kills", scores[i])
		p.set(&"star_wins", etoiles[i])
		i += 1
	# L'ÉTOILE AU SOL EST POSÉE DEVANT LE JOUEUR, en plus de celle que
	# porte l'adversaire. Deux objets différents à juger sur la même
	# image : le socle et la maille dorée dans le décor, et l'étoile
	# billboard au-dessus d'une tête. On ne peut pas régler la taille de
	# l'un sans voir l'autre.
	if moi != null:
		var devant: Vector3 = moi.global_position + Vector3(3.4, 0.0, -2.2)
		EtoileDirector.net_poser(Vector3(devant.x, 0.0, devant.z))
		await get_tree().process_frame
	EtoileDirector.net_ramasser(cible.get(&"peer_id"))
	# Le corps posé juste avant est consommé par le ramassage ; on en
	# repose un pour la photo, sans toucher à l'état logique.
	if moi != null:
		var devant2: Vector3 = moi.global_position + Vector3(3.4, 0.0, -2.2)
		EtoileDirector._creer_corps(Vector3(devant2.x, 0.0, devant2.z))
		await get_tree().process_frame
	# Dix-huit secondes sur trente : la jauge est à mi-course, ce qui est
	# le seul endroit où l'on voit à la fois le remplissage et le vide.
	EtoileDirector.temps = 18.0
