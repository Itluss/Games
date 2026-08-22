extends Camera3D
class_name ArenaCamera
## CAMÉRA D'ARÈNE — vue de dessus légèrement inclinée.
##
## L'inclinaison (~42°) est un compromis assumé : à la verticale on perd
## la silhouette des personnages et le jeu devient plat ; trop bas, les
## obstacles masquent le combat. Cet angle garde les corps lisibles ET le
## sol lisible.
##
## L'AVANCE SUR LA VISÉE est ce qui fait qu'on voit ce qu'on attaque : la
## caméra se décale légèrement dans la direction visée plutôt que de rester
## centrée sur le joueur, ce qui donne de la marge devant lui.
##
## CE QUE CE FICHIER A APPRIS DU MONDE OUVERT. Cette caméra a été réglée
## pour une arène plate de 68 m dont le plus haut obstacle montait à 3 m.
## Le monde fait maintenant 156 m et porte des mesas de 14 m, des tours et
## des temples. Reculée de 10 m derrière le joueur, elle se retrouvait
## RÉGULIÈREMENT à l'intérieur d'un rocher : la face de la roche remplissait
## l'écran entier, et le jeu n'affichait plus qu'un aplat violet.
##
## Ce n'était pas une supposition. Une sonde a promené le placement nominal
## de la caméra sur 1 085 positions du monde : le joueur était masqué dans
## 15,3 % des cas, et dans 5,2 % des cas plus de 60 % du cadre était bouché
## par quelque chose à moins de sept mètres — plusieurs dizaines de points à
## 100 %. C'est exactement l'image signalée.
##
## Deux garde-fous en découlent, et ils sont indépendants :
##   • un DÉGAGEMENT : la caméra ne reste jamais derrière un obstacle, elle
##     se rapproche du joueur jusqu'à le revoir ;
##   • un RECALAGE sur téléportation : une réapparition déplace le joueur de
##     150 m, et le rattrapage amorti passait un tiers de seconde à filmer
##     le ciel.

## Hauteur au-dessus de la cible.
##
## RAPPROCHEMENT DE 20 %, ET IL EST CALCULÉ, PAS TÂTONNÉ. La taille d'un
## personnage à l'écran est inversement proportionnelle à la distance
## caméra→joueur, soit √(hauteur² + recul²) :
##
##     avant   13,0 / 10,0  →  16,4 m
##     après   10,4 /  8,0  →  13,1 m     soit +25 % de taille apparente
##
## Le RAPPORT hauteur/recul est conservé (1,30) : l'angle de plongée reste
## à 52°, donc le compromis silhouette/sol décrit plus haut tient toujours.
## On rapproche, on ne rebascule pas la caméra vers le sol — c'est la
## consigne « adapter la hauteur et l'angle plutôt que zoomer brutalement ».
##
## Le champ reste à 58° : le rétrécir aurait rapproché l'image sans
## rapprocher la caméra, en aplatissant la perspective (effet téléobjectif)
## et en donnant ce cadrage à l'étroit qu'il faut éviter.
## REMONTÉE DE 10,4 À 11,7 APRÈS LE VERROUILLAGE. L'avance sur la visée
## offrait de fait 3,4 m de vision vers l'avant ; supprimée, le cadre
## s'est resserré et la carte à rues demande d'anticiper — « la caméra
## est un peu proche » est arrivé dans l'heure. On rend 12 % de recul
## (13,1 → 14,8 m de distance réelle, −10 % de taille apparente), à
## rapport hauteur/recul constant : l'angle de plongée reste à 52°.
##
## PUIS LA PLONGÉE BAISSE DE 52° À 42°, ET C'EST UNE RÉPONSE AU JEU, PAS
## UN GOÛT. Le retour de test : « je ne reconnais pas les autres
## participants — des boules blanches sans aucune identification
## visuelle ». À 52°, la caméra regarde les mascottes par le crâne : le
## chapeau du corsaire devient un disque, le visage disparaît, et tout
## chibi vu du dessus est une boule. La planche des personnages tranche
## elle-même la question : sa vignette « VUE EN JEU (caméra éloignée) »
## cadre le pirate sous ~40° de plongée, chapeau ET visage lisibles.
## On pivote donc la caméra sur son arc À DISTANCE CONSTANTE :
##
##     52°   11,7 / 9,0   →  14,8 m
##     42°    9,9 / 11,0  →  14,8 m     même taille apparente
##
## La silhouette gagne ce que le sol perd, et le dégagement d'obstacles
## (DEGAGEMENT_MINI) couvre le surcroît de décor qui entre dans l'axe.
@export var height: float = 9.9
## Recul derrière la cible.
@export var distance: float = 11.0
## Vitesse de rattrapage. Assez élevée pour ne jamais « traîner », assez
## basse pour amortir les à-coups.
@export var smoothing: float = 7.5
## Décalage maximal dans la direction visée.
##
## ZÉRO — LA CAMÉRA EST VERROUILLÉE SUR LE PERSONNAGE, façon Brawl Stars.
##
## L'avance de 3,4 m paraissait généreuse : montrer ce qu'on attaque. En
## jeu, elle était la première cause du « la caméra bouge sans cesse »
## rapporté : la visée automatique rend `aim_input` actif dès qu'un ennemi
## est à portée — c'est-à-dire presque toujours — et CHANGE DE DIRECTION à
## chaque changement de cible verrouillée. Chaque bot qui passait devant
## un autre faisait glisser tout le cadre de plusieurs mètres, et la visée
## manuelle au pouce l'aurait fait tanguer à chaque geste. Le modèle du
## genre n'a aucune avance : le personnage est cloué au cadre, et c'est le
## MONDE qui défile. La machinerie reste en place — remonter cette valeur
## suffit à réessayer un jour, en connaissance de cause.
@export var look_ahead: float = 0.0

