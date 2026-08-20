extends Area3D
class_name EtoileWanted
## L'ÉTOILE WANTED POSÉE AU SOL — l'objectif qu'on voit de loin.
##
## RÔLE EXACT DE CE FICHIER : il ne décide de rien. Il se montre, il flotte,
## il tourne, et il PRÉVIENT le directeur quand un joueur le touche. Toute
## la règle — qui la détient, depuis combien de temps, ce qui se passe à la
## mort — vit dans `EtoileDirector`, et sur le serveur uniquement.
##
## Ce partage n'est pas un principe abstrait : c'est ce qui empêche un
## client de s'attribuer l'étoile. Le corps qu'on voit est un décor
## bavard ; l'autorité est ailleurs.
##
## POURQUOI UN SOCLE. Posée seule sur le sable, l'étoile se lisait comme un
## butin d'arme de plus — le monde en est semé. Le socle de pierre dit
## « emplacement d'objectif » avant même qu'on sache à quoi elle sert, et
## il donne au drop un point d'appui visible quand elle tombe.

## Rayon de ramassage, en mètres.
##
## GÉNÉREUX, ET POUR LA MÊME RAISON QUE LE BUTIN : sur écran tactile, on ne
## se pose pas au centimètre. Courir « à côté » de l'objectif du mode sans
## le prendre serait la frustration la plus bête du jeu.
const RAYON_PRISE := 1.6
## Hauteur de flottaison au-dessus du socle.
const HAUTEUR := 1.15
## Amplitude et période du flottement.
const FLOTTE := 0.14
const PERIODE := 2.4
## Tours par seconde. Lente : une étoile qui tourne vite scintille et
## fatigue, alors qu'elle reste des dizaines de secondes à l'écran.
const TOURS := 0.22
## Hauteur du faisceau vertical, en mètres. Assez haut pour dépasser un
## muret, assez bas pour ne pas barrer l'écran.
const HAUTEUR_FAISCEAU := 3.4

## Émis quand un joueur entre dans la zone. Le serveur seul y répond.
signal touchee(peer_id: int)

var _pivot: Node3D
var _etoile: MeshInstance3D
var _socle: MeshInstance3D
var _lueur: OmniLight3D
var _faisceau: MeshInstance3D
var _t: float = 0.0
var _prise: bool = false

## Maillage partagé : une seule étoile existe à la fois, mais elle
## réapparaît souvent, et rebâtir sa géométrie à chaque fois pour vingt
## triangles serait du gaspillage pur.
static var _maille: ArrayMesh = null


