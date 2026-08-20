extends SceneTree
## MESURE DU PLAN WESTERN — sans moteur de rendu, sans arène bâtie.
##
## POURQUOI CET OUTIL EXISTE À CÔTÉ DU BANC. Le banc bâtit l'arène entière
## pour la juger : une trentaine de secondes par passage. Or une passe de
## level design, c'est cinquante essais de coordonnées. Ce script-ci ne lit
## que le PLAN — des nombres, pas des maillages — et répond en une seconde.
## Le banc reste l'autorité ; celui-ci est la règle qu'on garde en main
## pendant qu'on dessine.
##
## ─── LA PREMIÈRE VERSION DE CE FICHIER AVAIT TORT, ET C'EST INSTRUCTIF ──
##
## Elle mettait tonneaux, murs et grosses formations dans le même panier,
## annonçait une médiane de 1,7 m et zéro pour cent d'aire vide — sur une
## carte dont les rendus montraient 72 à 82 % de sable nu à l'écran. Un
## tonneau de cinquante-cinq centimètres compte pour un couvert dans un
## calcul de distance, et pour rien du tout dans une image.
##
## D'où les trois séparations qu'elle fait maintenant :
##
##   NIVEAU 1  tonneau, caisse, botte isolée — micro-placement.
##   NIVEAU 2  mur, barrière, chariot, empilement, crête moyenne — duel.
##   NIVEAU 3  grande crête — la ligne de vue disparaît.
##
## Et la mesure qui manquait : l'EMPRISE au sol, qui dit si l'écran est
## plein. C'est elle qui portait le vrai défaut — 84 % de l'emprise tenait
## dans les treize grosses formations de la V1.
##
## Les cactus et buissons NE COMPTENT NULLE PART. Un décor qui n'arrête
## rien ne doit pas améliorer une note de couverture, sinon on maquille la
## carte au lieu de la corriger.

## Vitesse de course du joueur, en m/s. Copiée de `player.gd`. Si elle y
## change, ce fichier ment : c'est le prix d'un outil hors moteur.
const VITESSE := 5.6
const UNE_SECONDE := VITESSE
const DEUX_SECONDES := VITESSE * 2.0

## Pas d'échantillonnage de l'aire jouable, en mètres.
const PAS := 1.0


func _init() -> void:
	var couverts := _couverts()
	print("\n=== MESURE DU PLAN WESTERN ===\n")
	var par_niveau := [0, 0, 0, 0]
	for c: Dictionary in couverts:
		par_niveau[int(c["niveau"])] += 1
	print("  couverts : %d — niveau 1 : %d · niveau 2 : %d · niveau 3 : %d"
			% [couverts.size(), par_niveau[1], par_niveau[2], par_niveau[3]])
	_emprise(couverts)
	_distances(couverts, 1, "tout couvert")
	_distances(couverts, 2, "couvert de duel (niveau 2 ou 3)")
	_dans_le_cadre(couverts)
	_lignes_de_vue(couverts)
	_quadrants(couverts)
	_apparitions(couverts)
	_contournabilite(couverts)
	quit()


## Tous les couverts qui comptent, chacun ramené à un rectangle orienté.
##
## LE RECTANGLE EST LE BON MODÈLE ICI, et le disque ne l'est plus : une
## crête de onze mètres sur cinq n'a pas de rayon. Murs et barrières sont
## des segments, donc des rectangles très plats. Les empilements et les
## petits sont presque carrés.
func _couverts() -> Array:
	var out: Array = []
	for f: Dictionary in PlanAreneWestern.FORMATIONS:
		out.append(_boite(f["pos"], float(f["long"]), float(f["large"]),
				float(f["angle"]), "crête",
				3 if float(f["hauteur"]) >= PlanAreneWestern.H_CRETE else 2))
	for c: Dictionary in PlanAreneWestern.CHARIOTS:
		out.append(_boite(c["pos"], 4.6, 2.6, float(c["angle"]), "chariot", 2))
	for m: Dictionary in PlanAreneWestern.MURS:
		out.append(_boite(m["pos"], float(m["long"]), 0.8,
				float(m["angle"]), "mur", 2))
	for b: Dictionary in PlanAreneWestern.BARRIERES:
		out.append(_boite(b["pos"], float(b["long"]), 0.5,
				float(b["angle"]), "barrière", 2))
	for e: Dictionary in PlanAreneWestern.PILES:
		var cote := 1.9 if int(e["etages"]) >= 3 else 1.6
		out.append(_boite(e["pos"], cote, cote, float(e["angle"]), "pile", 2))
	for e: Dictionary in PlanAreneWestern.PETITS:
		out.append(_boite(e["pos"], 1.1, 1.1, 0.0, "petit", 1))
	# La margelle du centre, découpée en tronçons : un arc n'est pas un
	# point, et sa corde ne dit rien de la distance à sa pierre.
	for m: Dictionary in PlanAreneWestern.ARCS_CENTRE:
		var ce: Vector2 = m["centre"]
		var r: float = m["rayon"]
		var a0 := deg_to_rad(float(m["depart"]))
		var arc := deg_to_rad(float(m["arc"]))
		var n := maxi(2, int(arc * r / 2.0))
		for i in n:
			var a := a0 + arc * (float(i) + 0.5) / float(n)
			out.append(_boite(ce + Vector2(cos(a), sin(a)) * r,
					arc * r / float(n), 0.8, rad_to_deg(a) + 90.0,
					"margelle", 2))
	return out


