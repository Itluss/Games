extends Node3D
class_name BlockoutBuilder
## BÂTISSEUR DU GRAYBOX — primitives simples, couleurs debug uniquement.
## Consomme exclusivement les données de `BlockoutPlan`. Aucune texture,
## aucun modèle, aucun shader décoratif — uniquement des `BoxMesh` /
## `CylinderMesh` / `SphereMesh` avec des matériaux plats, et leur
## collision statique correspondante.
##
## Identité couleur debug par secteur (base = murs, accent = couvertures
## et plateformes) : Sanctuary ivoire+bleu, Forge charbon+orange,
## Barracks marine+orange, Rift violet+cyan, Core gris neutre+jaune. Les
## hubs (zones de confrontation partagées, V2) ont leur propre couleur
## neutre « zone contestée », pas une couleur de faction.

const EPAISSEUR := 1.0
const EPAISSEUR_RAMPE := 1.0

var _mat_sol := StandardMaterial3D.new()
var _mat_neutre := StandardMaterial3D.new()      ## enceinte, rampes cardinales, flank
var _mat_couverture := StandardMaterial3D.new()  ## couvertures de flank (non liées à un secteur)
var _mat_core_mur := StandardMaterial3D.new()
var _mat_core_accent := StandardMaterial3D.new() ## capsule, sockets de zone finale
var _mat_rampe := StandardMaterial3D.new()
var _mat_hub_base := StandardMaterial3D.new()    ## murs des hubs — zone contestée
var _mat_hub_accent := StandardMaterial3D.new()  ## plateformes/couvertures des hubs

var _mat_secteur_base: Dictionary = {}
var _mat_secteur_accent: Dictionary = {}

var _mat_spawn := StandardMaterial3D.new()
var _mat_loot_haut := StandardMaterial3D.new()
var _mat_loot_moyen := StandardMaterial3D.new()
var _mat_loot_commun := StandardMaterial3D.new()
var _mat_soin := StandardMaterial3D.new()

var _compteur_rampe := 0


func _ready() -> void:
	_preparer_materiaux()
	_construire_sol()
	_construire_murs()
	_construire_couvertures()
	_construire_plateformes()
	_construire_rampes()
	_construire_spawns()
	_construire_loot(BlockoutPlan.LOOT_HAUT, "loot_high", _mat_loot_haut, 0.9, "LootHaut")
	_construire_loot(BlockoutPlan.LOOT_MOYEN, "loot_medium", _mat_loot_moyen, 0.6, "LootMoyen")
	_construire_loot(BlockoutPlan.LOOT_COMMUN, "loot_common", _mat_loot_commun, 0.42, "LootCommun")
	_construire_soins()
	_construire_capsule()
	_construire_sockets()


func _preparer_materiaux() -> void:
	_mat_sol.albedo_color = Color(0.55, 0.55, 0.58)
	_mat_neutre.albedo_color = Color(0.4, 0.4, 0.43)
	_mat_couverture.albedo_color = Color(0.45, 0.45, 0.48)
	_mat_core_mur.albedo_color = Color(0.5, 0.5, 0.53)
	_mat_core_accent.albedo_color = Color(0.95, 0.85, 0.15)
	_mat_rampe.albedo_color = Color(0.6, 0.6, 0.5)
	_mat_hub_base.albedo_color = Color(0.55, 0.2, 0.18)   ## rouille — zone de friction
	_mat_hub_accent.albedo_color = Color(0.95, 0.55, 0.15) ## ambre contesté

	_mat_secteur_base["Sanctuary"] = _mat(Color(0.85, 0.83, 0.75))
	_mat_secteur_accent["Sanctuary"] = _mat(Color(0.2, 0.45, 0.9))
	_mat_secteur_base["Forge"] = _mat(Color(0.16, 0.16, 0.18))
	_mat_secteur_accent["Forge"] = _mat(Color(0.9, 0.45, 0.1))
	_mat_secteur_base["Barracks"] = _mat(Color(0.08, 0.14, 0.32))
	_mat_secteur_accent["Barracks"] = _mat(Color(0.9, 0.5, 0.15))
	_mat_secteur_base["Rift"] = _mat(Color(0.32, 0.12, 0.42))
	_mat_secteur_accent["Rift"] = _mat(Color(0.15, 0.85, 0.85))

	_mat_spawn.albedo_color = Color(0.15, 0.85, 0.85)
	_mat_loot_haut.albedo_color = Color(0.95, 0.75, 0.1)
	_mat_loot_moyen.albedo_color = Color(0.75, 0.78, 0.82)
	_mat_loot_commun.albedo_color = Color(0.55, 0.55, 0.5)
	_mat_soin.albedo_color = Color(0.2, 0.85, 0.3)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Préfixe du nom de donnée → secteur, pour l'identité couleur. Retourne
