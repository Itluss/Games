extends Node3D
## APERÇU DES SIX DÉMARCHES — la seule preuve qui vaille.
##
## Les six avancent CÔTE À CÔTE, à la MÊME vitesse de jeu, pilotés par la
## vraie couche de locomotion. On capture le même instant pour tous, à
## intervalles réguliers d'un cycle. Si les profils fonctionnent, on doit
## voir sur une seule planche que leurs corps ne sont pas à la même
## hauteur, pas penchés pareil, pas au même moment de leur pas.
##
## L'ÉGALITÉ DE VITESSE EST LE CŒUR DU BANC. Si l'un avançait plus vite,
## la différence serait triviale. Ils parcourent tous exactement la même
## distance : tout ce qu'on voit vient de la démarche.

const LARGEUR := 1400
const HAUTEUR := 460
const VITESSE := 5.0
## Nombre de captures, réparties sur une seconde et demie.
const PRISES := 8
const PAS_TEMPS := 0.1875

const NOMS := ["milo", "poppy", "bruno", "nox", "ruby", "gus"]

var _cam: Camera3D
var _dossier := ""
var _corps: Array[Node3D] = []
var _pivots: Array[Node3D] = []
var _locos: Array[Locomotion] = []
var _t := 0.0
var _prise := 0
var _chauffe := 0

func _ready() -> void:
	_dossier = ProjectSettings.globalize_path("user://apercu_demarches")
	DirAccess.make_dir_recursive_absolute(_dossier)
	print("SORTIE=", _dossier)
	get_viewport().size = Vector2i(LARGEUR, HAUTEUR)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("d5cbb4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("cdd6e6")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.2
	add_child(sun)

	for i in NOMS.size():
		var nom: String = NOMS[i]
		var sc := load("res://assets/models/hero_%s.glb" % nom) as PackedScene
		# LE PIVOT PORTE LA POSE, LE MODÈLE PORTE SA MISE À L'ÉCHELLE.
		# Les mélanger rendrait impossible de régler l'un sans casser
		# l'autre — le même découpage que PropKit, et pour la même raison.
		var pivot := Node3D.new()
		pivot.position = Vector3((float(i) - 2.5) * 2.35, 0, 0)
		add_child(pivot)
		var m := sc.instantiate() as Node3D
		pivot.add_child(m)
		_ajuster(m, nom)
		_corps.append(m)
		_pivots.append(pivot)

		var loco := Locomotion.new()
		loco.profil = ProfilDemarche.profil(StringName(nom))
		loco.vitesse_nominale = VITESSE
		add_child(loco)
		loco.set_move_input(Vector2(0, 1))
		loco.set_aim_direction(Vector3(0, 0, 1))
		loco.set_velocity(Vector3(0, 0, VITESSE))
		_locos.append(loco)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 34.0
	_cam.position = Vector3(0, 1.55, 8.4)
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	add_child(_cam)

## Ramène chaque modèle à la hauteur de sa fiche et le pose au sol.
func _ajuster(m: Node3D, nom: String) -> void:
	var boites: Array[AABB] = []
	_col(m, Transform3D.IDENTITY, boites)
	if boites.is_empty():
		return
	var t := boites[0]
	for i in range(1, boites.size()):
		t = t.merge(boites[i])
	var hauteurs := {"milo": 1.85, "poppy": 1.58, "bruno": 2.05,
			"nox": 1.76, "ruby": 1.70, "gus": 1.48}
	var f: float = float(hauteurs[nom]) / maxf(t.size.y, 0.0001)
	m.scale = Vector3.ONE * f
	m.position = Vector3(-t.get_center().x * f, -t.position.y * f,
			-t.get_center().z * f)

func _process(delta: float) -> void:
	_chauffe += 1
	if _chauffe < 3:
		return
	# PAS DE TEMPS FIXE. Sous rendu logiciel la cadence s'effondre à
	# quelques images par seconde ; en lisant le delta réel, les six
	# seraient échantillonnés n'importe où dans leur cycle et la planche
	# ne prouverait rien. On avance d'un pas constant, identique pour tous.
	var d := 1.0 / 60.0
	_t += d
	for i in _locos.size():
		var loco: Locomotion = _locos[i]
		loco.avancer(d)
		var pivot: Node3D = _pivots[i]
		pivot.position.y = loco.hauteur()
		pivot.position.x = (float(i) - 2.5) * 2.35 + loco.derive_laterale()
		var inc := loco.inclinaison()
		pivot.rotation = Vector3(inc.x, PI, inc.z)

	if _t >= PAS_TEMPS * float(_prise + 1):
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/prise_%d.png" % [_dossier, _prise])
		_prise += 1
		if _prise >= PRISES:
			for i in _locos.size():
				var l: Locomotion = _locos[i]
				print("%-7s cadence=%.2f pas/s  état=%s  hauteur=%+.3f m"
						% [NOMS[i], float(l.profil[ProfilDemarche.CADENCE]),
							l.nom_etat(), l.hauteur()])
			get_tree().quit()

func _col(n: Node, t: Transform3D, out: Array[AABB]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(t * mi.get_aabb())
	for e in n.get_children():
		var s := t
		var e3 := e as Node3D
		if e3 != null:
			s = t * e3.transform
		_col(e, s, out)
