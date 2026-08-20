extends Node
## BANC DE SONS — synthétise des sons de tir provisoires, un par arme.
##
## Autoload : Sfx
##
## ─── POURQUOI SYNTHÉTISER PLUTÔT QU'ATTENDRE DES FICHIERS ──────────────
##
## Le projet n'avait AUCUN système audio. La consigne demande six armes
## reconnaissables « même sans voir le personnage » — or la moitié de cette
## reconnaissance passe par l'oreille, et un placeholder unique pour les
## six aurait rendu le test d'identification faux dès le départ : on aurait
## validé six armes distinctes en n'écoutant rien.
##
## On fabrique donc six sons DIFFÉRENTS à partir de quatre nombres portés
## par le profil de chaque arme : hauteur, durée, grain, chute. Ce ne sont
## pas des sons finis — ce sont des sons JUSTES, au sens où le grave de
## Bruno et le claquement sec de Nox ne se confondent pas.
##
## ─── COMMENT LES REMPLACER LE JOUR OÙ LES VRAIS ARRIVENT ───────────────
##
## Poser le fichier dans `res://audio/tir_<heros>.wav` (ou .ogg) : il est
## chargé à la place du son synthétisé, sans toucher une ligne de code.
## C'est la seule raison pour laquelle cette recherche de fichier existe.

const DOSSIER := "res://audio/"
const TAUX := 22050

## Voix simultanées. Dix joueurs qui tirent, plus les impacts : au-delà, on
## recycle la plus ancienne plutôt que d'empiler des nœuds.
const VOIX := 18

var _tirs: Dictionary = {}      # StringName -> AudioStreamWAV
var _impacts: Dictionary = {}
var _voix: Array[AudioStreamPlayer3D] = []
var _suivante: int = 0


func _ready() -> void:
	for i in VOIX:
		var j := AudioStreamPlayer3D.new()
		j.max_distance = 42.0
		j.unit_size = 6.0
		j.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(j)
		_voix.append(j)


func tir(profil: ProfilTir, pos: Vector3) -> void:
	if profil == null:
		return
	_jouer(_stream_tir(profil), pos, 1.0)


func impact(profil: ProfilTir, pos: Vector3) -> void:
	if profil == null:
		return
	# L'impact est plus discret que le départ : c'est le tir qui identifie
	# l'arme, l'impact ne fait que le confirmer. Un impact aussi fort que
	# le départ doublerait chaque coup et saturerait l'oreille à dix
	# joueurs.
	_jouer(_stream_impact(profil), pos, 0.55)


func _jouer(flux: AudioStream, pos: Vector3, volume: float) -> void:
	if flux == null or _voix.is_empty():
		return
	var j := _voix[_suivante]
	_suivante = (_suivante + 1) % _voix.size()
	j.global_position = pos
	j.stream = flux
	j.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	j.play()


func _stream_tir(profil: ProfilTir) -> AudioStream:
	var cle: StringName = profil.heros
	if _tirs.has(cle):
		return _tirs[cle]
	var charge := _charger("tir_%s" % cle)
	if charge == null:
		charge = _synthese(profil.son_hauteur, profil.son_duree,
				profil.son_grain, profil.son_chute, 0.32)
	_tirs[cle] = charge
	return charge


func _stream_impact(profil: ProfilTir) -> AudioStream:
	var cle: StringName = profil.heros
	if _impacts.has(cle):
		return _impacts[cle]
	var charge := _charger("impact_%s" % cle)
	if charge == null:
		# Un impact est plus haut, plus court et plus bruité que le départ :
		# c'est un choc, pas une détonation.
		charge = _synthese(profil.son_hauteur * 1.6,
				minf(profil.son_duree * 0.6, 0.10),
				clampf(profil.son_grain + 0.2, 0.0, 1.0),
				profil.son_chute * 1.8, 0.55)
	_impacts[cle] = charge
	return charge


func _charger(nom: String) -> AudioStream:
	for ext in [".wav", ".ogg", ".mp3"]:
		var chemin: String = DOSSIER + nom + ext
		if ResourceLoader.exists(chemin):
			return ResourceLoader.load(chemin) as AudioStream
	return null


## SYNTHÈSE — un balayage de hauteur décroissante, mêlé de bruit blanc,
## enveloppé d'une décroissance exponentielle.
##
## Les quatre paramètres suffisent à séparer les six armes :
##
##   hauteur  grave (Bruno, 110 Hz) contre aigu (Ruby, 880 Hz) ;
##   duree    claquement (Nox, 45 ms) contre coup de canon (Bruno, 260 ms) ;
##   grain    sifflement pur (Ruby, 0,15) contre souffle (Bruno, 0,80) ;
##   chute    extinction brutale (Nox, 70) contre traîne (Bruno, 12).
##
## `attaque` ajoute un clic très court au tout début — c'est lui qui donne
## le tranchant, et sans lui tous les sons commencent mollement.
func _synthese(hauteur: float, duree: float, grain: float, chute: float,
		attaque: float) -> AudioStreamWAV:
	var n := maxi(64, int(duree * float(TAUX)))
	var octets := PackedByteArray()
	octets.resize(n * 2)
	var phase := 0.0
	# Graine FIXE : deux parties doivent produire exactement le même son,
	# sinon le banc d'identification mesurerait du bruit d'un passage à
	# l'autre.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hauteur * 7.0) + int(duree * 1000.0)
	for i in n:
		var t := float(i) / float(TAUX)
		var av := t / duree
		# La hauteur descend vers un tiers de sa valeur : c'est ce
		# glissement qui fait entendre « détonation » plutôt que « bip ».
		var f: float = hauteur * lerpf(1.0, 0.34, av * av)
		phase += TAU * f / float(TAUX)
		var corps := sin(phase)
		var bruit := rng.randf_range(-1.0, 1.0)
		var s: float = lerpf(corps, bruit, grain)
		var enveloppe: float = exp(-chute * t)
		# Le clic d'attaque, sur les toutes premières millisecondes.
		if t < 0.004:
			s = lerpf(s, rng.randf_range(-1.0, 1.0), attaque)
			enveloppe = maxf(enveloppe, 1.0 - t / 0.004 * 0.3)
		var v := int(clampf(s * enveloppe, -1.0, 1.0) * 30000.0)
		octets[i * 2] = v & 0xFF
		octets[i * 2 + 1] = (v >> 8) & 0xFF
	var flux := AudioStreamWAV.new()
	flux.format = AudioStreamWAV.FORMAT_16_BITS
	flux.mix_rate = TAUX
	flux.stereo = false
	flux.data = octets
	return flux


## Nombre de voix libres. Exposé pour les bancs : sans lui, on ne peut pas
## distinguer « le son est joué » de « le banc de voix est saturé ».
func voix_libres() -> int:
	var n := 0
	for j in _voix:
		if not j.playing:
			n += 1
	return n