## Réglage nominal, mémorisé au démarrage. `adapt_to_zone` s'en écarte au
## lieu d'écrire des valeurs en dur.
var _hauteur_nominale := 9.9
var _recul_nominal := 11.0

## Hauteur de l'œil visé sur le joueur : la ligne de vue part de sa
## poitrine, pas de ses pieds, sinon le moindre muret la coupe.
const YEUX := 1.4
## Part minimale du recul nominal. En dessous, la caméra serait dans le dos
## du personnage et le jeu deviendrait illisible : mieux vaut alors accepter
## qu'un morceau de décor passe dans le cadre.
##
## REMONTÉE DE 0,3 À 0,8 EN DEUX FOIS, ET LA SECONDE EST UNE MESURE, PAS UN
## COMPROMIS. Le premier essai supposait qu'un dégagement plus doux
## protégerait moins. Un balayage de la valeur sur les 1 085 positions du
## monde dit le contraire :
##
##     minimum   joueur caché   cadre bouché
##       0,45         9,3 %          0,0 %
##       0,62         9,9 %          0,0 %
##       0,80        10,0 %          0,0 %
##
## Autrement dit, rabattre la caméra de 20 % suffit à tout ce que rabattre
## de 55 % apportait. L'amplitude du mouvement est donc divisée par près de
## trois pour sept dixièmes de point de visibilité — et c'est ce mouvement,
## pas le cadre bouché, que la joueuse a décrit comme insupportable.
const DEGAGEMENT_MINI := 0.8
## Rayon de la sonde de dégagement. Un simple rayon se faufilerait entre
## deux piliers et laisserait la caméra dans la pierre.
const RAYON_SONDE := 0.7
## Vitesses d'approche et de retour, en unités de lissage exponentiel.
##
## LA VERSION PRÉCÉDENTE RENTRAIT INSTANTANÉMENT, et c'était une erreur
## payée en jeu : la joueuse a décrit « des zoom et dézoom qui rendent le
## jeu injouable ». Un saut sec est justifiable quand il arrive une fois ;
## répété chaque fois qu'un pilier frôle le trajet, il donne le mal de mer.
## L'approche reste vive — un dixième de seconde — mais elle est amortie.
const ENTREE := 11.0
const RETOUR := 2.2
## Au-delà, la cible n'a pas marché : elle a été téléportée.
const SAUT := 25.0
## Période de la vérification « y a-t-il encore un monde sous moi ? ».
const CONTROLE := 0.25

var target: Node3D = null

var _desired: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO
## Point de visée lissé, distinct de la position du joueur.
var _focus: Vector3 = Vector3.ZERO
## Position lissée AVANT dégagement. On la garde à part : si le lissage
## repartait de la position rabattue, la caméra se rapprocherait un peu
## plus à chaque image et finirait collée au personnage.
var _ideal: Vector3 = Vector3.ZERO
## Fraction du recul réellement disponible, dans [DEGAGEMENT_MINI, 1].
var _degagement: float = 1.0

