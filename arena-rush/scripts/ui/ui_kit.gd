extends RefCounted
class_name UiKit
## KIT D'INTERFACE — l'équivalent 2D de VisualKit.
##
## POURQUOI CE FICHIER EXISTE : l'interface était fonctionnelle et plate —
## des cercles translucides à bord fin, du texte nu. La référence visée est
## celle des jeux d'arène mobiles : des formes CHARNUES, opaques, cerclées
## de blanc épais, posées sur une ombre, avec une typographie grasse et
## penchée. Recopier ces réglages bouton par bouton garantissait qu'ils
## divergent au premier ajout. Ils vivent donc ici, une seule fois.
##
## AUCUN FICHIER IMAGE. Tout est dessiné à l'exécution :
##   • une icône vectorielle reste nette à toute densité d'écran, du
##     téléphone au moniteur — et le jeu vise d'abord le mobile ;
##   • rien à télécharger avant de jouer, sur une build web où chaque
##     kilo-octet retarde la première image ;
##   • une couleur se change par une constante, pas en réexportant un
##     atlas.
##
## LE DÉGRADÉ, PIÈCE MAÎTRESSE DU STYLE. Godot ne sait pas remplir un
## cercle en dégradé. On le compose donc en bandes horizontales dont la
## largeur suit celle du disque à chaque hauteur : seize bandes suffisent à
## ce que l'œil ne voie plus de marches. Ce n'est calculé qu'au redessin,
## jamais à chaque image.

# --- PALETTE D'INTERFACE -------------------------------------------------
# Distincte de la palette du monde : une interface doit rester lisible
# quelle que soit l'arène derrière elle. Ces teintes ne dépendent donc pas
# de la direction artistique du décor.

const BLANC := Color("f4f7ff")
const ENCRE := Color("101a33")
const OMBRE := Color(0.03, 0.05, 0.12, 0.42)

## Chaque bouton porte DEUX tons : le clair en haut, le sombre en bas.
## C'est cet écart qui donne le volume, bien plus que l'ombre portée.
const TIR_CLAIR := Color("ff9b3d")
const TIR_SOMBRE := Color("f2452c")
const ESQUIVE_CLAIR := Color("54a8ff")
const ESQUIVE_SOMBRE := Color("2b62d8")
const ARME_CLAIR := Color("b07bff")
const ARME_SOMBRE := Color("7b3fd4")
const NEUTRE_CLAIR := Color("ffffff")
const NEUTRE_SOMBRE := Color("d5ddf0")
const VIE_CLAIR := Color("7ff06a")
const VIE_SOMBRE := Color("2fae3c")
const OR_CLAIR := Color("ffce4d")
const OR_SOMBRE := Color("f08b1e")

## Fond des panneaux : bleu nuit dense, jamais un gris neutre. Un gris
## paraît sale au-dessus d'une image colorée.
const PANNEAU := Color("16213f")
const PANNEAU_BORD := Color(1, 1, 1, 0.22)

const BANDES := 16


# --- TYPOGRAPHIE ---------------------------------------------------------

## Police grasse et penchée, dérivée de celle du moteur.
##
## POURQUOI UNE VARIATION plutôt qu'un fichier de police : embarquer une
## fonte grasse italique coûterait des centaines de kilo-octets sur une
## build web, et il faudrait la licencier. `FontVariation` épaissit et
## incline la fonte de base à l'exécution, ce qui donne l'essentiel du
## caractère pour zéro octet.
static var _polices: Dictionary = {}

static func police(gras := true, penche := true) -> FontVariation:
	var cle := "%s%s" % [gras, penche]
	if _polices.has(cle):
		return _polices[cle]
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.62 if gras else 0.0
	if penche:
		# Cisaillement : le haut des lettres part vers la droite. En 2D, l'axe
		# Y descend, donc le haut d'un glyphe est en Y négatif — d'où le signe.
		f.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.2, 1),
				Vector2.ZERO)
	_polices[cle] = f
	return f


## Applique la typographie maison à n'importe quel contrôle porteur de texte.
##
## Le CONTOUR SOMBRE n'est pas décoratif : le texte blanc doit rester lisible
## au-dessus d'un sol clair comme d'une explosion. Sans lui, l'interface
## disparaît exactement au moment où l'on en a besoin.
static func texte(c: Control, taille: int, couleur: Color = BLANC,
		contour: int = 6) -> void:
	c.add_theme_font_override(&"font", police())
	c.add_theme_font_size_override(&"font_size", taille)
	c.add_theme_color_override(&"font_color", couleur)
	c.add_theme_color_override(&"font_outline_color", Color(0.04, 0.07, 0.16, 0.9))
	c.add_theme_constant_override(&"outline_size", contour)
	# Un Button porte le même texte sous quatre états : sans cela, il
	# s'assombrit au survol et paraît changer de couleur.
	if c is Button:
		for etat in [&"font_pressed_color", &"font_hover_color",
				&"font_focus_color", &"font_hover_pressed_color"]:
			c.add_theme_color_override(etat, couleur)


