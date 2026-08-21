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
## Fond des panneaux. DENSE et non translucide : posé sur un sol clair, un
## panneau semi-transparent devient illisible exactement au moment où le
## joueur cherche à y lire quelque chose.
const PANNEAU := Color("16213f")
## Fond plus sombre, pour les creux : pistes de jauge, emplacements vides.
const CREUX := Color("0b1226")
## Bleu d'accent — le joueur, sa progression, ses repères.
const CYAN := Color("46b8ff")
## Rouge d'adversaire, réservé à ce qui menace.
const ROUGE := Color("ff4d5e")
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
	## Part de recharge écoulée, dans [0, 1]. À 1, la capacité est prête et
	## rien ne se dessine — une couronne toujours pleine devient un ornement
	## qu'on cesse de voir, donc qu'on ne voit plus quand elle sert.
	var recharge: float = 1.0
	## Secondes restantes, affichées à la place du libellé pendant l'attente.
	var attente: float = 0.0
	## MODE JOYSTICK — le bouton se dessine comme le stick de gauche :
	## socle translucide à chevrons, et une POIGNÉE charnue qui suit le
	## pouce. C'est le langage visuel qui dit « ça se glisse » : le bouton
	## de tir dessiné en simple pastille cachait complètement la visée
	## manuelle — rien n'invitait à glisser dessus.
	var mode_joystick: bool = false
	## Direction du pouce, en fraction du rayon ([-1, 1] par axe). ZERO :
	## poignée au centre.
	var visee: Vector2 = Vector2.ZERO

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

		if mode_joystick:
			# ─── SOCLE DE STICK, PAS PASTILLE ─────────────────────────
			#
			# Même vocabulaire que le joystick de gauche : disque
			# translucide, anneau, quatre chevrons vers l'extérieur. Un
			# joueur qui a compris le stick de déplacement comprend
			# celui-ci sans notice.
			draw_circle(c + Vector2(0, r * 0.06), r,
					Color(0.03, 0.05, 0.12, 0.22))
			draw_circle(c, r, Color(1, 1, 1, 0.14))
			draw_arc(c, r - 3.0, 0.0, TAU, 56, Color(1, 1, 1, 0.62),
					6.0, true)
			for i in 4:
				var a := TAU * float(i) / 4.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var pointe := c + d * (r - 10.0)
				var base := c + d * (r - 22.0)
				draw_colored_polygon(PackedVector2Array([
						pointe, base + n * 8.0, base - n * 8.0]),
						Color(1, 1, 1, 0.5))
			# ─── LA POIGNÉE PORTE LE TIR ──────────────────────────────
			#
			# Elle suit le pouce (bornée au socle) et transporte l'icône
			# de viseur : la direction du tir SE VOIT sur le bouton
			# lui-même, avant même de regarder la ligne au sol.
			var kr := r * 0.52
			var kpos := c + visee.limit_length(1.0) * (r - kr * 0.72)
			UiKit.poser_pastille(self, kpos, kr, ton_clair, ton_sombre,
					appuye)
			UiKit.icone(self, icone, kpos, kr * 0.55, UiKit.BLANC)
		else:
			# Ombre, anneau blanc et corps éclairé : trois textures lissées
			# au pixel. L'anneau blanc est ce qui détache le bouton de
			# N'IMPORTE QUEL fond, ce que ne fait aucune couleur seule ; le
			# corps porte le relief, calculé comme sur une sphère.
			UiKit.poser_pastille(self, c, r, ton_clair, ton_sombre, appuye)

			var haut_icone := c - Vector2(0, r * (0.20 if libelle != "" else 0.0))
			UiKit.icone(self, icone, haut_icone, r * 0.42, UiKit.BLANC)

		# LA COURONNE DE RECHARGE, par-dessus le corps du bouton. Elle dit
		# COMBIEN il reste, là où l'estompement du bouton ne disait que
		# « pas encore » — et « pas encore » ne permet pas de décider s'il
		# faut fuir maintenant ou tenir une seconde de plus.
		if recharge < 0.999:
			var f2 := UiKit.police()
			UiKit.arc_progression(self, c, r * 0.86, 1.0,
					Color(0.04, 0.07, 0.16, 0.5), r * 0.13)
			UiKit.arc_progression(self, c, r * 0.86, recharge,
					UiKit.BLANC, r * 0.13)
			var t2 := "%.1f" % maxf(0.0, attente)
			var ta := int(maxf(13.0, r * 0.42))
			var la := f2.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1,
					ta).x
			var pa := Vector2(c.x - la * 0.5, c.y + r * 0.66)
			draw_string_outline(f2, pa, t2, HORIZONTAL_ALIGNMENT_LEFT, -1,
					ta, 6, Color(0.04, 0.07, 0.16, 0.92))
			draw_string(f2, pa, t2, HORIZONTAL_ALIGNMENT_LEFT, -1, ta,
					UiKit.BLANC)
			return

		# En mode joystick, la poignée porte déjà l'icône : un libellé fixe
		# sous le socle serait recouvert dès que le pouce glisse vers le bas.
		if libelle == "" or mode_joystick:
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
		&"crane": _icone_crane(ci, centre, r, teinte)
		&"serie": _icone_serie(ci, centre, r, teinte)
		&"course": _icone_course(ci, centre, r, teinte)
		&"coffre": _icone_coffre(ci, centre, r, teinte)
		&"cadenas": _icone_cadenas(ci, centre, r, teinte)
		_: pass