## "" si le mur/élément est neutre (enceinte, Core, écran anti-LOS).
func _secteur_de(nom: String) -> String:
	for secteur in BlockoutPlan.SECTEURS:
		if nom.begins_with(secteur + "_"):
			return secteur
	return ""


## Idem pour les hubs diagonaux (zone contestée, pas une couleur de
## faction) — préfixes "NE_", "SE_", "SW_", "NW_".
func _hub_de(nom: String) -> String:
	for hub in BlockoutPlan.HUBS:
		if nom.begins_with(hub + "_"):
			return hub
	return ""


func _mat_mur_pour(nom: String) -> Material:
	var secteur := _secteur_de(nom)
	if secteur != "":
		return _mat_secteur_base[secteur]
	if _hub_de(nom) != "":
		return _mat_hub_base
	if nom.begins_with("core_"):
		return _mat_core_mur
	return _mat_neutre


func _mat_accent_pour(nom: String) -> Material:
	var secteur := _secteur_de(nom)
	if secteur != "":
		return _mat_secteur_accent[secteur]
	if _hub_de(nom) != "":
		return _mat_hub_accent
	return _mat_core_accent


# --- SOL -------------------------------------------------------------------

func _construire_sol() -> void:
	var taille := BlockoutPlan.R_BORD * 2.1
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(taille, taille)
	var mi := MeshInstance3D.new()
	mi.name = "Sol"
	mi.mesh = mesh
	mi.material_override = _mat_sol
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "SolCollision"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(taille, 0.2, taille)
	col.shape = shape
	col.position.y = -0.11
	body.add_child(col)
	add_child(body)


# --- MURS ET COUVERTURES (extrusion de polylignes) --------------------------

func _construire_murs() -> void:
	for m: Dictionary in BlockoutPlan.MURS:
		_extruder_polyligne(m["points"], m["haut"], m.get("y", 0.0),
				_mat_mur_pour(m["nom"]), true, "Mur_%s" % m["nom"])


func _construire_couvertures() -> void:
	for c: Dictionary in BlockoutPlan.COUVERTS:
		_extruder_polyligne(c["points"], c["haut"], c.get("y", 0.0),
				_mat_couverture, true, "Couvert_%s" % c["nom"])


func _extruder_polyligne(pts: PackedVector2Array, haut: float, y0: float,
		mat: Material, collision: bool, nom_base: String) -> void:
	var groupe := Node3D.new()
	groupe.name = nom_base
	add_child(groupe)
	for i in pts.size() - 1:
		_extruder_segment(pts[i], pts[i + 1], haut, y0, mat, collision,
				"%s_seg%d" % [nom_base, i], groupe)


func _extruder_segment(a: Vector2, b: Vector2, haut: float, y0: float,
		mat: Material, collision: bool, nom: String, parent: Node3D) -> void:
	var centre := (a + b) * 0.5
	var longueur := a.distance_to(b)
	if longueur < 0.05:
		return
	var angle := (b - a).angle()
	var body := StaticBody3D.new() if collision else Node3D.new()
	body.name = nom
	body.position = Vector3(centre.x, y0 + haut * 0.5, centre.y)
	body.rotation.y = -angle
	if collision:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(longueur + EPAISSEUR, haut, EPAISSEUR)
		col.shape = shape
		body.add_child(col)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(longueur + EPAISSEUR, haut, EPAISSEUR)
	mi.mesh = box
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)


# --- PLATEFORMES SURÉLEVÉES --------------------------------------------------
## V2 : TOUJOURS un socle plein, du sol jusqu'au sommet — jamais une dalle
## suspendue praticable en dessous (règle de level design explicite :
## « aucun espace jouable ne doit passer sous une plateforme »). C'est
## aussi ce qui a servi de socle collidable pour les tours sniper dès la
## V1 ; la V2 généralise ce choix à toutes les plateformes.
func _construire_plateformes() -> void:
	for p: Dictionary in BlockoutPlan.PLATEFORMES:
		var rect: Rect2 = p["rect"]
		var y: float = p["y"]
		var nom: String = p["nom"]
		var centre := rect.position + rect.size * 0.5

		var body := StaticBody3D.new()
		body.name = "Plateforme_%s" % nom
		body.position = Vector3(centre.x, y * 0.5, centre.y)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(rect.size.x, 0.5), y, maxf(rect.size.y, 0.5))
		col.shape = shape
		body.add_child(col)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		mi.mesh = box
		mi.material_override = _mat_accent_pour(nom)
		body.add_child(mi)
		add_child(body)


