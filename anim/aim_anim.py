# -*- coding: utf-8 -*-
"""Animations de visee : lever d'arme (port -> visee), marche en visee, tir.

   Toutes les poses de bras sont RESOLUES image par image a partir de la position
   monde de la crosse : la prise a deux mains n'est jamais recalculee, elle est
   simplement transportee. Le solveur de bras teste la collision avec le torse a
   chaque image et le solveur de chaine plafonne a 98,5 % de la longueur du bras,
   ce qui interdit a la fois l'interpenetration et l'hyperextension.

   Posture de visee : stance isocele - epaules face a la cible, arme sur l'axe
   median a hauteur d'oeil, coudes ~162 deg (tendus mais non verrouilles),
   leger appui vers l'avant."""
import bpy, math, runpy
from mathutils import Vector, Matrix, Quaternion

SP = r"C:\Users\camille\AppData\Local\Temp\claude\c--Users-camille-Games\3c1de467-7e42-4715-976e-32086eff673b\scratchpad"
A = runpy.run_path(SP + r"\pose_aim.py")
Wk = runpy.run_path(SP + r"\walk.py")

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world
U = bpy.context.view_layer.update
head = A['head']; set_world = A['set_world']; reset = A['reset']
rot_about_head = A['rot_about_head']; solve_leg = A['solve_leg']; twist_bone = A['twist_bone']

HIP_DROP = 0.095          # meme assiette que le cycle de marche

# ---- pose de PORT (arme haute) et pose de VISEE, exprimees pareil
PORT = dict(
    grip=Vector((-0.140, -0.245, 1.392)),
    rot=Quaternion((1, 0, 0), math.radians(-82.0)),
    twist=-22.0, lean=4.0, clav=7.0,
    rpole=Vector((-0.55, 0.10, -0.83)), lpole=Vector((0.72, -0.30, -0.62)),
)
VISEE = dict(
    grip=Vector((0.0, -0.545, 1.539)),   # ligne de visee alignee sur l'oeil
    rot=Quaternion((1, 0, 0), 0.0),          # identite : canon horizontal vers -Y
    twist=0.0, lean=6.0, clav=12.0,
    rpole=Vector((-0.45, 0.25, -0.86)), lpole=Vector((0.45, 0.25, -0.86)),
)

LOWER = Wk['LOWER']
UPPER = Wk['UPPER']
ALL = LOWER + UPPER
# os remis a zero a chaque image : les rotations de clavicule et de bras sont
# appliquees en relatif, sans reset elles s'accumuleraient d'image en image
PERFRAME = list(LOWER)
for _s in ('R', 'L'):
    PERFRAME += ['CC_Base_%s_Clavicle' % _s, 'CC_Base_%s_Upperarm' % _s,
                 'CC_Base_%s_Forearm' % _s, 'CC_Base_%s_Hand' % _s]


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def blend(k):
    """interpole les deux poses de reference ; k=0 port, k=1 visee"""
    e = ease(k)
    d = {}
    d['grip'] = PORT['grip'].lerp(VISEE['grip'], e)
    d['rot'] = PORT['rot'].slerp(VISEE['rot'], e)
    for f in ('twist', 'lean', 'clav'):
        d[f] = PORT[f] + (VISEE[f] - PORT[f]) * e
    for f in ('rpole', 'lpole'):
        d[f] = PORT[f].lerp(VISEE[f], e)
    return d


def apply_params(d, legs=True):
    P = A['P']
    P['grip_center'] = Vector(d['grip'])
    P['grip_rot'] = d['rot'] if d['rot'].angle > 1e-6 else None
    P['spine_twist_deg'] = d['twist']
    P['lean'] = d['lean']
    P['clavicle_deg'] = d['clav']
    P['r_pole'] = tuple(d['rpole'])
    P['l_pole'] = tuple(d['lpole'])
    P['hip_drop'] = HIP_DROP
    P['hip_fwd'] = 0.004
    P['r_ankle'] = (-0.105, 0.030, 0.118); P['l_ankle'] = (0.105, -0.010, 0.118)
    P['r_knee_dir'] = (-0.22, -0.97, 0.0); P['l_knee_dir'] = (0.20, -0.98, 0.0)
    P['r_foot_deg'] = -9.0; P['l_foot_deg'] = 6.0


def new_action(name):
    act = bpy.data.actions.get(name)
    if act:
        bpy.data.actions.remove(act)
    if ARM.animation_data is None:
        ARM.animation_data_create()
    act = bpy.data.actions.new(name)
    ARM.animation_data.action = act
    try:
        ARM.animation_data.action_slot = act.slots.new(id_type='OBJECT', name='Armature')
    except Exception:
        pass
    return act


