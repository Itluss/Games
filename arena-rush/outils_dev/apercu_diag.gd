extends Node
## APERÇU DU PANNEAU DE DIAGNOSTIC — temporaire, comme le panneau lui-même.
##
## Un panneau de diagnostic illisible ou tronqué ne diagnostique rien. On
## l'ouvre, on déclenche ses trois tests, et on photographie : c'est la
## seule façon de savoir qu'il sera exploitable depuis un téléphone.

const LARGEUR := 1280
const HAUTEUR := 720

var _main: Node
var _dossier := ""

func _ready() -> void:
	get_window().size = Vector2i(LARGEUR, HAUTEUR)
	_dossier = ProjectSettings.globalize_path("user://apercu")
	DirAccess.make_dir_recursive_absolute(_dossier)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	var d := _panneau()
	if d == null:
		push_error("Panneau de diagnostic introuvable.")
		get_tree().quit(1)
		return
	d.get(&"_panneau").visible = true
	d.set(&"_t", 0.0)
	await _capturer("diag_repos")
	d.call(&"_basculer_camera")
	await _capturer("diag_cam_neuve")
	d.call(&"_basculer_camera")
	d.call(&"_basculer_decor")
	await _capturer("diag_decor_off")
	d.call(&"_basculer_decor")
	d.call(&"_basculer_env")
	await _capturer("diag_env_mini")
	get_tree().quit()


func _panneau() -> Node:
	var hud := get_tree().get_first_node_in_group(&"hud")
	return hud.get_node_or_null("Diagnostic") if hud else null


func _capturer(nom: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dossier, nom])
	print("→ ", nom)
