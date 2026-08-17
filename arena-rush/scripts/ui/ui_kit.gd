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
## L'écart de TEINTE entre les deux tons compte autant que l'écart de
## luminosité : un bouton orange en haut et rouge en bas paraît bien plus
## riche que le même orange simplement assombri, parce que c'est ce que la
## lumière fait réellement sur une matière colorée.
const TIR_CLAIR := Color("ffb03a")
const TIR_SOMBRE := Color("e02f26")
const ESQUIVE_CLAIR := Color("6ec0ff")
const ESQUIVE_SOMBRE := Color("1c48cf")
const ARME_CLAIR := Color("c98cff")
const ARME_SOMBRE := Color("6524c4")
const NEUTRE_CLAIR := Color("ffffff")
const NEUTRE_SOMBRE := Color("cfd8ee")
const VIE_CLAIR := Color("9bf76d")
const VIE_SOMBRE := Color("1f9436")
const OR_CLAIR := Color("ffce4d")
const OR_SOMBRE := Color("f08b1e")

## Fond des panneaux : bleu nuit dense, jamais un gris neutre. Un gris
## paraît sale au-dessus d'une image colorée.
const PANNEAU := Color("16213f")
const PANNEAU_BORD := Color(1, 1, 1, 0.22)


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


# --- PASTILLES : DES TEXTURES, PLUS DES BANDES ---------------------------
#
# CE QUE FAISAIT LA VERSION PRÉCÉDENTE, ET POURQUOI C'ÉTAIT MAUVAIS.
# Le dégradé d'un bouton était peint en seize bandes rectangulaires
# empilées, chacune large de la corde du cercle à sa hauteur. À
# l'intérieur d'un disque, seize rectangles ne font pas un cercle : ils
# font un ESCALIER. Et `draw_circle` ne lisse pas davantage ses bords —
# Godot 4.3 ne lui offre aucun anticrénelage. Le résultat était
# franchement pixelisé, ce qui se voit d'autant plus que ces boutons sont
# les seuls objets fixes de l'écran.
#
# LA RÉPONSE : on calcule la pastille UNE FOIS, au pixel, dans une image,
# et on la dessine ensuite comme une texture. Le filtrage bilinéaire du
# moteur la lisse à n'importe quelle taille, et surtout on peut calculer
# par pixel ce qu'aucune primitive ne sait dessiner :
#
#   • une COUVERTURE progressive sur le dernier pixel du bord, donc un
#     contour net sans marches ;
#   • un ÉCLAIRAGE de sphère — on connaît la normale en chaque point du
#     disque, donc on peut l'éclairer comme un volume et non comme un
#     aplat. C'est de là que vient le relief ;
#   • un REFLET spéculaire, une lumière rasante en bas, et un
#     assombrissement du pourtour : les trois signes qui font lire
#     « objet en plastique » plutôt que « rond de couleur ».
#
# COÛT : trois textures de 192 px calculées au premier montage de
# l'interface, et jamais recalculées ensuite. On n'en calcule d'ailleurs
# que la MOITIÉ : la lumière est placée droit au-dessus, donc l'image est
# symétrique et la seconde moitié se recopie.

const TEX := 192

static var _pastilles: Dictionary = {}
static var _anneau: ImageTexture = null
static var _ombre_tex: ImageTexture = null


