extends Node
## POINT D'ENTRÉE — accueil, lancement et relance des parties.
##
## Le monde de jeu est CRÉÉ et DÉTRUIT à chaque partie plutôt que remis à
## zéro : c'est la seule façon fiable de garantir qu'aucun état résiduel
## (mob orphelin, tween en cours, projectile en vol) ne contamine la partie
## suivante. Une relance est donc toujours propre, par construction.

const AUTOSTART_SOLO := true

var world: GameWorld = null
var hud: HUD = null
var _menu: Control = null
var _debug: Node = null
var _last_mode: int = 0   # 0 = solo, 1 = hôte, 2 = client
## NEUF BOTS ET NON TROIS.
##
## Le nombre était écrit en dur à trois endroits — ici, au démarrage
## automatique et sur le bouton du menu. Relever le plafond du gestionnaire
## de réseau n'aurait donc rien changé : le jeu aurait continué à en lancer
## trois. Une valeur dupliquée est une valeur qui finit par diverger, alors
## elle est désormais unique et les trois endroits la lisent.
const BOTS_SOLO := 9

## DIX BOTS EN ARÈNE DE COMBAT, contre neuf dans le jeu.
##
## Le compte du jeu n'est pas touché : ce serait changer l'équilibre au
## prétexte d'un test. L'arène, elle, est un banc — on y veut exactement
## les onze corps demandés, dix bots plus le joueur local, pour que la
## densité observée soit celle qu'on a voulue et pas une de moins.
const BOTS_ARENE := 10

static func bots_solo() -> int:
	return BOTS_ARENE if Cfg.arene_test else BOTS_SOLO

var _last_bots: int = BOTS_SOLO   # remplacé au premier lancement

## Arguments de lancement, des DEUX côtés du séparateur `--`.
##
## POURQUOI CETTE FONCTION EXISTE : Godot répartit les arguments entre
## deux listes. Ce qui suit `--` va dans `get_cmdline_user_args()`, le
## reste dans `get_cmdline_args()`. On ne lisait que la seconde, si bien
## qu'un lancement de la forme
##
##     godot --path arena-rush --quit-after 900 -- --solo
##
## affichait le MENU au lieu de démarrer une partie, sans la moindre
## erreur. Une validation automatisée finissait donc au vert sans avoir
## rien joué. Ce faux succès a masqué un vrai bug pendant plusieurs
## vérifications — il est toujours plus dangereux qu'un échec.
func _arguments() -> PackedStringArray:
	var tout := OS.get_cmdline_args()
	tout.append_array(OS.get_cmdline_user_args())
	return tout


func _ready() -> void:
	add_to_group(&"main")
	var args := _arguments()
	# Argument de ligne de commande : permet de lancer une seconde instance
	# directement en client, sans passer par le menu à chaque test.
	if "--join" in args:
		_start(2, 0)
		return
	if "--host" in args:
		_start(1, 0)
		return
	# Démarrage direct en solo : sert aux tests automatisés et à relancer
	# une partie sans repasser par le menu pendant le développement.
	if "--solo" in args:
		_start(0, bots_solo())
		return
	_show_menu()

# --- MENU ----------------------------------------------------------------

