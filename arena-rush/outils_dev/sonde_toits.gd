extends Node
## SONDE DES TOITS — la barrière qui manquait, et qui aurait tout changé.
##
## CE QU'ELLE VÉRIFIE. Le monde contient six repères conçus pour qu'on
## passe DESSOUS : le pont, le dépôt, le temple, la place, la carcasse, la
## tour. Leur toit se trouve entre 8 et 14 m, la caméra de jeu à 10,4 m.
## Franchir l'un d'eux met donc de la pierre entre la caméra et le joueur —
## et l'écran se remplit. C'est le défaut « écran opaque » signalé cinq fois.
##
## POURQUOI LES SONDES PRÉCÉDENTES NE L'ONT PAS VU, et c'est la leçon.
##
##   • La sonde d'occlusion cherchait AU RAYON sur la couche du monde. Or
##     les tabliers sont bâtis en pièces NON SOLIDES, pour qu'on puisse
##     passer dessous : aucun rayon ne les rencontrait. L'instrument était
##     aveugle exactement à la géométrie fautive.
##   • La sonde d'écran cherchait un APLAT. Une voûte de pierre vue de près
##     n'est pas un aplat : elle a des faces, une ombre, un dégradé. Mesuré
##     ici : 54 % d'aplat sous le pont contre 95 % en plein désert — le
##     critère désignait le désert comme le cas suspect.
##
## Deux instruments, deux verdicts rassurants, un défaut intact. On ne
## mesure donc plus ni la matière ni les pixels, mais LA RÈGLE : si le
## regard qui va du joueur à la caméra traverse un repère, ce repère DOIT
## être effacé.
##
## Usage :
##   godot --headless --path arena-rush res://outils_dev/sonde_toits.tscn -- --solo

## Rayon de la couronne de positions essayées autour de chaque repère.
const COURONNE := 5.0
## Positions par repère : le centre, plus huit alentour.
const AZIMUTS := 8

var _main: Node
var _echecs := 0
var _total := 0
var _croisements := 0

## Images minimales avant de commencer à interroger : sous ce seuil, ni la
## caméra ni les groupes de l'arène ne sont encore à leur place, et l'on
## mesurerait un état de transition.
const ATTENTE_MIN := 3
## Images maximales avant de déclarer le toit non effacé. Vingt images,
## soit un tiers de seconde : au-delà, le joueur a le temps de se perdre
## sous un toit opaque, et c'est un vrai défaut.
const ATTENTE_MAX := 20


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	await _verifier_les_repères()
	print("=== %d échec(s) sur %d vérifications ===" % [_echecs, _total])
	get_tree().quit(1 if _echecs > 0 else 0)


func _verifier(libelle: String, obtenu, attendu) -> void:
	_total += 1
	var ok: bool = obtenu == attendu
	if not ok:
		_echecs += 1
	print("  [%s] %-56s obtenu=%s attendu=%s"
			% ["OK" if ok else "ÉCHEC", libelle, obtenu, attendu])


func _joueur() -> Node3D:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.get(&"is_local") == true or p.get(&"peer_id") == 1:
			return p
	return null


func _arene() -> Node:
	return get_tree().get_first_node_in_group(&"arene")


func _verifier_les_repères() -> void:
	var j := _joueur()
	var arene := _arene()
	if j == null or arene == null:
		_verifier("la scène est montée", false, true)
		return

	# Le nombre de volumes déclarés doit suivre le nombre de repères. Un
	# repère ajouté demain sans volume rouvrirait le défaut en silence.
	# Tous les repères n'ont pas de surplomb — le temple n'est que des
	# colonnes brisées. On exige donc qu'il y en ait plusieurs, pas six.
	var toits: Array = arene.get(&"_toits")
	print("      %d repères effaçables sur %d"
			% [toits.size(), PlanMonde.POINTS_INTERET.size()])
	_verifier("les repères couverts sont effaçables", toits.size() >= 3, true)

	for poi: Dictionary in PlanMonde.POINTS_INTERET:
		await _verifier_un_repère(j, arene, poi)

	# GARDE-FOU DU BANC LUI-MÊME. Si aucune position ne traverse le moindre
	# toit, ce banc ne prouve RIEN : il passerait au vert même sans les
	# volumes. On exige donc d'avoir rencontré des toits pour de bon.
	_verifier("le banc a bien traversé des toits", _croisements > 0, true)


