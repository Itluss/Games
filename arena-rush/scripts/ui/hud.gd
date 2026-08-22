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
## maintient. Un appui simple accroche automatiquement l'ennemi le mieux
## placé ; un GLISSEMENT sur le bouton oriente le tir, façon Brawl
## Stars — c'est lui qui permet de choisir SA cible au lieu de subir
## celle de l'accrochage.

const MARGIN := 26
const STICK_SIZE := 210
const FIRE_SIZE := 168
## Zone morte du glisser-pour-viser, en fraction du bouton de tir. En
## deçà, l'appui reste un TAP — visée automatique ; au-delà, le doigt
## VISE. Assez large pour qu'un pouce qui tremble ne bascule pas en
## manuel par accident, assez étroite pour que l'intention passe vite.
const VISEE_ZONE_MORTE := 0.35
const ESQUIVE_SIZE := 104
## Diamètre de la bourse (compteur de prime), en pixels.
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
## Direction de VISÉE MANUELLE du pouce droit, façon Brawl Stars : le
## doigt posé sur TIR puis GLISSÉ au-delà de la zone morte oriente le
## tir. ZERO tant que le glissement reste dans la zone morte — un appui
## simple demeure un tir auto-accroché. C'est ce glissement qui permet
## d'ARRACHER le verrou à une autre cible : sans lui, le premier ennemi
## accroché gardait le tir tant qu'il restait le mieux placé, et le
## joueur ne pouvait pas en choisir un autre.
var _visee_tactile: Vector2 = Vector2.ZERO
var _dash_button: UiKit.BoutonRond
## RENOMMÉ, ET CE N'EST PAS COSMÉTIQUE. Ce libellé s'appelait
## `_timer_label` et affichait le chronomètre de la partie. Le mode
## persistant n'a plus ni manche ni fin, et le champ montre désormais le
## niveau — mais `_process` continuait d'y réécrire « 0:52 » à chaque
## image, par-dessus « LV.1 ». Le défaut se voyait sur toute capture
## d'écran ; le nom, lui, le rendait invisible à la relecture.
var _announce: UiKit.Banniere
var _countdown: Label
var _slot_panels: Array[UiKit.CarteArme] = []
var _minicarte: Minicarte
var _fps_label: Label
var _classement: Classement
var _bourse: Bourse
var _kill_fx: KillFeedback
var _replay_center: CenterContainer
var _tueur_affiche: String = ""
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label

var _dash_queued: bool = false
var _special_button: UiKit.BoutonRond
var _special_queued: bool = false
## Doigts posés sur ESQUIVE et CANON, par index — la voie souris émulée
## est confisquée par le joystick dès qu'on court : sans ce suivi, les
## deux boutons étaient INJOIGNABLES en mouvement (retour de test :
## « la roulade n'est pas accessible quand le personnage court »).
var _doigt_dash: int = -1
var _doigt_special: int = -1
## Visée de la compétence, en pixels depuis le centre du bouton CANON.
var _visee_special: Vector2 = Vector2.ZERO
## Visée figée au LEVER du doigt — c'est elle que le contrôleur consomme.
var _special_visee_larguee: Vector2 = Vector2.ZERO
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
			elif _doigt_dash < 0 and _dash_button != null \
					and _dash_button.get_global_rect().has_point(t.position):
				_doigt_dash = t.index
				_dash_queued = true
				_dash_button.enfonce_doigt = true
				_dash_button.queue_redraw()
			elif _doigt_special < 0 and _special_button != null \
					and _special_button.get_global_rect().has_point(t.position):
				_doigt_special = t.index
				_visee_special = Vector2.ZERO
				_special_button.enfonce_doigt = true
				_special_button.queue_redraw()
		elif t.index == _doigt_tir:
			_doigt_tir = -1
			_visee_tactile = Vector2.ZERO
			_poignee_tir(Vector2.ZERO)
			_marquer_tir(false)
		elif t.index == _doigt_dash:
			_doigt_dash = -1
			_dash_button.enfonce_doigt = false
			_dash_button.queue_redraw()
		elif t.index == _doigt_special:
			# Le CANON part AU LEVER, comme les supers du genre : glisser
			# vise, lâcher tire. Un simple tap laisse la visée nulle et
			# retombe sur l'accrochage automatique.
			_doigt_special = -1
			_special_queued = true
			_special_visee_larguee = _visee_special
			_visee_special = Vector2.ZERO
			_special_button.enfonce_doigt = false
			_poignee_special(Vector2.ZERO)
	elif event is InputEventScreenDrag:
		# LE GLISSEMENT EST LA VISÉE — plus une raison de lâcher. L'ancienne
		# règle relâchait la gâchette dès que le doigt sortait du bouton ;
		# elle interdisait précisément le geste qu'on veut : glisser pour
		# orienter le tir. Le doigt qui a PRIS le bouton le garde jusqu'au
		# lever, où qu'il aille, et sa position par rapport au CENTRE du
		# bouton donne la direction — l'écran et le monde partagent déjà
		# leurs axes, comme pour le joystick de gauche.
		var d := event as InputEventScreenDrag
		if d.index == _doigt_tir:
			var v := d.position - _fire_button.get_global_rect().get_center()
			if v.length() > FIRE_SIZE * VISEE_ZONE_MORTE:
				_visee_tactile = v
			else:
				# Revenu dans la zone morte : on rend la main à l'accrochage
				# automatique, sans cesser de tirer.
				_visee_tactile = Vector2.ZERO
			_poignee_tir(v)
		elif d.index == _doigt_special and _special_button != null:
			var vs := d.position - _special_button.get_global_rect().get_center()
			if vs.length() > ESQUIVE_SIZE * VISEE_ZONE_MORTE:
				_visee_special = vs
			else:
				_visee_special = Vector2.ZERO
			_poignee_special(vs)


