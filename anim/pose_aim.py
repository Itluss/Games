# -*- coding: utf-8 -*-
"""Pose de visee pistolet a deux mains - reconstruction complete et deterministe."""
import bpy, math, json
from mathutils import Vector, Matrix, Quaternion

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world
MWi = MW.inverted()
U = bpy.context.view_layer.update

# ---------------------------------------------------------------- parametres
P = dict(
    grip_center = Vector((0.0, -0.505, 1.428)),
    grip_rot = None,                       # Quaternion : oriente arme+mains en bloc   # ou se trouve la crosse dans le monde
    # main droite : decalages poignet->crosse exprimes dans le repere de la main (m)
    r_wrist_tfs = (-2.1, -8.91, -4.4),
    r_palm_hint = (0.97, 0.24, 0.0),
    r_pole = (-0.32, 0.18, -0.93),
    # main gauche
    # Poignet gauche. A 6.0 la main de soutien etait 6 cm trop a l'exterieur :
    # ses doigts s'allongeaient vers la crosse sans que la paume vienne au
    # contact, et pas un seul sommet de la main gauche ne touchait l'arme
    # (distance mediane 81 mm). Elle serrait le vide a cote du pistolet.
    # A 2.5 la paume recouvre la main droite : 59 sommets au contact de l'arme,
    # poignets a 8 cm l'un de l'autre au lieu de 11.
    l_wrist_tfs = (-2.5, -5.0, 2.5),
    l_palm_hint = (-0.97, 0.24, 0.0),
    l_pole = (0.32, 0.18, -0.93),
    clavicle_deg = 9.0,
    spine_twist_deg = 0.0,                 # <0 : buste pivote vers la droite
    hip_drop = 0.035, hip_fwd = 0.010, lean = 7.0,
    r_ankle = (-0.235, 0.165, 0.118), l_ankle = (0.215, 0.020, 0.118),
    r_knee_dir = (-0.35, -0.90, 0.0), l_knee_dir = (0.30, -0.92, 0.0),
    r_foot_deg = -24.0, l_foot_deg = 9.0,
    # doigts : (MCP, PIP, DIP)
    r_fingers = {'Index': (45, 40, 20), 'Mid': (66, 62, 28), 'Ring': (68, 64, 30), 'Pinky': (70, 66, 32)},
    l_finger_targets = {'Index': (4.3, -3.1), 'Mid': (4.0, -3.3),
                        'Ring': (3.6, -3.3), 'Pinky': (3.2, -3.1)},
    l_finger_dt = -0.4,                     # decalage vertical des cibles (cm)
    ratio_prise = (1.0, 1.15, 0.6),         # couplage MCP / PIP / DIP en prise
    ratio_detente = (1.0, 2.2, 0.7),        # couplage pour l'index sur la detente
    r_thumb_target = (4.5, 7.0, 2.0), l_thumb_target = (2.0, 8.5, 2.6),
    trigger_local = (0.450, 0.155, -0.170), # detente : surface FLANC DROIT (pontet non perce)
    weapon_scale_mult = 1.0,               # ajustement d'echelle de l'arme
    trigger_tfs = (2.4, 1.6, -1.8),        # detente : point de contact sur le flanc droit
    index_spread_rng = (-15, 42),          # ecartement MCP plausible pour l'index
    r_cant_deg = 0.0, l_cant_deg = 0.0,    # cant des mains autour de l'axe avant
    index_angles_fixes = None,             # (MCP, PIP, DIP, ecartement) ; None = solveur
    r_spread = {'Index': -16, 'Mid': 0, 'Ring': 2, 'Pinky': 5},
    l_spread = {'Index': -4, 'Mid': 0, 'Ring': 2, 'Pinky': 5},
)

