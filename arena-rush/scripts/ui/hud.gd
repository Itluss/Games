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
const ARME_SIZE := 92

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
var _swap_button: UiKit.BoutonRond
var _dash_button: UiKit.BoutonRond
var _alive_label: Label
## RENOMMÉ, ET CE N'EST PAS COSMÉTIQUE. Ce libellé s'appelait
## `_timer_label` et affichait le chronomètre de la partie. Le mode
## persistant n'a plus ni manche ni fin, et le champ montre désormais le
## niveau — mais `_process` continuait d'y réécrire « 0:52 » à chaque
## image, par-dessus « LV.1 ». Le défaut se voyait sur toute capture
## d'écran ; le nom, lui, le rendait invisible à la relecture.
var _niveau_label: Label
var _announce: UiKit.Banniere
var _countdown: Label
var _health_bar: UiKit.BarreVie
var _slot_panels: Array[UiKit.CarteArme] = []
var _slot_verrou: UiKit.CarteArme
var _portrait: Portrait
var _minicarte: Minicarte
var _fil: FilEliminations
var _fps_label: Label
var _pod_kills: PanelContainer
var _serie_panel: PanelContainer
var _serie_label: Label
var _barre_xp: UiKit.JaugeXp
var _kill_fx: KillFeedback
var _replay_center: CenterContainer
var _tueur_affiche: String = ""
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label

var _swap_queued: bool = false
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
	_build_profil()
	_build_pods()
	_build_coin()


## PROFIL — portrait, nom, niveau, expérience.
func _build_profil() -> void:
	var carte := PanelContainer.new()
	carte.set_anchors_preset(Control.PRESET_TOP_LEFT)
	carte.position = Vector2(MARGIN, MARGIN)
	carte.add_theme_stylebox_override(&"panel",
			UiKit.panneau(22, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 3))
	carte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(carte)

	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override(&"separation", 14)
	ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carte.add_child(ligne)

	var marge := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right", &"margin_top",
			&"margin_bottom"]:
		marge.add_theme_constant_override(cote, 10)
	marge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ligne.add_child(marge)

	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(76, 76)
	marge.add_child(_portrait)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ligne.add_child(col)

	var titre := HBoxContainer.new()
	titre.add_theme_constant_override(&"separation", 14)
	titre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(titre)
	# LE NOM SUIT LE HÉROS RÉELLEMENT JOUÉ.
	#
	# Il était écrit en dur : « KAEL ». Vérifié en jeu au format téléphone,
	# le bandeau annonçait KAEL au-dessus d'un personnage qui est Milo. Un
	# joueur qui teste six démarches a besoin de savoir laquelle il tient —
	# c'est même la première chose qu'il regarde après l'avoir vue bouger.
	var nom := _label(String(Player.HEROS_LOCAL).to_upper(), 28)
	titre.add_child(nom)
	# LE NIVEAU EN OR, et pas en blanc. C'est la seule chose du bloc qui
	# progresse ; lui donner la couleur de la récompense la distingue d'un
	# simple libellé.
	_niveau_label = _label("LV.1", 26, UiKit.OR_CLAIR)
	titre.add_child(_niveau_label)

	_barre_xp = UiKit.JaugeXp.new()
	_barre_xp.custom_minimum_size = Vector2(216, 26)
	_barre_xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_barre_xp)

	var creux := MarginContainer.new()
	creux.add_theme_constant_override(&"margin_right", 12)
	creux.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ligne.add_child(creux)


## PODS DE PERFORMANCE — kills et série, au centre haut.
##
## Deux pastilles séparées plutôt qu'une barre continue : elles ne
## racontent pas la même chose, et la série APPARAÎT — un bloc qui pousse
## ses voisins en s'affichant serait perçu comme un défaut.
func _build_pods() -> void:
	var barre := HBoxContainer.new()
	barre.set_anchors_preset(Control.PRESET_CENTER_TOP)
	barre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	barre.offset_top = MARGIN
	barre.add_theme_constant_override(&"separation", 14)
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(barre)

	_pod_kills = _pod(&"crane", "KILLS", UiKit.BLANC)
	barre.add_child(_pod_kills)
	_alive_label = _pod_valeur(_pod_kills)

	_serie_panel = _pod(&"serie", "SÉRIE", UiKit.OR_CLAIR)
	barre.add_child(_serie_panel)
	_serie_label = _pod_valeur(_serie_panel)
	_serie_panel.visible = false