## Position de la POIGNÉE du bouton-joystick de tir, en fraction du
## rayon. On lui passe le vecteur BRUT du doigt : la poignée suit le
## pouce dès le premier pixel — c'est le retour qui enseigne le geste —
## même quand la direction de visée, elle, attend la sortie de la zone
## morte.
func _poignee_tir(v: Vector2) -> void:
	if _fire_button == null or not is_instance_valid(_fire_button):
		return
	_fire_button.visee = v / (FIRE_SIZE * 0.5)
	_fire_button.queue_redraw()


## Retour visuel de l'appui. Le style « pressé » d'un Button ne s'affiche
## que sur la voie souris : au doigt, sans cela, rien ne bougerait à
## l'écran et le bouton paraîtrait mort même quand il tire.
func _poignee_special(v: Vector2) -> void:
	if _special_button == null or not is_instance_valid(_special_button):
		return
	_special_button.visee = v / (ESQUIVE_SIZE * 0.5)
	_special_button.queue_redraw()


## Visée de la compétence EN COURS de glissement : direction × force
## (0 = zone morte, 1 = bord du bouton et au-delà). Sert à l'aperçu au
## sol — le joueur voit la marque avant de lâcher.
func special_aim_vector() -> Vector2:
	if _visee_special == Vector2.ZERO:
		return Vector2.ZERO
	var brute := _visee_special.length() / (ESQUIVE_SIZE * 0.5)
	var force := clampf((brute - VISEE_ZONE_MORTE) / (1.6 - VISEE_ZONE_MORTE),
			0.1, 1.0)
	return _visee_special.normalized() * force