var _forme := SphereShape3D.new()
var _requete := PhysicsShapeQueryParameters3D.new()
var _controle := 0.0

func _ready() -> void:
	# La caméra s'enregistre elle-même : les effets n'ont pas à la chercher
	# dans l'arbre à chaque impact.
	Fx.camera = self
	current = true
	# On mémorise le réglage nominal AVANT que quoi que ce soit y touche :
	# c'est la référence de `adapt_to_zone`.
	_hauteur_nominale = height
	_recul_nominal = distance
	# RETROUVABLE. Si la fenêtre se retrouve un jour sans caméra active, la
	# veille du monde doit pouvoir en désigner une — encore faut-il qu'elle
	# sache où chercher.
	add_to_group(&"camera_arene")
	fov = 58.0
	# Champ lointain court. Ce n'est PAS « la taille de l'arène » — le monde
	# fait 156 m — mais la portée réelle du cadre : incliné à 42° avec 29°
	# de demi-ouverture, le rayon le plus haut file à 13° sous l'horizon et
	# touche le sol vers 49 m. Tout ce qui est au-delà n'entre dans l'image
	# que par sa hauteur.
	far = 140.0
	_forme.radius = RAYON_SONDE
	_requete.shape = _forme
	_requete.collision_mask = Cfg.LAYER_WORLD

func set_target(node: Node3D) -> void:
	target = node
	if node:
		_snap()

func _snap() -> void:
	_focus = target.global_position
	_desired = target.global_position
	_ahead = Vector3.ZERO
	_ideal = _desired + Vector3(0, height, distance)
	# LE DÉGAGEMENT VAUT AUSSI POUR UN RECALAGE. Sans cette ligne, on
	# réapparaissait pile derrière un rocher avec une image de roche, et le
	# lissage ne la corrigeait qu'à l'image suivante — un clignotement noir
	# à chaque retour en jeu.
	var oeil := _desired + Vector3(0, YEUX, 0)
	_degagement = _mesurer_degagement(oeil, _ideal - oeil)
	global_position = oeil + placer(_ideal - oeil, _degagement)
	look_at(_desired, Vector3.UP)

## La caméra suit au rythme de l'AFFICHAGE, pas de la physique.
##
## Première cause de saccade : en `_physics_process`, la caméra ne bougeait
## que 60 fois par seconde par paliers, pendant que l'écran affichait à une
## cadence différente — surtout en navigateur, où elle est variable. Chaque
## image intermédiaire réutilisait la même position, ce qui se voit
## immédiatement sur un décor qui défile.
func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var focus: Vector3 = target.global_position
	if not _fini(focus) or not _fini(_focus) or not _fini(_ideal):
		_urgence("suivi")
		return

	# UNE TÉLÉPORTATION N'EST PAS UN DÉPLACEMENT. Réapparaître envoie le
	# joueur à l'autre bout du monde ; amortir ce saut faisait voyager la
	# caméra à l'horizontale pendant un tiers de seconde, cadre plein de
	# ciel et de brume. On recale sec : personne ne regrette une coupe.
	#
	# LA DISTANCE EST CELLE DU TORE. Franchir la limite du monde déplace le
	# joueur de 144 m d'un coup : mesuré à plat, chaque passage de couture
	# serait pris pour une réapparition et provoquerait une coupe. Mesuré
	# sur le tore, ce déplacement vaut quelques centimètres — ce qu'il est.
	if PlanMonde.distance3(_focus, focus) > SAUT:
		_snap()
		return

	var aim: Vector3 = target.get(&"aim_input") if target.get(&"aim_input") != null \
			else Vector3.ZERO
	if aim.length() > 0.1:
		_ahead = _ahead.lerp(aim.normalized() * look_ahead, 1.0 - exp(-4.0 * delta))
	else:
		_ahead = _ahead.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))

	# On lisse AUSSI la cible du regard. Amortir la position de la caméra
	# sans amortir son point de visée laisse l'orientation copier la
	# position brute du joueur, qui avance par pas de physique pendant que
	# l'écran affiche à une autre cadence : l'image tremble.
	# On suit le PLUS COURT CHEMIN, celui qui traverse la limite du monde
	# quand c'est plus court. Un `lerp` ordinaire renverrait la caméra faire
	# tout le tour de la carte à chaque franchissement.
	_focus += PlanMonde.ecart3(_focus, focus) * (1.0 - exp(-smoothing * delta))
	_replier()
	_desired = _focus + _ahead
	var goal := _desired + Vector3(0, height, distance)
	# Lissage exponentiel : indépendant du framerate, contrairement à un
	# lerp à facteur constant qui accélère quand les FPS montent.
	_ideal = _ideal.lerp(goal, 1.0 - exp(-smoothing * delta))

	var oeil := _desired + Vector3(0, YEUX, 0)
	var vise := _mesurer_degagement(oeil, _ideal - oeil)
	var vitesse := ENTREE if vise < _degagement else RETOUR
	_degagement = lerpf(_degagement, vise, 1.0 - exp(-vitesse * delta))
	global_position = oeil + placer(_ideal - oeil, _degagement)
	_regarder(_desired)
	# ON PART DU JOUEUR, PAS DU POINT REGARDÉ.
	#
	# `oeil` se trouve à `_desired`, c'est-à-dire jusqu'à 3,4 m en avant du
	# personnage — l'avance sur la visée. Or ce qu'il ne faut pas laisser
	# cacher, c'est LE PERSONNAGE. Un rayon lancé trois mètres devant lui
	# manquait les petites structures, comme le linteau du temple : mesuré,
	# une position sur trois échouait, et toujours la même.
	_gerer_les_toits(focus + Vector3(0.0, YEUX, 0.0))

	_controle -= delta
	if _controle <= 0.0:
		_controle = CONTROLE
		_verifier_le_sol()

