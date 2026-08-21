extends Resource
class_name ProfilTir
## IDENTITÉ DE TIR D'UNE ARME — le rythme, la forme, le bruit, la réaction.
##
## ─── POURQUOI CETTE RESSOURCE EXISTE À CÔTÉ DE `WeaponData` ─────────────
##
## `WeaponData` dit ce que l'arme FAIT : dégâts, cadence, portée, nombre de
## projectiles. Cette ressource-ci dit ce qu'elle DONNE À VOIR ET À
## ENTENDRE. Les deux ne changent pas pour les mêmes raisons ni au même
## moment : on équilibre des dégâts sans toucher à une gerbe d'étincelles,
## et on refait un flash sans jamais rouvrir une table de dégâts. Les
## mélanger, c'est se condamner à relire l'un pour modifier l'autre.
##
## ─── LA RÈGLE QUI COMMANDE TOUS LES CHAMPS ─────────────────────────────
##
## Un joueur doit reconnaître QUI lui tire dessus en moins d'une seconde,
## SANS voir le personnage, et SANS compter sur la couleur. C'est pourquoi
## chaque arme se distingue sur PLUSIEURS axes à la fois : le rythme, le
## nombre de traits, la largeur du départ, la forme de l'impact, la
## réaction du corps. Passée en niveaux de gris, la planche doit rester
## lisible — et c'est exactement ce que le banc d'identification vérifie.

## Le héros à qui appartient cette arme. Sert au banc et au mode d'essai.
@export var heros: StringName = &""

## COULEUR DOMINANTE DU HÉROS, telle que la planche la nomme.
##
## Elle vit ICI et pas dans `WeaponData` parce qu'elle suit le PERSONNAGE,
## pas l'arme : c'est la première chose qu'on lit quand on se demande qui
## nous tire dessus.
@export var couleur: Color = Color.WHITE

@export_group("Rythme")
## SIMPLE   un coup par déclenchement.
## RAFALE   plusieurs coups très rapprochés, comptés par `rafale_coups`.
## ALTERNE  comme RAFALE, mais chaque coup change de canon (Gus).
@export_enum("simple", "rafale", "alterne") var mode: String = "simple"
## Coups d'une rafale. Ignoré en mode simple.
@export var rafale_coups: int = 1
## Délai entre deux coups d'une même rafale, en secondes.
##
## IL EST TRAITÉ SUR L'HORLOGE PHYSIQUE, comme la cadence : sur l'horloge
## d'affichage, une rafale s'étirerait ou se tasserait selon la fluidité,
## et deux joueurs sur deux téléphones n'entendraient pas le même rythme.
@export var rafale_intervalle: float = 0.07

@export_group("Départ")
## ETOILE  branches nettes, peu de fumée — Milo, Ruby, Gus.
## LARGE   éventail irrégulier et étincelant — Poppy.
## MASSIF  large, cœur clair, fumée courte — Bruno.
## FIN     minuscule et pointu — Nox.
@export_enum("etoile", "large", "massif", "fin") var flash: String = "etoile"
## Multiplicateur de taille du départ. La référence est 1,0 = Milo.
@export var flash_taille: float = 1.0
## Nombre de branches de l'étoile de départ. C'est un marqueur de forme,
## donc lisible en niveaux de gris.
@export var flash_branches: int = 4

@export_group("Projectile")
## FINE      un trait court et net — Milo, Nox.
## MULTIPLE  plusieurs traits courts — Poppy.
## EPAISSE   grosse queue, sensation de masse — Bruno.
## RUBAN     queue ondulée et scintillante — Ruby.
@export_enum("fine", "multiple", "epaisse", "ruban") var trainee: String = "fine"
## Longueur de la queue, en multiples du rayon du projectile.
@export var trainee_longueur: float = 5.0
## Seconde teinte, utilisée par les traînées à deux tons (Ruby).
@export var couleur_secondaire: Color = Color.WHITE

