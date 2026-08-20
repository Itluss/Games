extends CanvasLayer
class_name HUD
## INTERFACE DE JEU — minimaliste, tactile, adaptée à tous les ratios.
##
## PRINCIPE : n'afficher que ce qui change une décision. Vies restantes,
## santé, arme active, temps. Rien d'autre — chaque élément superflu vole
## de la place à un écran de téléphone et de l'attention au combat.
##
## ADAPTATION AUX ÉCRANS : tout est ancré aux COINS via des marges, jamais
## positionné en absolu. Un iPhone très allongé et un iPad presque carré
## gardent donc des commandes sous les pouces, au même écart des bords.
##
## RÉPARTITION DES POUCES : le gauche DIRIGE, le droit TIRE. Le joystick
## de gauche ne sert qu'au déplacement, et le tir est un bouton que l'on
## maintient. La visée est automatique et accroche l'ennemi le plus
## proche — viser au doigt une cible mobile n'amuse personne.

const MARGIN := 26
const STICK_SIZE := 210
const FIRE_SIZE := 168
const ESQUIVE_SIZE := 104
## Diamètre du loader d'étoile, en pixels.
const LOADER_SIZE := 96

var player: Player = null

var _root: Control
var _move_stick: VirtualJoystick
var _fire_button: UiKit.BoutonRond
## Gâchette maintenue. Un booléen et non un compteur d'appuis : les armes
## automatiques se tiennent, elles ne se tapotent pas.
var _fire_held: bool = false
## Appui NEUF, à usage unique. Distinct de la gâchette maintenue : c'est
## lui qui autorise le tir accéléré au tapotement.
var _fire_tapped: bool = false
## Index du DOIGT qui tient le bouton de tir, -1 si aucun.
##
## POURQUOI UNE VOIE TACTILE SÉPARÉE : Godot fusionne le tactile en une
## souris unique, et un Button n'écoute que celle-ci. Or le joystick de
## déplacement, lui, suit son propre doigt. Dès qu'un doigt tenait le
## joystick — c'est-à-dire dès qu'on COURAIT — la souris émulée lui était
## acquise, et le second doigt n'atteignait jamais le bouton de tir.
## Appuyer sur TIR en courant ne faisait donc rien du tout.
##
## Le bouton suit désormais son propre doigt, par index, exactement comme
## le joystick. La voie souris subsiste pour le bureau.
var _doigt_tir: int = -1
var _dash_button: UiKit.BoutonRond
## RENOMMÉ, ET CE N'EST PAS COSMÉTIQUE. Ce libellé s'appelait
## `_timer_label` et affichait le chronomètre de la partie. Le mode
## persistant n'a plus ni manche ni fin, et le champ montre désormais le
## niveau — mais `_process` continuait d'y réécrire « 0:52 » à chaque
## image, par-dessus « LV.1 ». Le défaut se voyait sur toute capture
## d'écran ; le nom, lui, le rendait invisible à la relecture.
var _announce: UiKit.Banniere
var _countdown: Label
var _health_bar: UiKit.BarreVie
var _slot_panels: Array[UiKit.CarteArme] = []
var _minicarte: Minicarte
var _fps_label: Label
var _classement: Classement
var _loader_etoile: LoaderEtoile
var _kill_fx: KillFeedback
var _replay_center: CenterContainer
var _tueur_affiche: String = ""
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label

var _dash_queued: bool = false
var _help: Control = null

## Suivi du doigt posé sur le bouton de tir.
##
## On filtre par le RECTANGLE du bouton : un doigt posé ailleurs — sur le
## joystick, sur l'arène — ne déclenche rien. C'est ce qui évite de
## retomber dans le défaut où toucher l'écran tirait.
func _input(event: InputEvent) -> void:
	if _fire_button == null or not is_instance_valid(_fire_button):
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _doigt_tir < 0 and _fire_button.get_global_rect().has_point(t.position):
				_doigt_tir = t.index
				_fire_tapped = true
				_marquer_tir(true)
		elif t.index == _doigt_tir:
			_doigt_tir = -1
			_marquer_tir(false)
	elif event is InputEventScreenDrag and _doigt_tir >= 0:
		# Le doigt a glissé HORS du bouton : on relâche, sinon la gâchette
		# resterait tenue alors que le doigt est parti ailleurs.
		var d := event as InputEventScreenDrag
		if d.index == _doigt_tir \
				and not _fire_button.get_global_rect().has_point(d.position):
			_doigt_tir = -1
			_marquer_tir(false)


## Retour visuel de l'appui. Le style « pressé » d'un Button ne s'affiche
## que sur la voie souris : au doigt, sans cela, rien ne bougerait à
## l'écran et le bouton paraîtrait mort même quand il tire.
func _marquer_tir(actif: bool) -> void:
	if _fire_button == null or not is_instance_valid(_fire_button):
		return
	# Le bouton se redessine lui-même enfoncé : plus de bricolage d'échelle
	# ni de teinte depuis l'extérieur. Le DESSIN de l'état appartient au
	# bouton, la CONNAISSANCE du doigt au HUD.
	_fire_button.enfonce_doigt = actif
	_fire_button.queue_redraw()