GRIP_AXIS0 = Vector((0.013, -0.273, 0.962)).normalized()  # bas -> haut de la crosse (pose de visee)
R_BASE = Matrix(((0, -1, 0), (1, 0, 0), (0, 0, 1)))       # orientation d'arme de reference
GRIP_AXIS = GRIP_AXIS0.copy()
GRIP_L = Vector((0.66, -0.003, -0.353))                   # centre crosse en local arme
WSCALE0 = 0.1042                                          # echelle d'origine de l'arme
_F0 = (Vector((0, -1, 0)) - GRIP_AXIS0 * Vector((0, -1, 0)).dot(GRIP_AXIS0)).normalized()
_S0 = GRIP_AXIS0.cross(_F0).normalized()
_F = _F0.copy(); _S = _S0.copy(); _M = Matrix.Identity(3); R_W = R_BASE.copy()


def apply_grip_rot():
    """Oriente en bloc l'ensemble arme + deux mains (la prise reste identique)."""
    global GRIP_AXIS, _F, _S, _M, R_W
    q = P.get('grip_rot')
    _M = q.to_matrix() if q is not None else Matrix.Identity(3)
    GRIP_AXIS = (_M @ GRIP_AXIS0).normalized()
    _F = (_M @ _F0).normalized()
    _S = (_M @ _S0).normalized()
    R_W = _M @ R_BASE

def tfs(t, f, sl):
    """coordonnees crosse (cm) -> monde"""
    return P['grip_center'] + GRIP_AXIS * (t / 100.0) + _F * (f / 100.0) + _S * (sl / 100.0)

# ---------------------------------------------------------------- utilitaires
def head(n):
    U(); return (MW @ ARM.pose.bones[n].matrix).translation

def set_world(n, rot3, pos_world):
    m = rot3.to_4x4(); m.translation = MWi @ pos_world
    ARM.pose.bones[n].matrix = m; U()

def reset(n):
    pb = ARM.pose.bones[n]
    pb.rotation_mode = 'QUATERNION'
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)

def rot_about_head(name, cur_vec, tgt_vec):
    pb = ARM.pose.bones[name]; U()
    Mw = MW @ pb.matrix; h = Mw.translation
    R = Mw.to_3x3(); R.normalize()
    q = cur_vec.normalized().rotation_difference(tgt_vec.normalized())
    set_world(name, q.to_matrix() @ R, h)

def twist_bone(name, deg):
    """rotation de l'os autour de SON PROPRE axe (vrai twist ; reorienter la
       direction ne fait rien sur un os de colonne, qui pointe deja vers le haut)"""
    pb = ARM.pose.bones[name]
    U()
    Mw = MW @ pb.matrix
    h = Mw.translation
    R = Mw.to_3x3(); R.normalize()
    axis = (R @ Vector((0, 1, 0))).normalized()
    set_world(name, Quaternion(axis, math.radians(deg)).to_matrix() @ R, h)


def mat3(Xv, Yv, Zv):
    m = Matrix.Identity(3)
    for i, v in enumerate((Xv, Yv, Zv)):
        m[0][i], m[1][i], m[2][i] = v.x, v.y, v.z
    return m

def hand_axes(side, palm_hint):
    Z = GRIP_AXIS.copy()
    n = (_M @ Vector(palm_hint)).normalized()
    n = (n - Z * n.dot(Z)).normalized()
    X = -n if side == 'R' else n
    Y = Z.cross(X).normalized()
    return X, Y, Z

# ------------------------------------------------ anti-collision bras / torse
_TKD = None; _TPOS = None; _TNRM = None

TORSO_BONES = {'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_Waist', 'CC_Base_Hip',
               'CC_Base_Pelvis', 'CC_Base_R_RibsTwist', 'CC_Base_L_RibsTwist',
               'CC_Base_R_Breast', 'CC_Base_L_Breast', 'CC_Base_NeckTwist01',
               'CC_Base_NeckTwist02'}


