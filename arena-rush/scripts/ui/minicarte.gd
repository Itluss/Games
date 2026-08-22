extends Control
class_name Minicarte
## MINICARTE — le monde vu de dessus, centré sur le joueur.
##
## POURQUOI ELLE COMPTE ICI PLUS QU'AILLEURS. Sur une carte bordée, on se
## repère aux bords : « je suis en haut à gauche ». Un monde qui s'enroule
## n'en a aucun, et rien ne dit plus où l'on se trouve — c'est le prix payé
## pour l'absence de limite. La minicarte rembourse ce prix.
##
## ELLE EST CENTRÉE SUR LE JOUEUR, ET ELLE S'ENROULE AUSSI. Une carte fixe
## aurait un bord, donc reposerait le problème qu'on vient de supprimer :
## on la verrait « finir » quelque part. Ici le fond défile sous le
## joueur et se répète, exactement comme le monde.
##
## Le fond est CUIT UNE FOIS au lancement : interroger le découpage des
## secteurs à chaque image, pour chaque pixel, coûterait plus cher que tout
## le reste de l'interface réunie.

## Côté de l'image cuite, en pixels. 96 pour 144 m fait 1,5 m par pixel :
## assez fin pour lire la forme des secteurs, assez grossier pour que la
## cuisson tienne en un clignement.
const CUISSON := 96
## Largeur du monde visible dans la fenêtre, en mètres.
const PORTEE := 96.0

var joueur: Node3D = null

## Découpe circulaire plutôt que rectangulaire.
##
## POURQUOI C'EST PLUS QU'UN HABILLAGE. La carte est CENTRÉE SUR LE
## JOUEUR : elle montre donc la même distance dans toutes les directions.
## Un cadre rond dit exactement cela ; un rectangle promet plus
## d'information sur les côtés qu'en haut, ce qui est faux.
var ronde: bool = false

static var _fond: ImageTexture = null

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PAS DE `clip_children` ICI. `CLIP_CHILDREN_ONLY` transforme le dessin
	# de l'élément en simple MASQUE et cesse de l'afficher : la carte était
	# entièrement invisible, vérifié en capture. Elle n'a de toute façon
	# aucun enfant à découper — c'est son propre `_draw` qui fait tout, et
	# le débordement du fond répété est arrêté par le cadre qui l'entoure.


func _ready() -> void:
	_cuire()
	set_process(true)


## Période de rafraîchissement, en secondes. Vingt fois par seconde.
##
## POURQUOI PAS À CHAQUE IMAGE. La carte se redessine entièrement à chaque
## appel : neuf portions de fond, tous les repères, tous les mobs, tous les
## adversaires. À soixante images par seconde c'est autant de parcours de
## groupes et de tracés pour un résultat que l'œil ne distingue pas — un
## point qui avance de trois pixels par seconde n'a pas besoin de soixante
## positions intermédiaires.
const PERIODE := 0.05

var _prochain := 0.0

func _process(delta: float) -> void:
	_prochain -= delta
	if _prochain > 0.0:
		return
	_prochain = PERIODE
	queue_redraw()


## Cuit le fond : une image du découpage en secteurs, teintes du sol.
static func _cuire() -> void:
	if _fond != null:
		return
	var img := Image.create(CUISSON, CUISSON, false, Image.FORMAT_RGBA8)
	for y in CUISSON:
		for x in CUISSON:
			var p := Vector2(
					-PlanMonde.DEMI + (float(x) + 0.5) * PlanMonde.COTE / CUISSON,
					-PlanMonde.DEMI + (float(y) + 0.5) * PlanMonde.COTE / CUISSON)
			var s := PlanMonde.secteur(PlanMonde.secteur_de(p))
			var c: Color = s["sol"] if s.has("sol") else UiKit.CREUX
			# ASSOMBRIE ET DÉSATURÉE. Les teintes du sol sont réglées pour
			# être vues sous un soleil rasant ; reprises telles quelles sur
			# un fond d'interface, elles éclatent et les points de gameplay
			# posés dessus deviennent illisibles. La carte est un CALQUE,
			# pas une photographie.
			img.set_pixel(x, y, c.darkened(0.42).lerp(UiKit.CREUX, 0.28))
	_fond = ImageTexture.create_from_image(img)