# --- FORMES --------------------------------------------------------------

## Disque en dégradé vertical, clair en haut.
##
## Godot ne remplit pas un cercle en dégradé : on empile des bandes dont la
## demi-largeur vaut sqrt(r² - y²), c'est-à-dire la corde du cercle à cette
## hauteur. Le résultat est un vrai dégradé circulaire, sans texture.
static func disque_degrade(ci: CanvasItem, centre: Vector2, rayon: float,
		haut: Color, bas: Color) -> void:
	var pas := (rayon * 2.0) / float(BANDES)
	for i in BANDES:
		var y0 := -rayon + pas * float(i)
		var y1 := y0 + pas
		# On mesure la corde au point le plus large de la bande : ainsi les
		# bandes se recouvrent légèrement au lieu de laisser voir le fond
		# entre elles.
		var y_large: float = y0 if absf(y0) < absf(y1) else y1
		var demi := sqrt(maxf(0.0, rayon * rayon - y_large * y_large))
		if demi <= 0.0:
			continue
		var t := (float(i) + 0.5) / float(BANDES)
		ci.draw_rect(Rect2(centre.x - demi, centre.y + y0, demi * 2.0, pas + 1.0),
				haut.lerp(bas, t))


## Bouton circulaire « bonbon » : ombre portée, anneau blanc épais, disque
## en dégradé, reflet en haut, icône, et libellé posé en bas.
##
## C'est le seul élément que le joueur regarde en permanence : il mérite
## d'être dessiné à la main plutôt qu'assemblé en boîtes de style.
class BoutonRond extends Button:
	var ton_clair: Color = UiKit.TIR_CLAIR
	var ton_sombre: Color = UiKit.TIR_SOMBRE
	var libelle: String = ""
	var icone: StringName = &""
	## Enfoncement TACTILE, distinct de l'état souris du bouton : Godot
	## fusionne le multi-touch en une souris unique, donc le retour visuel
	## au doigt doit être piloté à la main. C'est le défaut qui rendait le
	## bouton de tir « mort » quand on courait.
	var enfonce_doigt: bool = false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		# Les quatre états sont VIDÉS : tout le dessin est fait par _draw,
		# et un fond de thème résiduel apparaîtrait derrière lui.
		var vide := StyleBoxEmpty.new()
		for etat in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(etat, vide)

	func _ready() -> void:
		# Le libellé est dessiné par _draw, à sa place exacte : le texte
		# natif d'un Button se centrerait et passerait sur l'icône.
		text = ""
		UiKit.texte(self, 18)

	func est_enfonce() -> bool:
		return enfonce_doigt or button_pressed

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		var appuye := est_enfonce()
		# L'enfoncement se lit à l'ŒIL avant de se lire au doigt : le bouton
		# rapetisse et son ombre se rapproche, comme s'il touchait le fond.
		var k := 0.94 if appuye else 1.0
		r *= k

		draw_circle(c + Vector2(0, r * (0.10 if appuye else 0.17)),
				r * 0.99, UiKit.OMBRE)
		# Anneau blanc : c'est lui qui détache le bouton de N'IMPORTE QUEL
		# fond, ce que ne fait aucune couleur seule.
		draw_circle(c, r, UiKit.BLANC)
		var bord := maxf(4.0, r * 0.09)
		var clair := ton_clair.lightened(0.12) if appuye else ton_clair
		var sombre := ton_sombre.lightened(0.10) if appuye else ton_sombre
		UiKit.disque_degrade(self, c, r - bord, clair, sombre)
		# Reflet : un arc clair en haut, la marque du plastique brillant.
		if not appuye:
			draw_arc(c, (r - bord) * 0.74, PI * 1.18, PI * 1.82, 20,
					Color(1, 1, 1, 0.34), maxf(3.0, r * 0.11), true)

		var haut_icone := c - Vector2(0, r * (0.20 if libelle != "" else 0.0))
		UiKit.icone(self, icone, haut_icone, r * 0.42, UiKit.BLANC)

		if libelle == "":
			return
		var f := UiKit.police()
		# LE LIBELLÉ S'ADAPTE AU BOUTON, jamais l'inverse. Mesuré en image,
		# « ESQUIVE » à une taille proportionnelle débordait franchement de
		# son cercle : un mot de sept lettres et un mot de trois n'occupent
		# pas la même largeur, et seule la mesure le sait. On réduit donc
		# jusqu'à ce que le mot tienne dans la corde du disque.
		var taille := int(maxf(11.0, r * 0.30))
		var largeur := f.get_string_size(libelle, HORIZONTAL_ALIGNMENT_LEFT,
				-1, taille).x
		# LA LARGEUR DISPONIBLE EST LA CORDE DU DISQUE À LA HAUTEUR DU MOT,
		# pas son diamètre. « ESQUIVE » tenait dans les 104 px du cercle mais
		# débordait quand même : posé aux quatre cinquièmes de la hauteur, le
		# disque n'y fait plus que 125 px de large sur son axe, et le mot en
		# occupait 95 une fois pris le contour. Mesurer au bon endroit change
		# tout.
		# ET LE CONTOUR COMPTE. `get_string_size` mesure les glyphes NUS :
		# les six pixels de contour de chaque côté, plus l'inclinaison,
		# ajoutent près de vingt pixels que la mesure ignore. « ESQUIVE »
		# rentrait donc « sur le papier » et débordait à l'écran.
		#
		# On remonte aussi le mot à 62 % du rayon plutôt que 78 % : plus haut,
		# la corde du disque est nettement plus large, donc le mot garde une
		# taille lisible au lieu d'être rapetissé jusqu'à l'inutile.
		var h := 0.62
		var dispo := 2.0 * sqrt(maxf(0.0, 1.0 - h * h)) * r - 18.0
		while largeur > dispo and taille > 9:
			taille -= 1
			largeur = f.get_string_size(libelle, HORIZONTAL_ALIGNMENT_LEFT,
					-1, taille).x
		var pos := Vector2(c.x - largeur * 0.5, c.y + r * h)
		draw_string_outline(f, pos, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1,
				taille, 6, Color(0.04, 0.07, 0.16, 0.9))
		draw_string(f, pos, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille,
				UiKit.BLANC)