## Pastille éclairée comme une sphère, dans deux tons.
##
## `clair` et `sombre` ne sont pas seulement le haut et le bas d'un
## dégradé : ils portent aussi la variation de TEINTE. Un bouton dont le
## haut est orange et le bas rouge paraît bien plus riche qu'un même
## orange assombri, parce que c'est ce que fait la lumière réelle sur une
## matière colorée.
static func pastille(clair: Color, sombre: Color) -> ImageTexture:
	var cle := "%s|%s" % [clair.to_html(), sombre.to_html()]
	if _pastilles.has(cle):
		return _pastilles[cle]

	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	# On vide explicitement : le contenu d'une image fraîchement créée n'est
	# pas garanti, et les pixels hors du disque ne sont jamais écrits.
	img.fill(Color(0, 0, 0, 0))
	var demi := TEX / 2
	var inv := 2.0 / float(TEX)
	for y in TEX:
		var v := (float(y) + 0.5) * inv - 1.0
		# Le dégradé de teinte suit la hauteur, indépendamment de
		# l'éclairage : c'est la couleur de la matière, pas de la lumière.
		var teinte := clair.lerp(sombre, clampf((v + 1.0) * 0.5, 0.0, 1.0))
		for x in range(demi + 1):
			var u := (float(x) + 0.5) * inv - 1.0
			var d2 := u * u + v * v
			if d2 > 1.06:
				continue
			var d := sqrt(d2)
			# Couverture : la transition tient sur un pixel, ce qui suffit à
			# supprimer les marches sans rendre le bord flou.
			var couv := clampf((1.0 - d) * float(demi), 0.0, 1.0)
			if couv <= 0.0:
				continue
			# Normale de la sphère au point courant. C'est elle qui permet
			# d'éclairer un disque comme un volume.
			var z := sqrt(maxf(0.0, 1.0 - d2))
			# Lumière DROIT AU-DESSUS et légèrement en avant : symétrique
			# gauche-droite, donc la moitié de l'image suffit à la calculer.
			var lam := clampf(-v * 0.62 + z * 0.78, 0.0, 1.0)
			var ombre_pourtour := 0.62 + 0.5 * lam
			# Lumière rasante sur le bord bas : c'est le rebond du sol. Sans
			# elle, la pastille paraît collée à l'écran au lieu d'être posée
			# dessus — c'est le détail qui donne l'épaisseur.
			var rebond: float = pow(clampf(d, 0.0, 1.0), 7.0) \
					* clampf(v, 0.0, 1.0) * 0.85
			# REFLET — un éclat, pas une tache.
			#
			# Mesuré en image : à la puissance 26 et pleine intensité, il
			# formait un dôme blanc qui montait jusqu'au centre et AVALAIT
			# l'icône du bouton. Sa direction est donc distincte de celle de
			# l'éclairage — plus verticale, donc plus haut placée — et il est
			# beaucoup plus serré. Un reflet doit accrocher l'œil sur un
			# millimètre carré, pas repeindre la moitié de l'objet.
			var glint := clampf(-v * 0.84 + z * 0.54, 0.0, 1.0)
			var brillance: float = pow(glint, 44.0) * 0.62
			var f := ombre_pourtour + rebond
			var col := Color(
					clampf(teinte.r * f + brillance, 0.0, 1.0),
					clampf(teinte.g * f + brillance, 0.0, 1.0),
					clampf(teinte.b * f + brillance, 0.0, 1.0),
					couv)
			img.set_pixel(x, y, col)
			# Symétrie : on recopie au lieu de recalculer.
			img.set_pixel(TEX - 1 - x, y, col)

	var t := ImageTexture.create_from_image(img)
	_pastilles[cle] = t
	return t


## Anneau blanc, lissé lui aussi. Séparé de la pastille pour n'être calculé
## qu'une fois quelle que soit la couleur du bouton.
static func anneau() -> ImageTexture:
	if _anneau != null:
		return _anneau
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var demi := TEX / 2
	var inv := 2.0 / float(TEX)
	# L'anneau est légèrement plus lumineux en haut : même un liseré blanc
	# gagne à ne pas être parfaitement uniforme.
	for y in TEX:
		var v := (float(y) + 0.5) * inv - 1.0
		for x in range(demi + 1):
			var u := (float(x) + 0.5) * inv - 1.0
			var d := sqrt(u * u + v * v)
			var dehors := clampf((1.0 - d) * float(demi), 0.0, 1.0)
			var dedans := clampf((d - 0.86) * float(demi) * 0.9, 0.0, 1.0)
			var a := minf(dehors, dedans)
			if a <= 0.0:
				continue
			var ton := 1.0 - clampf((v + 1.0) * 0.5, 0.0, 1.0) * 0.16
			var col := Color(ton, ton, ton, a)
			img.set_pixel(x, y, col)
			img.set_pixel(TEX - 1 - x, y, col)
	_anneau = ImageTexture.create_from_image(img)
	return _anneau