def build_torso_kd():
    """nuage de points du torse deforme (a appeler apres avoir pose buste/jambes)"""
    global _TKD, _TPOS, _TNRM
    from mathutils import kdtree
    obj = bpy.data.objects['output_unwrapped']
    U()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg); me = ev.data; OM = ev.matrix_world
    gi = {g.index: g.name for g in obj.vertex_groups}
    idx = []
    for v in obj.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda x: x.weight)
        if gi.get(g.group) in TORSO_BONES and g.weight > 0.5:
            idx.append(v.index)
    _TPOS = [OM @ me.vertices[i].co for i in idx]
    _TNRM = [(OM.to_3x3() @ me.vertices[i].normal).normalized() for i in idx]
    _TKD = kdtree.KDTree(len(idx))
    for k, pnt in enumerate(_TPOS):
        _TKD.insert(pnt, k)
    _TKD.balance()
    return len(idx)


def torso_clear(P0, P1, n=12, t0=0.0):
    """distance signee minimale (m) entre un segment et la surface du torse.
       negatif = le segment est a l'interieur du corps.
       t0 : fraction du debut ignoree (l'articulation d'epaule est par nature
       a l'interieur du corps, la compter fausserait la mesure)."""
    if _TKD is None:
        return 9.9
    worst = 9.9
    for k in range(n + 1):
        Pt = P0.lerp(P1, t0 + (1.0 - t0) * k / n)
        co, j, d = _TKD.find(Pt)
        sd = (Pt - _TPOS[j]).dot(_TNRM[j])
        if sd < worst:
            worst = sd
    return worst


_SWIVEL = {}
SWIVEL_COHERENCE = 0.030   # poids de la continuite de l'angle de coude


def reset_swivel():
    _SWIVEL.clear()


def solve_arm_safe(side, T, prefer_dir, margin=0.055, elbow_below=0.04):
    """Place le coude en balayant son orbite autour de l'axe epaule-poignet et en
       retenant l'angle qui degage le torse, a defaut le plus naturel."""
    up = 'CC_Base_%s_Upperarm' % side
    fo = 'CC_Base_%s_Forearm' % side
    ha = 'CC_Base_%s_Hand' % side
    S = head(up); F = head(fo); H = head(ha)
    l1 = (F - S).length; l2 = (H - F).length
    dv = T - S
    d = min(dv.length, (l1 + l2) * 0.985)
    u = dv.normalized()
    c = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    th = math.acos(c)
    ref = Vector((0, 0, 1)) if abs(u.z) < 0.9 else Vector((0, 1, 0))
    e1 = (ref - u * ref.dot(u)).normalized()
    e2 = u.cross(e1).normalized()
    pref = Vector(prefer_dir).normalized()
    cands = []
    for a in range(0, 360, 3):
        r = math.radians(a)
        v = (e1 * math.cos(r) + e2 * math.sin(r))
        E = S + l1 * (math.cos(th) * u + math.sin(th) * v)
        cl = min(torso_clear(S, E, t0=0.45), torso_clear(E, T))
        cands.append((E, cl, v, float(a)))
    # le coude doit rester sous l'epaule : pas de coude "en aile de poulet".
    # mais si aucune orientation basse ne degage le torse, on rouvre le choix
    # plutot que d'accepter une interpenetration.
    low = [c for c in cands if c[0].z < S.z - elbow_below]
    pool = low if low and max(c[1] for c in low) >= 0.015 else cands
    # CONTINUITE TEMPORELLE : sans elle, l'orbite du coude etant rebalayee a
    # chaque image, l'optimum peut sauter d'une image a l'autre et le coude
    # part en soubresauts. On penalise l'ecart a l'angle retenu precedemment.
    prev = _SWIVEL.get(side)

    def note(c):
        v = min(c[1], margin) * 100.0 + 0.8 * c[2].dot(pref)
        if prev is not None:
            d = abs(((c[3] - prev + 180.0) % 360.0) - 180.0)
            v -= SWIVEL_COHERENCE * d
        return v

    best = max(pool, key=note)
    _SWIVEL[side] = best[3]
    E = best[0]
    rot_about_head(up, F - S, E - S)
    F2 = head(fo)
    rot_about_head(fo, head(ha) - F2, T - F2)
    return E, round(best[1] * 100, 1)


