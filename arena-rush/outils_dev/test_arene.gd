extends Node
## TEST DU MONDE — outil de développement, hors jeu.
##
## POURQUOI CE FICHIER A CHANGÉ DE SUJET. Il vérifiait les garanties d'une
## arène de combat fermée : « aucune ligne de tir d'une apparition à une
## autre ». Cette exigence avait un sens sur 34 m, où quatre joueurs se
## voyaient d'un bout à l'autre. Sur 156 m et dix apparitions, elle n'en a
## plus : deux points distants de 120 m ne se voient de toute façon pas, et
## exiger un obstacle entre chacune des quarante-cinq paires reviendrait à
## exiger une carte pleine de murs.
##
## Un test qui vérifie une garantie devenue caduque est pire qu'une absence
## de test : il rassure sur ce qui n'est plus le sujet. Les garanties d'un
## MONDE OUVERT sont autres, et ce sont elles qui sont mesurées ici.
##
## Usage :
##   godot --headless --path arena-rush res://outils_dev/test_arene.tscn

var _echecs := 0
var _total := 0
var _boites: Array[Dictionary] = []
var _monde: Arena

func _ready() -> void:
	await get_tree().process_frame
	_relever()
	# DEUX TRAMES DE PHYSIQUE, APRÈS LA CONSTRUCTION. Les formes de
	# collision ne sont connues du serveur physique qu'après un pas de
	# simulation. Placées AVANT `_relever()`, elles s'écoulaient sur un
	# monde qui n'existait pas encore, et la garantie d'étanchéité annonçait
	# 1 440 brèches sur 1 440 angles — c'est-à-dire aucun mur du tout. Un
	# test qui échoue à 100 % accuse le test avant d'accuser le monde, et
	# c'est deux fois de suite que ce réflexe a payé.
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("=== MONDE CONSTRUIT ===")
	_garantie_pavage()
	_garantie_poi_dans_leur_secteur()
	_garantie_repartition_des_apparitions()
	_garantie_apparitions_libres()
	_garantie_apparitions_espacees()
	_garantie_tout_dans_le_monde()
	_garantie_foyers_de_mobs()
	_garantie_cout_de_dessin()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


## Relève le monde RÉELLEMENT monté, jamais le plan.
##
## La leçon est acquise : le plan déclare une intention, le jeu joue autre
## chose. Un « immeuble » déclaré 7 m de large n'en occupait que 1,9 une
## fois son modèle mis à l'échelle, et le test annonçait pourtant la ligne
## de tir coupée.
func _relever() -> void:
	_monde = Arena.new()
	add_child(_monde)
	var corps := _monde.get_node_or_null("Obstacles")
	if corps == null:
		push_error("Monde monté sans corps « Obstacles ».")
		return
	for n in corps.get_children():
		var forme := n as CollisionShape3D
		if forme == null:
			continue
		# LE SOL N'EST PAS UN OBSTACLE. Sa boîte de collision fait 187 m de
		# large et se centre sur l'origine : comptée comme un obstacle, elle
		# déclarait TOUT le monde bloqué — dix apparitions sur dix et
		# trente-cinq foyers sur trente-cinq. Un test qui échoue à 100 %
		# accuse le test avant d'accuser le monde.
		#
		# On la reconnaît à sa position : le sol est enterré, tout obstacle
		# réel a son centre au-dessus de zéro.
		if forme.position.y <= 0.0:
			continue
		var rayon := 0.0
		if forme.shape is BoxShape3D:
			var b := forme.shape as BoxShape3D
			rayon = maxf(b.size.x, b.size.z) * 0.5
		elif forme.shape is CylinderShape3D:
			rayon = (forme.shape as CylinderShape3D).radius
		else:
			continue
		_boites.append({
			"pos": Vector2(forme.position.x, forme.position.z),
			"rayon": rayon,
		})
	print("  %d obstacles relevés." % _boites.size())


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-54s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


# --- GARANTIE 1 : LES SECTEURS PAVENT LE CERCLE -------------------------
#
# C'est LE défaut qui s'est produit : des ouvertures écrites à la main
# totalisaient 113 % du tour, deux secteurs se chevauchaient, et l'un
# d'eux se retrouvait sans aucun point d'apparition.