func _ready() -> void:
	add_to_group(&"hud")
	layer = 10
	_build()
	MatchDirector.countdown_tick.connect(_on_countdown)
	MatchDirector.alive_count_changed.connect(_on_alive_changed)
	MatchDirector.announce.connect(_on_announce)
	MatchDirector.match_ended.connect(_on_match_ended)
	MatchDirector.player_eliminated.connect(_on_player_eliminated)
	# La progression pilote le bandeau, la réapparition pilote l'écran de
	# mort. Le HUD n'interroge personne en boucle : il réagit.
	Profil.statistiques_changees.connect(_rafraichir_progression)
	Profil.niveau_gagne.connect(_on_niveau_gagne)
	Respawn.joueur_elimine.connect(_on_joueur_elimine)
	Respawn.joueur_revenu.connect(_on_joueur_revenu)
	# L'ÉTOILE PARLE PAR LA PLAQUE D'ANNONCE, plus par un bandeau à
	# demeure. Trois messages, et seulement quand ils me concernent : le
	# loader se charge du reste, en silence.
	EtoileDirector.ramassee.connect(_sur_etoile_prise)
	EtoileDirector.lachee.connect(_sur_etoile_lachee)
	EtoileDirector.gagnee.connect(_sur_etoile_gagnee)
	_rafraichir_progression()

func bind_player(p: Player) -> void:
	player = p
	p.elimination_reussie.connect(_on_elimination_reussie)
	p.health_changed.connect(_on_health_changed)
	p.inventory_changed.connect(_on_inventory_changed)
	p.died.connect(_on_local_died)
	_on_health_changed(p.health.current_health, p.health.max_health)
	_on_inventory_changed(p.slots, p.active_slot)
	if _minicarte:
		_minicarte.joueur = p
	if _classement:
		_classement.joueur_local = p
		# UN RAFRAÎCHISSEMENT IMMÉDIAT, sans attendre la période. Sinon le
		# classement reste vide les quatre premiers dixièmes de seconde de
		# la partie, ce qui se voit sur la toute première capture — et
		# c'est exactement l'image qu'on montre.
		_classement.rafraichir()

# --- CONSTRUCTION --------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


	_build_top()
	_build_center()
	_build_bottom()
	_build_controls()
	_build_overlay()
	_build_help()
	# ─── LA LÉGENDE DÉMARRE ÉTEINTE ───────────────────────────────────
	#
	# Elle couvrait en permanence les quatre coins de l'écran — « SE
	# DÉPLACER », « MAINTENIR POUR TIRER », « ESQUIVER », « CHANGER
	# D'ARME ». La consigne interdit explicitement un tutoriel permanent,
	# et elle a raison : ces textes sont utiles dix secondes et gênants
	# ensuite. Le bouton sous la carte les rappelle à la demande.
	if _help:
		_help.visible = false

	# Le retour d'élimination est monté EN DERNIER : il doit passer par
	# dessus tout le reste, y compris la plaque d'annonce.
	_kill_fx = KillFeedback.new()
	_root.add_child(_kill_fx)
	# Les décalages verticaux sont posés APRÈS l'ajout : `_ready` du contrôle
	# règle ses ancres au moment de l'ajout, et les valeurs posées avant
	# auraient été recalculées dans son dos.
	# 205 ET NON 150. La plaque d'annonce occupe la bande 92-176, et ces
	# deux éléments surgissent précisément AU MÊME INSTANT : on tue, on
	# gagne l'XP, on passe un niveau. Les superposer aurait rendu illisible
	# le seul moment que le joueur avait envie de regarder.
	_kill_fx.offset_top = 205
	_kill_fx.offset_bottom = 340