## Une pastille : icône + libellé sur une ligne, grand nombre en dessous.
func _pod(icone: StringName, libelle: String, teinte: Color) -> PanelContainer:
	var pod := PanelContainer.new()
	pod.custom_minimum_size = Vector2(158, 78)
	pod.add_theme_stylebox_override(&"panel",
			UiKit.panneau(20, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 3))
	pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	# NOM EXPLICITE, ET C'EST UN CORRECTIF. Sans nom, Godot en attribue un
	# automatique — « @VBoxContainer@37 » — et le chemin écrit à la main ne
	# trouvait rien. Les deux libellés de pastille restaient donc NULS, et
	# toute la mise à jour des statistiques avortait à la première ligne :
	# kills, série, niveau et barre d'expérience gelés à leur valeur de
	# départ. Le journal du navigateur l'a dit en une ligne, ce qu'aucune
	# capture d'écran n'aurait révélé — l'interface avait l'air normale.
	col.name = "Colonne"
	col.add_theme_constant_override(&"separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pod.add_child(col)
	var tete := HBoxContainer.new()
	tete.alignment = BoxContainer.ALIGNMENT_CENTER
	tete.add_theme_constant_override(&"separation", 7)
	tete.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tete)
	var ic := UiKit.Glyphe.new()
	ic.id = icone
	ic.teinte = teinte
	ic.custom_minimum_size = Vector2(26, 26)
	tete.add_child(ic)
	var lib := _label(libelle, 16, Color(1, 1, 1, 0.7))
	lib.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tete.add_child(lib)
	var val := _label("0", 30, teinte)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.name = "Valeur"
	col.add_child(val)
	return pod


func _pod_valeur(pod: PanelContainer) -> Label:
	var l := pod.get_node_or_null("Colonne/Valeur") as Label
	if l == null:
		push_error("Pastille sans valeur : la mise à jour des statistiques "
				+ "serait silencieusement morte.")
	return l


## Largeur et hauteur du bloc d'orientation, en pixels.
const LARGEUR_COIN := 224
const HAUTEUR_COIN := 300


## COIN D'ORIENTATION — cadence, réglages, carte, fil des éliminations.
func _build_coin() -> void:
	# GÉOMÉTRIE EXPLICITE, PAS UN PRÉRÉGLAGE D'ANCRAGE.
	#
	# `PRESET_TOP_RIGHT` pose les quatre bords au même endroit : le
	# conteneur naît large de zéro pixel, et les ancrages « grandir vers la
	# gauche » ne le rattrapent pas. Vérifié en capture DEUX FOIS — seul le
	# premier enfant apparaissait, carte et fil restaient invisibles, et
	# j'ai d'abord accusé la découpe. Les ancrages posés à la main ne
	# laissent aucune place à ce genre de malentendu.
	var col := VBoxContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.0
	col.anchor_bottom = 0.0
	col.offset_left = -(LARGEUR_COIN + MARGIN)
	col.offset_right = -MARGIN
	col.offset_top = MARGIN
	col.offset_bottom = MARGIN + HAUTEUR_COIN
	col.add_theme_constant_override(&"separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)

	var tete := HBoxContainer.new()
	tete.alignment = BoxContainer.ALIGNMENT_END
	tete.add_theme_constant_override(&"separation", 10)
	tete.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tete)

	# LA CADENCE, ET NON UNE LATENCE RÉSEAU. La maquette affiche un ping ;
	# en solo il n'y en a pas, et inventer un chiffre serait mentir sur un
	# écran dont tout le rôle est d'informer. Les images par seconde disent
	# la même chose — le jeu tient-il la route — et elles, on les a.
	var pastille := PanelContainer.new()
	pastille.add_theme_stylebox_override(&"panel",
			UiKit.panneau(16, UiKit.PANNEAU, UiKit.PANNEAU_BORD, 3))
	pastille.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tete.add_child(pastille)
	var m := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right"]:
		m.add_theme_constant_override(cote, 12)
	for cote in [&"margin_top", &"margin_bottom"]:
		m.add_theme_constant_override(cote, 5)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pastille.add_child(m)
	_fps_label = _label("60 FPS", 18, Color("8ef0a8"))
	m.add_child(_fps_label)

	var reglages := UiKit.bouton_rond(46.0, "", &"engrenage",
			UiKit.NEUTRE_CLAIR, UiKit.NEUTRE_SOMBRE)
	reglages.pressed.connect(_basculer_legende)
	tete.add_child(reglages)

	# LA CARTE. Elle est encadrée d'un liseré cyan : c'est la couleur du
	# joueur dans tout le jeu, et l'encadrement dit à qui appartient ce
	# point de vue.
	var cadre := PanelContainer.new()
	cadre.add_theme_stylebox_override(&"panel",
			UiKit.panneau(16, UiKit.CREUX, UiKit.CYAN.lerp(UiKit.BLANC, 0.15), 3))
	cadre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cadre)
	var dedans := MarginContainer.new()
	for cote in [&"margin_left", &"margin_right", &"margin_top",
			&"margin_bottom"]:
		dedans.add_theme_constant_override(cote, 4)
	dedans.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cadre.add_child(dedans)
	_minicarte = Minicarte.new()
	_minicarte.custom_minimum_size = Vector2(LARGEUR_COIN - 14, 152)
	dedans.add_child(_minicarte)

	_fil = FilEliminations.new()
	_fil.custom_minimum_size = Vector2(LARGEUR_COIN, 70)
	_fil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_fil)


