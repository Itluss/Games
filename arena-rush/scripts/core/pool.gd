extends Node
## RÉSERVOIR D'OBJETS — recyclage des projectiles.
##
## POURQUOI : un fusil à pompe crache 8 projectiles par tir, quatre
## joueurs tirent en continu, les mobs aussi. Instancier et libérer des
## centaines de nœuds par seconde provoque des à-coups du ramasse-miettes
## très visibles sur mobile — exactement là où on vise 60 FPS stables.
##
## Le contrat attendu d'un objet recyclé : une méthode `_on_despawn()`
## optionnelle, et le fait de ne JAMAIS se `queue_free()` lui-même.
##
## Autoload : Pool

const MAX_PER_SCENE := 128

var _free: Dictionary = {}      # chemin de scène -> Array[Node]
var _scenes: Dictionary = {}    # chemin de scène -> PackedScene

func _preload(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## Sort un objet du réservoir (ou en crée un si vide) et l'attache à `parent`.
func acquire(path: String, parent: Node) -> Node:
	var bucket: Array = _free.get(path, [])
	var node: Node = null
	while not bucket.is_empty() and node == null:
		var candidate = bucket.pop_back()
		if is_instance_valid(candidate):
			node = candidate
	if node == null:
		var scene := _preload(path)
		if scene == null:
			push_error("Pool : scène introuvable — " + path)
			return null
		node = scene.instantiate()
		node.set_meta(&"pool_path", path)
	# Les objets au repos sont garés SOUS le réservoir (voir `release`) :
	# il faut donc les en détacher avant de les rendre au monde.
	if node.get_parent() == self:
		remove_child(node)
	parent.add_child(node)
	return node

## Rend un objet au réservoir. À appeler à la place de `queue_free()`.
func release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var path: String = node.get_meta(&"pool_path", "")
	if path.is_empty():
		node.queue_free()
		return
	if node.has_method("_on_despawn"):
		node.call("_on_despawn")
	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	var bucket: Array = _free.get(path, [])
	# Au-delà du plafond, on libère vraiment : un réservoir qui ne rend
	# jamais la mémoire est une fuite qui porte un autre nom.
	if bucket.size() >= MAX_PER_SCENE:
		node.queue_free()
		return
	# On RATTACHE l'objet au repos sous le réservoir au lieu de le laisser
	# orphelin. Un nœud détaché de l'arbre n'appartient à personne : plus
	# rien ne le libère, et Godot le signale comme fuite à la fermeture.
	add_child(node)
	bucket.append(node)
	_free[path] = bucket

## Vide le réservoir — appelé entre deux parties et à la fermeture.
func clear() -> void:
	for path in _free:
		for node in _free[path]:
			if is_instance_valid(node):
				node.queue_free()
	_free.clear()

func _exit_tree() -> void:
	clear()