func _draw() -> void:
	var boite := Rect2(Vector2.ZERO, size)
	var milieu_boite := size * 0.5
	var rayon: float = minf(size.x, size.y) * 0.5
	if ronde:
		draw_circle(milieu_boite, rayon, UiKit.CREUX)
	else:
		draw_style_box(UiKit.panneau(14, UiKit.CREUX,
				Color(1, 1, 1, 0.0), 0), boite)
	if joueur == null or not is_instance_valid(joueur):
		if ronde:
			_cercle_cadre(milieu_boite, rayon)
		return

	var centre := Vector2(joueur.global_position.x, joueur.global_position.z)
	# Pixels d'écran par mètre de monde.
	var ech := size.x / PORTEE
	var milieu := size * 0.5

	# LE FOND, RÉPÉTÉ NEUF FOIS. Une seule copie laisserait un vide dès que
	# le joueur approche d'un bord du carré de référence — c'est-à-dire
	# précisément le défaut que le monde enroulé a supprimé, réintroduit
	# dans sa propre carte.
	var cote := PlanMonde.COTE * ech
	if _fond != null:
		# SANS DÉCOUPE, ON BORNE À LA MAIN. Les neuf copies déborderaient
		# largement du cadre et repeindraient l'interface autour ; on ne
		# dessine donc que la portion de chacune qui tombe dans la boîte.
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var o := milieu - centre * ech \
						+ Vector2(float(dx) * cote, float(dz) * cote) \
						- Vector2(cote, cote) * 0.5
				var tuile := Rect2(o, Vector2(cote, cote))
				var vu := tuile.intersection(boite)
				if vu.size.x <= 0.5 or vu.size.y <= 0.5:
					continue
				var src := Rect2(
						(vu.position - o) / ech * (float(CUISSON) / PlanMonde.COTE),
						vu.size / ech * (float(CUISSON) / PlanMonde.COTE))
				draw_texture_rect_region(_fond, vu, src)

	# ─── APPARTENANCE AU CADRE ────────────────────────────────────────
	#
	# Sans découpe matérielle — voir `_init`, `CLIP_CHILDREN_ONLY` rend la
	# carte invisible — c'est ce test qui borne tout ce qu'on dessine. En
	# rond, un point du coin passait le test rectangulaire et débordait
	# visiblement du disque.
	var dedans := func(p: Vector2) -> bool:
		if ronde:
			return p.distance_to(milieu_boite) <= rayon - 3.0
		return boite.has_point(p)

	# Les repères : ce sont eux qu'on cherche quand on ouvre une carte.
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var d := PlanMonde.ecart(centre, PlanMonde.position_poi(poi))
		var p := milieu + d * ech
		if not dedans.call(p):
			continue
		draw_circle(p, 5.0, Color(0.05, 0.08, 0.17, 0.85))
		draw_arc(p, 5.0, 0.0, TAU, 14, UiKit.OR_CLAIR, 2.0, true)

	# Les mobs, puis les adversaires, puis soi : l'ordre de dessin est
	# l'ordre d'importance, et le dernier tracé est celui qu'on voit.
	for n in get_tree().get_nodes_in_group(&"mobs"):
		var m := n as Node3D
		if m == null:
			continue
		var p := milieu + PlanMonde.ecart(centre,
				Vector2(m.global_position.x, m.global_position.z)) * ech
		if dedans.call(p):
			draw_circle(p, 2.6, Color(1.0, 0.78, 0.35, 0.9))

	for n in get_tree().get_nodes_in_group(&"players"):
		var j := n as Node3D
		# Un joueur déconnecté reste dans le groupe jusqu'à la fin de
		# l'image : sans `is_instance_valid`, la carte le dessine et lève
		# une erreur d'accès à un objet libéré.
		if j == null or not is_instance_valid(j) or j == joueur \
				or j.get(&"is_eliminated") == true:
			continue
		var p := milieu + PlanMonde.ecart(centre,
				Vector2(j.global_position.x, j.global_position.z)) * ech
		if not dedans.call(p):
			continue
		draw_circle(p, 4.2, Color(0.05, 0.08, 0.17, 0.9))
		# LE POINT PORTE LA COULEUR DU HÉROS, plus un rouge uniforme. Sur
		# la maquette, les points de la carte reprennent les teintes des
		# combattants : c'est ce qui permet de dire « Ruby arrive par le
		# nord » plutôt que « quelqu'un arrive ».
		var teinte := UiKit.ROUGE
		if j.has_method(&"heros"):
			teinte = Cfg.couleur_identite(j.call(&"heros"))
		draw_circle(p, 3.2, teinte)

	# SOI : une FLÈCHE, pas un point. Sur une carte qui tourne autour de
	# soi, savoir où l'on est ne sert à rien si l'on ignore où l'on regarde.
	var cap: float = joueur.rotation.y
	var av := Vector2(-sin(cap), -cos(cap))
	var lat := Vector2(av.y, -av.x)
	var fleche := PackedVector2Array([
		milieu + av * 9.0,
		milieu - av * 5.0 + lat * 6.0,
		milieu - av * 2.0,
		milieu - av * 5.0 - lat * 6.0,
	])
	draw_colored_polygon(fleche, UiKit.CYAN)
	draw_polyline(fleche + PackedVector2Array([milieu + av * 9.0]),
			Color(0.04, 0.07, 0.16, 0.9), 1.6, true)

	# ─── LE ROI DE LA PRIME, EN DERNIER ───────────────────────────────
	#
	# Dessiné après tout le reste, donc jamais recouvert : c'est
	# l'objectif du mode — un joueur, pas un objet — et une carte où il
	# faudrait le chercher sous un point de mob ne servirait à rien.
	# Aucune trace, aucune trajectoire : une traînée persistante
	# transformerait la carte en radar illisible en trois secondes.
	_marquer_le_roi(milieu, ech, dedans)
	if ronde:
		_cercle_cadre(milieu_boite, rayon)