func _garantie_pavage() -> void:
	# LE DÉCOUPAGE PAR CENTRES NE PEUT PAS LAISSER DE TROU — chaque point a
	# exactement un centre le plus proche. Ce qu'on vérifie ici, c'est que
	# personne n'a été OUBLIÉ : un secteur dont le poids serait trop faible,
	# ou dont le centre serait posé sur celui d'un voisin, n'aurait aucun
	# territoire et disparaîtrait du monde sans que rien ne le signale.
	var vus: Dictionary = {}
	var manquants := 0
	for iz in 60:
		for ix in 60:
			var p := Vector2(
					-PlanMonde.DEMI + (float(ix) + 0.5) * PlanMonde.COTE / 60.0,
					-PlanMonde.DEMI + (float(iz) + 0.5) * PlanMonde.COTE / 60.0)
			var s := PlanMonde.secteur_de(p)
			if s == &"":
				manquants += 1
			vus[s] = int(vus.get(s, 0)) + 1
	_verifier("aucun point sans secteur", manquants, 0)
	_verifier("tous les secteurs existent sur la carte",
			vus.size(), PlanMonde.SECTEURS.size())
	var mini := 99999
	for s in vus:
		mini = mini(mini, int(vus[s]))
	print("      part du plus petit secteur : %.1f %%"
			% [100.0 * float(mini) / 3600.0])
	_verifier("aucun secteur ne fait moins de 3 % du monde",
			float(mini) / 3600.0 > 0.03, true)


# --- GARANTIE 2 : CHAQUE REPÈRE EST DANS SON SECTEUR --------------------

func _garantie_poi_dans_leur_secteur() -> void:
	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		var p := PlanMonde.position_poi(poi)
		_verifier("%s est dans %s" % [poi["id"], poi["secteur"]],
				PlanMonde.secteur_de(p), poi["secteur"])


# --- GARANTIE 3 : LES APPARITIONS SONT RÉPARTIES ------------------------
#
# Toutes dans le même secteur, le monde n'aurait qu'une seule porte
# d'entrée — et quatre secteurs sur cinq ne serviraient jamais.

func _garantie_repartition_des_apparitions() -> void:
	var par_secteur: Dictionary = {}
	for sp: Vector3 in _monde.player_spawn_points:
		var s := PlanMonde.secteur_de(Vector2(sp.x, sp.z))
		par_secteur[s] = int(par_secteur.get(s, 0)) + 1
	print("      répartition : %s" % str(par_secteur))
	# TOUS LES SECTEURS SAUF UN. On ne réapparaît jamais dans le Creuset :
	# c'est le point le plus disputé du monde, et y renvoyer un joueur qui
	# vient d'y mourir transformerait chaque mort en série de morts.
	_verifier("chaque secteur habitable a des apparitions",
			par_secteur.size(), PlanMonde.SECTEURS.size() - 1)
	_verifier("aucune apparition dans le Creuset",
			par_secteur.has(&"creuset"), false)
	var mini := 999
	for s in par_secteur:
		mini = mini(mini, int(par_secteur[s]))
	_verifier("aucun secteur n'en a moins de deux", mini >= 2, true)


# --- GARANTIE 4 : PERSONNE NE NAÎT DANS UN ROCHER -----------------------

func _garantie_apparitions_libres() -> void:
	var dans_le_decor := 0
	for sp: Vector3 in _monde.player_spawn_points:
		if not _libre(Vector2(sp.x, sp.z), 0.55):
			dans_le_decor += 1
			print("      ! apparition bloquée en %s" % str(sp))
	_verifier("aucune apparition dans un obstacle", dans_le_decor, 0)


# --- GARANTIE 5 : LES APPARITIONS SONT ESPACÉES -------------------------
#
# Deux points de retour côte à côte concentreraient tout le monde au même
# endroit — exactement ce qu'on cherche à éviter en les répartissant.

func _garantie_apparitions_espacees() -> void:
	var plus_court := INF
	var pts := _monde.player_spawn_points
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			plus_court = minf(plus_court, pts[i].distance_to(pts[j]))
	print("      distance minimale entre apparitions : %.1f m" % plus_court)
	_verifier("les apparitions sont à plus de 12 m l'une de l'autre",
			plus_court > 12.0, true)


# --- GARANTIE 6 : TOUT TIENT DANS LE MONDE ------------------------------