func _boite(pos: Vector2, l: float, w: float, deg: float,
		cat: String, niveau: int) -> Dictionary:
	return {"pos": pos, "demi": Vector2(l * 0.5, w * 0.5),
			"angle": deg_to_rad(deg), "cat": cat, "niveau": niveau,
			"aire": l * w}


## Distance du point au BORD du rectangle, zéro s'il est dedans.
func _ecart_boite(p: Vector2, c: Dictionary) -> float:
	var d: Vector2 = p - (c["pos"] as Vector2)
	var a: float = c["angle"]
	var loc := Vector2(d.x * cos(a) + d.y * sin(a),
			-d.x * sin(a) + d.y * cos(a))
	var demi: Vector2 = c["demi"]
	return Vector2(maxf(absf(loc.x) - demi.x, 0.0),
			maxf(absf(loc.y) - demi.y, 0.0)).length()


func _emprise(couverts: Array) -> void:
	var aire := _aire_jouable()
	var occupe := [0.0, 0.0, 0.0, 0.0]
	for c: Dictionary in couverts:
		occupe[int(c["niveau"])] += float(c["aire"])
	var total: float = occupe[1] + occupe[2] + occupe[3]
	print("\n  ── emprise au sol ──")
	print("     niveau 1 %5.0f m²  ·  niveau 2 %5.0f m²  ·  niveau 3 %5.0f m²"
			% [occupe[1], occupe[2], occupe[3]])
	print("     part du niveau 3 dans l'emprise : %.0f %%   (V1 : 84 %%)"
			% [100.0 * occupe[3] / maxf(total, 0.001)])
	print("     total %5.0f m² sur %5.0f m² jouables  →  %.1f %%   (V1 : 17.6 %%)"
			% [total, aire, 100.0 * total / aire])


func _distances(couverts: Array, mini: int, libelle: String) -> void:
	var releves: Array[float] = []
	var vides := 0
	var pire := 0.0
	var pire_pos := Vector2.ZERO
	var y := -PlanAreneWestern.BORD
	while y <= PlanAreneWestern.BORD:
		var x := -PlanAreneWestern.BORD
		while x <= PlanAreneWestern.BORD:
			var p := Vector2(x, y)
			if PlanAreneWestern.dans_enceinte(p, PlanAreneWestern.MARGE_BORD):
				var d := INF
				for c: Dictionary in couverts:
					if int(c["niveau"]) < mini:
						continue
					d = minf(d, _ecart_boite(p, c))
				releves.append(d)
				if d > DEUX_SECONDES:
					vides += 1
				if d > pire:
					pire = d
					pire_pos = p
			x += PAS
		y += PAS
	releves.sort()
	var n := releves.size()
	print("\n  ── distance au %s ──" % libelle)
	print("     médiane      %5.1f m  (%4.1f s)   cible ≤ %.1f m"
			% [releves[n / 2], releves[n / 2] / VITESSE, UNE_SECONDE])
	print("     9e décile    %5.1f m  (%4.1f s)   cible ≤ %.1f m"
			% [releves[n * 9 / 10], releves[n * 9 / 10] / VITESSE, DEUX_SECONDES])
	print("     maximum      %5.1f m  (%4.1f s)   en %s"
			% [pire, pire / VITESSE, str(pire_pos)])
	print("     aire à plus de deux secondes : %.1f %%  (%d cases sur %d)"
			% [100.0 * float(vides) / float(n), vides, n])