## FILET DE SÉCURITÉ — une caméra qui ne voit plus le monde se recale.
##
## POURQUOI SANS CONNAÎTRE LA CAUSE. Une capture prise sur téléphone
## montrait l'interface intacte sur un dégradé violet : corail en haut,
## bleu nuit en bas. Ce dégradé est l'hémisphère BAS du ciel procédural,
## donc une caméra correctement orientée vers le sol, avec plus aucun sol
## devant elle. Trois sondes n'ont pas su reproduire l'état, et chercher
## indéfiniment la cause d'un défaut qu'on ne reproduit pas revient à ne
## rien livrer.
##
## On rend donc l'état IRRÉCUPÉRABLE impossible, quelle qu'en soit
## l'origine : un rayon vers le bas toutes les quatre images, et si le
## monde a disparu, la caméra retourne sur son joueur — lequel a de son
## côté sa propre garantie de rester dans le monde.
func _verifier_le_sol() -> void:
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	var q := PhysicsRayQueryParameters3D.create(global_position,
			global_position - Vector3(0.0, 80.0, 0.0))
	q.collision_mask = Cfg.LAYER_WORLD
	if espace.intersect_ray(q).is_empty():
		_signaler("CAM PERDUE %s" % _bref(global_position))
		_snap()


## DIAGNOSTIC VISIBLE — temporaire, et assumé comme tel.
##
## L'écran violet a résisté à six sondes : aucune ne l'a reproduit, ni au
## bord du monde, ni en profil téléphone, ni sur 1 085 positions. Continuer
## à chercher à l'aveugle sur une machine qui n'a pas le défaut est du
## temps perdu ; le seul appareil qui SAIT le produire est le téléphone de
## la joueuse.
##
## Le jeu se signale donc lui-même. Si l'un des deux filets de sécurité se
## déclenche, une bannière l'annonce avec les coordonnées : la prochaine
## capture d'écran répondra à la question, et une absence de bannière y
## répondra tout autant — elle disculpera la caméra.
func _signaler(texte: String) -> void:
	push_warning(texte)
	if MatchDirector and MatchDirector.has_signal(&"announce"):
		MatchDirector.announce.emit(texte, Cfg.COL_DANGER)


func _bref(v: Vector3) -> String:
	return "(%d, %d, %d)" % [roundi(v.x), roundi(v.y), roundi(v.z)]

