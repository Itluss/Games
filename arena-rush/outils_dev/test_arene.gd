extends Node
## TEST DU PLAN DE L'ARÈNE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER EXISTE : le plan a été redessiné à la main, et une
## carte dessinée à la main se croit toujours équilibrée. Les quatre
## garanties annoncées dans `PlanArene` ne valent rien tant qu'elles sont
## des intentions ; ici, elles deviennent des mesures.
##
## Le test le plus important est le premier. Une arène où l'on peut tirer
## sur un adversaire AVANT qu'il ait bougé est cassée, et c'est le genre de
## défaut qu'on ne voit pas en jouant seul.
##
## Usage :
##   godot --headless --path arena-rush res://outils_dev/test_arene.tscn

var _echecs := 0
var _total := 0

func _ready() -> void:
	await get_tree().process_frame
	print("=== PLAN DE L'ARÈNE ===")
	_garantie_lignes_de_tir()
	_garantie_abri_au_depart()
	_garantie_apparitions_libres()
	_garantie_pas_de_chevauchement()
	_garantie_dans_l_enceinte()
	_garantie_mobs()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-52s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


# --- GARANTIE 1 : AUCUNE LIGNE DE TIR ENTRE APPARITIONS ------------------

## Chacune des six paires d'apparitions doit être coupée par au moins une
## masse. Six paires : quatre côtés du carré et ses deux diagonales.
func _garantie_lignes_de_tir() -> void:
	var points := PlanArene.apparitions_joueurs()
	for i in points.size():
		for j in range(i + 1, points.size()):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[j].x, points[j].z)
			var bloque := _segment_coupe(a, b)
			_verifier("apparition %d → %d : ligne coupée" % [i, j],
					bloque, true)


## Le segment traverse-t-il au moins une pièce solide ?
##
## Échantillonnage tous les 25 cm plutôt qu'une intersection analytique :
## la plus petite pièce du plan fait 90 cm de côté, donc aucun obstacle ne
## peut se glisser entre deux échantillons. C'est dix lignes de moins à
## déboguer pour une précision qui suffit très largement.
func _segment_coupe(a: Vector2, b: Vector2) -> bool:
	var longueur := a.distance_to(b)
	var pas := 0.25
	var n := int(longueur / pas)
	for k in range(1, n):
		var p := a.lerp(b, float(k) / float(n))
		if not PlanArene.est_libre(p, 0.0):
			return true
	return false


# --- GARANTIE 2 : UN ABRI À PORTÉE DE CHAQUE DÉPART ---------------------

func _garantie_abri_au_depart() -> void:
	var points := PlanArene.apparitions_joueurs()
	for i in points.size():
		var p := Vector2(points[i].x, points[i].z)
		var plus_proche := INF
		for piece in PlanArene.ABRIS:
			var c: Vector2 = piece["pos"]
			plus_proche = minf(plus_proche, p.distance_to(c))
		_verifier("apparition %d : abri à moins de 5 m" % i,
				plus_proche < 5.0, true)


# --- GARANTIE 3 : PERSONNE NE NAÎT DANS UN MUR --------------------------

func _garantie_apparitions_libres() -> void:
	var points := PlanArene.apparitions_joueurs()
	for i in points.size():
		var p := Vector2(points[i].x, points[i].z)
		# 0,45 m : le rayon du corps du joueur, avec un peu de marge.
		_verifier("apparition %d : position libre" % i,
				PlanArene.est_libre(p, 0.45), true)


# --- GARANTIE 4 : LES PIÈCES NE SE TRAVERSENT PAS -----------------------

## Deux abris qui s'interpénètrent, c'est un modèle 3D qui sort de l'autre.
## On tolère le contact, jamais le recouvrement franc.
func _garantie_pas_de_chevauchement() -> void:
	var pieces := PlanArene.pieces_solides()
	var fautes := 0
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var pa: Vector2 = pieces[i]["pos"]
			var pb: Vector2 = pieces[j]["pos"]
			var ta: Vector3 = pieces[i]["taille"]
			var tb: Vector3 = pieces[j]["taille"]
			# Comparaison par disques inscrits : approximation volontaire,
			# et prudente dans le bon sens — elle ne signale que les
			# recouvrements francs, pas les frôlements.
			var ra := minf(ta.x, ta.z) * 0.5
			var rb := minf(tb.x, tb.z) * 0.5
			if pa.distance_to(pb) < (ra + rb) * 0.85:
				fautes += 1
				print("      ! %s et %s se chevauchent (%.2f m)"
						% [pieces[i]["modele"], pieces[j]["modele"],
						pa.distance_to(pb)])
	_verifier("aucune pièce n'en traverse une autre", fautes, 0)


# --- GARANTIE 5 : TOUT TIENT DANS L'ENCEINTE ----------------------------

func _garantie_dans_l_enceinte() -> void:
	var dehors := 0
	for piece in PlanArene.pieces_solides():
		var p: Vector2 = piece["pos"]
		var t: Vector3 = piece["taille"]
		var portee := p.length() + maxf(t.x, t.z) * 0.5
		# Le mur est à ARENA_RADIUS et fait 2,4 m d'épaisseur ; une pièce
		# ne doit pas venir s'y encastrer.
		if portee > Cfg.ARENA_RADIUS - 1.2:
			dehors += 1
			print("      ! %s déborde (%.2f m)" % [piece["modele"], portee])
	_verifier("toutes les pièces tiennent dans l'enceinte", dehors, 0)


# --- GARANTIE 6 : DES MOBS PEUVENT APPARAÎTRE ---------------------------

func _garantie_mobs() -> void:
	var libres := 0
	for couronne in [{"r": 14.5, "n": 10}, {"r": 7.5, "n": 6}]:
		var rayon: float = couronne["r"]
		var nombre: int = couronne["n"]
		for i in nombre:
			var a := TAU * float(i) / float(nombre) \
					+ (0.31 if rayon < 10.0 else 0.0)
			if PlanArene.est_libre(Vector2(cos(a) * rayon, sin(a) * rayon), 0.9):
				libres += 1
	print("      %d points d'apparition de mob libres" % libres)
	_verifier("au moins 6 foyers d'apparition de mob", libres >= 6, true)