def solve_chain(up, fo, ha, T, pole_dir, reach=0.985):
    S = head(up); F = head(fo); H = head(ha)
    l1 = (F - S).length; l2 = (H - F).length
    dv = T - S; d = min(dv.length, (l1 + l2) * reach); u = dv.normalized()
    c = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    th = math.acos(c)
    p = Vector(pole_dir); v = (p - u * p.dot(u)).normalized()
    E = S + l1 * (math.cos(th) * u + math.sin(th) * v)
    rot_about_head(up, F - S, E - S)
    F2 = head(fo); rot_about_head(fo, head(ha) - F2, T - F2)
    return E

def solve_arm(side, T, pole_dir):
    return solve_chain('CC_Base_%s_Upperarm' % side, 'CC_Base_%s_Forearm' % side,
                       'CC_Base_%s_Hand' % side, T, pole_dir)

def solve_leg(side, ankle_T, knee_dir, reach=0.999):
    """reach : fraction maximale de la longueur de jambe. A 0.985 le genou ne
       peut jamais descendre sous 20 deg de flexion -- la jambe parait cassee
       en permanence. A 0.999 elle peut se tendre comme une vraie jambe."""
    return solve_chain('CC_Base_%s_Thigh' % side, 'CC_Base_%s_Calf' % side,
                       'CC_Base_%s_Foot' % side, ankle_T, knee_dir, reach)

def curl(bone, deg, side, spread=0.0):
    pb = ARM.pose.bones[bone]; pb.rotation_mode = 'QUATERNION'
    s = 1.0 if side == 'R' else -1.0
    q = Quaternion((0, 0, 1), math.radians(deg) * s)
    if spread:
        q = Quaternion((1, 0, 0), math.radians(spread) * s) @ q
    pb.rotation_quaternion = q

def signed_angle(v1, v2, axis):
    v1 = (v1 - axis * v1.dot(axis))
    v2 = (v2 - axis * v2.dot(axis))
    if v1.length < 1e-6 or v2.length < 1e-6:
        return 0.0
    v1.normalize(); v2.normalize()
    a = math.acos(max(-1.0, min(1.0, v1.dot(v2))))
    return a if v1.cross(v2).dot(axis) > 0 else -a

def add_local_rot(bone, axis_local, angle):
    pb = ARM.pose.bones[bone]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(axis_local, angle)
    U()

def ccd(bones, tip_bone, target, iters=10, axis_local=(0, 0, 1), free_first=False):
    """CCD contraint : chaque os ne tourne qu'autour de son axe de flexion local."""
    for it in range(iters):
        for i, bn in enumerate(bones):
            U()
            pb = ARM.pose.bones[bn]
            h = (MW @ pb.matrix).translation
            tipp = MW @ ARM.pose.bones[tip_bone].tail
            if free_first and i == 0 and it == 0:
                rot_about_head(bn, tipp - h, target - h)
                continue
            axw = ((MW @ pb.matrix).to_3x3().normalized() @ Vector(axis_local)).normalized()
            ang = signed_angle(tipp - h, target - h, axw)
            add_local_rot(bn, Vector(axis_local), ang)
    U()
    return MW @ ARM.pose.bones[tip_bone].tail

AXV = {'X': Vector((1, 0, 0)), 'Y': Vector((0, 1, 0)), 'Z': Vector((0, 0, 1))}


def set_joint(bone, flex, spread):
    """flex = rotation autour de Z local, spread = autour de X local (degres)"""
    pb = ARM.pose.bones[bone]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = (Quaternion(AXV['X'], math.radians(spread))
                              @ Quaternion(AXV['Z'], math.radians(flex)))