## COMBIEN DE COUVERTS TIENNENT DANS LE CADRE DE JEU.
##
## La caméra est posée huit mètres derrière le joueur, dix mètres quarante
## au-dessus, ouverture verticale de 58°. Le sol visible est donc un
## trapèze qui commence six mètres DERRIÈRE le joueur et finit seize mètres
## devant. On compte les couverts dont le centre y tombe, par niveau.
##
## La consigne demande deux à quatre couverts SIGNIFICATIFS à l'écran :
## on lit la colonne « niveau 2 ou 3 », jamais le total.
func _dans_le_cadre(couverts: Array) -> void:
	const DEVANT := 16.0
	const DERRIERE := 6.0
	const DEMI_ANGLE := 0.78
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var totaux: Array[int] = []
	var duels: Array[int] = []
	for essai in 800:
		var p := _point(rng)
		var cap := rng.randf() * TAU
		var avant := Vector2(cos(cap), sin(cap))
		var n_tout := 0
		var n_duel := 0
		for c: Dictionary in couverts:
			var v: Vector2 = (c["pos"] as Vector2) - p
			var le_long := v.dot(avant)
			if le_long > DEVANT or le_long < -DERRIERE:
				continue
			var en_travers := absf(v.dot(Vector2(-avant.y, avant.x)))
			if en_travers > (le_long + DERRIERE + 2.0) * DEMI_ANGLE:
				continue
			n_tout += 1
			if int(c["niveau"]) >= 2:
				n_duel += 1
		totaux.append(n_tout)
		duels.append(n_duel)
	totaux.sort()
	duels.sort()
	var n := duels.size()
	print("\n  ── couverts dans le cadre de jeu (%d poses au hasard) ──" % n)
	print("     tout niveau        médiane %2d   1er décile %2d   9e décile %2d"
			% [totaux[n / 2], totaux[n / 10], totaux[n * 9 / 10]])
	print("     niveau 2 ou 3      médiane %2d   1er décile %2d   9e décile %2d"
			% [duels[n / 2], duels[n / 10], duels[n * 9 / 10]])
	var maigres := 0
	for d in duels:
		if d < 2:
			maigres += 1
	print("     poses avec moins de deux couverts de duel : %.1f %%  cible ≤ 5 %%"
			% [100.0 * float(maigres) / float(n)])


func _lignes_de_vue(couverts: Array) -> void:
	# Une ligne est COUPÉE si un couvert d'au moins 1,5 m la traverse — les
	# caisses basses ne coupent pas un tir tendu, elles l'abaissent.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var longues := 0
	var degagees := 0
	for essai in 6000:
		var a := _point(rng)
		var b := _point(rng)
		if a.distance_to(b) < 24.0:
			continue
		longues += 1
		var coupe := false
		for c: Dictionary in couverts:
			if int(c["niveau"]) < 2:
				continue
			if _segment_touche(a, b, c):
				coupe = true
				break
		if not coupe:
			degagees += 1
	print("\n  ── lignes de vue au-delà de 24 m ──")
	print("     dégagées : %.1f %%  (%d sur %d)  cible ≤ 12 %%   (V1 : 11.8 %%)"
			% [100.0 * float(degagees) / float(longues), degagees, longues])


func _quadrants(couverts: Array) -> void:
	var noms := ["nord-ouest", "nord-est", "sud-ouest", "sud-est"]
	var comptes := [{}, {}, {}, {}]
	for c: Dictionary in couverts:
		if c["cat"] == "margelle":
			continue
		var p: Vector2 = c["pos"]
		var q := (0 if p.x < 0 else 1) + (0 if p.y < 0 else 2)
		var d: Dictionary = comptes[q]
		var cle := "n%d" % int(c["niveau"])
		d[cle] = int(d.get(cle, 0)) + 1
		d["aire"] = float(d.get("aire", 0.0)) + float(c["aire"])
	print("\n  ── par quadrant ──")
	for q in 4:
		var d: Dictionary = comptes[q]
		print("     %-11s  niveau 3 : %2d · niveau 2 : %2d · niveau 1 : %2d · emprise %4.0f m²"
				% [noms[q], int(d.get("n3", 0)), int(d.get("n2", 0)),
				int(d.get("n1", 0)), float(d.get("aire", 0.0))])


