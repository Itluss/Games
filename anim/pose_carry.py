# -*- coding: utf-8 -*-
"""Pose de base ('carry' / port compresse) : arme tenue A DEUX MAINS, canon vers le haut,
   devant le cote droit du torse. C'est la pose de depart pour la marche ;
   l'animation de visee consistera a tendre les deux bras vers l'avant.

   La prise a deux mains n'est PAS recalculee : elle est reprise telle quelle de
   pose_aim et pivotee en bloc via P['grip_rot']."""
import bpy, math, runpy
from mathutils import Vector, Quaternion

SP = r"C:\Users\camille\AppData\Local\Temp\claude\c--Users-camille-Games\3c1de467-7e42-4715-976e-32086eff673b\scratchpad"
A = runpy.run_path(SP + r"\pose_aim.py")
K = runpy.run_path(SP + r"\rig_ik.py")

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world

C = dict(
    # --- placement de l'ensemble arme + mains
    grip_center=Vector((-0.140, -0.245, 1.455)),   # crosse : devant le pectoral droit
    tilt_deg=-82.0,      # canon quasi vertical, 8 deg vers l'AVANT
    yaw_deg=0.0,
    roll_deg=0.0,
    r_pole=Vector((-0.55, 0.10, -0.83)),           # coude droit bas, pres du corps
    l_pole=Vector((0.72, -0.30, -0.62)),           # coude gauche bas, ouvert vers l'avant
    # --- posture debout neutre (base d'un cycle de marche)
    hip_drop=0.012, hip_fwd=0.004, lean=4.0,
    r_ankle=(-0.105, 0.030, 0.118), l_ankle=(0.105, -0.010, 0.118),
    r_knee_dir=(-0.22, -0.97, 0.0), l_knee_dir=(0.20, -0.98, 0.0),
    r_foot_deg=-9.0, l_foot_deg=6.0,
    clavicle_deg=7.0,
    spine_twist_deg=-22.0,   # buste pivote vers la droite : degage le bras gauche
    # --- camera TPS
    cam_back=3.60, cam_side=-0.68, cam_height=1.92,
    cam_pitch_deg=2.0, cam_yaw_deg=0.0, cam_fov_deg=65.0,
)


def build_carry():
    P = A['P']
    P['grip_rot'] = (Quaternion((0, 1, 0), math.radians(C['roll_deg']))
                     @ Quaternion((0, 0, 1), math.radians(C['yaw_deg']))
                     @ Quaternion((1, 0, 0), math.radians(C['tilt_deg'])))
    P['grip_center'] = Vector(C['grip_center'])
    P['r_pole'] = tuple(C['r_pole'])
    P['l_pole'] = tuple(C['l_pole'])
    for k in ('hip_drop', 'hip_fwd', 'lean', 'r_ankle', 'l_ankle', 'r_knee_dir',
              'l_knee_dir', 'r_foot_deg', 'l_foot_deg', 'clavicle_deg', 'spine_twist_deg'):
        P[k] = C[k]
    r = A['build']()

    bpy.context.view_layer.update()
    hm = {}
    for s in ('R', 'L'):
        m = MW @ ARM.pose.bones['CC_Base_%s_Hand' % s].matrix
        R3 = m.to_3x3(); R3.normalize()
        hm[s] = (R3, m.translation.copy())
    ik = K['setup'](r['coude_R'], r['coude_L'], hm)
    ik['arme'] = K['parent_weapon']()

    out = {}
    for s, e in (('D', r['coude_R']), ('G', r['coude_L'])):
        up = 'CC_Base_%s_Upperarm' % ('R' if s == 'D' else 'L')
        ha = 'CC_Base_%s_Hand' % ('R' if s == 'D' else 'L')
        S = A['head'](up); E = Vector(e); W = A['head'](ha)
        out['coude_' + s] = round(math.degrees((S - E).angle(W - E)), 1)
    Wm = WEAPON.matrix_world
    out['crosse'] = [round(v, 3) for v in (Wm @ Vector(A['GRIP_L']))]
    out['bouche'] = [round(v, 3) for v in (Wm @ Vector((-0.934, 0.002, 0.422)))]
    out['ik_err_cm'] = [ik['R_err_coude_cm'], ik['L_err_coude_cm']]
    out['arme_ecart_mm'] = ik['arme']['ecart_mm']
    out['collisions_doigts'] = A['collide']()['min_cm']
    out['degagement_torse_cm'] = r['degagement_torse_cm']
    ax = (Wm.to_3x3() @ Vector((-1, 0, 0))).normalized()
    out['canon_deg_vs_vertical'] = round(math.degrees(ax.angle(Vector((0, 0, 1)))), 1)
    out['canon_vers_avant'] = round(-ax.y, 3)
    return out


def integrite():
    """verifie qu'aucun os n'est etire ni deplace"""
    bpy.context.view_layer.update()
    bad = {'scale': [], 'loc': [], 'seg': []}
    for pb in ARM.pose.bones:
        if (pb.scale - Vector((1, 1, 1))).length > 1e-4:
            bad['scale'].append(pb.name)
        if pb.location.length > 1e-3 and pb.name != 'RL_BoneRoot':
            bad['loc'].append((pb.name, round(pb.location.length, 4)))
    pairs = [('CC_Base_R_Clavicle', 'CC_Base_R_Upperarm'), ('CC_Base_R_Upperarm', 'CC_Base_R_Forearm'),
             ('CC_Base_R_Forearm', 'CC_Base_R_Hand'), ('CC_Base_R_Hand', 'CC_Base_R_Mid1'),
             ('CC_Base_L_Clavicle', 'CC_Base_L_Upperarm'), ('CC_Base_L_Upperarm', 'CC_Base_L_Forearm'),
             ('CC_Base_L_Forearm', 'CC_Base_L_Hand'), ('CC_Base_L_Hand', 'CC_Base_L_Mid1'),
             ('CC_Base_R_Thigh', 'CC_Base_R_Calf'), ('CC_Base_R_Calf', 'CC_Base_R_Foot'),
             ('CC_Base_L_Thigh', 'CC_Base_L_Calf'), ('CC_Base_L_Calf', 'CC_Base_L_Foot'),
             ('CC_Base_Spine02', 'CC_Base_NeckTwist01')]
    worst = 0.0
    for a, b in pairs:
        r0 = (ARM.data.bones[b].head_local - ARM.data.bones[a].head_local).length * 0.01
        p0 = ((MW @ ARM.pose.bones[b].head) - (MW @ ARM.pose.bones[a].head)).length
        worst = max(worst, abs(p0 - r0) * 100)
    bad['ecart_max_cm'] = round(worst, 4)
    return bad


def setup_camera():
    cam = bpy.data.objects.get('Camera')
    if cam is None:
        cam = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera'))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.lens_unit = 'FOV'
    cam.data.angle = math.radians(C['cam_fov_deg'])
    cam.data.clip_start = 0.05
    cam.rotation_mode = 'XYZ'
    cam.location = Vector((C['cam_side'], C['cam_back'], C['cam_height']))
    cam.rotation_euler = (math.radians(90.0 - C['cam_pitch_deg']), 0.0,
                          math.radians(180.0 + C['cam_yaw_deg']))
    bpy.context.scene.camera = cam
    bpy.context.view_layer.update()
    return [round(v, 2) for v in cam.location]
