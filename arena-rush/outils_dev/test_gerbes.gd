extends Node3D
## TEST DES GERBES RECYCLÉES — outil de développement, hors jeu.
##
## POURQUOI CE BANC. Les gerbes de particules ne sont plus construites à
## chaque impact : leurs nœuds sont RECYCLÉS. C'est ce qui supprime les
## à-coups, et c'est aussi le genre d'optimisation qui casse en silence —
## un nœud réutilisé sans être correctement relancé n'émet plus rien.
##
## Le défaut serait invisible sur la PREMIÈRE gerbe, qui sort d'un nœud
## neuf, et n'apparaîtrait qu'à partir de la deuxième. Une capture d'écran
## prise au hasard passerait donc à côté. On en tire donc trois de suite,
## avec un temps de recyclage entre chacune, et on compte les pixels.
##
## Usage :
##   xvfb-run -a godot --path arena-rush res://outils_dev/test_gerbes.tscn \
##       --rendering-driver opengl3

const LARGEUR := 320
const HAUTEUR := 180
## Nombre de gerbes tirées à la suite. Trois suffit : la première crée, la
## deuxième recycle, la troisième confirme que le recyclage se répète.
const TIRS := 3
## Part de pixels lumineux en dessous de laquelle il ne s'est rien passé.
##
## LE SEUIL EST BAS, ET IL LE RESTE. Le premier jet exigeait 0,4 % et
## déclarait trois échecs alors que les trois gerbes émettaient bel et bien
## — une poignée de grains lumineux à quatre mètres dans une fenêtre de
## 320 × 180 n'occupe qu'un dixième de pour cent de l'image. Un seuil
## inventé sans mesure préalable accuse le code d'un défaut qui lui est
## étranger.
const SEUIL := 0.0004
## Part minimale d'une gerbe recyclée par rapport à la première.
##
## PAS DE BORNE SUPÉRIEURE, ET C'EST DÉLIBÉRÉ. Le défaut redouté est
## qu'un nœud réutilisé n'émette PLUS RIEN, ou beaucoup moins ; qu'il
## émette davantage n'a jamais cassé un jeu.
##
## LA BORNE INFÉRIEURE EST LARGE parce que l'instrument l'est. Une gerbe
## vit quatre dixièmes de seconde et cette machine rend trois images par
## seconde : on n'en attrape qu'un ou deux instantanés, jamais les mêmes.
## Mesuré sur plusieurs exécutions, les trois gerbes tombent entre 0,18 et
## 0,32 % — même ordre de grandeur, phases différentes. Exiger mieux ferait
## échouer le banc au hasard, et un test qui échoue au hasard finit ignoré,
## donc inutile.
const PART_MINIMALE := 0.35

var _echecs := 0
var _mesures: Array[float] = []

func _ready() -> void:
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.6, 4.0)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	Fx.camera = cam

	await get_tree().process_frame
	for i in TIRS:
		_mesures.append(await _tirer_une_gerbe())
		# On laisse la gerbe MOURIR et retourner au réservoir avant la
		# suivante : sans cette attente, la seconde prendrait un nœud neuf
		# et le recyclage ne serait jamais exercé.
		await get_tree().create_timer(1.2).timeout

	print("=== GERBES RECYCLÉES ===")
	var reference: float = _mesures[0]
	for i in _mesures.size():
		var v: float = _mesures[i]
		var ok := v >= SEUIL
		var note := ""
		if i > 0:
			var rapport := v / maxf(reference, 0.000001)
			ok = ok and rapport >= PART_MINIMALE
			note = " · %.0f %% de la première" % (rapport * 100.0)
		if not ok:
			_echecs += 1
		print("  [%s] gerbe n°%d : %.3f %% de pixels lumineux%s"
				% ["OK" if ok else "ÉCHEC", i + 1, v * 100.0, note])
	print("  réservoir : %d nœud(s) en attente" % Fx.reservoir())
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, TIRS])
	get_tree().quit(1 if _echecs > 0 else 0)


## Tire une gerbe et rend le PIC de luminosité observé sur sa vie entière.
##
## POURQUOI LE PIC ET NON UNE MESURE À L'INSTANT T. Une gerbe vit quatre
## dixièmes de seconde et cette machine rend trois images par seconde :
## selon la phase, on photographie son plein éclat ou sa dernière lueur.
## Deux exécutions du même banc ont ainsi rendu « 0,10 / 0,14 / 0,15 » puis
## « 0,26 / 0,06 / 0,06 » — de quoi conclure tout et son contraire.
##
## Le pic, lui, ne dépend pas de l'instant où l'on regarde : il suffit de
## regarder assez souvent pendant que ça dure.
func _tirer_une_gerbe() -> float:
	Fx.hit(Vector3.ZERO, Color("ffb347"), 1.4)
	var pic := 0.0
	for i in 14:
		await RenderingServer.frame_post_draw
		pic = maxf(pic, _part_lumineuse())
	return pic


func _part_lumineuse() -> float:
	var img := get_viewport().get_texture().get_image()
	var vifs := 0
	var total := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			total += 1
			if c.r + c.g + c.b > 0.35:
				vifs += 1
	return float(vifs) / maxf(1.0, float(total))
