extends Node3D
## BANC D'IDENTIFICATION DES SIX ARMES.
##
## ─── LA QUESTION QU'IL POSE ────────────────────────────────────────────
##
## « Un joueur peut-il reconnaître qui lui tire dessus en moins d'une
## seconde, sans voir le personnage, et SANS la couleur ? »
##
## La couleur est écartée de toutes les mesures, et ce n'est pas un excès
## de zèle : c'est la consigne. Six armes qui ne diffèrent que par leur
## teinte se ressemblent toutes dès qu'on joue de nuit, dès qu'on est
## daltonien, et dès qu'un effet lumineux les délave. On mesure donc
## uniquement ce qui survit au passage en niveaux de gris :
##
##   · le nombre de coups par déclenchement — le RYTHME ;
##   · la cadence ;
##   · le nombre de projectiles par coup ;
##   · la largeur du cône ;
##   · la taille et le nombre de branches du départ — la FORME ;
##   · la forme de la traînée ;
##   · la forme et la taille de l'impact ;
##   · la nature et l'amplitude du recul du corps.
##
## ─── ET IL VÉRIFIE AUSSI QUE ÇA TIRE VRAIMENT ──────────────────────────
##
## Comparer des tables de nombres ne prouve rien : on pourrait déclarer six
## profils magnifiques et n'en jouer aucun. Chaque arme est donc réellement
## équipée et déclenchée, et le banc compte les coups et les projectiles
## RÉELLEMENT partis. C'est la différence entre « les données diffèrent »
## et « les tirs diffèrent ».

const HEROS: Array[StringName] = [&"milo", &"poppy", &"bruno", &"nox",
		&"ruby", &"gus"]

## Axes sur lesquels deux armes doivent différer. En dessous de ce nombre,
## deux armes se confondent dès que la couleur disparaît.
const AXES_MINI := 3