static func bouton_rond(taille: float, libelle: String, icone_id: StringName,
		clair: Color, sombre: Color) -> BoutonRond:
	var b := BoutonRond.new()
	b.custom_minimum_size = Vector2(taille, taille)
	b.size = Vector2(taille, taille)
	b.libelle = libelle
	b.icone = icone_id
	b.ton_clair = clair
	b.ton_sombre = sombre
	return b


# --- PANNEAUX ------------------------------------------------------------

## Boîte de style commune : coins francs, bord clair, ombre portée.
static func panneau(rayon: int = 18, fond: Color = PANNEAU,
		bord: Color = PANNEAU_BORD, epaisseur: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fond
	s.set_corner_radius_all(rayon)
	s.set_border_width_all(epaisseur)
	s.border_color = bord
	# L'ombre pose l'élément SUR l'image au lieu de le coller dedans. C'est
	# ce détail, plus que la couleur, qui sépare une interface de jeu d'un
	# calque de débogage.
	s.shadow_color = OMBRE
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


## Rectangle arrondi en dégradé vertical, dessiné à la main.
##
## Même raison que pour le disque : Godot n'offre pas de dégradé dans une
## boîte de style. On peint le fond plein, puis un voile clair sur la
## moitié haute — deux dessins au lieu de seize, parce qu'un rectangle n'a
## pas de corde à suivre.
static func rect_degrade(ci: CanvasItem, zone: Rect2, haut: Color,
		bas: Color, rayon: int) -> void:
	var fond := StyleBoxFlat.new()
	fond.bg_color = bas
	fond.set_corner_radius_all(rayon)
	ci.draw_style_box(fond, zone)
	var voile := StyleBoxFlat.new()
	voile.bg_color = haut
	voile.set_corner_radius_all(rayon)
	# Le voile ne couvre que le haut, et ses coins bas restent arrondis pour
	# que la transition ne dessine pas une arête horizontale.
	ci.draw_style_box(voile, Rect2(zone.position,
			Vector2(zone.size.x, zone.size.y * 0.52)))


# --- ICÔNES --------------------------------------------------------------

## Répartiteur d'icônes. Chacune est tracée dans un carré centré sur
## `centre`, de demi-côté `r`, ce qui les rend interchangeables : changer
## l'icône d'un bouton ne demande aucun ajustement de position.
static func icone(ci: CanvasItem, id: StringName, centre: Vector2, r: float,
		teinte: Color) -> void:
	match id:
		&"viseur": _icone_viseur(ci, centre, r, teinte)
		&"eclair": _icone_eclair(ci, centre, r, teinte)
		&"echange": _icone_echange(ci, centre, r, teinte)
		&"coeur": _icone_coeur(ci, centre, r, teinte)
		&"menu": _icone_menu(ci, centre, r, teinte)
		&"engrenage": _icone_engrenage(ci, centre, r, teinte)
		_: pass


static func _icone_viseur(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(3.0, r * 0.17)
	ci.draw_arc(c, r * 0.62, 0.0, TAU, 32, t, e, true)
	ci.draw_circle(c, r * 0.17, t)
	# Quatre mires qui débordent du cercle : c'est ce débordement qui fait
	# lire « viseur » plutôt que « cible ».
	for i in 4:
		var a := TAU * float(i) / 4.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.44, c + d * r, t, e, true)


static func _icone_eclair(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	# Un éclair dit « vitesse » sans texte et se lit à toute taille, là où
	# une silhouette de coureur devient une tache sous 40 pixels.
	var p := PackedVector2Array([
		c + Vector2(r * 0.22, -r),
		c + Vector2(-r * 0.52, r * 0.14),
		c + Vector2(-r * 0.05, r * 0.14),
		c + Vector2(-r * 0.24, r),
		c + Vector2(r * 0.54, -r * 0.16),
		c + Vector2(r * 0.05, -r * 0.16),
	])
	ci.draw_colored_polygon(p, t)


static func _icone_echange(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(3.0, r * 0.19)
	# `s` est TYPÉ explicitement. Sorti d'un tableau littéral, il n'a aucun
	# type, et GDScript refuse alors d'inférer celui de tout ce qu'on en
	# dérive. C'est le même piège qui m'a déjà coûté deux exécutions
	# ailleurs — il échoue à la compilation, donc au moins il se voit.
	for s: float in [-1.0, 1.0]:
		var y := c.y + r * 0.34 * s
		ci.draw_line(Vector2(c.x - r * 0.66, y), Vector2(c.x + r * 0.66, y),
				t, e, true)
		# Pointe orientée à l'opposé pour chaque flèche : c'est l'opposition
		# qui signifie « échanger », pas la flèche seule.
		var px := c.x + r * 0.66 * -s
		var dir := -s
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(px + r * 0.30 * dir, y),
			Vector2(px, y - r * 0.26),
			Vector2(px, y + r * 0.26)]), t)