## Tout le texte de l'interface passe par ici, et donc par UiKit : grasse,
## penchée, cerclée de sombre. Un seul label réglé à la main suffirait à
## faire jurer l'ensemble.
func _label(text: String, size_px: int, color: Color = UiKit.BLANC) -> Label:
	var l := Label.new()
	l.text = text
	UiKit.texte(l, size_px, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## BARRE DU HAUT — la progression, plus le décompte d'une partie.
##
## CE QUI A DISPARU, ET POURQUOI. Le nombre de survivants et le chronomètre
## répondaient à des questions qui n'existent plus : « combien avant que je
## gagne » et « combien de temps me reste-t-il ». Dans un monde continu,
## personne ne gagne et rien ne se termine. Les laisser aurait affiché deux
## chiffres que le joueur aurait cherché à interpréter en vain.
##
## CE QUI LES REMPLACE répond aux questions du nouveau mode : combien j'en
## ai tué cette session, est-ce que je suis en série, et où j'en suis.
##
## LA SÉRIE N'APPARAÎT QU'À PARTIR DE DEUX. Un « SÉRIE 1 » permanent
## banaliserait l'affichage ; en le faisant surgir, il devient un signal.
## HAUT DE L'ÉCRAN — trois blocs, trois rôles, jamais mélangés.
##
## Le premier jet empilait tout au centre : niveau, kills, série, dans une
## seule barre. Cela lisait mal parce que ces trois informations ne se
## consultent pas au même moment. On les sépare selon QUAND on les regarde :
##
##   • À GAUCHE, l'identité — qui je suis, où j'en suis. On la consulte
##     entre deux combats, jamais pendant.
##   • AU CENTRE, la performance — kills et série. On la vérifie d'un coup
##     d'œil juste après une élimination, et le centre haut est le seul
##     endroit que le regard croise sans quitter l'action.
##   • À DROITE, l'orientation — carte et fil des éliminations. C'est
##     l'information qu'on va CHERCHER, donc celle qui peut être la plus
##     loin du centre.
func _build_top() -> void:
	_build_carte()
	_build_classement()


## Largeur du bloc de carte, en pixels.
const COTE_CARTE := 190
## Côté du portrait du bas, en pixels.
## Largeur commune de la vie et de l'expérience. Alignée sur la rangée
## d'armes : trois blocs de largeurs différentes empilés donnent une pile
## en escalier, et l'œil lit un défaut là où il n'y a qu'un contenu plus
## court.
## Largeur de la barre de vie du bas. Alignée sur la carte d'arme
## au-dessus : deux blocs de largeurs différentes empilés donnent une pile
## en escalier, et l'œil lit un défaut là où il n'y a qu'un contenu plus
## court.
const LARGEUR_BAS := 300
## Largeur du classement.
const LARGEUR_CLASSEMENT := 232


## ─── HAUT GAUCHE : LA CARTE ──────────────────────────────────────────
##
## ELLE ÉTAIT À DROITE, EMPILÉE AVEC LE FIL DES ÉLIMINATIONS. La maquette
## la met à gauche et lui donne le coin pour elle seule, et c'est un
## meilleur découpage : à droite elle partageait la place avec le
## classement, qui est le seul autre bloc qu'on consulte hors combat.
## Séparés, chacun a un coin, et l'œil sait où aller sans chercher.
##
## RONDE PLUTÔT QUE RECTANGULAIRE, comme la maquette. Ce n'est pas une
## coquetterie : une carte centrée sur le joueur montre la même distance
## dans toutes les directions, et un cadre rond dit exactement cela. Un
## rectangle promet plus d'information sur les côtés qu'en haut.
func _build_carte() -> void:
	# ─── LA DÉCOUPE SE FAIT SUR LE PARENT, PAS SUR LA CARTE ────────────
	#
	# `CLIP_CHILDREN_ONLY` transforme le dessin d'un contrôle en MASQUE et
	# cesse de l'afficher. Posé sur la carte elle-même, il la faisait
	# disparaître entièrement — c'est écrit dans `minicarte.gd`, et vérifié
	# en capture à l'époque. Posé sur un parent qui ne dessine QUE le
	# disque, il fait exactement ce qu'on veut : le fond répété neuf fois
	# s'arrête net au bord rond au lieu de remplir un carré.
	var masque := UiKit.Disque.new()
	masque.set_anchors_preset(Control.PRESET_TOP_LEFT)
	masque.position = Vector2(MARGIN, MARGIN)
	masque.custom_minimum_size = Vector2(COTE_CARTE, COTE_CARTE)
	masque.size = Vector2(COTE_CARTE, COTE_CARTE)
	masque.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	masque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(masque)

	_minicarte = Minicarte.new()
	_minicarte.ronde = true
	_minicarte.set_anchors_preset(Control.PRESET_FULL_RECT)
	masque.add_child(_minicarte)

	# Le lisere est tracé PAR-DESSUS et hors du masque : dessiné dedans, il
	# serait découpé par lui-même et n'apparaîtrait qu'à moitié.
	var lisere := UiKit.Anneau.new()
	lisere.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lisere.position = Vector2(MARGIN, MARGIN)
	lisere.custom_minimum_size = Vector2(COTE_CARTE, COTE_CARTE)
	lisere.size = Vector2(COTE_CARTE, COTE_CARTE)
	lisere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lisere)

	# LE PETIT BOUTON SOUS LA CARTE. La maquette y met une loupe ; ici il
	# ouvre la légende, qui est la même intention — « explique-moi ce que
	# je vois ». On garde donc la fonction existante plutôt que d'ajouter
	# un zoom qui n'existe pas.
	var reglages := UiKit.bouton_rond(42.0, "", &"engrenage",
			UiKit.NEUTRE_CLAIR, UiKit.NEUTRE_SOMBRE)
	reglages.position = Vector2(MARGIN + 4, MARGIN + COTE_CARTE - 6)
	reglages.pressed.connect(_basculer_legende)
	_root.add_child(reglages)

	# LA CADENCE RESTE, EN PLUS PETIT ET À CÔTÉ DU BOUTON. Ce n'est pas une
	# information de jeu et la maquette ne la montre pas — mais c'est le
	# seul témoin de performance dont dispose ce projet, et le supprimer
	# reviendrait à se priver du seul instrument qui dit si le jeu tient
	# la route sur l'appareil qu'on a en main.
	var pastille := PanelContainer.new()
	pastille.add_theme_stylebox_override(&"panel",
			UiKit.panneau(12, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 2))
	pastille.position = Vector2(MARGIN + 58, MARGIN + COTE_CARTE + 6)
	pastille.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pastille)
	var m := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right"]:
		m.add_theme_constant_override(cote, 8)
	for cote in [&"margin_top", &"margin_bottom"]:
		m.add_theme_constant_override(cote, 2)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pastille.add_child(m)
	_fps_label = _label("60 FPS", 15, Color("8ef0a8"))
	m.add_child(_fps_label)


## ─── LE HAUT CENTRE EST RENDU AU JEU ─────────────────────────────────
##
## La barre WANTED occupait ici deux lignes : nom du porteur, jauge,
## compteur « 18 / 30 ». Elle était lisible, et elle était posée là où l'on
## regarde en combat — sur 390 pixels de haut, elle mangeait le tiers
## supérieur du champ de vision.
##
## Tout ce qu'elle disait tient désormais dans `LoaderEtoile`, un disque de
## la taille d'un bouton posé près du pouce droit. Voir ce fichier pour le
## détail de ce qui a été gardé et de ce qui a été jeté.


