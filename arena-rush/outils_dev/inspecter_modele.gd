extends Node3D
## Où POINTE l'arme par rapport à l'avant du personnage — outil de dev.
##
## L'arme est bien à la main (2,4 mm d'écart, mesuré). Reste à savoir si
## elle pointe où le personnage tire : le canon suit l'orientation de l'OS
## de la main, dont les axes n'ont aucune raison d'être alignés sur le
## corps.

var _visuel: CharacterVisual

func _ready() -> void:
	_visuel = CharacterVisual.new()
	add_child(_visuel)
	_visuel.build(Color.WHITE, Color.WHITE, 1.7)
	_visuel.attach_weapon(VisualKit.build_weapon("rifle", Color.ORANGE))
	_visuel.forcer_clip("garde")
	for i in 40:
		_visuel.update_visual(1.0 / 60.0, 0.0)
		await get_tree().process_frame

	var mount := _visuel.get_weapon_mount()
	# Le canon des armes pointe vers -Z dans leur propre repère.
	var canon := -mount.global_transform.basis.z.normalized()
	# L'avant du personnage : le nœud n'est pas tourné ici, donc -Z monde.
	var avant := Vector3(0, 0, -1)
	print("CANON  direction monde = ", canon)
	print("AVANT  du personnage   = ", avant)
	print("ÉCART angulaire        = %.1f°" % rad_to_deg(canon.angle_to(avant)))
	print("inclinaison verticale du canon = %.1f°"
			% rad_to_deg(asin(clampf(canon.y, -1.0, 1.0))))
	get_tree().quit()