func _verifier_un_repère(j: Node3D, arene: Node, poi: Dictionary) -> void:
	var p := PlanMonde.position_poi(poi)
	var croise_ici := 0
	var manques := 0
	for i in AZIMUTS + 1:
		var d := Vector3.ZERO
		if i > 0:
			var a := TAU * float(i - 1) / float(AZIMUTS)
			d = Vector3(cos(a), 0.0, sin(a)) * COURONNE
		j.global_position = Vector3(p.x, 0.6, p.y) + d
		PlanMonde.ancre = j.global_position
		# ─── ON ATTEND UN ÉTAT, PLUS UN NOMBRE D'IMAGES ────────────────
		#
		# CE BANC COMPTAIT CINQ IMAGES, et la valeur avait été mesurée sur
		# CETTE machine-ci. Il a échoué en intégration continue, sur un
		# repère et un seul azimut, alors qu'il passait six fois de suite en
		# local : cinq images sur un coureur plus lent ne laissent pas le
		# même temps réel, et l'on mesurait la cadence du coureur autant que
		# la fonctionnalité.
		#
		# Le recalage de la caméra consomme une image ; l'arène ne replace
		# ses groupes qu'APRÈS la caméra (priorité 100), donc le volume du
		# repère n'est à sa place qu'à l'image suivante. Ce qui compte pour
		# le joueur, ce n'est pas « en cinq images » mais « assez vite pour
		# qu'il ne se perde pas » : on laisse donc jusqu'à un tiers de
		# seconde, et l'on échoue si le toit n'est TOUJOURS pas effacé.
		#
		# La différence est essentielle : l'attente est bornée, donc un toit
		# qui ne s'efface jamais est toujours détecté.
		var cam: Camera3D = null
		var touche := {}
		var voile := false
		for essai in ATTENTE_MAX:
			await get_tree().process_frame
			if essai < ATTENTE_MIN:
				continue
			cam = get_viewport().get_camera_3d()
			if cam == null:
				continue
			var oeil := j.global_position + Vector3(0.0, 1.4, 0.0)
			var espace := j.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(oeil,
					cam.global_position)
			q.collision_mask = Cfg.LAYER_TOIT
			# ON COMPTE AUSSI LES DÉPARTS DE L'INTÉRIEUR. Sans cela, un
			# rayon qui NAÎT dans le volume — c'est-à-dire le cas où l'on
			# est déjà sous le toit, donc le seul qui nous intéresse — ne
			# rend aucune touche.
			q.hit_from_inside = true
			touche = espace.intersect_ray(q)
			if touche.is_empty():
				continue
			voile = _est_voile(arene, touche["collider"])
			if voile:
				break
		if cam == null or touche.is_empty():
			continue
		croise_ici += 1
		_croisements += 1
		# LA RÈGLE : traversé, donc effacé. On lit l'état réel de l'arène,
		# pas l'intention du code.
		if not voile:
			manques += 1
			if manques <= 2:
				var toits: Array = arene.get(&"_toits")
				var idx := -1
				for k in toits.size():
					if toits[k]["corps"] == touche["collider"]:
						idx = k
				print("      DIAG %s i=%d touche=%s idx=%d voile=%s cam=%s"
						% [poi["id"], i, touche["collider"], idx,
						arene.get(&"_toit_voile"), cam.global_position])
				print("      DIAG2 cam_arene=%s cam_proc=%s type=%s"
						% [cam.get(&"_arene"), cam.is_processing(),
						cam.get_script().resource_path if cam.get_script() else "?"])

	_verifier("%s : tout toit traversé est effacé (%d croisements)"
			% [String(poi["id"]).to_upper(), croise_ici], manques, 0)


## Le repère porté par ce corps est-il effectivement en tenue fantôme ?
func _est_voile(arene: Node, corps: Node) -> bool:
	var toits: Array = arene.get(&"_toits")
	var voile: int = arene.get(&"_toit_voile")
	if voile < 0 or voile >= toits.size():
		return false
	if toits[voile]["corps"] != corps:
		return false
	# On ne se contente pas de l'index : on vérifie que les maillages
	# portent bien un matériau transparent. Un index juste et un matériau
	# oublié donneraient le même écran plein.
	for mi: MeshInstance3D in toits[voile]["maillages"]:
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true