## ─── HAUT DROITE : LE CLASSEMENT ─────────────────────────────────────
func _build_classement() -> void:
	_classement = Classement.new()
	# GÉOMÉTRIE EXPLICITE, PAS UN PRÉRÉGLAGE D'ANCRAGE. `PRESET_TOP_RIGHT`
	# pose les quatre bords au même endroit : le conteneur naît large de
	# zéro pixel et les ancrages « grandir vers la gauche » ne le
	# rattrapent pas. Vérifié en capture deux fois sur l'ancien coin.
	_classement.anchor_left = 1.0
	_classement.anchor_right = 1.0
	_classement.offset_left = -(LARGEUR_CLASSEMENT + MARGIN)
	_classement.offset_right = -MARGIN
	_classement.offset_top = MARGIN
	_root.add_child(_classement)


func _build_center() -> void:
	# Une PLAQUE et non un texte nu : une élimination est un évènement, elle
	# mérite un objet à l'écran. Un mot qui apparaît seul se confond avec le
	# décor ; une plaque dorée s'impose et s'oublie aussitôt après.
	_announce = UiKit.Banniere.new()
	_announce.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# RETOUR À 92. La barre WANTED occupait la bande 26-104 et forçait
	# l'annonce à descendre ; elle n'est plus là.
	_announce.offset_top = 92
	_announce.offset_bottom = 92 + 84
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce.modulate.a = 0.0
	_root.add_child(_announce)

	_countdown = _label("", 132, Color.WHITE)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown.modulate.a = 0.0
	_root.add_child(_countdown)

## ─── BAS CENTRE : LE HUD PERSONNEL ───────────────────────────────────
##
## Portrait à gauche, puis un bloc sombre qui porte l'armement au-dessus et
## la vie en dessous. C'est la silhouette de la maquette, et c'est aussi la
## seule zone qu'aucun pouce ne couvre — d'où les deux informations qu'on
## lit EN COMBAT.
##
## CE QUI A DÉMÉNAGÉ ICI. Le portrait, le niveau et l'expérience occupaient
## le coin haut gauche, que la carte réclame maintenant. Ils ne sont pas
## supprimés pour autant : la progression est un système vivant du jeu, et
## la faire disparaître de l'écran reviendrait à la retirer sans le dire.
## Elle passe simplement au second plan — badge de niveau sur le portrait,
## expérience en filet sous la vie.
func _build_bottom() -> void:
	var ligne := HBoxContainer.new()
	ligne.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ligne.offset_bottom = -MARGIN
	ligne.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ligne.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ligne.add_theme_constant_override(&"separation", 12)
	ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ligne)

	# ─── CE QUI A ÉTÉ RETIRÉ D'ICI, ET POURQUOI ───────────────────────
	#
	# Le portrait, le badge de niveau, la barre d'expérience, le deuxième
	# emplacement d'arme et l'emplacement verrouillé ont tous disparu.
	#
	# Ce ne sont pas des suppressions par économie : ces cinq éléments
	# décrivaient un jeu de progression — collectionner, débloquer, monter
	# de niveau — alors que le mode qui se joue est un deathmatch à
	# réapparition permanente avec une étoile à tenir trente secondes. Rien
	# de ce qu'ils affichaient ne change une décision prise en combat.
	#
	# Il reste donc les deux seules choses qu'on lit EN JOUANT : avec quoi
	# je tire et combien il m'en reste, et combien de vie j'ai.
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ligne.add_child(col)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(slots)

	# ─── UN SEUL EMPLACEMENT, ET IL N'EST PLUS CLIQUABLE ──────────────
	#
	# Le bouton « ARME » et la sélection au doigt sur les cartes étaient
	# les deux seules façons de changer d'arme. Les retirer sans toucher au
	# reste aurait laissé un deuxième emplacement invisible où les armes
	# ramassées seraient tombées pour ne jamais en ressortir — un butin
	# qu'on prend et qu'on ne peut pas employer.
	#
	# L'inventaire tient donc en UNE arme : voir `Player.server_pickup`,
	# qui remplace désormais toujours l'arme en main.
	var carte := UiKit.CarteArme.new()
	carte.custom_minimum_size = Vector2(LARGEUR_BAS, 70)
	carte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_child(carte)
	_slot_panels.append(carte)

	_health_bar = UiKit.BarreVie.new()
	_health_bar.custom_minimum_size = Vector2(LARGEUR_BAS, 34)
	_health_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_health_bar)