## CRÂNE — l'icône des éliminations.
##
## Trois formes suffisent, et c'est le minimum : une calotte, deux orbites,
## une mâchoire. En dessous on obtient un galet ; au-dessus, à 24 pixels de
## côté, le détail se referme en bouillie.
static func _icone_crane(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var calotte := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		calotte.append(c + Vector2(cos(a) * r * 0.82, sin(a) * r * 0.86
				- r * 0.08))
	calotte.append(c + Vector2(r * 0.62, r * 0.42))
	calotte.append(c + Vector2(-r * 0.62, r * 0.42))
	ci.draw_colored_polygon(calotte, t)
	# La mâchoire, séparée par un trait de fond : c'est ce vide qui fait
	# lire « crâne » plutôt que « caillou ».
	ci.draw_rect(Rect2(c + Vector2(-r * 0.42, r * 0.46),
			Vector2(r * 0.84, r * 0.34)), t)
	var creux := Color(0, 0, 0, 0.0)
	for cote: float in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(cote * r * 0.34, -r * 0.02), r * 0.26,
				Color(0.05, 0.08, 0.17, 1.0))
	ci.draw_rect(Rect2(c + Vector2(-r * 0.09, r * 0.2),
			Vector2(r * 0.18, r * 0.22)), Color(0.05, 0.08, 0.17, 1.0))
	if creux.a > 0.0:
		pass


## SÉRIE — une cible frappée d'une étoile.
static func _icone_serie(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(2.5, r * 0.16)
	ci.draw_arc(c, r * 0.78, 0.0, TAU, 28, t, e, true)
	ci.draw_circle(c, r * 0.24, t)
	# L'étoile déborde en haut à droite : c'est ce débordement qui
	# distingue l'icône de série de celle du bouton de tir.
	var etoile := PackedVector2Array()
	var centre := c + Vector2(r * 0.66, -r * 0.66)
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var rr: float = r * (0.42 if i % 2 == 0 else 0.17)
		etoile.append(centre + Vector2(cos(a) * rr, sin(a) * rr))
	ci.draw_colored_polygon(etoile, t)


## COURSE — la silhouette qui court, icône de l'esquive.
static func _icone_course(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(3.0, r * 0.2)
	ci.draw_circle(c + Vector2(r * 0.12, -r * 0.6), r * 0.24, t)
	# Tronc penché vers l'avant : c'est l'inclinaison, plus que les membres,
	# qui fait lire la course plutôt que la station debout.
	ci.draw_line(c + Vector2(-r * 0.12, -r * 0.28),
			c + Vector2(r * 0.24, r * 0.06), t, e, true)
	ci.draw_line(c + Vector2(-r * 0.12, -r * 0.24),
			c + Vector2(-r * 0.62, -r * 0.06), t, e * 0.8, true)
	ci.draw_line(c + Vector2(r * 0.06, -r * 0.16),
			c + Vector2(r * 0.58, -r * 0.36), t, e * 0.8, true)
	ci.draw_line(c + Vector2(r * 0.24, r * 0.06),
			c + Vector2(-r * 0.16, r * 0.5), t, e, true)
	ci.draw_line(c + Vector2(-r * 0.16, r * 0.5),
			c + Vector2(-r * 0.56, r * 0.44), t, e * 0.8, true)
	ci.draw_line(c + Vector2(r * 0.24, r * 0.06),
			c + Vector2(r * 0.5, r * 0.56), t, e, true)


## COFFRE — l'icône du butin.
static func _icone_coffre(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var couvercle := PackedVector2Array()
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		couvercle.append(c + Vector2(cos(a) * r * 0.82, sin(a) * r * 0.5
				- r * 0.06))
	ci.draw_colored_polygon(couvercle, t)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.82, -r * 0.02),
			Vector2(r * 1.64, r * 0.7)), t)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.14, -r * 0.3),
			Vector2(r * 0.28, r * 0.5)), Color(0.05, 0.08, 0.17, 1.0))