def ccd_joints(bones, tip_bone, target, dofs, limits, iters=14):
    """CCD anatomique : chaque os n'a que flexion (Z) et/ou abduction (X), avec butees.
       dofs   : liste de tuples ('Z',) ou ('Z','X') par os
       limits : dict bone -> {'Z': (min,max), 'X': (min,max)} en degres
       state  : angles courants"""
    st = {b: {'Z': 0.0, 'X': 0.0} for b in bones}
    for b in bones:
        set_joint(b, 0.0, 0.0)
    U()
    for _ in range(iters):
        for bn, dd in zip(bones, dofs):
            for ax in dd:
                U()
                pb = ARM.pose.bones[bn]
                h = (MW @ pb.matrix).translation
                tipp = MW @ ARM.pose.bones[tip_bone].tail
                axw = ((MW @ pb.matrix).to_3x3().normalized() @ AXV[ax]).normalized()
                dang = math.degrees(signed_angle(tipp - h, target - h, axw))
                lo, hi = limits[bn][ax]
                st[bn][ax] = max(lo, min(hi, st[bn][ax] + dang))
                set_joint(bn, st[bn]['Z'], st[bn]['X'])
                U()
    return st, (MW @ ARM.pose.bones[tip_bone].tail)


def solve_finger(bones, target, sign, ratios, c_rng=(0, 105), sp_rng=(-25, 25)):
    """Cherche (courbure c, ecartement sp) tel que le bout du doigt atteigne target.
       Les 3 phalanges restent couplees par `ratios` -> courbure toujours anatomique.
       sign = +1 (main droite) / -1 (main gauche)."""
    tip = bones[-1]

    def apply(c, sp):
        for b, k in zip(bones, ratios):
            ang = max(0.0, min(108.0, c * k))
            set_joint(b, ang * sign, (sp * sign) if b is bones[0] else 0.0)
        U()
        return (MW @ ARM.pose.bones[tip].tail - target).length

    best = (1e9, 0.0, 0.0)
    for c in range(int(c_rng[0]), int(c_rng[1]) + 1, 6):
        for sp in range(int(sp_rng[0]), int(sp_rng[1]) + 1, 6):
            e = apply(float(c), float(sp))
            if e < best[0]:
                best = (e, float(c), float(sp))
    for step in (2.0, 0.5):
        e0, c0, s0 = best
        for i in range(-3, 4):
            for j in range(-3, 4):
                c = max(c_rng[0], min(c_rng[1], c0 + i * step))
                sp = max(sp_rng[0], min(sp_rng[1], s0 + j * step))
                e = apply(c, sp)
                if e < best[0]:
                    best = (e, c, sp)
    apply(best[1], best[2])
    return {'c': round(best[1], 1), 'spread': round(best[2], 1),
            'err_cm': round(best[0] * 100, 2),
            'angles': [round(max(0.0, min(108.0, best[1] * k)), 1) for k in ratios]}


def seg_dist(p1, q1, p2, q2):
    """distance minimale entre deux segments 3D"""
    d1 = q1 - p1; d2 = q2 - p2; r = p1 - p2
    a = d1.dot(d1); e = d2.dot(d2); f = d2.dot(r)
    if a < 1e-9 and e < 1e-9:
        return r.length
    if a < 1e-9:
        s_, t_ = 0.0, max(0.0, min(1.0, f / e))
    else:
        c = d1.dot(r)
        if e < 1e-9:
            t_, s_ = 0.0, max(0.0, min(1.0, -c / a))
        else:
            b = d1.dot(d2); den = a * e - b * b
            s_ = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-9 else 0.0
            t_ = (b * s_ + f) / e
            if t_ < 0.0:
                t_ = 0.0; s_ = max(0.0, min(1.0, -c / a))
            elif t_ > 1.0:
                t_ = 1.0; s_ = max(0.0, min(1.0, (b - c) / a))
    return ((p1 + d1 * s_) - (p2 + d2 * t_)).length


def finger_segments(side, fingers=('Index', 'Mid', 'Ring', 'Pinky')):
    U()
    segs = []
    for f in fingers:
        for i in (1, 2, 3):
            pb = ARM.pose.bones['CC_Base_%s_%s%d' % (side, f, i)]
            segs.append(('%s_%s%d' % (side, f, i), MW @ pb.head, MW @ pb.tail))
    return segs


