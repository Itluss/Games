# -*- coding: utf-8 -*-
"""Cycle de marche, arme tenue a deux mains canon vers le haut.

   Principe : le haut du corps (clavicules, bras, mains, doigts) garde EXACTEMENT
   les rotations locales de la pose statique validee. Comme ce sont des rotations
   locales, tout le bloc suit le buste sans jamais changer de geometrie relative :
   la prise sur l'arme et les degagements bras/torse restent donc identiques a
   chaque image, par construction.

   Seuls sont animes : la racine, le bassin, les deux jambes, la colonne et la nuque."""
import bpy, math, runpy
from mathutils import Vector, Matrix, Quaternion

SP = r"C:\Users\camille\AppData\Local\Temp\claude\c--Users-camille-Games\3c1de467-7e42-4715-976e-32086eff673b\scratchpad"
A = runpy.run_path(SP + r"\pose_aim.py")
Cy = runpy.run_path(SP + r"\pose_carry.py")

ARM = bpy.data.objects['Armature']
MW = ARM.matrix_world
U = bpy.context.view_layer.update
head = A['head']; set_world = A['set_world']; reset = A['reset']
rot_about_head = A['rot_about_head']; solve_leg = A['solve_leg']; twist_bone = A['twist_bone']

W = dict(
    fps=30,
    frames=36,              # 1 cycle complet = 2 pas (cadence ~100 pas/min)
    stride=0.78,            # avancee du corps par cycle (m) : pas courts, controles
    duty=0.62,              # appui au sol prolonge = plus stable
    foot_side=0.045,        # appuis proches de l'axe de marche (9 cm au total)
    foot_lift=0.062,        # le pied rase le sol
    hip_base_drop=0.095,    # genoux flechis : centre de gravite bas
    bob=0.012,              # rebond vertical minimal (arme stable)
    sway=0.011,             # balancement lateral reduit (2,2 cm au total)
    pelvis_yaw=3.0,         # rotation du bassin (deg)
    pelvis_roll=2.5,        # bascule du bassin (deg)
    spine_counter=0.78,     # buste garde son axe : epaules quasi fixes
    heel_strike_deg=-13.0,  # pointe relevee a l'attaque du talon
    toe_off_deg=32.0,       # pointe baissee au deroule
    toe_out_R=-5.0, toe_out_L=4.0,   # ouverture de pied faible
    ball_len=0.165,         # cheville -> avant-pied
    heel_len=0.075,         # cheville -> talon
    in_place=True,          # True : cycle sur place (boucle sans raccord)
                            # False : le personnage avance reellement (root motion)
    action_name='Marche_ArmeHaute',
)

UPPER = []
for s in ('R', 'L'):
    UPPER += ['CC_Base_%s_Clavicle' % s, 'CC_Base_%s_Upperarm' % s,
              'CC_Base_%s_Forearm' % s, 'CC_Base_%s_Hand' % s]
    for f in ('Thumb', 'Index', 'Mid', 'Ring', 'Pinky'):
        UPPER += ['CC_Base_%s_%s%d' % (s, f, i) for i in (1, 2, 3)]

LOWER = ['RL_BoneRoot', 'CC_Base_Hip', 'CC_Base_Pelvis', 'CC_Base_Waist',
         'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_NeckTwist01',
         'CC_Base_NeckTwist02', 'CC_Base_Head']
for s in ('R', 'L'):
    LOWER += ['CC_Base_%s_Thigh' % s, 'CC_Base_%s_Calf' % s, 'CC_Base_%s_Foot' % s,
              'CC_Base_%s_ToeBase' % s]


