# -*- coding: utf-8 -*-
"""Contraintes IK + parentage de l'arme, appliques SUR la pose FK deja construite."""
import bpy, math
from mathutils import Vector, Matrix

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world
MWi = MW.inverted()
U = bpy.context.view_layer.update
SC = bpy.context.scene


def bhead(n):
    U(); return MW @ ARM.pose.bones[n].head


def btail(n):
    U(); return MW @ ARM.pose.bones[n].tail


def mk_empty(name, loc, kind='SPHERE', size=0.05):
    o = bpy.data.objects.get(name)
    if o is None:
        o = bpy.data.objects.new(name, None)
        SC.collection.objects.link(o)
    o.empty_display_type = kind
    o.empty_display_size = size
    o.location = loc
    o.rotation_euler = (0, 0, 0)
    return o


def setup(elbow_R, elbow_L, hand_mats):
    # --- nettoyage
    for pb in ARM.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    U()

    info = {}
    for side, E in (('R', Vector(elbow_R)), ('L', Vector(elbow_L))):
        up = 'CC_Base_%s_Upperarm' % side
        fo = 'CC_Base_%s_Forearm' % side
        ha = 'CC_Base_%s_Hand' % side
        S = bhead(up); W = bhead(ha)
        # la contrainte IK vise la QUEUE de l'avant-bras (et non le poignet)
        Ttail = btail(fo)
        u = (W - S).normalized()
        v = (E - S - u * (E - S).dot(u))
        v = v.normalized() if v.length > 1e-5 else Vector((0, 1, 0))

        tgt = mk_empty('IK_Hand_%s' % side, Ttail, 'SPHERE', 0.04)
        pol = mk_empty('IK_Elbow_%s' % side, E + v * 0.25, 'PLAIN_AXES', 0.05)

        pb = ARM.pose.bones[fo]
        c = pb.constraints.new('IK')
        c.name = 'IK_Arm_%s' % side
        c.target = tgt
        c.pole_target = pol
        c.chain_count = 2
        c.use_tail = True
        c.use_stretch = False
        c.iterations = 500

        # --- 1) angle de pole : reproduit le plan du coude (cible a sa place FK)
        best, bestang = 1e9, 0.0
        for step, grid in ((10.0, [float(x) for x in range(-180, 180, 10)]), (0.5, None)):
            if grid is None:
                grid = [bestang + k * 0.5 for k in range(-20, 21)]
            for ang in grid:
                c.pole_angle = math.radians(ang)
                U()
                err = (bhead(fo) - E).length
                if err < best:
                    best, bestang = err, ang
        c.pole_angle = math.radians(bestang)
        U()

        # --- 2) angle fige, on deplace la cible pour que le POIGNET retombe pile
        W_goal = W.copy()
        for _ in range(8):
            d = W_goal - bhead(ha)
            if d.length < 1e-5:
                break
            tgt.location = tgt.location + d
            U()
        info['%s_pole_angle' % side] = round(bestang, 2)
        info['%s_err_coude_cm' % side] = round((bhead(fo) - E).length * 100, 3)
        info['%s_err_poignet_mm' % side] = round((bhead(ha) - W_goal).length * 1000, 3)

    # --- remise en place exacte de l'orientation des mains (l'IK a change le twist)
    for side in ('R', 'L'):
        ha = 'CC_Base_%s_Hand' % side
        rot3, pos = hand_mats[side]
        pb = ARM.pose.bones[ha]
        U()
        m = rot3.to_4x4()
        m.translation = pb.matrix.translation      # tete naturelle : aucun decalage induit
        pb.matrix = m
        pb.location = (0, 0, 0)                    # garantit zero etirement du poignet
        U()
    info['poignet_R'] = [round(v, 4) for v in bhead('CC_Base_R_Hand')]
    info['poignet_L'] = [round(v, 4) for v in bhead('CC_Base_L_Hand')]
    return info


def parent_weapon(bone='CC_Base_R_Hand'):
    """arme enfant de l'os de la main droite, transformation monde conservee"""
    mw = WEAPON.matrix_world.copy()
    pb = ARM.pose.bones[bone]
    U()
    # Blender parente a la QUEUE de l'os
    P_world = MW @ pb.matrix @ Matrix.Translation((0, ARM.data.bones[bone].length, 0))
    WEAPON.parent = ARM
    WEAPON.parent_type = 'BONE'
    WEAPON.parent_bone = bone
    WEAPON.matrix_parent_inverse = Matrix.Identity(4)
    loc, rot, sca = (P_world.inverted() @ mw).decompose()
    WEAPON.rotation_mode = 'QUATERNION'
    WEAPON.location = loc
    WEAPON.rotation_quaternion = rot
    WEAPON.scale = sca
    U()
    return {'monde_avant': [round(v, 4) for v in mw.translation],
            'monde_apres': [round(v, 4) for v in WEAPON.matrix_world.translation],
            'ecart_mm': round((WEAPON.matrix_world.translation - mw.translation).length * 1000, 2)}