## CADENAS — l'icône d'un emplacement verrouillé.
static func _icone_cadenas(ci: CanvasItem, c: Vector2, r: float,
		t: Color) -> void:
	var e := maxf(2.5, r * 0.18)
	ci.draw_arc(c + Vector2(0, -r * 0.28), r * 0.42, PI, TAU, 16, t, e, true)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.22),
			Vector2(r * 1.24, r * 0.92)), t)
	ci.draw_circle(c + Vector2(0, r * 0.22), r * 0.16,
			Color(0.05, 0.08, 0.17, 1.0))


## ARC DE PROGRESSION — la couronne des recharges.
##
## Il part du HAUT et tourne dans le sens des aiguilles : c'est la lecture
## d'un cadran, la seule que personne n'a besoin d'apprendre.
static func arc_progression(ci: CanvasItem, centre: Vector2, rayon: float,
		part: float, couleur: Color, epaisseur: float) -> void:
	var p := clampf(part, 0.0, 1.0)
	if p <= 0.001:
		return
	var debut := -PI * 0.5
	ci.draw_arc(centre, rayon, debut, debut + TAU * p,
			maxi(8, int(48.0 * p)), couleur, epaisseur, true)


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


## GLYPHE — une icône posée dans un conteneur, sans bouton autour.
##
## Les icônes se dessinaient jusqu'ici À L'INTÉRIEUR des boutons. Dès qu'on
## veut la même icône dans un libellé, un pod ou une carte, il faut un
## Control minuscule qui ne fasse que cela.
class Glyphe extends Control:
	var id: StringName = &"viseur"
	var teinte: Color = UiKit.BLANC

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		UiKit.icone(self, id, size * 0.5, minf(size.x, size.y) * 0.5, teinte)


## JAUGE D'EXPÉRIENCE — la barre bleue du bloc de profil.
##
## POURQUOI PAS UN `ProgressBar`. Il en faudrait trois surcharges de style
## pour obtenir des bouts arrondis, un dégradé et un chiffre centré, et le
## résultat resterait à la merci du thème. Vingt lignes de dessin donnent
## exactement l'objet voulu et se lisent d'un trait.
class JaugeXp extends Control:
	var part: float = 0.0
	var courant: int = 0
	var palier: int = 100

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func regler(dans: int, requis: int) -> void:
		courant = dans
		palier = maxi(1, requis)
		part = clampf(float(dans) / float(palier), 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := int(size.y * 0.5)
		draw_style_box(UiKit.panneau(r, UiKit.CREUX,
				Color(1, 1, 1, 0.12), 2), Rect2(Vector2.ZERO, size))
		var marge := 3.0
		if part > 0.004:
			var utile := size.x - marge * 2.0
			var zone := Rect2(marge, marge,
					maxf(size.y - marge * 2.0, utile * part),
					size.y - marge * 2.0)
			UiKit.rect_degrade(self, zone, UiKit.CYAN.lerp(UiKit.BLANC, 0.35),
					Color("1b62d8"), int(zone.size.y * 0.5))
		var f := UiKit.police()
		var t := "%d / %d XP" % [courant, palier]
		var taille := int(size.y * 0.58)
		var l := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille)
		var pos := Vector2(size.x * 0.5 - l.x * 0.5,
				size.y * 0.5 + taille * 0.36)
		draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille,
				5, Color(0.04, 0.07, 0.16, 0.95))
		draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, BLANC)


