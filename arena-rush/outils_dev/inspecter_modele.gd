extends Node3D
## Le mélange par étage fait-il ce qu'on croit ? — outil de dev.
##
## On compare, os par os, la pose obtenue en « tir debout » avec celles
## des deux clips purs. Le HAUT doit coller au clip de tir, le BAS au
## repos. Un filtre mal posé donnerait l'inverse, ou un mélange des deux
## partout — et rien à l'écran ne le dirait clairement.

var _v: CharacterVisual

func _ready() -> void:
	_v = CharacterVisual.new()
	add_child(_v)
	_v.build(Color.WHITE, Color.WHITE, 1.7)
	await get_tree().process_frame

	var repos := await _poses(false, false)
	var course_tir := await _poses(true, true)
	var debout := await _poses(false, true)

	print("posture relevée = ", _v.posture())
	print("%-14s %10s %10s   verdict" % ["os", "vs repos", "vs tir"])
	var haut_ok := 0
	var haut_tot := 0
	var bas_ok := 0
	var bas_tot := 0
	for os_nom in repos.keys():
		var d_repos: float = _ecart(debout[os_nom], repos[os_nom])
		var d_tir: float = _ecart(debout[os_nom], course_tir[os_nom])
		var est_haut: bool = os_nom in CharacterVisual.HAUT_DU_CORPS
		var suit := "TIR" if d_tir < d_repos else "REPOS"
		if est_haut:
			haut_tot += 1
			if suit == "TIR":
				haut_ok += 1
		else:
			bas_tot += 1
			if suit == "REPOS":
				bas_ok += 1
		print("%-14s %10.2f %10.2f   suit %s%s"
				% [os_nom, d_repos, d_tir, suit, "  (haut)" if est_haut else ""])
	print("HAUT du corps qui suit le TIR   : %d/%d" % [haut_ok, haut_tot])
	print("BAS  du corps qui suit le REPOS : %d/%d" % [bas_ok, bas_tot])
	get_tree().quit()

func _ecart(a: Dictionary, b: Dictionary) -> float:
	return rad_to_deg((a["q"] as Quaternion).angle_to(b["q"] as Quaternion))

## Laisse le mélange s'installer, puis relève toutes les rotations d'os.
func _poses(court: bool, tire: bool) -> Dictionary:
	_v.set_aiming(tire)
	for i in 90:
		_v.update_visual(1.0 / 60.0, 1.0 if court else 0.0)
		await get_tree().process_frame
	var sq := _cherche(_v, "Skeleton3D") as Skeleton3D
	var out := {}
	for i in sq.get_bone_count():
		out[sq.get_bone_name(i)] = {"q": sq.get_bone_pose_rotation(i)}
	return out

func _cherche(n: Node, c: String) -> Node:
	if n.is_class(c):
		return n
	for e in n.get_children():
		var r := _cherche(e, c)
		if r:
			return r
	return null