func _show_menu() -> void:
	_clear_world()
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color("1b2436")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 16)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "ARENA RUSH"
	title.add_theme_font_size_override(&"font_size", 54)
	title.add_theme_color_override(&"font_color", Cfg.COL_LOCAL_PLAYER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	# LE MENU DÉCRIVAIT UN AUTRE JEU. « Restez le dernier » était la promesse
	# du Battle Royale ; l'arène est persistante depuis, on y revient toujours
	# et personne n'y gagne. Une accroche fausse est le premier mensonge que
	# le joueur lit, et il la lit avant même d'avoir joué.
	sub.text = "Un monde sans bord. Pillez, affrontez, recommencez."
	sub.add_theme_font_size_override(&"font_size", 22)
	sub.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_spacer(14))

	# ─── LE BANDEAU DE PROGRESSION ────────────────────────────────────
	#
	# La première chose qu'on voit en ouvrant le jeu : QUI l'on est
	# devenu. Niveau, barre d'XP vers le prochain, trésor d'or cumulé.
	# C'est la moitié de la promesse « le joueur a envie de progresser » :
	# la progression s'affiche AVANT de jouer, pas seulement pendant.
	box.add_child(_bandeau_progression())
	box.add_child(_spacer(16))

	# ─── LA PORTE DES CARTES ──────────────────────────────────────────
	#
	# Deux affiches côte à côte : l'île jouable, et la suivante —
	# verrouillée, silhouette sombre, cadenas d'or, « NIVEAU 10 ». On ne
	# cache pas la suite du jeu : on la fait désirer. C'est la structure
	# des grands du genre, dans notre thème.
	var cartes := HBoxContainer.new()
	cartes.alignment = BoxContainer.ALIGNMENT_CENTER
	cartes.add_theme_constant_override(&"separation", 18)
	var ile := CarteMonde.new()
	ile.titre = "L'ÎLE SANS BORD"
	ile.sous_titre = "NIVEAUX 1-10  ·  %d BOTS" % BOTS_SOLO
	ile.choisie.connect(func(): _lancer_monde())
	cartes.add_child(ile)
	var suivante := CarteMonde.new()
	suivante.verrouillee = true
	suivante.niveau_requis = 10
	# Le palier ATTEINT change le message : la carte n'existe pas encore,
	# on le dit honnêtement plutôt que de laisser un cadenas mensonger.
	if Profil.niveau_compte >= 10:
		suivante.sous_titre = "BIENTÔT DISPONIBLE"
	else:
		suivante.sous_titre = "MONTE EN NIVEAU POUR L'OUVRIR"
	cartes.add_child(suivante)
	box.add_child(cartes)
	box.add_child(_spacer(16))
	# ─── L'ARÈNE DOIT ÊTRE ATTEIGNABLE SANS LIGNE DE COMMANDE ───────────
	#
	# Elle n'existait que derrière `-- --arene-test`. Or le jeu se joue au
	# NAVIGATEUR, sur un téléphone : il n'y a pas de ligne de commande, et
	# l'arène était donc rigoureusement injouable là où elle devait
	# précisément être essayée. Un mode de test qu'on ne peut pas atteindre
	# depuis l'appareil du joueur ne teste rien.
	#
	# Le drapeau reste, pour les bancs automatiques ; le bouton le pose.
	# LIBELLÉ COURT : vérifié en navigateur au format téléphone, « ARÈNE DE
	# COMBAT — 10 BOTS + 10 MOBS » touchait les deux bords de son cadre.
	# Sur un écran plus étroit il aurait débordé.
	box.add_child(_menu_button("ARÈNE DE COMBAT", Cfg.COL_ENERGY,
			func(): _lancer_arene()))
	box.add_child(_menu_button("HÉBERGER UNE PARTIE", Cfg.COL_BASIC,
			func(): _start(1, 0)))
	box.add_child(_menu_button("REJOINDRE (127.0.0.1)", Cfg.COL_BASIC,
			func(): _start(2, 0)))

	var hint := Label.new()
	hint.text = "Clavier : ZQSD/WASD · Souris = viser · Clic = tirer · A = arme · Maj = esquive · F1 = debug"
	hint.add_theme_font_size_override(&"font_size", 15)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_spacer(20))
	box.add_child(hint)

## POSE LE DRAPEAU AVANT DE BÂTIR, et l'ordre est tout.
##
## `Arena._ready()` lit `Cfg.arene_test` une seule fois, au moment où elle
## se construit. Le poser après aurait donné une partie annoncée « arène »
## et bâtie « monde ouvert » — le genre d'incohérence qui se débogue une
## heure pour une ligne mal placée.
func _lancer_arene() -> void:
	Cfg.arene_test = true
	_start(0, BOTS_ARENE)


func _lancer_monde() -> void:
	Cfg.arene_test = false
	_start(0, BOTS_SOLO)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

