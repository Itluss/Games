extends Node3D
## SONDE ANTI-SCINTILLEMENT — cherche les causes de clignotement.
##
## ─── CE QU'ELLE CHERCHE, ET POURQUOI CHACUN CLIGNOTE ────────────────────
##
## Un objet qui clignote n'est presque jamais un objet cassé : c'est DEUX
## surfaces qui se disputent le même pixel. Le rendu tranche par la
## profondeur, la profondeur est un nombre à précision finie, et quand deux
## surfaces tombent dans le même cran, laquelle gagne dépend de l'angle de
## la caméra. D'où le scintillement : il n'apparaît qu'en mouvement, et
## jamais sur une capture fixe — c'est ce qui le rend si difficile à
## signaler et si facile à ignorer.
##
## Quatre causes, quatre mesures :
##
##   1. DOUBLONS — deux pièces au même endroit. Chaque face de l'une est
##      coplanaire avec celle de l'autre. C'est le cas le plus violent et
##      le plus fréquent quand un plan est édité à la main.
##   2. CHEVAUCHEMENT ANORMAL — deux grosses masses qui s'interpénètrent.
##      Tolérable sur quelques centimètres (un débris posé contre un mur),
##      pathologique au-delà.
##   3. BASE AU RAS D'UN PLAN DE SOL — la face inférieure d'une pièce
##      tombe à quelques millimètres du sol. C'est la cause la plus
##      sournoise : géométriquement irréprochable, et elle clignote quand
##      même. Attention au raisonnement inverse, que cette sonde a tenu un
##      temps : une pièce ENFONCÉE ne clignote pas. Une face verticale qui
##      traverse le sol ne lui dispute aucun pixel, elle est simplement
##      cachée dessous. Les socles des modèles Meshy sont enterrés exprès.
##   4. PIÈCE ENFOUIE — sous un demi-mètre de sol. Celle-là n'est pas un
##      défaut de rendu mais une pose ratée ; elle est mesurée à part et
##      nommée pour ce qu'elle est.
##
## La sonde ne juge pas la beauté du niveau. Elle ne répond qu'à une
## question : « quelque chose va-t-il clignoter ? »

## Deux pièces dont les centres sont plus proches que ceci sont considérées
## comme un doublon. 35 cm : en dessous, aucune composition volontaire ne
## place deux props distincts.
const SEUIL_DOUBLON := 0.35

## Part de volume commun au-delà de laquelle deux masses s'interpénètrent
## anormalement. 35 % : un objet appuyé contre un autre en partage
## quelques pour cent, pas un tiers.
const SEUIL_CHEVAUCHEMENT := 0.35

## En dessous de ce volume, une pièce est trop petite pour que son
## chevauchement compte (une plante dans un buisson ne clignote pas).
const VOLUME_SIGNIFICATIF := 0.8

## Levée minimale attendue au-dessus du sol.
const LEVEE_MINI := 0.004

var _echecs := 0

func _ready() -> void:
	Cfg.arene_test = true
	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)
	await get_tree().process_frame
	await get_tree().process_frame

	var pieces := _relever(arene)
	print("SONDE SCINTILLEMENT — %d pièces relevées.\n" % pieces.size())

	_doublons(pieces)
	_chevauchements(pieces)
	_enfoncements(pieces, _plans_de_sol(arene))
	_sols_multiples(arene)

	print("")
	if _echecs == 0:
		print("Scintillement : conforme.")
	else:
		print("Scintillement : %d anomalie(s)." % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-46s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])


## Relève chaque pièce : son nom, sa position, et sa boîte englobante
## MONDIALE — c'est elle qui dit ce qui occupe quel volume.
func _relever(n: Node, out: Array[Dictionary] = []) -> Array[Dictionary]:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null and not _est_du_sol_ou_fondu(mi):
		var b := mi.get_aabb()
		var coins: Array[Vector3] = []
		for i in 8:
			coins.append(mi.global_transform * (b.position + Vector3(
					b.size.x * float(i & 1),
					b.size.y * float((i >> 1) & 1),
					b.size.z * float((i >> 2) & 1))))
		var mondiale := AABB(coins[0], Vector3.ZERO)
		for c in coins:
			mondiale = mondiale.expand(c)
		out.append({"nom": _piece_parente(mi), "aabb": mondiale,
				"centre": mondiale.get_center()})
	for e in n.get_children():
		_relever(e, out)
	return out