def collide(seuil=1.6):
    """distances min entre doigts gauche et droite (cm). < seuil = interpenetration"""
    L = finger_segments('L'); R = finger_segments('R')
    worst = []
    for nl, a1, a2 in L:
        m = min(((seg_dist(a1, a2, b1, b2) * 100, nr) for nr, b1, b2 in R))
        worst.append((round(m[0], 2), nl, m[1]))
    worst.sort()
    return {'min_cm': worst[0][0], 'conflits': [w for w in worst if w[0] < seuil]}

# ---------------------------------------------------------------- construction
def build():
    apply_grip_rot()
    # 1) arme placee selon P['grip_center'] et P['grip_rot']
    WEAPON.parent = None
    WEAPON.parent_type = 'OBJECT'
    WEAPON.parent_bone = ''
    WEAPON.matrix_parent_inverse = Matrix.Identity(4)
    WS = WSCALE0 * P['weapon_scale_mult']
    WEAPON.scale = (WS, WS, WS)
    WEAPON.rotation_mode = 'QUATERNION'
    WEAPON.rotation_quaternion = R_W.to_quaternion()
    WEAPON.location = P['grip_center'] - (R_W @ (GRIP_L * WS))
    U()
    # les contraintes IK doivent etre absentes pendant la resolution FK
    for pb in ARM.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    U()

    # 2) reset bras + doigts
    for s in ('R', 'L'):
        for b in ('Clavicle', 'Upperarm', 'Forearm', 'Hand'):
            reset('CC_Base_%s_%s' % (s, b))
        for f in ('Thumb', 'Index', 'Mid', 'Ring', 'Pinky'):
            for i in (1, 2, 3):
                reset('CC_Base_%s_%s%d' % (s, f, i))
    U()

    # 2b) bassin abaisse + appui jambes ecartees
    for n in ('RL_BoneRoot', 'CC_Base_Hip', 'CC_Base_Pelvis', 'CC_Base_Waist',
              'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_NeckTwist01',
              'CC_Base_NeckTwist02', 'CC_Base_Head'):
        reset(n)
    for s_ in ('R', 'L'):
        for b in ('Thigh', 'Calf', 'Foot', 'ToeBase'):
            reset('CC_Base_%s_%s' % (s_, b))
    U()
    root = ARM.pose.bones['RL_BoneRoot']
    hip0 = head('CC_Base_Hip')
    set_world('RL_BoneRoot', (MW @ root.matrix).to_3x3().normalized(),
              (MW @ root.matrix).translation + Vector((0, P['hip_fwd'], -P['hip_drop'])))
    for s_, ank, kd, toe_deg in (('R', P['r_ankle'], P['r_knee_dir'], P['r_foot_deg']),
                                 ('L', P['l_ankle'], P['l_knee_dir'], P['l_foot_deg'])):
        solve_leg(s_, Vector(ank), Vector(kd))
        fb = 'CC_Base_%s_Foot' % s_
        h = head(fb)
        cur = (MW @ ARM.pose.bones[fb].tail) - h
        tgt = Matrix.Rotation(math.radians(toe_deg), 3, 'Z') @ Vector((0, -0.92, -0.39)) * cur.length
        rot_about_head(fb, cur, tgt)

    # 2c) buste legerement incline vers l'avant, tete a l'horizontale
    for bn, deg in (('CC_Base_Waist', P['lean'] * 0.3), ('CC_Base_Spine01', P['lean'] * 0.35),
                    ('CC_Base_Spine02', P['lean'] * 0.35)):
        h = head(bn)
        d0 = (MW @ ARM.pose.bones[bn].tail) - h
        rot_about_head(bn, d0, Matrix.Rotation(math.radians(deg), 3, 'X') @ d0)
    # rotation du buste (negatif = epaule gauche vers l'avant, buste vers la droite)
    tw = P.get('spine_twist_deg', 0.0)
    if tw:
        twist_bone('CC_Base_Spine01', tw * 0.4)
        twist_bone('CC_Base_Spine02', tw * 0.6)
        twist_bone('CC_Base_NeckTwist01', -tw * 0.5)   # la tete reste face a l'avant
        twist_bone('CC_Base_NeckTwist02', -tw * 0.5)
    for bn, deg in (('CC_Base_NeckTwist01', -P['lean'] * 0.5), ('CC_Base_NeckTwist02', -P['lean'] * 0.5)):
        h = head(bn)
        d0 = (MW @ ARM.pose.bones[bn].tail) - h
        rot_about_head(bn, d0, Matrix.Rotation(math.radians(deg), 3, 'X') @ d0)

    # 3) clavicules : legere protraction
    for s, sg in (('R', -1), ('L', 1)):
        h = head('CC_Base_%s_Clavicle' % s)
        dirv = head('CC_Base_%s_Upperarm' % s) - h
        rot_about_head('CC_Base_%s_Clavicle' % s, dirv,
                       Matrix.Rotation(math.radians(P['clavicle_deg']) * sg, 3, 'Z') @ dirv)

    # 4) bras + mains (avec test de collision torse)
    build_torso_kd()
    XR, YR, ZR = hand_axes('R', P['r_palm_hint'])
    XL, YL, ZL = hand_axes('L', P['l_palm_hint'])
    if P.get('r_cant_deg'):
        Rc = Matrix.Rotation(math.radians(P['r_cant_deg']), 3, _F)
        XR, YR, ZR = (Rc @ XR).normalized(), (Rc @ YR).normalized(), (Rc @ ZR).normalized()
    if P.get('l_cant_deg'):
        Rl = Matrix.Rotation(math.radians(P['l_cant_deg']), 3, _F)
        XL, YL, ZL = (Rl @ XL).normalized(), (Rl @ YL).normalized(), (Rl @ ZL).normalized()
    wrist_R = tfs(*P['r_wrist_tfs'])
    wrist_L = tfs(*P['l_wrist_tfs'])
    ER, clR = solve_arm_safe('R', wrist_R, Vector(P['r_pole']))
    EL, clL = solve_arm_safe('L', wrist_L, Vector(P['l_pole']))
    set_world('CC_Base_R_Hand', mat3(XR, YR, ZR), head('CC_Base_R_Hand'))
    set_world('CC_Base_L_Hand', mat3(XL, YL, ZL), head('CC_Base_L_Hand'))

    # 5) doigts main droite (angles) ; main gauche (CCD sur cibles exterieures)
    for f, angs in P['r_fingers'].items():
        for i, a in enumerate(angs, start=1):
            curl('CC_Base_R_%s%d' % (f, i), a, 'R',
                 spread=P['r_spread'].get(f, 0) if i == 1 else 0)
    for f in ('Index', 'Mid', 'Ring', 'Pinky'):
        for i in (1, 2, 3):
            curl('CC_Base_L_%s%d' % (f, i), 0.0, 'L')
    # index droit : pose sur la detente par CCD anatomique
    trig = tfs(*P['trigger_tfs']) if P.get('trigger_tfs') else (WEAPON.matrix_world @ Vector(P['trigger_local']))
    ib = ['CC_Base_R_Index%d' % i for i in (1, 2, 3)]
    if P.get('index_angles_fixes'):
        a1, a2, a3, sp = P['index_angles_fixes']
        set_joint(ib[0], a1, sp); set_joint(ib[1], a2, 0.0); set_joint(ib[2], a3, 0.0); U()
        st_idx = {'angles': [a1, a2, a3], 'spread': sp, 'c': None, 'err_cm': None}
    else:
        st_idx = solve_finger(ib, trig, +1, P['ratio_detente'], (0, 80), P['index_spread_rng'])
    tip_idx = MW @ ARM.pose.bones[ib[2]].tail

    # doigts gauches : chaque bout de doigt vise un point hors de la coque des doigts droits
    l_st = {}
    for f, (tf, ts) in P['l_finger_targets'].items():
        lb = ['CC_Base_L_%s%d' % (f, i) for i in (1, 2, 3)]
        t_mcp = ((MW @ ARM.pose.bones[lb[0]].head) - P['grip_center']).dot(GRIP_AXIS) * 100
        tgt = tfs(t_mcp + P['l_finger_dt'], tf, ts)
        l_st[f] = solve_finger(lb, tgt, -1, P['ratio_prise'], (0, 100), (-22, 22))

    # pouces : vises vers une cible le long de la carcasse
    res = {}
    for side, key in (('R', 'r_thumb_target'), ('L', 'l_thumb_target')):
        for i in (1, 2, 3):
            reset('CC_Base_%s_Thumb%d' % (side, i))
        U()
        chain = ['CC_Base_%s_Thumb%d' % (side, i) for i in (1, 2, 3)]
        got = ccd(chain, chain[-1], tfs(*P[key]), iters=8, free_first=True)
        res['pouce_' + side] = got
    U()
    return {'coude_R': ER, 'coude_L': EL, 'poignet_R': wrist_R, 'poignet_L': wrist_L,
            'degagement_torse_cm': {'D': clR, 'G': clL},
            'pouces': res, 'index_angles': st_idx, 'doigts_G': l_st,
            'index_err_cm': round((tip_idx - trig).length * 100, 2)}