## ORIENTE LA CAMÉRA, EN REFUSANT LES CAS QUI LA DÉTRUISENT.
##
## POURQUOI UN GARDE AUTOUR D'UN SIMPLE `look_at`. Un écran entièrement vide
## — ciel visible, décor absent, interface intacte — n'a qu'une explication
## côté rendu : un TRONC DE VISION DÉGÉNÉRÉ. Plus rien ne passe le test de
## visibilité, tandis que le ciel, dessiné en passe pleine page, continue de
## s'afficher. C'est exactement l'image signalée quatre fois.
##
## Or `look_at` produit précisément cela dans deux cas : une direction NULLE
## — la caméra se trouve sur son point de visée — et une direction ALIGNÉE
## sur la verticale, qui ne laisse aucune façon de choisir « le haut ». Godot
## signale l'erreur et laisse la base de rotation dans un état invalide.
##
## Le troisième cas est pire parce qu'il est silencieux : une coordonnée
## infinie ou non numérique. Une seule division mal bornée quelque part dans
## la simulation, et toute la chaîne — position du joueur, visée lissée,
## position de la caméra — devient non numérique en une image. La caméra ne
## regarde alors nulle part, définitivement.
##
## On ne cherche plus d'où viendrait ce nombre : on refuse de s'en servir,
## et l'on se recale.
func _regarder(vers: Vector3) -> void:
	if not _fini(global_position) or not _fini(vers):
		_urgence("coordonnees")
		return
	var d := vers - global_position
	if d.length_squared() < 0.0004:
		return
	# Direction quasi verticale : `look_at` n'a plus de repère latéral.
	if absf(d.normalized().y) > 0.999:
		return
	look_at(vers, Vector3.UP)