## CE QUI N'EST PAS UNE PIÈCE.
##
## Trois maillages ne se jugent pas comme des props, et les compter comme
## tels faisait crier la sonde sur du travail sain :
##
##   · « Sol » et « Dalles » SONT le sol. Une pièce coplanaire avec le sol
##     est un défaut ; le sol coplanaire avec lui-même est une tautologie.
##   · « Fusion_… » est un LOT FONDU — toutes les caisses d'une teinte
##     réunies en un seul maillage pour n'être dessinées qu'une fois. Sa
##     boîte englobante couvre l'arène entière, donc recouvre celle de tous
##     les autres à cent pour cent. La sonde y voyait le pire
##     chevauchement possible là où il n'y a qu'un gain de performance.
##
## Une sonde qui accuse ce qu'elle devrait ignorer finit par être ignorée
## elle-même — et c'est comme ça qu'un vrai scintillement passe.
func _est_du_sol_ou_fondu(mi: MeshInstance3D) -> bool:
	return mi.name == "Sol" or mi.name == "Dalles" \
			or String(mi.name).begins_with("Fusion_")


## Remonte au pivot posé par l'arène : c'est LUI la pièce, pas la maille.
func _piece_parente(n: Node) -> String:
	var p := n
	for i in 6:
		if p.get_parent() == null:
			break
		if p.get_parent().name == "Arena":
			return "%s@%s" % [p.name, str(Vector2(
					snappedf((p as Node3D).position.x, 0.1),
					snappedf((p as Node3D).position.z, 0.1)))] \
					if p is Node3D else p.name
		p = p.get_parent()
	return n.name


func _doublons(pieces: Array[Dictionary]) -> void:
	var pires: Array[String] = []
	var mini := INF
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var d: float = (pieces[i]["centre"] as Vector3).distance_to(
					pieces[j]["centre"])
			mini = minf(mini, d)
			if d < SEUIL_DOUBLON:
				pires.append("%s ≈ %s (%.3f m)"
						% [pieces[i]["nom"], pieces[j]["nom"], d])
	_ligne(pires.is_empty(), "aucune pièce en doublon",
			"écart minimal %.2f m (seuil %.2f)" % [mini, SEUIL_DOUBLON])
	for p in pires.slice(0, 6):
		print("        → %s" % p)


func _chevauchements(pieces: Array[Dictionary]) -> void:
	var pires: Array[String] = []
	var pire := 0.0
	for i in pieces.size():
		var a: AABB = pieces[i]["aabb"]
		if a.get_volume() < VOLUME_SIGNIFICATIF:
			continue
		for j in range(i + 1, pieces.size()):
			var b: AABB = pieces[j]["aabb"]
			if b.get_volume() < VOLUME_SIGNIFICATIF:
				continue
			var inter := a.intersection(b)
			if inter.size == Vector3.ZERO:
				continue
			# Rapporté à la PLUS PETITE des deux : une petite pièce noyée
			# dans une grosse est le vrai défaut, et le rapport au volume
			# total le diluerait jusqu'à l'invisible.
			var part := inter.get_volume() / minf(a.get_volume(), b.get_volume())
			# ET LE CENTRE DE LA PETITE DOIT ÊTRE AU CŒUR DE LA GROSSE.
			#
			# La boîte englobante d'un rocher Meshy est un pavé posé autour
			# d'une forme irrégulière montée sur un socle : une caisse
			# rangée contre le flanc du rocher tombe DANS la boîte sans
			# jamais toucher la pierre. La sonde criait alors à
			# l'interpénétration sur des poses parfaitement propres — six
			# fois de suite, ce qui est le meilleur moyen de faire ignorer
			# la septième, celle qui aurait été vraie. On exige donc que le
			# centre de la petite pièce soit dans le TIERS CENTRAL de la
			# grosse : là, elle est vraiment dedans.
			var grosse: AABB = a if a.get_volume() >= b.get_volume() else b
			var petite: AABB = b if a.get_volume() >= b.get_volume() else a
			var noyau := AABB(grosse.position + grosse.size * 0.25,
					grosse.size * 0.5)
			if not noyau.has_point(petite.get_center()):
				continue
			pire = maxf(pire, part)
			if part > SEUIL_CHEVAUCHEMENT:
				pires.append("%s ∩ %s (%.0f %%)"
						% [pieces[i]["nom"], pieces[j]["nom"], part * 100.0])
	_ligne(pires.is_empty(), "aucune interpénétration anormale",
			"pire recouvrement %.0f %% (seuil %.0f %%)"
			% [pire * 100.0, SEUIL_CHEVAUCHEMENT * 100.0])
	for p in pires.slice(0, 6):
		print("        → %s" % p)