var _echecs := 0
var _releves: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	print("\n=== BANC DES SIX ARMES ===\n")
	for h in HEROS:
		_releves[h] = await _mesurer(h)
	_table()
	_tirs_reels()
	_separations()
	await _charge()

	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh` : sans elle, un banc conforme est
	# compté comme non exécuté.
	print("=== %d échec(s) ===" % _echecs)
	print("Armes : %s." % ("conforme" if _echecs == 0
			else "%d anomalie(s)" % _echecs))
	get_tree().quit(1 if _echecs > 0 else 0)


## Équipe l'arme du héros, la déclenche une fois, et relève ce qui est
## RÉELLEMENT parti.
func _mesurer(h: StringName) -> Dictionary:
	var data := Registry.arme_de_heros(h)
	if data == null or data.profil == null:
		_ligne(false, "arme de %s" % h, "introuvable ou sans profil")
		return {}
	var arme := Weapon.new()
	add_child(arme)
	arme.equip(data)

	var canons: Array[int] = []
	arme.coup_parti.connect(func(c: int): canons.append(c))
	Projectile.remettre_compteur()
	arme.fire(Vector3(0, 1.2, 0), Vector3.FORWARD, Cfg.Team.PLAYER, 1, false)
	# On laisse la rafale se dérouler : elle s'écoule sur l'horloge
	# physique, donc on attend des trames de PHYSIQUE, pas d'affichage.
	var attente: float = data.profil.rafale_intervalle \
			* float(data.coups_par_declenchement() + 1) + 0.12
	var t := 0.0
	while t < attente:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var projectiles := Projectile.emis
	arme.queue_free()
	return {
		"data": data, "profil": data.profil,
		"coups": arme.tirs, "projectiles": projectiles, "canons": canons,
	}


## LA TABLE — c'est elle qu'on compare à la planche, ligne par ligne.
func _table() -> void:
	print("  %-7s %-8s %5s %5s %6s %7s %-9s %-10s %-8s" % ["héros",
			"mode", "coups", "proj", "cad.", "cône", "départ", "impact",
			"recul"])
	for h in HEROS:
		var r: Dictionary = _releves[h]
		if r.is_empty():
			continue
		var d: WeaponData = r["data"]
		var p: ProfilTir = r["profil"]
		print("  %-7s %-8s %5d %5d %5.1f/s %6.0f° %-9s %-10s %-8s" % [h,
				p.mode, d.coups_par_declenchement(), d.projectile_count,
				d.fire_rate, d.spread_degrees,
				"%s×%d" % [p.flash, p.flash_branches], p.impact,
				p.recul_corps])


## LES TIRS SONT-ILS RÉELLEMENT PARTIS, ET EN BON NOMBRE ?
func _tirs_reels() -> void:
	print("")
	for h in HEROS:
		var r: Dictionary = _releves[h]
		if r.is_empty():
			continue
		var d: WeaponData = r["data"]
		var attendus_coups := d.coups_par_declenchement()
		var attendus_proj := attendus_coups * d.projectile_count
		_ligne(int(r["coups"]) == attendus_coups,
				"%s : coups par déclenchement" % h,
				"%d parti(s), %d attendu(s)" % [int(r["coups"]), attendus_coups])
		_ligne(int(r["projectiles"]) == attendus_proj,
				"%s : projectiles émis" % h,
				"%d émis, %d attendu(s)" % [int(r["projectiles"]), attendus_proj])

	# GUS DOIT VRAIMENT ALTERNER. C'est sa signature entière : deux
	# revolvers qui tirent ensemble ne se distinguent pas d'un seul.
	var gus: Dictionary = _releves.get(&"gus", {})
	if not gus.is_empty():
		var canons: Array = gus["canons"]
		var alterne := canons.size() >= 2
		for i in range(1, canons.size()):
			if canons[i] == canons[i - 1]:
				alterne = false
		_ligne(alterne, "gus : les deux canons alternent",
				"séquence %s" % str(canons))


## AUCUNE PAIRE NE DOIT SE CONFONDRE SANS LA COULEUR.
func _separations() -> void:
	print("")
	var pires: Array[String] = []
	var pire := 99
	var pire_nom := "—"
	for i in HEROS.size():
		for j in range(i + 1, HEROS.size()):
			var a: Dictionary = _releves[HEROS[i]]
			var b: Dictionary = _releves[HEROS[j]]
			if a.is_empty() or b.is_empty():
				continue
			var detail: Array[String] = []
			var axes := _axes(a, b, detail)
			if axes < pire:
				pire = axes
				pire_nom = "%s/%s" % [HEROS[i], HEROS[j]]
			if axes < AXES_MINI:
				pires.append("%s ↔ %s : %d axe(s) seulement — %s"
						% [HEROS[i], HEROS[j], axes, ", ".join(detail)])
	_ligne(pires.is_empty(), "chaque paire se sépare sans la couleur",
			"pire paire %s avec %d axes (seuil %d)"
			% [pire_nom, pire, AXES_MINI])
	for p in pires:
		print("        → %s" % p)


## Compte les axes NON COLORÉS sur lesquels deux armes diffèrent nettement.
func _axes(a: Dictionary, b: Dictionary, detail: Array[String]) -> int:
	var da: WeaponData = a["data"]
	var db: WeaponData = b["data"]
	var pa: ProfilTir = a["profil"]
	var pb: ProfilTir = b["profil"]
	var n := 0
	# RYTHME — un coup contre une rafale, c'est la différence la plus
	# audible et la plus visible de toutes.
	if da.coups_par_declenchement() != db.coups_par_declenchement():
		n += 1
		detail.append("rythme")
	# CADENCE — un facteur 1,5 est perceptible à l'oreille et à l'œil.
	var ra: float = maxf(da.fire_rate, db.fire_rate) \
			/ maxf(minf(da.fire_rate, db.fire_rate), 0.01)
	if ra >= 1.5:
		n += 1
		detail.append("cadence ×%.1f" % ra)
	# NOMBRE DE TRAITS — une volée ne se confond pas avec une balle.
	if da.projectile_count != db.projectile_count:
		n += 1
		detail.append("projectiles")
	# LARGEUR — un cône contre un trait droit.
	if absf(da.spread_degrees - db.spread_degrees) >= 8.0:
		n += 1
		detail.append("cône")
	# FORME DU DÉPART — la famille, ou le nombre de branches, ou la taille.
	if pa.flash != pb.flash or pa.flash_branches != pb.flash_branches \
			or maxf(pa.flash_taille, pb.flash_taille) \
			/ maxf(minf(pa.flash_taille, pb.flash_taille), 0.01) >= 1.6:
		n += 1
		detail.append("départ")
	# FORME DE LA TRAÎNÉE.
	if pa.trainee != pb.trainee:
		n += 1
		detail.append("traînée")
	# FORME DE L'IMPACT.
	if pa.impact != pb.impact:
		n += 1
		detail.append("impact")
	# DEUX POINTS DE DÉPART — l'axe que le premier banc avait oublié.
	#
	# Une arme dont le départ apparaît alternativement à gauche et à droite
	# du corps ne se confond avec aucune autre, quelle que soit sa couleur.
	# C'est la signature entière de Gus, et ne pas la compter revenait à le
	# juger sur tout SAUF ce qui le rend reconnaissable.
	if (pa.mode == "alterne") != (pb.mode == "alterne"):
		n += 1
		detail.append("double canon")
	# ─── TAILLE DU PROJECTILE, EN MÈTRES ───────────────────────────────
	#
	# AXE AJOUTÉ, ET IL MANQUAIT. Le banc jugeait la FORME de la traînée et
	# la famille du départ, mais pas le CALIBRE de la balle — alors que
	# c'est la première chose qu'on voit passer, et qu'elle va désormais du
	# simple au quadruple : 0,038 pour l'aiguille de Nox, 0,165 pour l'obus
	# de Bruno. Ne pas la compter, c'était noter Bruno sur tout sauf ce qui
	# le rend reconnaissable — la même faute que pour le double canon de
	# Gus, commise une seconde fois.
	var ta: float = maxf(pa.tete_rayon, 0.001)
	var tb: float = maxf(pb.tete_rayon, 0.001)
	if maxf(ta, tb) / minf(ta, tb) >= 1.5:
		n += 1
		detail.append("calibre ×%.1f" % (maxf(ta, tb) / minf(ta, tb)))
	# LONGUEUR DE LA QUEUE. Un trait bref derrière une gerbe (Poppy) ne se
	# lit pas comme une traînée longue derrière une aiguille (Nox), même
	# si les deux sont classées « fine ».
	var qa: float = maxf(pa.trainee_metres, 0.001)
	var qb: float = maxf(pb.trainee_metres, 0.001)
	if maxf(qa, qb) / minf(qa, qb) >= 1.5:
		n += 1
		detail.append("queue ×%.1f" % (maxf(qa, qb) / minf(qa, qb)))
	# RÉACTION DU CORPS.
	if pa.recul_corps != pb.recul_corps:
		n += 1
		detail.append("recul")
	return n


## DIX JOUEURS QUI TIRENT EN MÊME TEMPS.
##
## POURQUOI ON NE MESURE PAS DES IMAGES PAR SECONDE. Ce banc tourne en
## rendu logiciel à quelques images par seconde : un chiffre de fluidité
## relevé ici serait inventé, et je refuse d'en publier un. On mesure donc
## ce qui est MESURABLE sur cette machine et qui décide vraiment du coût
## sur téléphone : est-ce que les réservoirs tiennent, ou est-ce que chaque
## coup alloue de la mémoire neuve ?
##
## Un réservoir qui se remplit puis se stabilise, c'est du recyclage. Un
## compteur d'objets qui grimpe sans fin, c'est une allocation permanente —
## et c'est elle qui fait saccader un mobile, bien avant le nombre de
## particules.
func _charge() -> void:
	var armes: Array[Weapon] = []
	for h in HEROS:
		var a := Weapon.new()
		add_child(a)
		a.equip(Registry.arme_de_heros(h))
		armes.append(a)
	Projectile.remettre_compteur()
	var noeuds_avant := _compter_noeuds(get_tree().current_scene)
	var salves := 10
	for tour in salves:
		for a in armes:
			a.fire(Vector3(randf_range(-6, 6), 1.2, randf_range(-6, 6)),
					Vector3.FORWARD, Cfg.Team.PLAYER, 1, false)
		for i in 12:
			await get_tree().physics_frame
	# On laisse les effets s'éteindre et les réservoirs se reprendre.
	for i in 90:
		await get_tree().physics_frame
	var noeuds_apres := _compter_noeuds(get_tree().current_scene)
	for a in armes:
		a.queue_free()
	print("")
	print("  ── charge : %d salves des six armes ──" % salves)
	print("     projectiles émis          %d" % Projectile.emis)
	print("     gerbes au réservoir       %d" % Fx.reservoir())
	print("     voix audio libres         %d sur 18" % Sfx.voix_libres())
	print("     nœuds de scène avant/après %d / %d" % [noeuds_avant, noeuds_apres])
	# Le seuil est large exprès : on cherche une fuite, pas une variation.
	# Soixante salves de six armes laissant moins de deux cents nœuds de
	# plus, c'est du recyclage ; le double du nombre de tirs, c'est une
	# fuite.
	_ligne(noeuds_apres - noeuds_avant < 200,
			"aucune fuite de nœuds après la charge",
			"%+d nœud(s)" % (noeuds_apres - noeuds_avant))


func _compter_noeuds(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _compter_noeuds(c)
	return total


func _ligne(ok: bool, libelle: String, detail: String) -> void:
	if not ok:
		_echecs += 1
	print("  [%s] %-44s %s" % ["OK" if ok else "ÉCHEC", libelle, detail])