static func _fini(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Remet la caméra dans un état sain quand son état courant ne l'est plus.
func _urgence(cause: String) -> void:
	push_warning("Caméra : état invalide (%s) — recalage d'urgence." % cause)
	if target == null or not is_instance_valid(target) \
			or not _fini(target.global_position):
		return
	_focus = target.global_position
	_desired = _focus
	_ahead = Vector3.ZERO
	_degagement = 1.0
	_ideal = _desired + Vector3(0, height, distance)
	global_position = _ideal
	look_at(_desired, Vector3.UP)
	if MatchDirector and MatchDirector.has_signal(&"announce"):
		MatchDirector.announce.emit("VEILLE : CAMERA RECALEE", Cfg.COL_DANGER)


## REPLIE TOUT L'ÉTAT DE LA CAMÉRA D'UN MONDE ENTIER, D'UN SEUL BLOC.
##
## En suivant le plus court chemin, le point de visée franchit la limite du
## monde sans s'en apercevoir et s'éloigne indéfiniment du carré de
## référence : au bout d'une longue partie, les coordonnées finiraient par
## perdre leur précision.
##
## On le ramène donc périodiquement — mais en translatant EN MÊME TEMPS la
## position lissée et la position réelle, exactement du même vecteur. Un
## déplacement rigide d'une période entière ne change rien à ce qui est
## visible, puisque le monde se répète : la coupe est mathématiquement
## invisible. Replier la seule cible, en revanche, ferait traverser la carte
## à la caméra.
func _replier() -> void:
	var saut := PlanMonde.enrouler3(_focus) - _focus
	if saut.length_squared() < 0.0001:
		return
	_focus += saut
	_desired += saut
	_ideal += saut
	global_position += saut


## Où se met la caméra quand elle ne peut reculer que d'une fraction ?
##
## PAS SUR LE SEGMENT. Rabattre proportionnellement les trois axes plaque la
## caméra au niveau du sol, juste derrière le personnage — c'est-à-dire à la
## hauteur exacte où se trouvent les rochers, les tentes et les piliers. Une
## caméra de dessus se dégage en MONTANT, pas en s'aplatissant.
##
## La racine carrée fait ce compromis sans discontinuité : à 30 % de recul
## il reste 55 % de hauteur, donc une vue plus plongeante et plus dégagée.
## Mesuré sur 1 085 positions : le cadre bouché tombe de 0,9 % à 0 %.
static func placer(course: Vector3, part: float) -> Vector3:
	return Vector3(course.x * part, course.y * sqrt(part), course.z * part)

## Jusqu'où faut-il se rapprocher pour revoir le joueur ?
##
## LA QUESTION A CHANGÉ, ET C'EST TOUTE LA CORRECTION. La version
## précédente demandait « quelque chose touche-t-il le trajet de la
## caméra ? » et se rapprochait dès que oui. Or un pilier peut frôler ce
## trajet sans cacher qui que ce soit : la caméra plongeait alors sans
## raison, ressortait, replongeait. C'est l'origine du zoom continuel
## signalé en jeu.
##
## On demande maintenant « le joueur est-il masqué ? ». Tant qu'on le voit,
## la caméra ne bouge pas d'un millimètre, quoi qu'il y ait autour. C'est un
## rayon de plus par image, et c'est ce rayon qui rend le cadre stable.
func _mesurer_degagement(oeil: Vector3, course: Vector3) -> float:
	var espace := get_world_3d().direct_space_state
	if espace == null or course.length_squared() < 0.01:
		return 1.0
	var vue := PhysicsRayQueryParameters3D.create(oeil + course, oeil)
	vue.collision_mask = Cfg.LAYER_WORLD
	if espace.intersect_ray(vue).is_empty():
		return 1.0

	# Le joueur est bel et bien caché : on cherche jusqu'où reculer sans
	# entrer dans le décor. Le sol n'entre jamais en compte — le trajet part
	# de la poitrine du joueur et monte, il ne le rencontre pas.
	_requete.transform = Transform3D(Basis(), oeil)
	_requete.motion = course
	var bornes := espace.cast_motion(_requete)
	if bornes.size() < 1:
		return 1.0
	# `cast_motion` rend [sûr, premier contact]. On prend la fraction sûre,
	# et on retranche de quoi ne pas raser la surface : une caméra collée à
	# une paroi la voit en gros plan, ce qui revient au même défaut.
	var sur: float = bornes[0]
	return clampf(sur - 0.04, DEGAGEMENT_MINI, 1.0)

## Zoom arrière progressif quand la zone se referme : la fin de partie se
## joue dans un espace réduit, la caméra doit le montrer entièrement.
func adapt_to_zone(zone_radius: float) -> void:
	var t := clampf(zone_radius / Cfg.ARENA_RADIUS, 0.35, 1.0)
	# ON RECULE PAR RAPPORT AU RÉGLAGE, ON NE LE REMPLACE PAS.
	#
	# Ces deux lignes écrivaient 13,0 et 10,0 en dur : les valeurs d'AVANT
	# le rapprochement. Autrement dit, la première fermeture de zone
	# annulait silencieusement le rapprochement de caméra et le joueur
	# rapetissait sans que rien ne l'explique. Un réglage exporté qu'une
	# autre fonction réécrit en dur n'est plus un réglage.
	#
	# La zone qui se referme doit MONTRER PLUS, donc reculer : on garde le
	# réglage nominal quand la zone est entière et on s'en écarte de 25 %
	# au plus quand elle est au plus petit.
	height = _hauteur_nominale * lerpf(1.25, 1.0, t)
	distance = _recul_nominal * lerpf(1.25, 1.0, t)

## EFFACE LE REPÈRE SOUS LEQUEL ON PASSE.
##
## Le dégagement gère ce qui est DERRIÈRE le joueur ; ceci gère ce qui est
## AU-DESSUS. Les deux sont nécessaires et aucun ne remplace l'autre : on ne
## recule pas pour sortir de sous un pont, on ne monte pas non plus — un
## tablier de pierre est un plafond, et un plafond, on le traverse du regard
## ou on ne voit rien.
##
## Un seul rayon par image, sur une couche que rien d'autre n'occupe.
func _gerer_les_toits(oeil: Vector3) -> void:
	if _arene == null or not is_instance_valid(_arene):
		_arene = get_tree().get_first_node_in_group(&"arene")
		if _arene == null:
			return
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	var q := PhysicsRayQueryParameters3D.create(oeil, global_position)
	q.collision_mask = Cfg.LAYER_TOIT
	# ON COMPTE AUSSI LES DÉPARTS DE L'INTÉRIEUR. Sans cela, un rayon qui
	# NAÎT dans le volume — c'est-à-dire le cas où l'on est déjà sous le
	# toit, donc le seul qui nous intéresse — ne rend aucune touche.
	q.hit_from_inside = true
	var touche := espace.intersect_ray(q)
	if touche.is_empty():
		_arene.call(&"devoiler_toits")
	else:
		_arene.call(&"voiler_toit", touche["collider"])


## L'arène, retrouvée une seule fois puis conservée.
var _arene: Node = null