func _build_controls() -> void:
	_move_stick = VirtualJoystick.new()
	_move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_stick.custom_minimum_size = Vector2(STICK_SIZE, STICK_SIZE)
	_move_stick.size = Vector2(STICK_SIZE, STICK_SIZE)
	_move_stick.offset_left = MARGIN
	_move_stick.offset_top = -(STICK_SIZE + MARGIN)
	_move_stick.offset_right = MARGIN + STICK_SIZE
	_move_stick.offset_bottom = -MARGIN
	_root.add_child(_move_stick)

	# BOUTON DE TIR — un vrai bouton, maintenu, et non plus un second
	# joystick.
	#
	# POURQUOI CE CHANGEMENT : le tir était porté par un joystick, qui
	# donnait à la fois la direction et l'ordre de tirer. Deux
	# conséquences fâcheuses. La première est qu'on ne savait pas à quoi
	# il servait — un cercle se manipule, il ne se presse pas. La seconde
	# est qu'il fallait viser ET tirer du même pouce, alors que le genre
	# repose sur une visée automatique.
	#
	# La règle est désormais celle de tout jeu d'arène tactile : le pouce
	# gauche DIRIGE, le pouce droit TIRE, et le jeu accroche la cible.
	_fire_button = UiKit.bouton_rond(FIRE_SIZE, "TIR", &"viseur",
			UiKit.TIR_CLAIR, UiKit.TIR_SOMBRE)
	_fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fire_button.offset_left = -(FIRE_SIZE + MARGIN)
	_fire_button.offset_top = -(FIRE_SIZE + MARGIN)
	_fire_button.offset_right = -MARGIN
	_fire_button.offset_bottom = -MARGIN
	# MAINTENU, et non pas « cliqué » : on lit l'appui et le relâchement.
	# Le signal `pressed` ne se déclencherait qu'au relâchement, ce qui
	# interdirait de tenir la gâchette d'une arme automatique.
	# VOIE SOURIS, pour le bureau. La voie TACTILE est traitée dans
	# `_input`, par index de doigt : un Button n'écoute que la souris
	# émulée, dont le joystick s'empare dès qu'on court.
	_fire_button.button_down.connect(func():
		_fire_held = true
		_fire_tapped = true
		_marquer_tir(true))
	_fire_button.button_up.connect(func():
		_fire_held = false
		if _doigt_tir < 0:
			_marquer_tir(false))
	_root.add_child(_fire_button)

	# HIÉRARCHIE DES TAILLES. Le bouton de tir est le plus gros parce qu'il
	# est pressé cent fois par partie ; l'échange d'arme est le plus petit
	# parce qu'il l'est trois fois. Une taille égale pour les trois ferait
	# manquer le seul qui compte.
	# ─── LE LOADER D'ÉTOILE, À PORTÉE DE POUCE ────────────────────────
	#
	# Il occupe la place laissée libre par le bouton « ARME », à gauche du
	# bouton de tir. Ce n'est pas un rangement par défaut : c'est là que le
	# regard passe déjà, entre la visée et le décor, et un objectif se
	# surveille du coin de l'œil sans quitter l'action.
	_loader_etoile = LoaderEtoile.new()
	_loader_etoile.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_loader_etoile.offset_left = -(FIRE_SIZE + MARGIN + LOADER_SIZE + 20)
	_loader_etoile.offset_top = -(MARGIN + LOADER_SIZE + 26)
	_loader_etoile.offset_right = -(FIRE_SIZE + MARGIN + 20)
	_loader_etoile.offset_bottom = -(MARGIN + 26)
	_root.add_child(_loader_etoile)

	# ─── PLUS DE BOUTON « ARME » ──────────────────────────────────────
	#
	# Il servait à basculer entre deux emplacements ; il n'y en a plus
	# qu'un. Le laisser aurait donné un bouton qui ne fait rien, ce qui est
	# pire qu'un bouton absent : on appuie, on attend un effet, il ne vient
	# pas, et l'on croit que le jeu a raté l'appui.
	#
	# La place gagnée profite au pouce droit, qui n'a plus que TIR et
	# ESQUIVE à distinguer.

	_dash_button = UiKit.bouton_rond(ESQUIVE_SIZE, "ESQUIVE", &"eclair",
			UiKit.ESQUIVE_CLAIR, UiKit.ESQUIVE_SOMBRE)
	_dash_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# MESURÉ EN IMAGE : ESQUIVE mordait sur TIR de vingt-cinq pixels. Deux
	# boutons qui se touchent, ce n'est pas seulement laid — au pouce, on
	# déclenche l'un en visant l'autre. On le cale FRANCHEMENT au-dessus.
	_dash_button.offset_bottom = -(MARGIN + FIRE_SIZE + 16)
	_dash_button.offset_top = _dash_button.offset_bottom - ESQUIVE_SIZE
	_dash_button.offset_right = -(MARGIN + 20)
	_dash_button.offset_left = _dash_button.offset_right - ESQUIVE_SIZE
	_dash_button.pressed.connect(func(): _dash_queued = true)
	_root.add_child(_dash_button)

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 22)
	_overlay.add_child(box)

	_overlay_title = _label("VICTOIRE", 92, Cfg.COL_HEAL)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)

	_overlay_sub = _label("", 28)
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_sub)

	# BOUTON EN CAPSULE, et non rond : celui-ci porte un mot, pas une icône,
	# et un mot enfermé dans un cercle oblige à rapetisser le texte jusqu'à
	# l'illisible. Il reprend le reste de la charte — dégradé, bord clair,
	# ombre — pour rester de la même famille que les boutons d'action.
	var replay := Button.new()
	replay.text = "REJOUER"
	replay.custom_minimum_size = Vector2(300, 80)
	replay.focus_mode = Control.FOCUS_NONE
	UiKit.texte(replay, 30)
	var repos := UiKit.panneau(24, UiKit.VIE_SOMBRE, Color(1, 1, 1, 0.85), 5)
	replay.add_theme_stylebox_override(&"normal", repos)
	var appuye := UiKit.panneau(24, UiKit.VIE_CLAIR, Color(1, 1, 1, 0.85), 5)
	replay.add_theme_stylebox_override(&"pressed", appuye)
	replay.add_theme_stylebox_override(&"hover", appuye)
	replay.pressed.connect(_on_replay)
	var center := CenterContainer.new()
	center.add_child(replay)
	box.add_child(center)
	# REJOUER n'a plus lieu d'être : on ne « rejoue » pas un monde qui ne
	# s'arrête jamais. Le bouton reste construit, et seulement masqué, pour
	# que le mode Battle Royale le retrouve intact.
	_replay_center = center
	center.visible = not MatchDirector.est_persistant()