## CE QUI FAIT CLIGNOTER, C'EST LA PROXIMITÉ, PAS LA PROFONDEUR.
##
## La première version de cette mesure signalait toute pièce dont la base
## passait sous zéro. Le raisonnement écrit à côté — « les faces qui
## traversent le plan du sol se battent avec lui » — est FAUX, et il m'a
## fait chercher un défaut là où il n'y en avait pas. Deux surfaces ne se
## disputent un pixel que si elles sont COPLANAIRES. Une face verticale qui
## traverse le sol ne lui dispute rien : elle est simplement cachée en
## dessous.
##
## Ce qui compte est donc la DISTANCE de la base de chaque pièce au plan de
## sol le plus proche. Les modèles Meshy arrivent sur un socle qu'on
## enterre exprès — treize centimètres pour les gros rochers — et c'est
## sain tant que cette base ne vient pas frôler un plan de sol.
##
## Reste une seconde question, qui n'a rien à voir avec le scintillement :
## une pièce enfouie d'un demi-mètre n'est pas un défaut de rendu, c'est
## une pose ratée. Elle garde sa mesure, séparée et nommée pour ce qu'elle
## est.
func _enfoncements(pieces: Array[Dictionary], sols: Array[float]) -> void:
	var frolent: Array[String] = []
	var enfouies: Array[String] = []
	var plus_proche := INF
	for p: Dictionary in pieces:
		var y: float = (p["aabb"] as AABB).position.y
		var d := INF
		for s_y: float in sols:
			d = minf(d, absf(y - s_y))
		plus_proche = minf(plus_proche, d)
		if d < LEVEE_MINI:
			frolent.append("%s (base à %.4f m, plan à %.4f m)"
					% [p["nom"], y, y + d])
		if y < -0.50:
			enfouies.append("%s (base à %.3f m)" % [p["nom"], y])
	_ligne(frolent.is_empty(), "aucune base au ras d'un plan de sol",
			"écart le plus faible %.4f m (seuil %.3f)"
			% [plus_proche, LEVEE_MINI])
	for f in frolent.slice(0, 6):
		print("        → %s" % f)
	_ligne(enfouies.is_empty(), "aucune pièce enfouie",
			"%d pièce(s) sous -0.50 m" % enfouies.size())
	for e in enfouies.slice(0, 6):
		print("        → %s" % e)


## RELÈVE LES PLANS DE SOL — le dessus du pavé, et la nappe de dalles.
func _plans_de_sol(n: Node, out: Array[float] = []) -> Array[float]:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null \
			and (mi.name == "Sol" or mi.name == "Dalles"):
		var b := mi.get_aabb()
		out.append(mi.global_position.y + b.position.y + b.size.y)
	for e in n.get_children():
		_plans_de_sol(e, out)
	return out


## UN SEUL SOL. Deux dalles de sol superposées est la cause de
## scintillement la plus large qui soit — elle couvre tout l'écran.
func _sols_multiples(arene: Node) -> void:
	var sols: Array = []
	_compter_sols(arene, sols)
	_ligne(sols.size() == 1, "un seul plan de sol",
			"%d dalle(s) nommée(s) « Sol »" % sols.size())


func _compter_sols(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.name == "Sol":
		out.append(n)
	for e in n.get_children():
		_compter_sols(e, out)