## ─── LA TÊTE ET LE RUBAN, EN MÈTRES ────────────────────────────────────
##
## POURQUOI EN MÈTRES ET PLUS EN MULTIPLES DU CALIBRE. Le calibre sert à la
## COLLISION : y accrocher la taille du dessin liait la lisibilité à la
## difficulté, et la moindre retouche de l'un déplaçait l'autre. Surtout,
## un multiplicateur unique donnait à Milo une queue de trois mètres — le
## « trait laser persistant » que la planche interdit explicitement.
##
## Une tête de vingt centimètres et un ruban d'un mètre : à la caméra de
## jeu, cela fait un point net suivi d'un trait bref. C'est le dessin de la
## planche, et c'est un choix de LISIBILITÉ, pas de puissance.
@export var tete_rayon: float = 0.0
@export var tete_longueur: float = 0.0
## Longueur du ruban derrière la tête, en mètres. Zéro = ancien cône.
@export var trainee_metres: float = 0.0
## Amplitude latérale de l'ondulation, en mètres. Zéro = ruban droit.
##
## LE PROJECTILE, LUI, RESTE PARFAITEMENT DROIT. L'ondulation est dessinée
## dans le ruban et nulle part ailleurs : la collision ne la voit pas, le
## serveur ne la connaît pas, et la trajectoire ne s'en trouve pas
## compliquée d'une ligne.
@export var trainee_ondulation: float = 0.0
## Longueur d'onde de cette ondulation, en mètres.
@export var trainee_periode: float = 1.2
## Couleur de la QUEUE du ruban. La tête garde `couleur` : c'est ce dégradé
## qui donne à Ruby son rose-vers-cyan sans un seul shader.
@export var couleur_bout: Color = Color(1, 1, 1, 0)

## ─── CANON EN COURS D'EMPLOI — ÉTAT, PAS RÉGLAGE ────────────────────
##
## 0 = droite, 1 = gauche. Il n'est PAS exporté : ce n'est pas un choix
## d'artiste enregistré dans la ressource, c'est une information vivante
## que `Weapon` pose juste avant de demander le départ, et que `Fx` lit
## pour dessiner la gerbe du bon côté.
##
## POURQUOI PASSER PAR LE PROFIL PLUTÔT QUE PAR UN ARGUMENT. `Fx.depart`
## est appelé depuis trois endroits et sa signature sert aussi aux armes de
## butin, qui n'ont pas de canons. Lui ajouter un paramètre qui ne concerne
## qu'un héros sur six l'aurait alourdi partout pour servir ici.
##
## LA RESSOURCE EST PARTAGÉE ENTRE TOUTES LES ARMES D'UN MÊME HÉROS, et
## c'est sans conséquence : la valeur est posée puis lue dans la même
## fonction, sans une image entre les deux.
var canon_courant: int = 0

@export_group("Impact")
## ETOILE     petite étoile nette — Milo, Gus.
## ECLATS     plusieurs éclats dispersés — Poppy.
## EXPLOSION  souffle court, poussière, onde — Bruno.
## POINT      éclat minuscule et précis — Nox.
## SCINTILLE  étoile plus des particules brillantes — Ruby.
@export_enum("etoile", "eclats", "explosion", "point", "scintille")
var impact: String = "etoile"
@export var impact_taille: float = 1.0

@export_group("Réaction")
## SEC      l'arme recule, le corps encaisse à peine — Milo.
## LOURD    épaules et buste partent en arrière — Poppy.
## MASSIF   tout le corps recule, retour lent — Bruno.
## MINIMAL  presque rien ne bouge — Nox.
## VIF      petit contrecoup rapide et rebondi — Ruby.
## ALTERNE  l'épaule qui tire réagit, l'autre non — Gus.
@export_enum("sec", "lourd", "massif", "minimal", "vif", "alterne")
var recul_corps: String = "sec"
## Amplitude du recul du corps, en mètres.
@export var recul_amplitude: float = 0.05
## Durée du retour en position, en secondes.
@export var recul_duree: float = 0.16
## Secousse caméra, POUR LE TIREUR LOCAL SEULEMENT.
##
## Elle reste minuscule et n'est justifiée que pour une arme lourde : une
## arme rapide qui secoue à chaque coup produit une vibration continue,
## jamais une sensation de puissance.
@export var secousse_locale: float = 0.0

@export_group("Son")
## Fréquence de base du son de tir, en hertz. C'est le grave/aigu.
@export var son_hauteur: float = 320.0
## Durée du son, en secondes.
@export var son_duree: float = 0.10
## Part de bruit blanc dans le son, de 0 (sifflement pur) à 1 (souffle).
## C'est ce qui sépare un revolver sec d'un canon lourd.
@export var son_grain: float = 0.5
## Vitesse d'extinction. Grande = claquement, petite = résonance.
@export var son_chute: float = 30.0