# --- LECTURE PAR LE CONTRÔLEUR -------------------------------------------

func move_vector() -> Vector2:
	return _move_stick.value if _move_stick else Vector2.ZERO

## Le tactile ne fournit PLUS de direction de visée : le joystick droit a
## laissé la place à un bouton. Le pouce gauche dirige, la visée est
## automatique. La fonction subsiste pour que le contrôleur reste
## indifférent au périphérique.
func aim_vector() -> Vector2:
	return Vector2.ZERO

func is_firing() -> bool:
	return _fire_held or _doigt_tir >= 0

## Consommation à usage unique : sans cela un seul appui vaudrait un
## bonus de cadence à chaque image.
func consume_tap() -> bool:
	var v := _fire_tapped
	_fire_tapped = false
	return v

## PLUS RIEN NE L'ARME, ET LA FONCTION RESTE. Le contrôleur l'interroge à
## chaque image ; la supprimer demanderait de le modifier lui aussi, pour
## un gain nul. Elle rend donc toujours faux, et la ligne le dit.
##
## Le jour où l'on voudra deux armes, il suffira de reposer un bouton :
## tout le chemin en aval — `Player.swap_weapon`, la réplication, l'effet —
## est intact.
func consume_swap() -> bool:
	return false

func consume_dash() -> bool:
	var v := _dash_queued
	_dash_queued = false
	return v

# --- MISES À JOUR --------------------------------------------------------

func _process(_delta: float) -> void:
	if _fps_label:
		var f := Engine.get_frames_per_second()
		_fps_label.text = "%d FPS" % f
		# VERT, ORANGE, ROUGE. Le chiffre seul demande de savoir ce qu'est
		# une bonne cadence ; la couleur, non.
		_fps_label.add_theme_color_override(&"font_color",
				Color("8ef0a8") if f >= 50 else
				(UiKit.OR_CLAIR if f >= 30 else UiKit.ROUGE))
	# LES CINQ DERNIÈRES SECONDES SE DISENT. Le loader chauffe vers le
	# blanc sur la fin, mais un joueur en pleine fusillade ne regarde pas
	# son coin d'écran : c'est l'instant où l'on veut savoir qu'il faut
	# tenir encore un peu.
	if _je_portais and not _alerte_dite \
			and EtoileDirector.porteur_id == Net.local_id() \
			and EtoileDirector.DUREE - EtoileDirector.temps <= ALERTE_FIN:
		_alerte_dite = true
		_on_announce("TIENS BON", UiKit.OR_CLAIR)

	if player and _dash_button:
		var pret := player.dash_ready_ratio()
		_dash_button.modulate.a = lerpf(0.55, 1.0, pret)
		_dash_button.recharge = pret
		_dash_button.attente = (1.0 - pret) * Player.DASH_COOLDOWN
		_dash_button.queue_redraw()

func _on_health_changed(current: float, maximum: float) -> void:
	# La barre se dessine elle-même, teinte comprise : le HUD lui donne des
	# chiffres, pas des pixels.
	_health_bar.regler(current, maximum)

func _on_inventory_changed(slots: Array, active: int) -> void:
	for i in _slot_panels.size():
		var id: StringName = slots[i] if i < slots.size() else &""
		var data := Registry.weapon(id)
		var carte := _slot_panels[i]
		if data == null:
			carte.regler("—", "", UiKit.NEUTRE_SOMBRE, false)
			continue
		var muni := ""
		if i == active and player and player.weapon:
			muni = player.weapon.ammo_text()
		var etait := carte.active
		carte.regler(data.display_name, muni, data.color, i == active)
		# LA CARTE TRESSAILLE QUAND ON LA PREND, et seulement à ce
		# moment-là. Rejouer l'animation à chaque coup tiré — l'inventaire
		# se signale à chaque changement de munitions — ferait vibrer
		# l'armement en permanence.
		if i == active and not etait:
			var tw := create_tween()
			tw.tween_property(carte, "scale", Vector2(1.07, 1.07), 0.07)
			tw.tween_property(carte, "scale", Vector2.ONE, 0.1)

## Le nombre de survivants n'a plus de sens dans un monde continu : on
## laisse le signal branché — il reste utile au mode Battle Royale — mais
## il ne pilote plus rien ici.
func _on_alive_changed(_count: int) -> void:
	pass


func _rafraichir_progression() -> void:
	# LES KILLS ONT QUITTÉ CETTE FONCTION. Ils vivaient dans une pastille
	# du haut, alimentée par `Profil.kills_session` — donc par la
	# progression du seul joueur local. Le classement les lit désormais
	# sur les joueurs eux-mêmes, ce qui est la seule façon de citer aussi
	# les bots. La série, elle, n'a plus de place à l'écran : elle reste
	# tenue par `Profil` et célébrée par le retour d'élimination.
	# ET LE NIVEAU AUSSI A QUITTÉ L'ÉCRAN. Portrait, badge de niveau et
	# barre d'expérience décrivaient un jeu de progression ; le mode qui se
	# joue est un deathmatch permanent avec une étoile à tenir. `Profil`
	# continue de tout enregistrer — la progression n'est pas supprimée,
	# elle n'est plus AFFICHÉE en combat.
	pass


