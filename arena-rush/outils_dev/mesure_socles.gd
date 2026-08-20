extends SceneTree
## Contrôle de la mesure de socle, pièce par pièce.
func _init() -> void:
	print("%-26s %7s %7s   %s" % ["pièce", "tot.", "socle", "objet utile (m)"])
	for n in ["west_rock_formation_a","west_rock_formation_b","west_rock_small",
			"west_stonewall_straight","west_fence_straight","west_sign_wood",
			"west_haybale","west_crate","west_barrel","west_wagon","west_cactus_a"]:
		if not KitWestern.disponible(n):
			print("%-26s ABSENT" % n); continue
		var sc := load("res://assets/models/%s.glb" % n) as PackedScene
		var m := sc.instantiate() as Node3D
		var r := KitWestern._mesurer(StringName(n), m)
		var b: AABB = r["boite"]
		var u: AABB = r["utile"]
		print("%-26s %7.2f %7.2f   %5.2f × %5.2f × %5.2f"
				% [n, b.size.y, float(r["socle"]), u.size.x, u.size.y, u.size.z])
		m.free()
	quit()