# --- RAMPES PRATICABLES ------------------------------------------------------
## Bloc plein incliné (pas un visuel seul) : la base orthonormée est
## construite directement à partir de la pente, sans passer par les
## angles d'Euler (évite toute ambiguïté d'ordre de rotation).
func _construire_rampes() -> void:
	for r: Dictionary in BlockoutPlan.RAMPES:
		var bas: Vector2 = r["bas"]
		var haut: Vector2 = r["haut"]
		var y_bas: float = r["y_bas"]
		var y_haut: float = r["y_haut"]
		var large: float = r["large"]
		var delta := haut - bas
		var horiz := delta.length()
		var vert := y_haut - y_bas
		if horiz < 0.05 and absf(vert) < 0.05:
			continue
		var longueur_pente := Vector2(horiz, vert).length()
		var avant := Vector3(delta.x, vert, delta.y).normalized()
		var droite := Vector3(-delta.y, 0.0, delta.x).normalized() if horiz > 0.001 \
				else Vector3(1, 0, 0)
		var haut_local := droite.cross(avant).normalized()
		# Le centre de la boîte suit la ligne (bas→haut), mais sa SURFACE DE
		# MARCHE doit coïncider avec cette ligne — pas son milieu vertical.
		# Sans ce décalage d'une demi-épaisseur vers le bas, chaque rampe
		# affleure ~0,5 m au-dessus du sol qu'elle est censée prolonger : un
		# rebord invisible mais infranchissable à chaque seuil (trouvé via
		# la vérification de déplacement par capsule, qui restait bloquée
		# net à chaque entrée de rampe).
		var centre := Vector3((bas.x + haut.x) * 0.5, (y_bas + y_haut) * 0.5,
				(bas.y + haut.y) * 0.5) - haut_local * (EPAISSEUR_RAMPE * 0.5)

		var body := StaticBody3D.new()
		body.name = "Rampe_%d" % _compteur_rampe
		_compteur_rampe += 1
		body.transform = Transform3D(Basis(droite, haut_local, avant), centre)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(large, EPAISSEUR_RAMPE, longueur_pente)
		col.shape = shape
		body.add_child(col)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		mi.mesh = box
		mi.material_override = _mat_rampe
		body.add_child(mi)
		add_child(body)


# --- MARQUEURS DE GAMEPLAY ---------------------------------------------------

func _marqueur(nom: String, groupe: String, pos: Vector2, y: float, mat: Material,
		taille: float) -> Marker3D:
	var m := Marker3D.new()
	m.name = nom
	m.position = Vector3(pos.x, y, pos.y)
	m.add_to_group(groupe)
	add_child(m)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = taille
	sphere.height = taille * 2.0
	mi.mesh = sphere
	mi.material_override = mat
	m.add_child(mi)
	return m


func _construire_spawns() -> void:
	for s: Dictionary in BlockoutPlan.SPAWNS:
		var nom: String = s["nom"]
		var pos: Vector2 = s["pos"]
		var marqueur := Marker3D.new()
		marqueur.name = "Spawn_%s" % nom
		marqueur.position = Vector3(pos.x, 0.0, pos.y)
		marqueur.add_to_group("player_spawns")
		add_child(marqueur)

		var disque := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.4
		cyl.height = 0.1
		disque.mesh = cyl
		disque.material_override = _mat_spawn
		disque.position = Vector3(0, 0.05, 0)
		marqueur.add_child(disque)

		var label3d := Label3D.new()
		label3d.text = nom
		label3d.font_size = 64
		label3d.position = Vector3(0, 2.0, 0)
		label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label3d.outline_size = 12
		marqueur.add_child(label3d)


func _construire_loot(points: Array, groupe: String, mat: Material, taille: float,
		prefixe: String) -> void:
	for i in points.size():
		var pos: Vector2 = points[i]
		_marqueur("%s_%02d" % [prefixe, i + 1], groupe, pos, taille + 0.1, mat, taille)


func _construire_soins() -> void:
	for i in BlockoutPlan.SOINS.size():
		var pos: Vector2 = BlockoutPlan.SOINS[i]
		var m := _marqueur("Soin_%02d" % (i + 1), "heal_stations", pos, 0.05, _mat_soin, 0.1)
		var mi: MeshInstance3D = m.get_child(0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.1
		cyl.bottom_radius = 1.1
		cyl.height = 0.15
		mi.mesh = cyl
		mi.position = Vector3(0, 0.08, 0)


func _construire_capsule() -> void:
	var m := Marker3D.new()
	m.name = "SupplyCapsule"
	m.position = Vector3(BlockoutPlan.CAPSULE_CENTRALE.x, 0.15,
			BlockoutPlan.CAPSULE_CENTRALE.y)
	m.add_to_group("supply_capsule")
	add_child(m)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.6, 1.6)
	mi.mesh = box
	mi.material_override = _mat_core_accent
	m.add_child(mi)


func _construire_sockets() -> void:
	for s: Dictionary in BlockoutPlan.SOCKETS_ZONE_FINALE:
		var pos: Vector2 = s["pos"]
		var m := _marqueur("Socket_%s" % s["nom"], "final_zone_sockets", pos, 0.6,
				_mat_core_accent, 0.5)
		var mi: MeshInstance3D = m.get_child(0)
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 1.2, 1.0)
		mi.mesh = box