# --- ÉTOILE ---------------------------------------------------------------
#
# ON N'ANNONCE QUE CE QUI ME CONCERNE. Une plaque à chaque fois qu'un bot
# ramasse ou perd l'étoile ferait clignoter le haut de l'écran en
# permanence — dix joueurs, quelques secondes chacun. Le loader, lui,
# montre l'état de tout le monde sans dire un mot.

## Le porteur au moment où j'ai perdu l'étoile : sert à savoir si la chute
## me concerne.
var _je_portais := false
## Le seuil d'alerte a-t-il déjà été annoncé pour cette possession ?
var _alerte_dite := false

## Secondes restantes en dessous desquelles on prévient le porteur.
const ALERTE_FIN := 5.0


func _sur_etoile_prise(peer_id: int) -> void:
	_je_portais = peer_id == Net.local_id()
	_alerte_dite = false
	if _je_portais:
		_on_announce("ÉTOILE CAPTURÉE", UiKit.OR_CLAIR)


func _sur_etoile_lachee(_position: Vector3) -> void:
	if _je_portais:
		_on_announce("ÉTOILE PERDUE", UiKit.ROUGE)
	_je_portais = false
	_alerte_dite = false


func _sur_etoile_gagnee(peer_id: int, victoires: int) -> void:
	_je_portais = false
	_alerte_dite = false
	if peer_id == Net.local_id():
		_on_announce("+1 ÉTOILE  ·  %d" % victoires, UiKit.OR_CLAIR)


func _on_niveau_gagne(niveau: int) -> void:
	_on_announce("NIVEAU %d" % niveau, UiKit.OR_CLAIR)


func _on_elimination_reussie(nom_victime: String, bilan: Dictionary) -> void:
	if _kill_fx != null:
		_kill_fx.celebrer(nom_victime, bilan)
	_rafraichir_progression()

func _on_countdown(value: int) -> void:
	# « GO » : la partie commence, la légende doit libérer l'écran.
	if value == 0:
		_hide_help()
	_countdown.text = str(value) if value > 0 else "GO"
	_countdown.modulate.a = 1.0
	_countdown.scale = Vector2(1.6, 1.6)
	_countdown.pivot_offset = _countdown.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown, "modulate:a", 0.0, 0.8).set_delay(0.2)

func _on_announce(text: String, color: Color) -> void:
	# La plaque prend la TEINTE de l'évènement — dorée pour une élimination,
	# rouge pour la mort du joueur — tout en gardant son dégradé. Une
	# couleur plate perdrait le relief qui la fait exister.
	_announce.afficher(text, color.lightened(0.30), color.darkened(0.22))
	_announce.modulate.a = 1.0
	# Elle ARRIVE, elle ne se contente pas d'apparaître : un objet qui
	# surgit se remarque, un objet qui se révèle en fondu se manque.
	_announce.scale = Vector2(0.7, 0.7)
	_announce.pivot_offset = Vector2(_announce.size.x * 0.5, 40.0)
	var tw := create_tween()
	tw.tween_property(_announce, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_property(_announce, "modulate:a", 0.0, 0.5)

func _on_player_eliminated(peer_id: int, name_text: String) -> void:
	if player and peer_id == player.peer_id:
		return
	_on_announce("%s ÉLIMINÉ" % name_text.to_upper(), Cfg.COL_ENEMY_PLAYER)

## MORT DU JOUEUR LOCAL — plus un écran de fin, un simple entracte.
##
## Ce qui s'affichait avant : « En attente de la fin de la partie… ». C'était
## juste, et c'est devenu faux — il n'y a plus de fin à attendre. Ce que le
## joueur veut savoir tient en deux choses : QUI l'a eu, et DANS COMBIEN DE
## TEMPS il revient.
func _on_local_died() -> void:
	_overlay_title.text = "ÉLIMINÉ"
	_overlay_title.add_theme_color_override(&"font_color", Cfg.COL_DANGER)
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.25)


func _on_joueur_elimine(victime_id: int, tueur_id: int,
		tueur_nom: String) -> void:
	# ─── PLUS DE FIL D'ÉLIMINATIONS PERMANENT ─────────────────────────
	#
	# Il listait toutes les éliminations de la carte, et c'était défendable
	# — savoir que deux adversaires se battent à l'autre bout donne des
	# habitants plutôt que des cibles. La consigne le retire explicitement,
	# et l'arbitrage se tient : le coin haut droit revient au classement,
	# qui dit la même chose en permanence et en trois chiffres, sans
	# défiler. Les éliminations qui concernent le joueur restent
	# annoncées — bannière au ramassage d'une victime, écran de mort.
	if player == null or victime_id != player.peer_id:
		return
	_tueur_affiche = tueur_nom.to_upper()
	_overlay_sub.text = "ABATTU PAR %s" % _tueur_affiche


## Nom affichable d'un pair, retrouvé dans la scène.
func _nom_de(peer_id: int) -> String:
	for n in get_tree().get_nodes_in_group(&"players"):
		if n.get(&"peer_id") == peer_id:
			return str(n.get(&"display_name"))
	return "?"


func _on_joueur_revenu(peer_id: int) -> void:
	if player == null or peer_id != player.peer_id:
		return
	# On efface l'écran D'UN COUP : un fondu long au retour donnerait
	# l'impression de reprendre le contrôle en retard.
	_overlay.visible = false
	_overlay.modulate.a = 0.0
	_rafraichir_progression()