func _marquer_le_roi(milieu: Vector2, ech: float, dedans: Callable) -> void:
	if not PrimeDirector.est_actif():
		return
	var roi := PrimeDirector.roi()
	if roi == null or roi == joueur:
		return
	var pos := Vector2(roi.global_position.x, roi.global_position.z)
	var centre := Vector2(joueur.global_position.x, joueur.global_position.z)
	var p := milieu + PlanMonde.ecart(centre, pos) * ech
	# HORS CADRE, ON LE RABAT SUR LE BORD. Un roi qui disparaît dès qu'il
	# sort du disque laisse le joueur sans direction au moment précis où
	# il en a le plus besoin. Rabattu, il continue de dire « par là ».
	if not dedans.call(p):
		var r: float = minf(size.x, size.y) * 0.5 - 9.0
		var d := p - milieu
		if d.length() < 0.01:
			return
		p = milieu + d.normalized() * r
	_poser_couronne(p, 7.0)


## Une couronne stylisée : trois pointes sur un bandeau — la même
## silhouette que la couronne 3D du roi. Deux dessins, une enseigne.
func _poser_couronne(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.3, Color(0.05, 0.04, 0.0, 0.75))
	var b := r * 0.55
	var pts := PackedVector2Array([
		c + Vector2(-r, b), c + Vector2(-r, -b * 0.2),
		c + Vector2(-r * 0.5, b * 0.15), c + Vector2(0, -r),
		c + Vector2(r * 0.5, b * 0.15), c + Vector2(r, -b * 0.2),
		c + Vector2(r, b),
	])
	draw_colored_polygon(pts, UiKit.OR_CLAIR)


## Le liseré du disque. Cyan comme le reste du point de vue du joueur.
func _cercle_cadre(c: Vector2, r: float) -> void:
	draw_arc(c, r - 1.0, 0.0, TAU, 48,
			UiKit.CYAN.lerp(UiKit.BLANC, 0.15), 3.0, true)