## Visée figée au lever du doigt, consommée avec l'ordre de tir.
func consume_special_visee() -> Vector2:
	var v := _special_visee_larguee
	_special_visee_larguee = Vector2.ZERO
	if v == Vector2.ZERO:
		return Vector2.ZERO
	var brute := v.length() / (ESQUIVE_SIZE * 0.5)
	var force := clampf((brute - VISEE_ZONE_MORTE) / (1.6 - VISEE_ZONE_MORTE),
			0.1, 1.0)
	return v.normalized() * force


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
	PrimeDirector.roi_change.connect(_sur_roi_change)
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
## Tout ce qu'elle disait tient désormais dans la BOURSE, un disque de
## la taille d'un bouton posé près du pouce droit.


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
	# réapparition permanente autour de la Prime. Rien
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

	# ─── PLUS DE BARRE DE VIE EN BAS ──────────────────────────────────
	#
	# Elle doublait la plaque au-dessus du personnage, et obligeait à
	# lire sa vie AILLEURS que là où on regarde — le combat. Le joueur
	# local porte désormais sa barre au-dessus de la tête, comme les neuf
	# autres : une seule règle de lecture pour tout le monde.


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
	# EN JOYSTICK, PAS EN PASTILLE. Le glisser-pour-viser existait mais
	# rien ne l'annonçait : une image ronde se presse, elle ne se glisse
	# pas. Dessiné comme le stick de gauche — socle à chevrons, poignée
	# mobile — le bouton dit lui-même « oriente le tir ».
	_fire_button.mode_joystick = true
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
		_poignee_tir(Vector2.ZERO)
		if _doigt_tir < 0:
			_marquer_tir(false))
	_root.add_child(_fire_button)

	# HIÉRARCHIE DES TAILLES. Le bouton de tir est le plus gros parce qu'il
	# est pressé cent fois par partie ; l'échange d'arme est le plus petit
	# parce qu'il l'est trois fois. Une taille égale pour les trois ferait
	# manquer le seul qui compte.
	# ─── LA BOURSE — le compteur de prime, à portée de pouce ──────────
	#
	# À la place qu'occupait le loader d'étoile : là où le regard passe
	# déjà, entre la visée et le décor. Une pièce d'or dessinée, le
	# montant, et le multiplicateur quand il dépasse ×1 — le joueur voit
	# d'un coup d'œil ce qu'il risque de perdre et ce que rapporte
	# chacun de ses coups.
	_bourse = Bourse.new()
	_bourse.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bourse.offset_left = -(FIRE_SIZE + MARGIN + LOADER_SIZE + 20)
	_bourse.offset_top = -(MARGIN + LOADER_SIZE + 26)
	_bourse.offset_right = -(FIRE_SIZE + MARGIN + 20)
	_bourse.offset_bottom = -(MARGIN + 26)
	_root.add_child(_bourse)

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

	# ─── LA COMPÉTENCE SPÉCIALE : LE BOMBARDEMENT ─────────────────────
	#
	# Un bouton doré à tête de mort, à gauche de l'esquive — la place du
	# pouce droit qui monte. Un TAP suffit : la zone se pose sur la cible
	# accrochée, sinon droit devant. La couronne de recharge du bouton
	# dit quand le canon est prêt — treize secondes, la carte qui change
	# un combat ne se spamme pas.
	_special_button = UiKit.bouton_rond(ESQUIVE_SIZE, "CANON", &"crane",
			UiKit.COMP_CLAIR, UiKit.COMP_SOMBRE)
	_special_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_special_button.offset_bottom = -(MARGIN + FIRE_SIZE + 16)
	_special_button.offset_top = _special_button.offset_bottom - ESQUIVE_SIZE
	_special_button.offset_right = -(MARGIN + 20 + ESQUIVE_SIZE + 18)
	_special_button.offset_left = _special_button.offset_right - ESQUIVE_SIZE
	_special_button.mode_joystick = true
	_special_button.pressed.connect(func(): _special_queued = true)
	_root.add_child(_special_button)
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

## Visée manuelle du pouce droit — le doigt posé sur TIR et glissé
## au-delà de la zone morte donne la direction, façon Brawl Stars. Un
## appui sans glissement rend ZERO : visée automatique, comme avant.
func aim_vector() -> Vector2:
	return _visee_tactile.normalized() \
			if _visee_tactile.length_squared() > 1.0 else Vector2.ZERO

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

func consume_special() -> bool:
	if _special_queued:
		_special_queued = false
		return true
	return false


func consume_dash() -> bool:
	var v := _dash_queued
	_dash_queued = false
	return v

# --- MISES À JOUR --------------------------------------------------------

## Prochaine mise à jour du compteur FPS, en secondes.
var _fps_prochain := 0.0
## Dernière valeur dessinée de la jauge de dash.
var _dash_precedent := -1.0
var _special_precedent := -1.0


