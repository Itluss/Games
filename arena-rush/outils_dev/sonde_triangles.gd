extends Node
## RÉPARTITION DES TRIANGLES — qui consomme le budget de la carte.
##
## La sonde de charge dit COMBIEN de triangles partent au rendu. Celle-ci
## dit D'OÙ ils viennent. Sans ce second chiffre, on optimise au jugé : on
## allège ce qu'on croit lourd, et le total ne bouge pas.
##
## Elle bâtit l'arène, parcourt tous les maillages, et somme les triangles
## par FAMILLE — le nom du nœud portant le rôle dans cette arène (Crete,
## Pile, Mur, Sol, Cactus…). Le classement qui en sort désigne la cible.

var _par_famille: Dictionary = {}
var _par_famille_n: Dictionary = {}
## Le détail par maillage SOURCE : une famille lourde ne dit pas encore si
## c'est un modèle cher posé cent fois ou cent modèles honnêtes.
var _par_source: Dictionary = {}
var _par_source_n: Dictionary = {}
var _total := 0


func _ready() -> void:
	Cfg.arene_test = true
	var arene := Arena.new()
	arene.name = "Arena"
	add_child(arene)
	await get_tree().process_frame
	await get_tree().process_frame
	_parcourir(arene)
	_rapport()
	get_tree().quit(0)


func _parcourir(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null and mi.visible:
		var tris := _triangles(mi.mesh)
		var f := _famille(mi)
		_par_famille[f] = int(_par_famille.get(f, 0)) + tris
		_par_famille_n[f] = int(_par_famille_n.get(f, 0)) + 1
		var src := _source(mi)
		_par_source[src] = int(_par_source.get(src, 0)) + tris
		_par_source_n[src] = int(_par_source_n.get(src, 0)) + 1
		_total += tris
	for c in n.get_children():
		_parcourir(c)


## Le préfixe alphabétique du nom : « Crete07_roche » donne « Crete ».
func _famille(n: Node) -> String:
	var nom := String(n.name)
	var out := ""
	for i in nom.length():
		var ch := nom[i]
		if ch >= "0" and ch <= "9":
			break
		if ch == "_" or ch == "@":
			break
		out += ch
	return out if out != "" else nom


## Le nom qui identifie le MODÈLE, pas l'exemplaire : le chemin de la
## ressource quand elle vient d'un fichier, sinon le nom de l'ancêtre le
## plus proche qui porte un rôle lisible.
func _source(mi: MeshInstance3D) -> String:
	var chemin := String(mi.mesh.resource_path)
	if chemin != "":
		return chemin.get_file()
	var p := mi.get_parent()
	var remonte := 0
	while p != null and remonte < 4:
		var nom := String(p.name)
		if nom != "mesh" and nom != "Scene" and not nom.begins_with("@"):
			return "<%s>" % nom
		p = p.get_parent()
		remonte += 1
	return "<inconnu>"


func _triangles(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var tableau := m.surface_get_arrays(s)
		if tableau.is_empty():
			continue
		var idx = tableau[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var som = tableau[Mesh.ARRAY_VERTEX]
			if som != null:
				t += som.size() / 3
	return t


func _rapport() -> void:
	print("\n=== RÉPARTITION DES TRIANGLES ===\n")
	var cles := _par_famille.keys()
	cles.sort_custom(func(a, b): return _par_famille[a] > _par_famille[b])
	print("  %-22s %10s %8s %7s" % ["famille", "triangles", "nœuds", "part"])
	for c in cles:
		var t: int = _par_famille[c]
		if t < 400:
			continue
		print("  %-22s %10d %8d %6.1f %%"
				% [c, t, _par_famille_n[c], 100.0 * float(t) / maxf(_total, 1)])
	print("")
	print("  %-34s %10s %8s %7s" % ["modèle source", "triangles", "posé", "part"])
	var srcs := _par_source.keys()
	srcs.sort_custom(func(a, b): return _par_source[a] > _par_source[b])
	for c in srcs:
		var t: int = _par_source[c]
		if t < 2000:
			continue
		print("  %-34s %10d %8d %6.1f %%"
				% [c, t, _par_source_n[c], 100.0 * float(t) / maxf(_total, 1)])
	print("")
	print("  TOTAL de l'arène bâtie : %d triangles" % _total)
	print("")
	print("=== 0 échec(s) ===")