def key_all(f):
    for b in ALL:
        pb = ARM.pose.bones[b]
        pb.keyframe_insert('rotation_quaternion', frame=f)
        if b == 'RL_BoneRoot':
            pb.keyframe_insert('location', frame=f)


def controle(tag, out):
    """etirement + collision bras/torse, mesures sur la pose courante"""
    U()
    worst = 0.0
    for a, b in (('CC_Base_R_Upperarm', 'CC_Base_R_Forearm'), ('CC_Base_R_Forearm', 'CC_Base_R_Hand'),
                 ('CC_Base_L_Upperarm', 'CC_Base_L_Forearm'), ('CC_Base_L_Forearm', 'CC_Base_L_Hand'),
                 ('CC_Base_R_Thigh', 'CC_Base_R_Calf'), ('CC_Base_R_Calf', 'CC_Base_R_Foot'),
                 ('CC_Base_L_Thigh', 'CC_Base_L_Calf'), ('CC_Base_L_Calf', 'CC_Base_L_Foot')):
        r0 = (ARM.data.bones[b].head_local - ARM.data.bones[a].head_local).length * 0.01
        p0 = ((MW @ ARM.pose.bones[b].head) - (MW @ ARM.pose.bones[a].head)).length
        worst = max(worst, abs(p0 - r0))
    sc = max((ARM.pose.bones[b].scale - Vector((1, 1, 1))).length for b in ALL)
    out['etirement_cm'] = max(out.get('etirement_cm', 0.0), round(worst * 100, 4))
    out['scale_max'] = max(out.get('scale_max', 0.0), round(sc, 5))
    cl = 9.9
    for s in ('R', 'L'):
        S = head('CC_Base_%s_Upperarm' % s); E = head('CC_Base_%s_Forearm' % s)
        Wp = head('CC_Base_%s_Hand' % s)
        cl = min(cl, A['torso_clear'](S, E, t0=0.6), A['torso_clear'](E, Wp))
    out['degagement_min_cm'] = min(out.get('degagement_min_cm', 99.0), round(cl * 100, 1))
    return out


# --------------------------------------------------------------- 1) transition
def bake_transition(name='Transition_Visee', n=12):
    scn = bpy.context.scene
    act = new_action(name)
    out = {}
    for i in range(n + 1):
        f = i + 1
        scn.frame_set(f)
        apply_params(blend(i / float(n)))
        A['build']()
        controle(f, out)
        key_all(f)
    scn.frame_start = 1; scn.frame_end = n + 1
    out.update({'action': name, 'images': n + 1, 'duree_s': round(n / 30.0, 2)})
    return out


