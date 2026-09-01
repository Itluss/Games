# -*- coding: utf-8 -*-
"""Relevage de l'arme : de la prise basse a deux mains au port arme haute.

   C'est l'etape qui manquait entre la course et la mise en joue. En sortie de
   course le personnage ralentit et la main gauche vient saisir l'arme sur le
   cote droit, canon toujours vers le bas -- cela, le ralentissement le fait
   deja, a condition que sa cible soit la PRISE BASSE et non le port haut.
   Reste a relever l'arme, ce que fait ce module : les deux mains restent
   solidaires de la crosse pendant que celle-ci monte et pivote, du bas-droit
   vers la poitrine, canon qui passe de -22 deg a la verticale.

   La crosse est interpolee dans le repere du BUSTE, pas dans le monde : elle
   suit donc l'oscillation de la marche pendant tout le mouvement, au lieu de
   flotter en ligne droite.
"""
import bpy, math, os, runpy
from mathutils import Vector, Matrix, Quaternion

SP = os.path.dirname(os.path.abspath(__file__))

R = dict(
    images=26,
    depart=0.15,        # part du clip avant que le relevage commence
    duree=0.70,         # part du clip pendant laquelle il se fait
    action='Relevage',
    y0=0.0,
)


def _ctx_port(carry_over, nom):
    """monte une instance de walk2 avec un port donne et renvoie son contexte"""
    W2 = runpy.run_path(os.path.join(SP, 'walk2.py'))
    W2['P2']['in_place'] = True
    W2['P2']['carry_over'] = carry_over
    W2['P2']['action_name'] = nom
    W2['build_walk2'](repeats=1)
    if nom in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[nom])
    return W2


def build(carry_bas, images=None, phase0=0.0, action=None, in_place=False):
    arm = bpy.data.objects['Armature']
    scn = bpy.context.scene
    U = bpy.context.view_layer.update
    Wb = _ctx_port(carry_bas, '__rel_bas')
    cb = Wb['P2']['_ctx']
    Wh = _ctx_port(None, '__rel_haut')
    ch = Wh['P2']['_ctx']
    # on pose le corps avec l'instance du port BAS ; seule la crosse bouge
    A = Wb['A']
    poser = Wb['P2']['_poser']
    Wb['P2']['in_place'] = in_place
    N = Wb['P2']['frames']
    n = int(images or R['images'])
    ALL = Wb['ALL']
    fingers = cb['fingers']
    rp = Vector(cb['rpole']); lp = Vector(cb['lpole'])
    gl_b = cb['grip_local']; gl_h = ch['grip_local']
    gr_b = cb['grip_rot0']; gr_h = ch['grip_rot0']
    smooth = Wb['smooth']
    act = Wb['new_action'](action or R['action'])
    scn.frame_start = 1; scn.frame_end = n
    A['reset_swivel']()
    infos = {'canon_debut': None, 'canon_fin': None}
    ARME = bpy.data.objects['Mesh_0']
    for i in range(n):
        f = i + 1
        scn.frame_set(f)
        u = (i / float(n) - R['depart']) / R['duree']
        k = smooth(u)
        tau = phase0 + i / float(N)
        Mc = poser(tau)
        A['P']['grip_center'] = Mc @ gl_b.lerp(gl_h, k)
        Rc = Mc.to_3x3(); Rc.normalize()
        q0 = gr_b.normalized().slerp(gr_h.normalized(), k)
        A['P']['grip_rot'] = ((Rc @ ch['Rc0'].inverted()).to_quaternion() @ q0).normalized()
        A['apply_grip_rot']()
        XR, YR, ZR = A['hand_axes']('R', A['P']['r_palm_hint'])
        XL, YL, ZL = A['hand_axes']('L', A['P']['l_palm_hint'])
        A['solve_arm']('R', A['tfs'](*A['P']['r_wrist_tfs']), rp)
        A['solve_arm']('L', A['tfs'](*A['P']['l_wrist_tfs']), lp)
        A['set_world']('CC_Base_R_Hand', A['mat3'](XR, YR, ZR), A['head']('CC_Base_R_Hand'))
        A['set_world']('CC_Base_L_Hand', A['mat3'](XL, YL, ZL), A['head']('CC_Base_L_Hand'))
        for b, q in fingers.items():
            pb = arm.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()
        bo = (-ARME.matrix_world.to_3x3().normalized().col[0]).normalized()
        el = math.degrees(math.asin(max(-1.0, min(1.0, bo.z))))
        if i == 0:
            infos['canon_debut'] = round(el, 1)
        infos['canon_fin'] = round(el, 1)
        for b in ALL:
            pb = arm.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=f)
    scn.frame_set(1)
    infos.update({'action': act.name, 'images': n,
                  'phase_fin': round(phase0 + n / float(N), 4)})
    return infos