func _ready() -> void:
	add_to_group(&"etoile_wanted")
	name = "EtoileWanted"
	collision_layer = Cfg.LAYER_PICKUP
	# On ne surveille QUE les joueurs. Tester chaque projectile et chaque
	# mob contre l'étoile à chaque image ne rapporterait rien.
	collision_mask = Cfg.LAYER_PLAYER
	# Différé : l'étoile peut naître au beau milieu de la diffusion des
	# signaux physiques — un porteur meurt d'un projectile, elle tombe. Le
	# moteur refuse alors toute modification directe de la surveillance.
	set_deferred(&"monitoring", true)
	set_deferred(&"monitorable", false)

	var forme := CollisionShape3D.new()
	var boule := SphereShape3D.new()
	boule.radius = RAYON_PRISE
	forme.shape = boule
	forme.position = Vector3(0, HAUTEUR, 0)
	add_child(forme)

	_socle = MeshInstance3D.new()
	_socle.name = "SocleEtoile"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.78
	cyl.height = 0.22
	cyl.radial_segments = 18
	_socle.mesh = cyl
	_socle.position = Vector3(0, 0.11, 0)
	# SOCLE SOMBRE, ET C'EST UNE QUESTION DE CONTRASTE. En pierre claire,
	# il se fondait dans le sable et l'étoile paraissait flotter sur rien.
	# Le fond sombre lui rend le contour que la lumière ne lui donne pas.
	_socle.material_override = VisualKit.mat(Color("5c4a35"), 0.0, 0.92)
	_socle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_socle)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0, HAUTEUR, 0)
	add_child(_pivot)

	_etoile = MeshInstance3D.new()
	_etoile.name = "MailleEtoile"
	_etoile.mesh = _maille_etoile()
	# L'OR PASSE PAR `glow_mat`, DONC PAR LA SUR-EXPOSITION. En mode non
	# éclairé Godot ignore l'émission : sans ce passage, l'étoile serait un
	# aplat jaune mat au milieu d'un désert jaune. Voir `VisualKit`.
	_etoile.material_override = VisualKit.glow_mat(Color("ffc73a"), 1.8)
	_etoile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_etoile)
	# LE CONTOUR SOMBRE, comme sur les personnages. C'est la signature
	# graphique du jeu, et c'est aussi ce qui fait tenir une forme dorée
	# sur du sable doré : sans lui, l'étoile est un aplat un peu plus clair
	# que son fond, et l'œil ne l'accroche pas.
	# ─── PAS DE CONTOUR SUR CETTE PIÈCE-LÀ ─────────────────────────────
	#
	# Essayé, puis retiré, et la raison mérite d'être écrite pour qu'on ne
	# le retente pas. Le contour du jeu est une COQUE INVERSÉE : la même
	# maille, dilatée le long de ses normales, dont on n'affiche que les
	# faces arrière. Sur les personnages, dont les normales pointent dans
	# toutes les directions, cela donne un liseré. Sur une étoile PLATE,
	# toutes les normales valent ±Z : la coque n'est plus un liseré mais
	# deux plaques noires posées juste devant les deux faces. Vérifié en
	# gros plan — l'étoile se rendait NOIRE, bordée d'un filet doré.
	#
	# Sa lisibilité vient donc d'ailleurs, et c'est suffisant : le socle
	# sombre en dessous, la tranche qui accroche la lumière rasante, et le
	# faisceau au-dessus.
	# ─── ELLE EST INCLINÉE VERS LA CAMÉRA ──────────────────────────────
	#
	# La caméra de jeu plonge à 52°. Une étoile dressée verticalement est
	# donc vue presque par la tranche : on lit une lame, pas une étoile.
	# On la couche de 38° en arrière — sa face regarde alors le joueur —
	# tout en gardant la rotation lente autour de la verticale, qui la
	# fait miroiter comme un trophée.
	_etoile.rotation.x = -deg_to_rad(38.0)

	# UNE LUMIÈRE, PAS UN PROJECTEUR. Portée courte : elle doit poser une
	# flaque dorée sous l'étoile pour qu'on la repère derrière un muret,
	# sans éclairer la moitié de l'arène.
	_lueur = OmniLight3D.new()
	_lueur.light_color = Color("ffc73a")
	_lueur.light_energy = 2.2
	_lueur.omni_range = 3.4
	_lueur.shadow_enabled = false
	_lueur.position = Vector3(0, HAUTEUR, 0)
	add_child(_lueur)

	# ─── LE FAISCEAU : CE QUI LA REND VISIBLE DE LOIN ──────────────────
	#
	# Une étoile posée au sol, vue sous une caméra plongeante à 52°, occupe
	# quelques dizaines de pixels et disparaît dans le sable clair. Le
	# faisceau, lui, monte VERTICALEMENT : il ne se raccourcit pas avec la
	# distance de la même manière, et il dépasse des murets bas derrière
	# lesquels l'étoile serait cachée. C'est le repère que les jeux du
	# genre posent sur leurs objectifs, et pour cette raison précise.
	#
	# Cône ouvert vers le haut, sans capuchon, en mélange normal et très
	# transparent : additif, il aurait blanchi comme tout le reste sur du
	# sable en plein soleil.
	_faisceau = MeshInstance3D.new()
	_faisceau.name = "FaisceauEtoile"
	var cone := CylinderMesh.new()
	# FIN, ET TRÈS TRANSPARENT. Large, le faisceau lisait comme un mur
	# jaune posé en travers du décor et cachait ce qu'il y avait derrière —
	# exactement ce que la consigne interdit à un effet d'objectif.
	cone.top_radius = 0.30
	cone.bottom_radius = 0.15
	cone.height = HAUTEUR_FAISCEAU
	cone.radial_segments = 12
	cone.cap_top = false
	cone.cap_bottom = false
	_faisceau.mesh = cone
	_faisceau.position = Vector3(0, HAUTEUR_FAISCEAU * 0.5, 0)
	var fm := VisualKit.glow_mat(Color("ffc73a"), 1.5, 0.10)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_faisceau.material_override = fm
	_faisceau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_faisceau)

	body_entered.connect(_sur_corps)
	set_process(true)