func _on_match_ended(winner_id: int, winner_name: String) -> void:
	var won := player != null and winner_id == player.peer_id
	_overlay_title.text = "VICTOIRE" if won else "ÉLIMINÉ"
	_overlay_title.add_theme_color_override(&"font_color",
			Cfg.COL_HEAL if won else Cfg.COL_DANGER)
	_overlay_sub.text = "Dernier survivant de l'arène." if won \
			else "Vainqueur : %s" % winner_name
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.5)

func _on_replay() -> void:
	var main := get_tree().get_first_node_in_group(&"main")
	if main and main.has_method(&"restart_match"):
		main.call(&"restart_match")


# --- LÉGENDE DES COMMANDES ----------------------------------------------
#
# Affichée pendant le compte à rebours, puis effacée au « GO ».
#
# POURQUOI ELLE EST NÉCESSAIRE : quatre boutons sans explication, c'est
# quatre boutons qu'on n'utilise pas. Un joueur qui ignore l'existence de
# l'esquive ou du changement d'arme ne joue qu'à la moitié du jeu. La
# légende ne coûte rien puisqu'elle occupe un temps mort — celui du
# décompte, pendant lequel il n'y a de toute façon rien à faire.

## L'ENGRENAGE RAPPELLE LA LÉGENDE DES COMMANDES.
##
## La maquette y met un menu de réglages. Il n'y a pas encore de réglages à
## régler — mettre un bouton qui n'ouvre rien serait pire que pas de bouton.
## En attendant, il rend service à ce qui existe : la légende des commandes,
## qui s'efface au « GO » et qu'aucun geste ne permettait de faire revenir.
func _basculer_legende() -> void:
	if _help == null:
		return
	_help.visible = not _help.visible
	if _help.visible:
		_help.modulate.a = 1.0


func _build_help() -> void:
	_help = Control.new()
	_help.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_help)

	# Chaque encart est ancré PRÈS de la commande qu'il décrit : une
	# légende déportée en liste obligerait à faire la correspondance
	# soi-même, ce que personne ne fait sous la pression d'un décompte.
	_help_note("SE DÉPLACER\nUNIQUEMENT", Cfg.COL_LOCAL_PLAYER,
			Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN + 14, -(STICK_SIZE + 74)))
	# LES TROIS ENCARTS DE DROITE SONT REGROUPÉS EN UNE COLONNE.
	#
	# Éparpillés, chacun collé à son bouton, ils se chevauchaient entre eux
	# ET recouvraient les cartes d'armes — vérifié en image, deux fois. Le
	# coin bas-droit d'un écran de téléphone en paysage n'a tout simplement
	# pas la place d'accueillir trois blocs de texte et trois boutons.
	#
	# La colonne est alignée à DROITE et remonte au-dessus des commandes :
	# elle reste du côté des boutons qu'elle décrit, sans jamais mordre
	# dessus. Chaque ligne garde la couleur de son bouton, ce qui suffit à
	# faire la correspondance sans flèche ni encadré.
	var aide := VBoxContainer.new()
	aide.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	aide.offset_right = -(MARGIN + 14)
	aide.offset_bottom = -(MARGIN + FIRE_SIZE + ESQUIVE_SIZE + 34)
	aide.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	aide.grow_vertical = Control.GROW_DIRECTION_BEGIN
	aide.alignment = BoxContainer.ALIGNMENT_END
	aide.add_theme_constant_override(&"separation", 4)
	aide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(aide)

	for entree in [
			{"t": "MAINTENIR POUR TIRER · VISÉE AUTOMATIQUE", "c": Cfg.COL_SHOTGUN},
			{"t": "ESQUIVER", "c": Cfg.COL_BASIC},
			{"t": "CHANGER D'ARME", "c": Cfg.COL_ENERGY}]:
		var ligne := _label(entree["t"], 19, entree["c"])
		ligne.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		aide.add_child(ligne)

	# L'OBJECTIF A CHANGÉ, LE TEXTE AUSSI. « Soyez le dernier » décrivait un
	# Battle Royale : c'était vrai, et c'est devenu faux. Une consigne
	# périmée est pire qu'une absence de consigne — elle envoie le joueur
	# chercher une fin de partie qui n'existe plus.
	# L'OBJECTIF A CHANGÉ UNE SECONDE FOIS. Le mode a maintenant un but
	# qui n'est plus « tuer en attendant » : l'étoile. La consigne veut
	# qu'on la comprenne sans tutoriel, et une phrase de sept mots au
	# premier lancement fait ce travail mieux qu'un didacticiel.
	var goal := _label("PRENEZ L'ÉTOILE · GARDEZ-LA 30 SECONDES · SURVIVEZ",
			24, Color(1, 1, 1, 0.92))
	goal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# 196 et non 150 : la plaque d'annonce occupe la bande 92-176, et les
	# deux se superposaient dès qu'une élimination tombait.
	goal.offset_top = 196
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.add_child(goal)

func _help_note(text: String, color: Color, preset: int, offset: Vector2) -> void:
	var lbl := _label(text, 19, color)
	lbl.set_anchors_preset(preset)
	lbl.offset_left = offset.x
	lbl.offset_top = offset.y
	lbl.grow_horizontal = Control.GROW_DIRECTION_END
	lbl.grow_vertical = Control.GROW_DIRECTION_END
	_help.add_child(lbl)

func _hide_help() -> void:
	if _help == null or not is_instance_valid(_help):
		return
	var tw := create_tween()
	tw.tween_property(_help, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_help.queue_free)
	_help = null