func _garantie_tout_dans_le_monde() -> void:
	# IL N'Y A PLUS DE BORD DONT ON PUISSE DÉBORDER. La question devient
	# l'inverse : le monde se RECOLLE-T-IL sur lui-même ?
	#
	# C'est la garantie centrale du monde enroulé, et la seule chose qui
	# puisse la casser est une périodicité mal choisie. L'ondulation qui
	# adoucit les frontières de secteur est faite de sinus ; si l'une de
	# leurs périodes ne divise pas le côté du monde, la couture réapparaît —
	# une seule fois, en pleine carte, sous la forme d'une frontière nette
	# là où il ne devrait rien y avoir.
	var ruptures := 0
	var premiere := 0.0
	for i in 600:
		var t := -PlanMonde.DEMI + PlanMonde.COTE * float(i) / 600.0
		# Deux points séparés de 2 cm SUR LE TORE, de part et d'autre de la
		# limite du carré de référence. Ils doivent appartenir au même
		# secteur, comme n'importe quels voisins immédiats.
		if PlanMonde.secteur_de(Vector2(t, PlanMonde.DEMI - 0.01)) \
				!= PlanMonde.secteur_de(Vector2(t, -PlanMonde.DEMI + 0.01)):
			ruptures += 1
			if premiere == 0.0:
				premiere = t
		if PlanMonde.secteur_de(Vector2(PlanMonde.DEMI - 0.01, t)) \
				!= PlanMonde.secteur_de(Vector2(-PlanMonde.DEMI + 0.01, t)):
			ruptures += 1
			if premiere == 0.0:
				premiere = t
	if ruptures > 0:
		print("      ! %d rupture(s) à la couture, la première en %.1f m"
				% [ruptures, premiere])
	_verifier("le monde se recolle sur lui-même", ruptures, 0)

	# ET LES COLLISIONS SE RECOLLENT AUSSI. Un rocher posé à un mètre du
	# bord doit arrêter un joueur qui arrive de l'autre côté : sans copie,
	# la physique les croit séparés de 142 m et on traverse le décor.
	var pres_du_bord := 0
	var doubles := 0
	for b in _boites:
		var c: Vector2 = b["pos"]
		if absf(c.x) < PlanMonde.DEMI - 3.0 and absf(c.y) < PlanMonde.DEMI - 3.0:
			continue
		pres_du_bord += 1
		for autre in _boites:
			var d: Vector2 = autre["pos"]
			if d != c and PlanMonde.distance(c, d) < 0.05:
				doubles += 1
				break
	print("      %d obstacles à moins de 3 m d'une couture, %d recollés"
			% [pres_du_bord, doubles])
	_verifier("tous les obstacles de la couture ont leur jumeau",
			doubles, pres_du_bord)


# --- GARANTIE 7 : DES MOBS PEUVENT APPARAÎTRE PARTOUT -------------------

func _garantie_foyers_de_mobs() -> void:
	var libres := 0
	var par_secteur: Dictionary = {}
	for f: Vector3 in _monde.mob_spawn_points:
		var p := Vector2(f.x, f.z)
		if _libre(p, 0.9):
			libres += 1
			var s := PlanMonde.secteur_de(p)
			par_secteur[s] = int(par_secteur.get(s, 0)) + 1
	print("      %d foyers libres sur %d · %s"
			% [libres, _monde.mob_spawn_points.size(), str(par_secteur)])
	_verifier("au moins 20 foyers de mobs libres", libres >= 20, true)
	_verifier("les foyers couvrent au moins quatre zones",
			par_secteur.size() >= 4, true)


# --- GARANTIE 8 : LE COÛT DE DESSIN RESTE TENABLE -----------------------
#
# La seule garantie qui décide si le jeu tourne sur un téléphone, et la
# seule qu'aucune capture d'écran ne montrera jamais.

func _garantie_cout_de_dessin() -> void:
	var semis := 0
	var instances := 0
	var maillages := 0
	var pile: Array[Node] = [_monde]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if n is MultiMeshInstance3D:
			semis += 1
			instances += (n as MultiMeshInstance3D).multimesh.instance_count
		elif n is MeshInstance3D:
			maillages += 1
		for e in n.get_children():
			pile.append(e)
	print("      %d props en %d semis · %d maillages individuels"
			% [instances, semis, maillages])
	# Le semis doit RASSEMBLER : moins de dix props par semis signifierait
	# que le découpage en tuiles a échoué et qu'on paie un appel de dessin
	# pour presque rien.
	var par_semis := float(instances) / maxf(1.0, float(semis))
	print("      moyenne : %.1f props par semis" % par_semis)
	_verifier("les semis rassemblent (plus de 5 props chacun)",
			par_semis > 5.0, true)
	# Les maillages individuels sont le vrai coût fixe : ils sont dessinés
	# un par un. Le noyau en concentre l'essentiel, et c'est voulu.
	_verifier("moins de 200 maillages individuels", maillages < 200, true)


# --- GARANTIE 9 : IL N'Y A PLUS DE MUR ---------------------------------
#
# La garantie précédente vérifiait qu'aucune brèche ne laissait passer le
# joueur à travers le mur du monde. Elle a fait son travail — le mur était
# étanche sur 1 440 angles — puis le mur a été supprimé, et avec lui la
# question. On ne garde pas un test qui rassure sur ce qui n'existe plus.
#
# Ce qui la remplace est dans `_garantie_tout_dans_le_monde` : le monde
# doit se RECOLLER sur lui-même, secteurs et collisions compris.

func _libre(p: Vector2, rayon: float) -> bool:
	for b in _boites:
		var centre: Vector2 = b["pos"]
		var r: float = b["rayon"]
		if PlanMonde.distance(p, centre) < r + rayon:
			return false
	return true
