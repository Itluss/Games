class_name SondeChrono
## CHRONOMÈTRES DE BISSECTION — outil de mesure, ne fait rien en jeu.
##
## Des accumulateurs statiques que les systèmes alimentent quand la sonde
## CPU le demande (drapeau `actif`). Le coût à l'arrêt est UNE comparaison
## booléenne par tick et par système : assez bon marché pour vivre dans le
## code de jeu, ce qui évite de patcher temporairement dix fichiers à
## chaque campagne de mesure — et d'oublier d'en dépatcher un.

static var actif := false
static var postes: Dictionary = {}


static func ajouter(poste: StringName, usec: int) -> void:
	postes[poste] = int(postes.get(poste, 0)) + usec


static func rapport(ticks: int) -> String:
	var cles := postes.keys()
	cles.sort_custom(func(a, b): return postes[a] > postes[b])
	var out := ""
	for c in cles:
		out += "  %-18s %8.3f ms par tick\n" \
				% [c, float(postes[c]) / 1000.0 / maxf(ticks, 1)]
	return out