## Ombre portée à bord DOUX. Un disque plein, même bien placé, dessine une
## silhouette dure sous le bouton ; une ombre réelle s'estompe.
static func ombre_douce() -> ImageTexture:
	if _ombre_tex != null:
		return _ombre_tex
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var demi := TEX / 2
	var inv := 2.0 / float(TEX)
	for y in TEX:
		var v := (float(y) + 0.5) * inv - 1.0
		for x in range(demi + 1):
			var u := (float(x) + 0.5) * inv - 1.0
			var d := sqrt(u * u + v * v)
			if d >= 1.0:
				continue
			# Plateau opaque au centre, fondu sur le tiers extérieur.
			var a: float = clampf((1.0 - d) / 0.34, 0.0, 1.0)
			var col := Color(OMBRE.r, OMBRE.g, OMBRE.b, a * a * OMBRE.a)
			img.set_pixel(x, y, col)
			img.set_pixel(TEX - 1 - x, y, col)
	_ombre_tex = ImageTexture.create_from_image(img)
	return _ombre_tex


## PRÉCHAUFFE — calcule la pastille d'avance.
##
## POURQUOI : calculée paresseusement, elle le serait au premier affichage
## du bouton, sous la forme d'un à-coup. On paie donc la note au montage de
## l'interface, exactement comme on précompile les effets de tir avant le
## « GO ».
##
## Il n'y a QU'UNE texture par bouton, et non deux. L'état enfoncé se
## contentait d'éclaircir les deux tons — donc une seconde texture, qui
## aurait été calculée au PREMIER APPUI, c'est-à-dire au pire moment
## possible. Un simple facteur de teinte au moment du dessin donne le même
## éclaircissement pour zéro calcul : la moitié du coût disparaît.
static func prechauffer(clair: Color, sombre: Color) -> void:
	anneau()
	ombre_douce()
	pastille(clair, sombre)


## Dessine une pastille complète — ombre, anneau, corps — centrée.
static func poser_pastille(ci: CanvasItem, centre: Vector2, rayon: float,
		clair: Color, sombre: Color, appuye: bool) -> void:
	var e := rayon * 2.0
	var ombre_r := Rect2(centre - Vector2(e, e) * 0.58
			+ Vector2(0, rayon * (0.12 if appuye else 0.20)),
			Vector2(e, e) * 1.16)
	ci.draw_texture_rect(ombre_douce(), ombre_r, false)
	var zone := Rect2(centre - Vector2(rayon, rayon), Vector2(e, e))
	ci.draw_texture_rect(anneau(), zone, false)
	# Le corps est rentré de l'épaisseur de l'anneau.
	var interne := rayon * 0.87
	# L'éclaircissement de l'appui est une TEINTE de dessin, pas une seconde
	# texture : `draw_texture_rect` multiplie, donc un facteur au-dessus de
	# 1 éclaircit sans rien recalculer.
	var teinte := Color(1.16, 1.16, 1.16) if appuye else Color.WHITE
	ci.draw_texture_rect(pastille(clair, sombre),
			Rect2(centre - Vector2(interne, interne),
					Vector2(interne * 2.0, interne * 2.0)), false, teinte)


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
		# Filtrage LINÉAIRE explicite : la pastille est une texture de 192 px
		# redimensionnée à la taille du bouton. En filtrage au plus proche —
		# réglage possible du projet — elle redeviendrait crénelée, ce qu'on
		# vient précisément de corriger.
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
		UiKit.prechauffer(ton_clair, ton_sombre)

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

		# Ombre, anneau blanc et corps éclairé : trois textures lissées au
		# pixel. L'anneau blanc est ce qui détache le bouton de N'IMPORTE
		# QUEL fond, ce que ne fait aucune couleur seule ; le corps porte le
		# relief, calculé comme sur une sphère.
		UiKit.poser_pastille(self, c, r, ton_clair, ton_sombre, appuye)

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

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

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
		UiKit.poser_pastille(self, c, rc, UiKit.VIE_CLAIR, UiKit.VIE_SOMBRE,
				false)
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
