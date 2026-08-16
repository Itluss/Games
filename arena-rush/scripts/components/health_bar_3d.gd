extends Node3D
class_name HealthBar3D
## BARRE DE VIE FLOTTANTE — toujours face caméra.
##
## Volontairement construite en quads plutôt qu'en Viewport d'interface :
## un Viewport par entité coûterait une passe de rendu par mob, ce qui est
## exactement le genre de détail qui fait chuter les FPS sur tablette.

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _width: float = 1.0
var _ratio: float = 1.0

func build(width: float = 1.0, color: Color = Color("4cd964")) -> void:
	_width = width
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.75)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Billboard : la barre reste lisible quel que soit l'angle de caméra.
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.billboard_keep_scale = true
	# Toujours visible, même derrière un rocher : perdre de vue la santé
	# d'un ennemi derrière un obstacle rendrait le combat illisible.
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1

	_fill_mat = bg_mat.duplicate()
	_fill_mat.albedo_color = color
	_fill_mat.render_priority = 2

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(width, width * 0.13)
	_bg = MeshInstance3D.new()
	_bg.mesh = bg_mesh
	_bg.material_override = bg_mat
	_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bg)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(width * 0.94, width * 0.09)
	_fill = MeshInstance3D.new()
	_fill.mesh = fill_mesh
	_fill.material_override = _fill_mat
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)

func set_ratio(value: float) -> void:
	_ratio = clampf(value, 0.0, 1.0)
	if _fill == null:
		return
	# On rétrécit depuis la gauche (et non depuis le centre) : c'est la
	# lecture attendue d'une jauge.
	_fill.scale.x = maxf(_ratio, 0.001)
	_fill.position.x = -(_width * 0.94) * (1.0 - _ratio) * 0.5
	# La couleur bascule vers le rouge en fin de vie : une information de
	# plus, gratuite, lisible du coin de l'œil.
	_fill_mat.albedo_color = Cfg.COL_HEAL.lerp(Cfg.COL_DANGER,
			clampf(1.0 - _ratio, 0.0, 1.0) ** 1.6)

func set_bar_color(color: Color) -> void:
	if _fill_mat:
		_fill_mat.albedo_color = color