## CONTOURNABILITÉ, VUE DU PLAN.
##
## Le banc pose la même question en bâtissant l'arène et en tirant des
## rayons — trente secondes, et il ne dit que le nom du coupable. Ici on
## veut savoir en une seconde LAQUELLE des masses est serrée et PAR QUOI :
## sans cela on corrige une coordonnée au jugé, on relance, et on
## recommence quatre fois.
func _contournabilite(couverts: Array) -> void:
	print("\n  ── contournabilité des masses (anneau à %.1f m du bord) ──"
			% (PlanAreneWestern.DEGAGEMENT * 0.5))
	var marge := PlanAreneWestern.DEGAGEMENT * 0.5
	var serrees := 0
	for m: Dictionary in PlanAreneWestern.masses():
		var c: Vector2 = m["pos"]
		var demi: Vector2 = m["demi"]
		var libres := 0
		var n := 48
		var coupables := {}
		for i in n:
			var a := TAU * float(i) / float(n)
			var dir := Vector2(cos(a), sin(a))
			var bas := 0.0
			var haut := demi.length() + marge * 3.0 + 2.0
			for pas in 20:
				var mm := (bas + haut) * 0.5
				if PlanAreneWestern.ecart_masse(c + dir * mm, m) < marge:
					bas = mm
				else:
					haut = mm
			var p := c + dir * haut
			var pris := ""
			if not PlanAreneWestern.dans_enceinte(p, PlanAreneWestern.MARGE_BORD):
				pris = "clôture"
			else:
				for o: Dictionary in couverts:
					if (o["pos"] as Vector2).distance_to(c) < 0.01:
						continue
					if _ecart_boite(p, o) < 0.35:
						pris = "%s en %s" % [o["cat"], str(o["pos"])]
						break
			if pris == "":
				libres += 1
			else:
				coupables[pris] = int(coupables.get(pris, 0)) + 1
		var taux := float(libres) / float(n)
		if taux < 0.80:
			serrees += 1
			var liste: Array[String] = []
			for k in coupables:
				liste.append("%s ×%d" % [k, coupables[k]])
			print("     %-14s %3.0f %% libre   pris par : %s"
					% [str(c), taux * 100.0, ", ".join(liste.slice(0, 3))])
	if serrees == 0:
		print("     toutes au-dessus de 80 %% d'anneau libre.")


## LES APPARITIONS, VUES DU PLAN.
##
## Le banc les juge en bâtissant l'arène — trente secondes. Ici on veut
## seulement savoir, en une seconde, laquelle est trop près d'un couvert et
## laquelle est trop près de sa voisine : ce sont les deux erreurs qu'on
## fait en déplaçant des coordonnées à la main.
func _apparitions(couverts: Array) -> void:
	print("\n  ── apparitions ──")
	var aps := PlanAreneWestern.APPARITIONS
	for i in aps.size():
		var p: Vector2 = aps[i]
		var d_couvert := INF
		var quoi := "—"
		for c: Dictionary in couverts:
			var d := _ecart_boite(p, c)
			if d < d_couvert:
				d_couvert = d
				quoi = c["cat"]
		var d_voisine := INF
		for j in aps.size():
			if j != i:
				d_voisine = minf(d_voisine, p.distance_to(aps[j]))
		var souci := ""
		if d_couvert < 1.2:
			souci += "  ← COUVERT À %.1f m (%s)" % [d_couvert, quoi]
		if d_voisine < 12.0:
			souci += "  ← VOISINE À %.1f m" % d_voisine
		if not PlanAreneWestern.dans_enceinte(p, PlanAreneWestern.MARGE_BORD):
			souci += "  ← HORS ENCEINTE"
		print("     %-2d %-16s couvert %5.1f m · voisine %5.1f m%s"
				% [i + 1, str(p), d_couvert, d_voisine, souci])


## Un point au hasard, uniformément réparti DANS L'ENCEINTE.
func _point(rng: RandomNumberGenerator) -> Vector2:
	for essai in 40:
		var p := Vector2(rng.randf_range(-PlanAreneWestern.BORD, PlanAreneWestern.BORD),
				rng.randf_range(-PlanAreneWestern.BORD, PlanAreneWestern.BORD))
		if PlanAreneWestern.dans_enceinte(p, PlanAreneWestern.MARGE_BORD):
			return p
	return Vector2.ZERO


func _aire_jouable() -> float:
	var n := 0
	var dedans := 0
	var y := -PlanAreneWestern.BORD
	while y <= PlanAreneWestern.BORD:
		var x := -PlanAreneWestern.BORD
		while x <= PlanAreneWestern.BORD:
			n += 1
			if PlanAreneWestern.dans_enceinte(Vector2(x, y),
					PlanAreneWestern.MARGE_BORD):
				dedans += 1
			x += PAS
		y += PAS
	var cote := PlanAreneWestern.BORD * 2.0
	return cote * cote * float(dedans) / float(n)


## Le segment ab traverse-t-il le rectangle orienté `c` ?
func _segment_touche(a: Vector2, b: Vector2, c: Dictionary) -> bool:
	# On échantillonne : exact serait plus élégant, mais ce fichier tourne
	# six mille fois par passage et l'écart d'un demi-mètre ne change
	# aucune décision de level design.
	var n := maxi(8, int(a.distance_to(b) / 0.6))
	for i in n + 1:
		if _ecart_boite(a.lerp(b, float(i) / float(n)), c) <= 0.0:
			return true
	return false