def smooth(x):
    """ease in/out sur [0,1]"""
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def foot_state(tau, phase):
    """position monde et pitch du pied, pour une phase donnee du cycle.
       tau = temps en cycles ; phase = 0 (droit) ou 0.5 (gauche)."""
    S = W['stride']; duty = W['duty']
    half = duty * S / 2.0                      # amplitude avant/arriere du pied
    p = (tau - phase) % 1.0
    n = math.floor(tau - phase)                # numero du pas en cours
    y_plant = -S * (n + phase) - half          # pose du pied, en avant du corps
    if p < duty:                               # --- appui : le pied ne bouge pas
        y = y_plant
        z = 0.0
        q = p / duty
        if q < 0.12:                           # attaque talon : pivot sur le TALON
            pitch = W['heel_strike_deg'] * (1.0 - smooth(q / 0.12))
            z = W['heel_len'] * (1.0 - math.cos(math.radians(pitch)))
            z += W['heel_len'] * math.sin(math.radians(-pitch)) * 0.35
        elif q < 0.68:
            pitch = 0.0
        else:                                  # deroule : le pied pivote sur l'AVANT-PIED
            k = smooth((q - 0.68) / 0.32)
            pitch = W['toe_off_deg'] * k
            a0 = math.radians(23.0)            # inclinaison au repos cheville->avant-pied
            z = W['ball_len'] * (math.sin(a0 + math.radians(pitch)) - math.sin(a0))
    else:                                      # --- vol
        q = (p - duty) / (1.0 - duty)
        y = y_plant - S * smooth(q)
        z = W['foot_lift'] * math.sin(math.pi * q) ** 1.25
        if q < 0.35:
            pitch = W['toe_off_deg'] * (1.0 - smooth(q / 0.35))
        else:
            pitch = W['heel_strike_deg'] * smooth((q - 0.35) / 0.65)
        # garde-fou : la cheville doit rester assez haute pour que ni la pointe
        # ni le talon ne passent sous le sol quand le pied est incline
        a0 = math.radians(23.0)
        if pitch > 0:
            z = max(z, W['ball_len'] * (math.sin(a0 + math.radians(pitch)) - math.sin(a0)))
        else:
            th = math.radians(-pitch)
            z = max(z, W['heel_len'] * ((1.0 - math.cos(th)) + math.sin(th) * 0.35))
    return y, z, pitch