## Étoile à cinq branches, EXTRUDÉE — pas un panneau plat.
##
## Un panneau tourné vers la caméra aurait été moins cher, mais l'objet est
## posé dans le monde et le joueur tourne autour : une étoile qui reste
## obstinément de face trahit qu'elle est peinte. Vingt triangles de plus
## coûtent moins qu'un objectif qui ne se croit pas.
static func _maille_etoile() -> ArrayMesh:
	if _maille != null:
		return _maille
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var branches := 5
	# AGRANDIE APRÈS COUP. À 0,42 de rayon — quatre-vingts centimètres de
	# large — elle faisait moins de cinquante pixels à la caméra de jeu et
	# se confondait avec un reflet de sable. C'est l'objectif du mode : il
	# doit se repérer d'un bout de l'arène à l'autre, pas se chercher.
	var grand := 0.62
	var petit := 0.27
	var ep := 0.13
	var contour: Array[Vector3] = []
	for i in branches * 2:
		var a := TAU * float(i) / float(branches * 2) + PI * 0.5
		var r: float = grand if i % 2 == 0 else petit
		contour.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for face in 2:
		var z: float = ep if face == 0 else -ep
		var n := Vector3(0, 0, 1.0 if face == 0 else -1.0)
		for i in contour.size():
			var j := (i + 1) % contour.size()
			var trio := [Vector3(0, 0, z), contour[i] + Vector3(0, 0, z * 0.35),
					contour[j] + Vector3(0, 0, z * 0.35)]
			if face == 1:
				trio.reverse()
			for v in trio:
				st.set_normal(n)
				st.add_vertex(v)
	# La tranche : elle ferme le volume et attrape la lumière rasante, ce
	# qui donne l'arête franche du dessin animé.
	for i in contour.size():
		var j := (i + 1) % contour.size()
		var a0 := contour[i] + Vector3(0, 0, ep * 0.35)
		var b0 := contour[j] + Vector3(0, 0, ep * 0.35)
		var a1 := contour[i] - Vector3(0, 0, ep * 0.35)
		var b1 := contour[j] - Vector3(0, 0, ep * 0.35)
		var cote := (b0 - a0).cross(a1 - a0).normalized()
		for v in [a0, b0, b1, a0, b1, a1]:
			st.set_normal(cote)
			st.add_vertex(v)
	_maille = st.commit()
	return _maille


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = _t * TAU * TOURS
	var h := sin(_t * TAU / PERIODE) * FLOTTE
	_pivot.position.y = HAUTEUR + h
	_lueur.position.y = HAUTEUR + h
	# La lumière respire avec le flottement : c'est ce qui la fait vivre de
	# loin, quand l'étoile ne fait plus que quelques pixels.
	_lueur.light_energy = 2.2 + h * 2.0


func _sur_corps(corps: Node3D) -> void:
	if _prise:
		return
	var j := corps as Player
	if j == null or j.is_eliminated:
		return
	# ON NE DÉCIDE PAS ICI, ON SIGNALE. Le verrou local `_prise` n'est
	# qu'un garde-fou d'affichage contre deux déclenchements dans la même
	# image ; l'exclusion réelle est arbitrée par le serveur.
	touchee.emit(j.peer_id)


## Marque l'étoile comme prise : elle cesse de répondre et s'efface.
func consommer() -> void:
	if _prise:
		return
	_prise = true
	set_deferred(&"monitoring", false)
	# ─── ELLE QUITTE LE GROUPE AVANT DE QUITTER L'ÉCRAN ────────────────
	#
	# `queue_free` ne libère qu'en fin d'image, et l'escamotage dure encore
	# cent soixante millisecondes par-dessus. Pendant ce temps, une étoile
	# déjà prise restait trouvable par `get_nodes_in_group` : le banc en a
	# compté TROIS dans la scène là où il ne devait y en avoir qu'une. Ce
	# n'était pas qu'un artefact de test — n'importe quel code qui compte
	# les étoiles pour savoir s'il y en a une aurait eu la même réponse
	# fausse. On sort du groupe dès que la règle a tranché ; l'animation,
	# elle, peut finir tranquillement.
	remove_from_group(&"etoile_wanted")
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_pivot, "scale", Vector3.ONE * 0.05, 0.16) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	t.tween_property(_lueur, "light_energy", 0.0, 0.16)
	if _faisceau != null and is_instance_valid(_faisceau):
		t.tween_property(_faisceau, "scale", Vector3(0.05, 1.4, 0.05), 0.16)
	t.chain().tween_callback(queue_free)
