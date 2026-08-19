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
##   3. PIÈCE ENFONCÉE — sa base est sous le sol. Les faces qui traversent
##      le plan du sol se battent avec lui sur toute leur surface.
##   4. PIÈCE POSÉE PILE À ZÉRO — sa face inférieure est EXACTEMENT dans le
##      plan du sol. C'est la cause la plus sournoise : géométriquement
##      irréprochable, et elle clignote quand même.
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
	_enfoncements(pieces)
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
	if mi != null and mi.mesh != null and mi.name != "Sol":
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
			pire = maxf(pire, part)
			if part > SEUIL_CHEVAUCHEMENT:
				pires.append("%s ∩ %s (%.0f %%)"
						% [pieces[i]["nom"], pieces[j]["nom"], part * 100.0])
	_ligne(pires.is_empty(), "aucune interpénétration anormale",
			"pire recouvrement %.0f %% (seuil %.0f %%)"
			% [pire * 100.0, SEUIL_CHEVAUCHEMENT * 100.0])
	for p in pires.slice(0, 6):
		print("        → %s" % p)


func _enfoncements(pieces: Array[Dictionary]) -> void:
	var enfonces: Array[String] = []
	var rases: Array[String] = []
	var plus_bas := INF
	for p: Dictionary in pieces:
		var y: float = (p["aabb"] as AABB).position.y
		plus_bas = minf(plus_bas, y)
		if y < -0.02:
			enfonces.append("%s (base à %.3f m)" % [p["nom"], y])
		elif y < LEVEE_MINI:
			rases.append("%s (base à %.4f m)" % [p["nom"], y])
	_ligne(enfonces.is_empty(), "aucune pièce enfoncée dans le sol",
			"base la plus basse %.3f m" % plus_bas)
	for e in enfonces.slice(0, 6):
		print("        → %s" % e)
	_ligne(rases.is_empty(), "aucune pièce coplanaire avec le sol",
			"%d pièce(s) sous %.3f m" % [rases.size(), LEVEE_MINI])
	for r in rases.slice(0, 6):
		print("        → %s" % r)


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