func _process(delta: float) -> void:
	if _fps_label:
		# QUATRE FOIS PAR SECONDE, PAS SOIXANTE. Réécrire le texte d'un
		# Label force sa remise en forme et son redessin ; le faire à
		# chaque image, c'est payer soixante mises en page par seconde
		# pour un chiffre qu'aucun œil ne lit à cette cadence.
		_fps_prochain -= delta
		if _fps_prochain <= 0.0:
			_fps_prochain = 0.25
			var f := Engine.get_frames_per_second()
			if Cfg.stats_detaillees:
				# t = scripts d'affichage, φ = physique+simulation, a =
				# appels de dessin. Les deux temps sont en millisecondes :
				# leur somme comparée à 16,6 dit si le blocage est dans le
				# code ; des appels par centaines disent qu'il est dans le
				# pilote graphique.
				_fps_label.text = "%d FPS · t %.1f · φ %.1f · a %d" % [f,
						Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
						Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
						int(RenderingServer.get_rendering_info(
								RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
			else:
				_fps_label.text = "%d FPS" % f
			# VERT, ORANGE, ROUGE. Le chiffre seul demande de savoir ce
			# qu'est une bonne cadence ; la couleur, non.
			_fps_label.add_theme_color_override(&"font_color",
					Color("8ef0a8") if f >= 50 else
					(UiKit.OR_CLAIR if f >= 30 else UiKit.ROUGE))
	# La bourse suit la prime du joueur local, et dit qui est roi.
	if _bourse != null and player != null:
		_bourse.poser(player.prime,
				PrimeDirector.multiplicateur(player.prime),
				PrimeDirector.roi_id == Net.local_id())

	if player and _special_button:
		var pret_c := player.special_ready_ratio()
		if absf(pret_c - _special_precedent) > 0.003:
			_special_precedent = pret_c
			_special_button.modulate.a = lerpf(0.55, 1.0, pret_c)
			_special_button.recharge = pret_c
			_special_button.attente = (1.0 - pret_c) * Player.SPECIAL_COOLDOWN
			_special_button.queue_redraw()

	if player and _dash_button:
		var pret := player.dash_ready_ratio()
		# LE BOUTON NE SE REDESSINE QUE SI SA JAUGE A BOUGÉ. Prêt, il est
		# STATIQUE — et « prêt » est son état les neuf dixièmes du temps.
		# L'ancien code le redessinait à chaque image, y compris immobile.
		if absf(pret - _dash_precedent) > 0.003:
			_dash_precedent = pret
			_dash_button.modulate.a = lerpf(0.55, 1.0, pret)
			_dash_button.recharge = pret
			_dash_button.attente = (1.0 - pret) * Player.DASH_COOLDOWN
			_dash_button.queue_redraw()

func _on_health_changed(_current: float, _maximum: float) -> void:
	# La vie du joueur local se lit sur SA plaque, au-dessus de sa tête —
	# le HUD n'affiche plus de jauge en bas. Le branchement reste : d'autres
	# retours (flash d'écran, sons de vie basse) pourront s'y greffer.
	pass

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
	# joue est un deathmatch permanent autour de la Prime. `Profil`
	# continue de tout enregistrer — la progression n'est pas supprimée,
	# elle n'est plus AFFICHÉE en combat.
	pass


# --- LA COURONNE ----------------------------------------------------------
#
# ON N'ANNONCE QUE LES COURONNEMENTS. Le trône change rarement de tête —
# et chaque bascule est un événement de la partie, digne de la plaque.

## LE COURONNEMENT S'ANNONCE — à celui qui monte comme à celui qui
## tombe. C'est la moitié du plaisir du trône : le moment où on le
## prend, et le moment où on nous le prend.
func _sur_roi_change(ancien_id: int, nouveau_id: int) -> void:
	if nouveau_id == Net.local_id():
		_on_announce("TU ES LE ROI", UiKit.OR_CLAIR)
	elif ancien_id == Net.local_id() and nouveau_id != 0:
		_on_announce("COURONNE PERDUE", UiKit.ROUGE)
	elif nouveau_id != 0:
		var nom := PrimeDirector.nom_roi()
		if nom != "":
			_on_announce("%s PREND LA COURONNE" % nom.to_upper(),
					UiKit.OR_CLAIR)


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