static func _icone_coeur(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.24), r * 0.42, t)
	ci.draw_circle(c + Vector2(r * 0.36, -r * 0.24), r * 0.42, t)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.76, -r * 0.10),
		c + Vector2(r * 0.76, -r * 0.10),
		c + Vector2(0, r * 0.82)]), t)


static func _icone_menu(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(3.0, r * 0.22)
	for i in 3:
		var y := c.y + (float(i) - 1.0) * r * 0.52
		ci.draw_line(Vector2(c.x - r * 0.62, y), Vector2(c.x + r * 0.62, y),
				t, e, true)


static func _icone_engrenage(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.5, c + d * r * 0.98, t,
				maxf(3.0, r * 0.26), true)
	# Le corps est un ANNEAU et non un disque : le moyeu reste ainsi
	# réellement vide, quelle que soit la couleur du bouton derrière.
	# Percer un disque en repeignant par-dessus n'aurait marché que sur un
	# fond uni, et le nôtre est en dégradé.
	ci.draw_arc(c, r * 0.46, 0.0, TAU, 28, t, maxf(4.0, r * 0.3), true)


# --- ÉLÉMENTS COMPOSÉS ---------------------------------------------------

## BARRE DE VIE — médaillon à gauche, jauge en dégradé, chiffres au centre.
##
## POURQUOI UN MÉDAILLON QUI DÉBORDE : une barre seule se confond avec
## n'importe quelle autre jauge. Le cœur, posé à cheval sur son extrémité,
## dit ce que la barre mesure sans un mot — et le débordement crée un
## relief que la barre à elle seule n'a pas.
##
## LA JAUGE VIRE AU ROUGE en fin de course, et pas linéairement : à
## mi-vie on est encore en jeu, à 20 % on est en danger. La courbe
## concentre donc l'alerte là où elle compte.
class BarreVie extends Control:
	var ratio: float = 1.0
	var valeur: int = 100
	var maximum: int = 100

	func regler(courant: float, maxi: float) -> void:
		maximum = int(round(maxi))
		valeur = int(ceil(courant))
		ratio = clampf(courant / maxf(maxi, 0.01), 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := int(size.y * 0.5)
		var fond := UiKit.panneau(r, Color(0.05, 0.08, 0.17, 0.86))
		draw_style_box(fond, Rect2(Vector2.ZERO, size))

		var marge := 5.0
		var utile := size.x - marge * 2.0
		if ratio > 0.005:
			var zone := Rect2(marge, marge, maxf(size.y - marge * 2.0,
					utile * ratio), size.y - marge * 2.0)
			var danger: float = pow(1.0 - ratio, 1.8)
			var clair := UiKit.VIE_CLAIR.lerp(Color("ff8a6a"), danger)
			var sombre := UiKit.VIE_SOMBRE.lerp(Color("d62d2d"), danger)
			UiKit.rect_degrade(self, zone, clair, sombre,
					int(zone.size.y * 0.5))

		var f := UiKit.police()
		var t := "%d / %d" % [valeur, maximum]
		var taille := int(size.y * 0.52)
		var l := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille)
		var p := Vector2(size.x * 0.5 - l.x * 0.5, size.y * 0.5 + taille * 0.36)
		draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 6,
				Color(0.04, 0.07, 0.16, 0.95))
		draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, UiKit.BLANC)

		# Le médaillon EN DERNIER : il doit passer par-dessus la jauge, dont
		# il masque volontairement le départ.
		var c := Vector2(0.0, size.y * 0.5)
		var rc := size.y * 0.76
		draw_circle(c + Vector2(0, rc * 0.14), rc, UiKit.OMBRE)
		draw_circle(c, rc, UiKit.BLANC)
		UiKit.disque_degrade(self, c, rc - maxf(3.0, rc * 0.14),
				UiKit.VIE_CLAIR, UiKit.VIE_SOMBRE)
		UiKit.icone(self, &"coeur", c, rc * 0.5, UiKit.BLANC)