# ---------------------------------------------------------------- diagnostic
def diag(keys=None):
    apply_grip_rot()
    """coordonnees dans le repere de la crosse, en cm :
       t = le long de la crosse (+ = vers le haut/carcasse)
       f = avant/arriere (+ = vers le canon / front strap)
       s = lateral (+ = cote gauche du perso)"""
    U()
    G = P['grip_center']; A = GRIP_AXIS
    F = Vector((0, -1, 0)); F = (F - A * F.dot(A)).normalized()
    S = A.cross(F).normalized()
    def rel(p):
        d = p - G
        return (round(d.dot(A) * 100, 1), round(d.dot(F) * 100, 1), round(d.dot(S) * 100, 1))
    out = {}
    for side in ('R', 'L'):
        out['%s_wrist' % side] = rel(MW @ ARM.pose.bones['CC_Base_%s_Hand' % side].head)
        for f in ('Index', 'Mid', 'Ring', 'Pinky'):
            out['%s_%s_MCP' % (side, f)] = rel(MW @ ARM.pose.bones['CC_Base_%s_%s1' % (side, f)].head)
            out['%s_%s_PIP' % (side, f)] = rel(MW @ ARM.pose.bones['CC_Base_%s_%s2' % (side, f)].head)
            out['%s_%s_TIP' % (side, f)] = rel(MW @ ARM.pose.bones['CC_Base_%s_%s3' % (side, f)].tail)
        out['%s_Thumb_MCP' % side] = rel(MW @ ARM.pose.bones['CC_Base_%s_Thumb2' % side].head)
        out['%s_Thumb_TIP' % side] = rel(MW @ ARM.pose.bones['CC_Base_%s_Thumb3' % side].tail)
    for name, lp in (('ARME_crosse_bas', (0.75, 0, -0.58)), ('ARME_crosse_haut', (0.52, 0, -0.07)),
                     ('ARME_detente', (0.33, 0, -0.13)), ('ARME_front_strap', (0.47, 0, -0.35)),
                     ('ARME_back_strap', (0.86, 0, -0.35)), ('ARME_cote_G', (0.66, 0.145, -0.35)),
                     ('ARME_cote_D', (0.66, -0.145, -0.35)), ('ARME_slide_avant', (-0.7, 0, 0.5)),
                     ('ARME_pontet_bas', (0.30, 0, -0.27))):
        out[name] = rel(WEAPON.matrix_world @ Vector(lp))
    if keys:
        out = {k: v for k, v in out.items() if any(k.startswith(x) for x in keys)}
    return out