func _build_center() -> void:
	# Une PLAQUE et non un texte nu : une élimination est un évènement, elle
	# mérite un objet à l'écran. Un mot qui apparaît seul se confond avec le
	# décor ; une plaque dorée s'impose et s'oublie aussitôt après.
	_announce = UiKit.Banniere.new()
	_announce.set_anchors_preset(Control.PRESET_TOP_WIDE)
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

## BAS DE L'ÉCRAN — vie au-dessus, armement en dessous.
##
## Le centre bas est la seule zone qu'aucun pouce ne couvre : c'est pour
## cela que les deux informations qu'on lit EN COMBAT y sont posées.
func _build_bottom() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.offset_bottom = -MARGIN
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override(&"separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)

	var health_row := CenterContainer.new()
	health_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(health_row)

	_health_bar = UiKit.BarreVie.new()
	_health_bar.custom_minimum_size = Vector2(380, 40)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_row.add_child(_health_bar)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override(&"separation", 14)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(slots)

	# DEUX EMPLACEMENTS OUVERTS, UN VERROUILLÉ. Le troisième n'est pas un
	# ornement : il montre ce que le niveau débloquera. Un emplacement vide
	# ne dit rien ; un emplacement fermé avec sa condition écrite dessus
	# donne une raison de continuer, et c'est exactement ce que la
	# progression horizontale doit produire.
	for i in 2:
		var carte := UiKit.CarteArme.new()
		carte.custom_minimum_size = Vector2(206, 76)
		carte.gui_input.connect(_on_slot_input.bind(i))
		carte.mouse_filter = Control.MOUSE_FILTER_STOP
		carte.pivot_offset = Vector2(103, 38)
		slots.add_child(carte)
		_slot_panels.append(carte)

	_slot_verrou = UiKit.CarteArme.new()
	_slot_verrou.custom_minimum_size = Vector2(150, 76)
	_slot_verrou.verrouille = true
	_slot_verrou.nom = "ÉPÉE VORTEX"
	_slot_verrou.condition = "NIV. %d" % NIVEAU_TROISIEME_ARME
	_slot_verrou.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_child(_slot_verrou)


## Niveau auquel le troisième emplacement s'ouvrira. La valeur est ICI et
## nulle part ailleurs : l'étiquette affichée et la règle qui l'ouvrira un
## jour doivent être le même nombre.
const NIVEAU_TROISIEME_ARME := 6


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
	_swap_button = UiKit.bouton_rond(ARME_SIZE, "ARME", &"echange",
			UiKit.ARME_CLAIR, UiKit.ARME_SOMBRE)
	_swap_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_swap_button.offset_left = -(FIRE_SIZE + MARGIN + ARME_SIZE + 18)
	_swap_button.offset_top = -(MARGIN + ARME_SIZE + 8)
	_swap_button.offset_right = -(FIRE_SIZE + MARGIN + 18)
	_swap_button.offset_bottom = -(MARGIN + 8)
	_swap_button.pressed.connect(func(): _swap_queued = true)
	_root.add_child(_swap_button)

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

## Consommation à usage unique : le contrôleur lit l'appui une seule fois,
## sinon un simple tap déclencherait un changement d'arme par image.
func consume_swap() -> bool:
	var v := _swap_queued
	_swap_queued = false
	return v

func consume_dash() -> bool:
	var v := _dash_queued
	_dash_queued = false
	return v

func _on_slot_input(event: InputEvent, index: int) -> void:
	var tapped: bool = false
	if event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if tapped and player and player.active_slot != index:
		_swap_queued = true

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
	if _alive_label == null:
		return
	# Les KILLS DE SESSION, pas le total de la vie entière. « 7 » veut dire
	# quelque chose maintenant ; « 4 213 » ne veut plus rien dire.
	_alive_label.text = str(Profil.kills_session)
	var serie: int = Profil.serie_actuelle
	_serie_panel.visible = serie >= 2
	_serie_label.text = "x%d" % serie
	var etat := Profil.etat_niveau()
	_niveau_label.text = "LV.%d" % int(etat["niveau"])
	_barre_xp.regler(int(etat["xp_dans_niveau"]), int(etat["xp_du_niveau"]))
	if _slot_verrou:
		# L'emplacement fermé disparaît le jour où le niveau l'ouvre : une
		# case verrouillée qu'on a débloquée n'a plus rien à dire.
		_slot_verrou.visible = int(etat["niveau"]) < NIVEAU_TROISIEME_ARME


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
	# LE FIL REÇOIT TOUTES LES ÉLIMINATIONS, pas seulement les siennes.
	# C'est tout son intérêt : lire que deux adversaires se sont battus à
	# l'autre bout de la carte est ce qui fait qu'un monde persistant a des
	# habitants plutôt que des cibles.
	if _fil:
		_fil.ajouter(tueur_nom.to_upper(), _nom_de(victime_id).to_upper(),
				player != null and tueur_id == player.peer_id)
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
	var goal := _label("TUEZ DES MOBS · PRENEZ LEURS ARMES · ÉLIMINEZ LES JOUEURS",
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