def build_walk(repeats=1):
    scn = bpy.context.scene
    scn.render.fps = W['fps']
    N = W['frames']
    TOT = N * repeats
    scn.frame_start = 1
    scn.frame_end = TOT + 1

    # ---- 1) pose statique de reference : elle fixe tout le haut du corps
    Cy['build_carry']()
    U()
    upper_rot = {}
    for b in UPPER:
        pb = ARM.pose.bones[b]
        pb.rotation_mode = 'QUATERNION'
        upper_rot[b] = pb.rotation_quaternion.copy()
    carry_twist = A['P'].get('spine_twist_deg', 0.0)
    lean = A['P']['lean']

    # ---- 2) l'IK des bras est retiree : l'animation est en FK pur (export propre)
    for pb in ARM.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    U()

    # ---- 3) reference de hauteur du bassin
    for b in LOWER:
        reset(b)
    U()
    root_rest = (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).translation.copy()
    z_ankle = 0.118

    act = bpy.data.actions.get(W['action_name'])
    if act:
        bpy.data.actions.remove(act)
    if ARM.animation_data is None:
        ARM.animation_data_create()
    act = bpy.data.actions.new(W['action_name'])
    ARM.animation_data.action = act
    try:
        ARM.animation_data.action_slot = act.slots.new(id_type='OBJECT', name='Armature')
    except Exception:
        pass

    rapport_max = 0.0
    for i in range(TOT + 1):
        f = i + 1
        tau = i / float(N)          # continu : les pas s'enchainent
        scn.frame_set(f)
        for b in LOWER:
            reset(b)
        U()

        # --- bassin : avancee + oscillation verticale + balancement + rotations
        adv = W['stride'] * tau
        y_body = 0.0 if W['in_place'] else -adv
        bob = W['bob'] * (1.0 - math.cos(4.0 * math.pi * tau)) / 2.0
        sway = -W['sway'] * math.sin(2.0 * math.pi * tau)
        dz = -W['hip_base_drop'] + bob
        set_world('RL_BoneRoot', (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).to_3x3().normalized(),
                  root_rest + Vector((sway, y_body, dz)))
        yaw = -W['pelvis_yaw'] * math.sin(2.0 * math.pi * tau)
        roll = W['pelvis_roll'] * math.sin(2.0 * math.pi * tau)
        hp = ARM.pose.bones['CC_Base_Hip']
        Mw = MW @ hp.matrix
        R = Mw.to_3x3(); R.normalize()
        Rz = Matrix.Rotation(math.radians(yaw), 3, 'Z')
        Ry = Matrix.Rotation(math.radians(roll), 3, 'Y')
        set_world('CC_Base_Hip', Rz @ Ry @ R, Mw.translation)

        # --- jambes
        for side, phase, toe in (('R', 0.0, W['toe_out_R']), ('L', 0.5, W['toe_out_L'])):
            y, z, pitch = foot_state(tau, phase)
            sgn = -1.0 if side == 'R' else 1.0
            if W['in_place']:
                y += adv
            T = Vector((sgn * W['foot_side'], y, z_ankle + z))
            S0 = head('CC_Base_%s_Thigh' % side)
            l1 = (head('CC_Base_%s_Calf' % side) - S0).length
            l2 = (head('CC_Base_%s_Foot' % side) - head('CC_Base_%s_Calf' % side)).length
            rapport_max = max(rapport_max, (T - S0).length / (l1 + l2))
            solve_leg(side, T, Vector((sgn * 0.06, -0.998, 0.0)))   # genou vers l'avant
            fb = 'CC_Base_%s_Foot' % side
            cur = (MW @ ARM.pose.bones[fb].tail) - head(fb)
            d0 = (Matrix.Rotation(math.radians(toe), 3, 'Z')
                  @ Matrix.Rotation(math.radians(pitch), 3, 'X') @ Vector((0, -0.92, -0.39)))
            rot_about_head(fb, cur, d0)
            # orteils : contre-rotation pour rester a plat au sol pendant le deroule
            tb = 'CC_Base_%s_ToeBase' % side
            if pitch > 0.5:
                cur2 = (MW @ ARM.pose.bones[tb].tail) - head(tb)
                axis = Vector((math.cos(math.radians(toe)), math.sin(math.radians(toe)), 0))
                rot_about_head(tb, cur2, Matrix.Rotation(math.radians(-pitch), 3, axis) @ cur2)

        # --- colonne : inclinaison avant + port de l'arme + contre-rotation de marche
        for bn, part in (('CC_Base_Waist', 0.3), ('CC_Base_Spine01', 0.35), ('CC_Base_Spine02', 0.35)):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0, Matrix.Rotation(math.radians(lean * part), 3, 'X') @ d0)
        tw = carry_twist - W['spine_counter'] * yaw
        twist_bone('CC_Base_Spine01', tw * 0.4)
        twist_bone('CC_Base_Spine02', tw * 0.6)
        twist_bone('CC_Base_NeckTwist01', -tw * 0.5)
        twist_bone('CC_Base_NeckTwist02', -tw * 0.5)
        for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0, Matrix.Rotation(math.radians(-lean * 0.5), 3, 'X') @ d0)

        # --- haut du corps : rotations locales de la pose validee, a l'identique
        for b, q in upper_rot.items():
            pb = ARM.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()

        # --- cles
        for b in LOWER + UPPER:
            pb = ARM.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=f)

    scn.frame_set(1)
    return {'images': TOT + 1, 'fps': W['fps'],
            'duree_s': round(N / float(W['fps']), 2),
            'vitesse_m_s': round(W['stride'] / (N / float(W['fps'])), 2),
            'longueur_pas_cm': round(W['stride'] / 2 * 100, 1),
            'extension_jambe_max': round(rapport_max, 3),
            'action': act.name}