## CARTE D'ARME — un emplacement de l'armement.
##
## Elle porte trois états et un seul dessin : ACTIVE (bord épais à la
## couleur de l'arme, fond teinté), EN RÉSERVE (bord pâle), VERROUILLÉE
## (cadenas et condition d'ouverture). Les trois se ressemblent assez pour
## former une rangée, et diffèrent assez pour se distinguer à bout de bras
## — c'était la limite de la version précédente, où trois pixels de bord
## séparaient l'arme tenue de celle rangée.
class CarteArme extends Control:
	var nom: String = "—"
	var munitions: String = ""
	var teinte: Color = UiKit.NEUTRE_SOMBRE
	var active: bool = false
	var verrouille: bool = false
	var condition: String = ""

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func regler(n: String, muni: String, c: Color, act: bool) -> void:
		nom = n
		munitions = muni
		teinte = c
		active = act
		queue_redraw()

	func _draw() -> void:
		var boite := Rect2(Vector2.ZERO, size)
		var fond := UiKit.PANNEAU
		var bord := Color(1, 1, 1, 0.16)
		var ep := 3
		if verrouille:
			fond = UiKit.CREUX
		elif active:
			fond = UiKit.PANNEAU.lerp(teinte, 0.24)
			bord = teinte
			ep = 5
		else:
			bord = Color(teinte.r, teinte.g, teinte.b, 0.5)
		draw_style_box(UiKit.panneau(18, fond, bord, ep), boite)

		var f := UiKit.police()
		if verrouille:
			UiKit.icone(self, &"cadenas", Vector2(size.x * 0.5, size.y * 0.38),
					size.y * 0.2, Color(1, 1, 1, 0.4))
			_ecrire(f, condition, 19, Color(1, 1, 1, 0.5), size.y * 0.86)
			return

		# LE NOM EN HAUT, LES MUNITIONS EN BAS. Sur une seule ligne, le
		# compteur repoussait le titre à chaque coup tiré et la carte
		# tremblait en permanence — mesuré, et corrigé une première fois en
		# séparant les étiquettes ; la séparation est maintenant verticale,
		# ce qui la rend impossible à défaire par un texte trop long.
		_ecrire(f, nom, 20, UiKit.BLANC, size.y * 0.42)
		if munitions == "":
			return
		var taille := 22
		var l := f.get_string_size(munitions, HORIZONTAL_ALIGNMENT_LEFT, -1,
				taille)
		var depart := size.x * 0.5 - (l.x + 24.0) * 0.5
		for i in 3:
			draw_rect(Rect2(depart + float(i) * 6.0, size.y * 0.62,
					3.0, 12.0), Color(1, 1, 1, 0.62))
		var pos := Vector2(depart + 24.0, size.y * 0.74)
		draw_string_outline(f, pos, munitions, HORIZONTAL_ALIGNMENT_LEFT, -1,
				taille, 5, Color(0.04, 0.07, 0.16, 0.95))
		draw_string(f, pos, munitions, HORIZONTAL_ALIGNMENT_LEFT, -1, taille,
				Color(1, 1, 1, 0.86))

	func _ecrire(f: Font, t: String, taille: int, c: Color, y: float) -> void:
		var l := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille)
		var pos := Vector2(size.x * 0.5 - l.x * 0.5, y)
		draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille,
				5, Color(0.04, 0.07, 0.16, 0.95))
		draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, c)

## DISQUE PLEIN — sert de MASQUE de découpe, pas de décoration.
##
## Un parent en `CLIP_CHILDREN_ONLY` n'affiche pas son propre dessin : il
## s'en sert comme pochoir. Ce contrôle n'existe donc que pour donner cette
## forme-là à ce qu'il contient — aujourd'hui la minicarte, qui doit
## s'arrêter net sur un bord rond au lieu de remplir un carré.
class Disque extends Control:
	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, Color.WHITE)


## ANNEAU — le liseré posé PAR-DESSUS un contenu découpé.
##
## Il vit à part du masque parce qu'un trait dessiné à l'intérieur du
## pochoir serait rogné par lui : on n'en verrait que la moitié intérieure,
## c'est-à-dire un bord flou au lieu d'un cadre net.
class Anneau extends Control:
	var teinte: Color = CYAN.lerp(BLANC, 0.15)
	var epaisseur: float = 3.0

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5 - epaisseur * 0.5
		draw_arc(size * 0.5, r, 0.0, TAU, 56, teinte, epaisseur, true)

## ÉTOILE DESSINÉE — parce que « ★ » n'existe pas dans la police du jeu.
##
## Écrit en caractère Unicode, il se rendait en RECTANGLE VIDE — le carré
## que les polices affichent quand elles n'ont pas le glyphe. Vérifié en
## capture dans le navigateur : l'en-tête de la colonne des victoires
## montrait une case blanche. Un symbole qu'on ne peut pas garantir ne se
## met pas dans une chaîne ; on le dessine.
##
## Même contour à cinq branches que la maille 3D et que l'icône de la barre
## WANTED : trois dessins, une seule silhouette.
class EtoileGlyphe extends Control:
	var teinte: Color = OR_CLAIR

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for i in 10:
			var a := TAU * float(i) / 10.0 - PI * 0.5
			var rayon: float = r if i % 2 == 0 else r * 0.44
			pts.append(c + Vector2(cos(a), sin(a)) * rayon)
		draw_colored_polygon(pts, teinte)

