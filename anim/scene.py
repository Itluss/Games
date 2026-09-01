# -*- coding: utf-8 -*-
"""Cinematique : marche, course, ralentissement, rassemblement, relevage,
   mise en joue, tir.

   L'assemblage ne concatene pas des clips bout a bout : il rejoue chaque
   generateur et recolle les poses dans une seule action, en decalant la racine
   de l'avancee deja parcourue. Aucun saut de position aux raccords.

   La sequence suit ce qu'on voit dans la realite : on ne passe pas d'une arme
   au poing en courant a une arme haute a deux mains d'un seul coup. Le
   personnage ralentit, sa main gauche vient saisir l'arme sur le cote droit
   canon toujours vers le bas -- c'est la PRISE BASSE, et c'est elle que vise
   le ralentissement -- puis il releve l'arme jusqu'au port haut, et seulement
   ensuite il met en joue.

   Chaque raccord tombe sur une phase entiere, c'est-a-dire un contact du pied
   droit, et a vitesse de marche des deux cotes.
"""
import bpy, math, os, runpy
from mathutils import Vector

SP = os.path.dirname(os.path.abspath(__file__))

S = dict(
    fps=30,
    marche_1=40,        # marche arme haute
    acceleration=24,    # marche -> course
    course=44,
    freinage=26,        # course -> marche, vers la PRISE BASSE
    marche_2=20,        # quelques pas arme rassemblee en bas
    relevage=28,        # l'arme remonte de la prise basse au port haut
    visee_cycles=3,
    visee_debut=0.35,
    tirs=(64, 76),
    action='Cinematique',
)


def _lire(action, n, ALL, arm):
    scn = bpy.context.scene
    arm.animation_data.action = bpy.data.actions[action]
    out = []
    for f in range(1, n + 1):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        d = {b: arm.pose.bones[b].rotation_quaternion.copy() for b in ALL}
        m = arm.matrix_world @ arm.pose.bones['RL_BoneRoot'].matrix
        d['__pos'] = m.translation.copy()
        d['__rot'] = m.to_3x3().normalized()
        out.append(d)
    return out


def _prolonger(lo, ALL, arm, n0, nom):
    """continue la marche jusqu'au prochain contact du pied droit"""
    scn = bpy.context.scene
    rab = 0
    while (lo.phase % 1.0) > 0.5 / lo.Nm and rab < int(lo.Nm) + 1:
        rab += 1
        scn.frame_set(n0 + rab)
        lo.image(0.0)
        for b in ALL:
            pb = arm.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=n0 + rab)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=n0 + rab)
    return n0 + rab


def build():
    arm = bpy.data.objects['Armature']
    scn = bpy.context.scene
    U = bpy.context.view_layer.update
    LO = runpy.run_path(os.path.join(SP, 'locomotion.py'))
    RE = runpy.run_path(os.path.join(SP, 'relevage.py'))
    lo = LO['Loco']()
    ALL = lo.ALL
    A = lo.A

    # ---------- 1) marche arme haute, acceleration, course
    ia = lo.cuire([(0.0, 0.0, S['marche_1']), (0.0, 1.0, S['acceleration']),
                   (1.0, 1.0, S['course'])], action='__sc_a')
    na = ia['images']

    # ---------- 2) ralentissement vers la PRISE BASSE, puis quelques pas
    lo.changer_port(LO['PRISE_BASSE'])
    ib = lo.cuire([(1.0, 0.0, S['freinage']), (0.0, 0.0, S['marche_2'])],
                  action='__sc_b')
    nb = _prolonger(lo, ALL, arm, ib['images'], '__sc_b')
    phase_rel = lo.phase % 1.0

    # ---------- 3) relevage de l'arme, en marchant
    ic = RE['build'](LO['PRISE_BASSE'], images=S['relevage'], phase0=0.0,
                     action='__sc_c', in_place=False)
    nc = ic['images']

    # ---------- 4) mise en joue et tir
    MJ = runpy.run_path(os.path.join(SP, 'mise_en_joue.py'))
    MJ['J'].update(debut=S['visee_debut'], duree=0.55, cycles=S['visee_cycles'],
                   action='__sc_d', tirs=S['tirs'])
    MJ['P2']['in_place'] = False
    idd = MJ['build']()
    nd = idd['images']

    # ---------- 5) recollage
    pa = _lire('__sc_a', na, ALL, arm)
    pb_ = _lire('__sc_b', nb, ALL, arm)
    pc = _lire('__sc_c', nc, ALL, arm)
    pd = _lire('__sc_d', nd, ALL, arm)
    suite = []
    dy = 0.0
    for bloc, saute in ((pa, 0), (pb_, 1), (pc, 1), (pd, 1)):
        if suite:
            # On cale le premier point du bloc UNE IMAGE apres le dernier point
            # deja pose, et cette image vaut la vitesse courante -- pas une
            # valeur fixe : au raccord sortie de course elle vaut 12 cm et non
            # les 3,4 cm d'un pas de marche, ce qui produisait un a-coup de
            # 2,6 m/s.
            pas = suite[-1][1].y - suite[-2][1].y if len(suite) > 1 else -0.0338
            dy = suite[-1][1].y + pas - bloc[saute]['__pos'].y
        for d in bloc[saute:]:
            p = d['__pos'].copy()
            p.y += dy
            suite.append((d, p))
    act = lo.W2['new_action'](S['action'])
    total = len(suite)
    scn.frame_start = 1
    scn.frame_end = total
    for i, (d, p) in enumerate(suite):
        f = i + 1
        scn.frame_set(f)
        for b in ALL:
            pb2 = arm.pose.bones[b]
            pb2.rotation_mode = 'QUATERNION'
            pb2.rotation_quaternion = d[b].copy()
        A['set_world']('RL_BoneRoot', d['__rot'], p)
        U()
        for b in ALL:
            pb2 = arm.pose.bones[b]
            pb2.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb2.keyframe_insert('location', frame=f)
    for n in ('__sc_a', '__sc_b', '__sc_c', '__sc_d'):
        if n in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[n])
    scn.frame_set(1)
    d1 = na
    d2 = d1 + nb - 1
    d3 = d2 + nc - 1
    return {'action': S['action'], 'images': total,
            'duree_s': round(total / float(S['fps']), 2),
            'jalons': {'course': (S['marche_1'] + S['acceleration'], na),
                       'prise_basse': (d1, d2),
                       'relevage': (d2, d3),
                       'visee': (d3, total)},
            'phase_avant_relevage': round(phase_rel, 4),
            'canon_relevage': (ic['canon_debut'], ic['canon_fin']),
            'tirs_img': tuple(d3 + t for t in S['tirs'])}