## Niveau, barre d'XP, trésor — l'identité du joueur, dessinée en une
## ligne au-dessus des cartes.
func _bandeau_progression() -> Control:
	var ligne := HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	ligne.add_theme_constant_override(&"separation", 14)

	var niveau := Label.new()
	niveau.text = "NIVEAU %d" % Profil.niveau_compte
	niveau.add_theme_font_size_override(&"font_size", 24)
	niveau.add_theme_color_override(&"font_color", UiKit.OR_CLAIR)
	ligne.add_child(niveau)

	# La barre d'XP vers le prochain niveau.
	var etat: Dictionary = ConfigProgression.niveau_pour_xp(Profil.xp_compte)
	var barre := ProgressBar.new()
	barre.custom_minimum_size = Vector2(190, 16)
	barre.min_value = 0.0
	barre.max_value = 1.0
	barre.value = float(etat.get("xp_dans_niveau", 0)) \
			/ maxf(1.0, float(etat.get("xp_du_niveau", 1)))
	barre.show_percentage = false
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(0.06, 0.09, 0.17)
	fond.set_corner_radius_all(8)
	barre.add_theme_stylebox_override(&"background", fond)
	var plein := StyleBoxFlat.new()
	plein.bg_color = UiKit.OR_CLAIR
	plein.set_corner_radius_all(8)
	barre.add_theme_stylebox_override(&"fill", plein)
	var porte_barre := VBoxContainer.new()
	porte_barre.alignment = BoxContainer.ALIGNMENT_CENTER
	porte_barre.add_child(barre)
	ligne.add_child(porte_barre)

	# Le trésor : la pièce du classement et l'or cumulé.
	var piece := UiKit.PieceGlyphe.new()
	piece.custom_minimum_size = Vector2(18, 18)
	var porte_piece := VBoxContainer.new()
	porte_piece.alignment = BoxContainer.ALIGNMENT_CENTER
	porte_piece.add_child(piece)
	ligne.add_child(porte_piece)
	var tresor := Label.new()
	tresor.text = str(Profil.or_total)
	tresor.add_theme_font_size_override(&"font_size", 22)
	tresor.add_theme_color_override(&"font_color", UiKit.OR_CLAIR)
	ligne.add_child(tresor)
	return ligne


func _menu_button(text: String, color: Color, action: Callable) -> Control:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 56)
	b.add_theme_font_size_override(&"font_size", 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.22)
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = color
	b.add_theme_stylebox_override(&"normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(color.r, color.g, color.b, 0.45)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	b.pressed.connect(action)
	var center := CenterContainer.new()
	center.add_child(b)
	return center

# --- CYCLE DE PARTIE -----------------------------------------------------

func _start(mode: int, bots: int) -> void:
	_last_mode = mode
	_last_bots = bots
	match mode:
		0:
			Net.start_solo(bots)
			_build_world()
		1:
			if Net.host():
				_build_world()
		2:
			# Le client attend que le serveur lui envoie la liste des pairs
			# avant de construire quoi que ce soit : construire trop tôt
			# donnerait un monde vide et désynchronisé.
			if Net.join():
				Net.peer_list_changed.connect(_on_peers_ready,
						CONNECT_ONE_SHOT)

func _on_peers_ready() -> void:
	if world == null:
		_build_world()

func _build_world() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)

	world = GameWorld.new()
	world.name = "World"
	add_child(world)

	if OS.is_debug_build():
		_debug = preload("res://scripts/core/debug_panel.gd").new()
		_debug.name = "DebugPanel"
		add_child(_debug)

func _clear_world() -> void:
	for node in [world, hud, _debug]:
		if node and is_instance_valid(node):
			node.queue_free()
	world = null
	hud = null
	_debug = null
	Pool.clear()
	MatchDirector.reset()

## Relance avec les mêmes réglages — le bouton REJOUER de l'écran de fin.
func restart_match() -> void:
	_clear_world()
	# Une image d'attente laisse aux `queue_free()` le temps d'être traités
	# avant qu'on reconstruise des nœuds portant les mêmes noms.
	await get_tree().process_frame
	if _last_mode == 0:
		Net.start_solo(_last_bots)
	_build_world()

func back_to_lobby() -> void:
	Net.leave()
	_show_menu()