# --------------------------------------------------------------- 2) marche visee
def bake_aim_walk(name='Marche_Visee', stab=0.45, counter=0.90):
    """cycle de marche, arme stabilisee sur la cible.
       stab = part du mouvement du bassin repercutee sur l'arme (0 = arme fixe)."""
    scn = bpy.context.scene
    Wpar = Wk['W']
    N = Wpar['frames']
    act = new_action(name)
    out = {}
    apply_params(blend(1.0))
    A['build']()                       # etat de reference (assiette + doigts)
    U()
    upper_fingers = {}
    for b in UPPER:
        if any(k in b for k in ('Thumb', 'Index', 'Mid', 'Ring', 'Pinky')):
            upper_fingers[b] = ARM.pose.bones[b].rotation_quaternion.copy()
    for b in PERFRAME:
        reset(b)
    U()
    root_rest = (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).translation.copy()
    XR, YR, ZR = A['hand_axes']('R', A['P']['r_palm_hint'])
    XL, YL, ZL = A['hand_axes']('L', A['P']['l_palm_hint'])
    wr_R = A['tfs'](*A['P']['r_wrist_tfs'])
    wr_L = A['tfs'](*A['P']['l_wrist_tfs'])
    base_grip = Vector(VISEE['grip'])

    for i in range(N + 1):
        f = i + 1
        tau = (i % N) / float(N)
        scn.frame_set(f)
        for b in PERFRAME:
            reset(b)
        U()
        # --- bassin / jambes : identiques au cycle de marche
        adv = Wpar['stride'] * tau
        bob = Wpar['bob'] * (1.0 - math.cos(4.0 * math.pi * tau)) / 2.0
        sway = -Wpar['sway'] * math.sin(2.0 * math.pi * tau)
        dz = -Wpar['hip_base_drop'] + bob
        set_world('RL_BoneRoot', (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).to_3x3().normalized(),
                  root_rest + Vector((sway, 0.0, dz)))
        yaw = -Wpar['pelvis_yaw'] * math.sin(2.0 * math.pi * tau)
        roll = Wpar['pelvis_roll'] * math.sin(2.0 * math.pi * tau)
        Mw = MW @ ARM.pose.bones['CC_Base_Hip'].matrix
        R = Mw.to_3x3(); R.normalize()
        set_world('CC_Base_Hip', Matrix.Rotation(math.radians(yaw), 3, 'Z')
                  @ Matrix.Rotation(math.radians(roll), 3, 'Y') @ R, Mw.translation)
        for side, phase, toe in (('R', 0.0, Wpar['toe_out_R']), ('L', 0.5, Wpar['toe_out_L'])):
            y, z, pitch = Wk['foot_state'](tau, phase)
            y += adv
            sgn = -1.0 if side == 'R' else 1.0
            T = Vector((sgn * Wpar['foot_side'], y, 0.118 + z))
            solve_leg(side, T, Vector((sgn * 0.06, -0.998, 0.0)))
            fb = 'CC_Base_%s_Foot' % side
            cur = (MW @ ARM.pose.bones[fb].tail) - head(fb)
            d0 = (Matrix.Rotation(math.radians(toe), 3, 'Z')
                  @ Matrix.Rotation(math.radians(pitch), 3, 'X') @ Vector((0, -0.92, -0.39)))
            rot_about_head(fb, cur, d0)
            if pitch > 0.5:
                tb = 'CC_Base_%s_ToeBase' % side
                cur2 = (MW @ ARM.pose.bones[tb].tail) - head(tb)
                axis = Vector((math.cos(math.radians(toe)), math.sin(math.radians(toe)), 0))
                rot_about_head(tb, cur2, Matrix.Rotation(math.radians(-pitch), 3, axis) @ cur2)
        # --- colonne
        for bn, part in (('CC_Base_Waist', 0.3), ('CC_Base_Spine01', 0.35), ('CC_Base_Spine02', 0.35)):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0, Matrix.Rotation(math.radians(VISEE['lean'] * part), 3, 'X') @ d0)
        tw = -counter * yaw          # buste garde presque constamment l'axe de la cible
        twist_bone('CC_Base_Spine01', tw * 0.4)
        twist_bone('CC_Base_Spine02', tw * 0.6)
        twist_bone('CC_Base_NeckTwist01', -tw * 0.5)
        twist_bone('CC_Base_NeckTwist02', -tw * 0.5)
        for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0, Matrix.Rotation(math.radians(-VISEE['lean'] * 0.5), 3, 'X') @ d0)
        # --- clavicules
        for s_, sg in (('R', -1), ('L', 1)):
            h = head('CC_Base_%s_Clavicle' % s_)
            dirv = head('CC_Base_%s_Upperarm' % s_) - h
            rot_about_head('CC_Base_%s_Clavicle' % s_, dirv,
                           Matrix.Rotation(math.radians(VISEE['clav']) * sg, 3, 'Z') @ dirv)
        # --- arme stabilisee : ne suit le corps que partiellement
        off = Vector((sway * stab, 0.0, (bob - Wpar['bob'] * 0.5) * stab))
        A['P']['grip_center'] = base_grip + off
        A['apply_grip_rot']()
        A['build_torso_kd']()
        wR = A['tfs'](*A['P']['r_wrist_tfs'])
        wL = A['tfs'](*A['P']['l_wrist_tfs'])
        A['solve_arm_safe']('R', wR, Vector(VISEE['rpole']))
        A['solve_arm_safe']('L', wL, Vector(VISEE['lpole']))
        set_world('CC_Base_R_Hand', A['mat3'](XR, YR, ZR), head('CC_Base_R_Hand'))
        set_world('CC_Base_L_Hand', A['mat3'](XL, YL, ZL), head('CC_Base_L_Hand'))
        for b, q in upper_fingers.items():
            pb = ARM.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()
        controle(f, out)
        key_all(f)
    scn.frame_start = 1; scn.frame_end = N + 1
    scn.frame_set(1)
    out.update({'action': name, 'images': N + 1})
    return out


# --------------------------------------------------------------- 3) tir
def bake_fire(name='Tir', n=9, kick_deg=11.0, kick_back=0.055):
    """recul : l'arme part en rotation vers le haut et recule, puis revient."""
    scn = bpy.context.scene
    act = new_action(name)
    out = {}
    prof = [0.0, 1.0, 0.85, 0.6, 0.4, 0.25, 0.14, 0.06, 0.0, 0.0]
    for i in range(n + 1):
        f = i + 1
        k = prof[min(i, len(prof) - 1)]
        d = blend(1.0)
        d['grip'] = Vector(VISEE['grip']) + Vector((0.0, kick_back * k, 0.012 * k))
        d['rot'] = Quaternion((1, 0, 0), math.radians(kick_deg * k))
        d['lean'] = VISEE['lean'] - 1.2 * k
        scn.frame_set(f)
        apply_params(d)
        A['build']()
        controle(f, out)
        key_all(f)
    scn.frame_start = 1; scn.frame_end = n + 1
    out.update({'action': name, 'images': n + 1, 'recul_deg': kick_deg})
    return out