## BANNIÈRE D'ANNONCE — la plaque dorée des éliminations.
##
## Elle se dimensionne sur son texte plutôt que d'occuper une largeur fixe :
## « BOT 3 ÉLIMINÉ » et « VICTOIRE » n'ont pas la même longueur, et une
## plaque trop large autour d'un mot court sonne faux.
class Banniere extends Control:
	var contenu: String = ""
	var clair: Color = UiKit.OR_CLAIR
	var sombre: Color = UiKit.OR_SOMBRE

	func afficher(t: String, c1: Color, c2: Color) -> void:
		contenu = t
		clair = c1
		sombre = c2
		queue_redraw()

	func _draw() -> void:
		if contenu == "":
			return
		var f := UiKit.police()
		var taille := 40
		var l := f.get_string_size(contenu, HORIZONTAL_ALIGNMENT_LEFT, -1,
				taille)
		var zone := Rect2(size.x * 0.5 - l.x * 0.5 - 46.0, 0.0,
				l.x + 92.0, 74.0)
		var ombre := StyleBoxFlat.new()
		ombre.bg_color = UiKit.OMBRE
		ombre.set_corner_radius_all(18)
		draw_style_box(ombre, Rect2(zone.position + Vector2(0, 6), zone.size))
		UiKit.rect_degrade(self, zone, clair, sombre, 18)
		# Liseré clair : la plaque doit tenir au-dessus d'un ciel clair
		# comme d'une explosion.
		var bord := StyleBoxFlat.new()
		bord.bg_color = Color(0, 0, 0, 0)
		bord.set_corner_radius_all(18)
		bord.set_border_width_all(4)
		bord.border_color = Color(1, 1, 1, 0.8)
		draw_style_box(bord, zone)

		var p := Vector2(size.x * 0.5 - l.x * 0.5, zone.size.y * 0.5 + taille * 0.36)
		draw_string_outline(f, p, contenu, HORIZONTAL_ALIGNMENT_LEFT, -1,
				taille, 9, Color(0.35, 0.13, 0.02, 0.95))
		draw_string(f, p, contenu, HORIZONTAL_ALIGNMENT_LEFT, -1, taille,
				UiKit.BLANC)


## SEGMENT DE LA BARRE DU HAUT. Les segments s'accolent en une seule
## capsule : seuls les coins des EXTRÉMITÉS sont arrondis, sinon on verrait
## deux pastilles posées côte à côte au lieu d'un bandeau d'un seul tenant.
static func segment(fond: Color, gauche: bool, droite: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fond
	var r := 22
	s.corner_radius_top_left = r if gauche else 0
	s.corner_radius_bottom_left = r if gauche else 0
	s.corner_radius_top_right = r if droite else 0
	s.corner_radius_bottom_right = r if droite else 0
	s.content_margin_left = 26 if gauche else 20
	s.content_margin_right = 26 if droite else 20
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.shadow_color = OMBRE
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s
