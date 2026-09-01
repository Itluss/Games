# -*- coding: utf-8 -*-
"""Mesure de degagement bras / torse.

   L'ancienne version prenait la normale du SOMMET le plus proche. Des que le
   bras s'eloigne du buste -- bras tendus en visee -- le sommet retenu peut se
   trouver de l'autre cote du torse et le signe s'inverse : elle annoncait
   -13 cm la ou le lancer de rayon montre le point dehors, a 2,8 cm de la peau.
   Ici on construit un BVH des seules FACES du torse et on utilise la normale
   de face du point le plus proche, qui elle est fiable."""
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

TORSO = {'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_Waist', 'CC_Base_Hip',
         'CC_Base_Pelvis', 'CC_Base_R_RibsTwist', 'CC_Base_L_RibsTwist',
         'CC_Base_R_Breast', 'CC_Base_L_Breast', 'CC_Base_NeckTwist01',
         'CC_Base_NeckTwist02', 'CC_Base_R_Clavicle', 'CC_Base_L_Clavicle'}

_IDX = None


def _torse_idx(obj):
    """indices des sommets dont le groupe dominant est un os du torse"""
    global _IDX
    if _IDX is not None:
        return _IDX
    gid = {g.index: g.name for g in obj.vertex_groups}
    keep = set()
    for v in obj.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda e: e.weight)
        if gid.get(g.group) in TORSO:
            keep.add(v.index)
    _IDX = keep
    return keep


def boite_torse():
    """boite englobante des sommets du torse, en monde"""
    dg = bpy.context.evaluated_depsgraph_get()
    src = bpy.data.objects['output_unwrapped']
    keep = _torse_idx(src)
    ev = src.evaluated_get(dg)
    me = ev.to_mesh(); m = ev.matrix_world
    pts = [m @ me.vertices[i].co for i in keep]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ev.to_mesh_clear()
    return lo, hi


def bvh_torse():
    dg = bpy.context.evaluated_depsgraph_get()
    src = bpy.data.objects['output_unwrapped']
    keep = _torse_idx(src)
    ev = src.evaluated_get(dg)
    me = ev.to_mesh()
    m = ev.matrix_world
    verts = [m @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons
             if all(i in keep for i in p.vertices)]
    bvh = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    ev.to_mesh_clear()
    return bvh


def degagement(bvh, P0, P1, n=16, t0=0.0, boite=None):
    """distance signee minimale du segment [P0,P1] a la surface du torse.
       t0 saute le debut du segment : la tete de l'humerus est anatomiquement
       DANS le volume de l'epaule, la compter donnerait toujours du negatif."""
    mini = 9.0
    for i in range(n + 1):
        t = t0 + (1.0 - t0) * i / float(n)
        P = P0.lerp(P1, t)
        r = bvh.find_nearest(P)
        if r[0] is None:
            continue
        loc = r[0]
        d = (P - loc).length
        # Le signe pris sur la SEULE face la plus proche bascule des que cette
        # face est rasante : on a vu le meme point mesure 2,33 / 2,24 / 2,12 cm
        # sur trois images et declare dedans sur celle du milieu. On fait donc
        # voter toutes les faces situees a moins d'un centimetre de plus, en
        # ponderant par la proximite.
        vote = 0.0
        for loc2, nrm2, _i, d2 in bvh.find_nearest_range(P, d + 0.010):
            v = P - loc2
            if v.length < 1e-9:
                continue
            w = 1.0 / (d2 + 1e-4)
            vote += w * (1.0 if v.dot(nrm2) >= 0.0 else -1.0)
        if vote < 0.0:
            # Garde-fou : un point situe HORS de la boite englobante du torse ne
            # peut pas etre dedans, quoi que disent les normales. Sans cela un
            # bras tendu loin devant, dont la face de torse la plus proche est
            # un flanc vu par la tranche, etait declare a -12 cm dans le buste.
            if boite is not None:
                lo, hi = boite
                if (P.x < lo.x or P.x > hi.x or P.y < lo.y or P.y > hi.y
                        or P.z < lo.z or P.z > hi.z):
                    mini = min(mini, d)
                    continue
            d = -d
        mini = min(mini, d)
    return mini


def controler(action, images, verbose=False):
    arm = bpy.data.objects['Armature']
    MW = arm.matrix_world
    scn = bpy.context.scene
    arm.animation_data.action = bpy.data.actions[action]
    pire = (9.0, 0, '')
    for f in range(1, images + 1):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        bvh = bvh_torse()
        bte = boite_torse()
        for s in ('R', 'L'):
            S = MW @ arm.pose.bones['CC_Base_%s_Upperarm' % s].head
            E = MW @ arm.pose.bones['CC_Base_%s_Forearm' % s].head
            W = MW @ arm.pose.bones['CC_Base_%s_Hand' % s].head
            for P0, P1, t0, lab in ((S, E, 0.55, 'humerus'), (E, W, 0.0, 'avant-bras')):
                d = degagement(bvh, P0, P1, t0=t0, boite=bte)
                if d < pire[0]:
                    pire = (d, f, '%s %s' % (s, lab))
        if verbose and f % 10 == 0:
            print('   ... img %d' % f)
    return pire
