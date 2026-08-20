extends Node
## BANC DES DÉMARCHES — les six sont-ils VRAIMENT distinguables ?
##
## POURQUOI CE BANC EXISTE. Une planche d'images fixes est un support
## faible pour juger un mouvement : on y devine une différence, on ne la
## prouve pas. Ici on échantillonne la couche de locomotion pendant trois
## secondes à vitesse IDENTIQUE pour tous, et on relève quatre signatures :
## cadence réelle, amplitude verticale, roulis, penché.
##
## LE TEST N'EST PAS « les nombres sont-ils différents » — ils le sont par
## construction, ce serait une tautologie. Il vérifie que chaque paire de
## personnages se sépare d'au moins UN QUART sur au moins DEUX signatures.
## Un seul axe ne suffit pas : deux personnages qui ne diffèrent que par
## leur cadence se confondent dès qu'on les regarde de loin ou qu'ils
## ralentissent.

const DUREE := 3.0
const PAS := 1.0 / 120.0
const VITESSE := 5.0
const NOMS := ["milo", "poppy", "bruno", "nox", "ruby", "gus"]
## Écart relatif minimal pour considérer deux valeurs distinctes.
const SEUIL := 0.25
## Nombre de signatures qui doivent séparer chaque paire.
const AXES_MINI := 2

var _echecs := 0

func _ready() -> void:
	var mesures := {}
	for nom in NOMS:
		mesures[nom] = _mesurer(nom)

	print("\n=== SIGNATURES DE DÉMARCHE (vitesse identique : %.1f m/s) ===\n" % VITESSE)
	print("  %-7s %8s %10s %8s %8s" % ["", "pas/s", "rebond cm", "roulis°", "penché°"])
	for nom in NOMS:
		var m: Dictionary = mesures[nom]
		print("  %-7s %8.2f %10.1f %8.1f %8.1f"
				% [nom, m["cadence"], m["rebond"] * 100.0,
					rad_to_deg(m["roulis"]), rad_to_deg(m["penche"])])

	print("\n  Séparation par paire (il faut %d axes à plus de %d %%) :"
			% [AXES_MINI, int(SEUIL * 100)])
	var pires := []
	for i in NOMS.size():
		for j in range(i + 1, NOMS.size()):
			var a: Dictionary = mesures[NOMS[i]]
			var b: Dictionary = mesures[NOMS[j]]
			var axes := 0
			var detail := []
			for cle in ["cadence", "rebond", "roulis", "penche"]:
				var va: float = a[cle]
				var vb: float = b[cle]
				var base: float = maxf(maxf(absf(va), absf(vb)), 0.0001)
				var ecart: float = absf(va - vb) / base
				if ecart >= SEUIL:
					axes += 1
					detail.append("%s %.0f%%" % [cle, ecart * 100.0])
			if axes < AXES_MINI:
				pires.append("%s / %s : %d axe(s) — %s"
						% [NOMS[i], NOMS[j], axes, ", ".join(detail)])
	if pires.is_empty():
		print("      les quinze paires se séparent sur au moins %d axes." % AXES_MINI)
	else:
		_echecs += pires.size()
		for p in pires:
			print("      [ÉCHEC] %s" % p)

	print("")
	# MARQUE DE FIN LUE PAR `barriere.sh`.
	#
	# Le lanceur refuse de croire un banc qui n'imprime pas cette ligne :
	# c'est ainsi qu'il distingue « tout est passé » de « le banc s'est
	# arrêté en route ». Sans elle, un banc pourtant conforme était
	# compté comme non exécuté.
	print("=== %d échec(s) ===" % _echecs)
	if _echecs == 0:
		print("Démarches : conforme.")
	else:
		print("Démarches : %d paire(s) trop proche(s)." % _echecs)
	get_tree().quit(1 if _echecs > 0 else 0)


## Fait marcher un personnage trois secondes et relève ses extrêmes.
func _mesurer(nom: String) -> Dictionary:
	var loco := Locomotion.new()
	loco.profil = ProfilDemarche.profil(StringName(nom))
	loco.vitesse_nominale = VITESSE
	add_child(loco)
	loco.set_move_input(Vector2(0, 1))
	loco.set_aim_direction(Vector3(0, 0, 1))
	loco.set_velocity(Vector3(0, 0, VITESSE))

	var h_min := INF
	var h_max := -INF
	var roulis := 0.0
	var penche := 0.0
	var appuis := 0
	var montait := false
	var t := 0.0
	# On laisse l'élan s'établir avant de compter : les premières images
	# sont un démarrage, pas une marche, et fausseraient la cadence.
	while t < DUREE:
		loco.avancer(PAS)
		t += PAS
		if t < 0.6:
			continue
		var h := loco.hauteur()
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
		var inc := loco.inclinaison()
		roulis = maxf(roulis, absf(inc.z))
		penche = maxf(penche, absf(inc.x))
		# Un appui = un passage par le bas. On compte les changements de
		# sens vers le haut, ce qui est insensible au bruit numérique.
		var monte := h > h_min + 0.0005
		if monte and not montait:
			appuis += 1
		montait = monte
	loco.queue_free()
	return {
		"cadence": float(appuis) / (DUREE - 0.6),
		"rebond": h_max - h_min,
		"roulis": roulis,
		"penche": penche,
	}
