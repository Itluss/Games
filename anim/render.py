# -*- coding: utf-8 -*-
"""Rend les sequences WEBP. La camera SUIT le personnage : elle garde un
   decalage constant par rapport au bassin, sinon sur trois foulees le
   personnage sort du cadre. Decor volontairement vide : sol et fond gris uni."""
import bpy, os, math, runpy
from mathutils import Vector

SP = os.path.dirname(os.path.abspath(__file__))

# decalage camera par rapport au bassin, et hauteur visee.
# Le personnage avance vers -Y ; sa droite (ou il tient l'arme) est en -X.
VUES = {
    'profil':      ((-5.00,  0.00, 1.05), 0.95),
    'troisquarts': ((-3.60,  3.30, 1.20), 0.98),
    'face':        (( 0.00, -5.00, 1.05), 0.95),
    'dos':         (( 0.00,  5.00, 1.05), 0.95),
    'misenjoue':   ((-3.70, -3.20, 1.25), 1.00),
    'viseeprofil': ((-5.00,  0.00, 1.05), 0.95),
    'viseeface':   (( 0.00, -5.00, 1.05), 0.95),
    'courseprofil':      ((-4.60, 0.00, 1.02), 0.92),
    'coursetroisquarts': ((-3.40, 3.10, 1.15), 0.95),
    'cinematique':       ((-4.20, 2.60, 1.20), 0.98),
}

# Vues a camera FIXE : le personnage traverse le cadre. C'est le seul moyen de
# juger l'avancee reelle -- une camera qui suit exactement le bassin place le
# personnage au centre a chaque image, et la course parait sur place quel que
# soit le deplacement.
VUES_FIXES = {
    'coursetravers': dict(pos=(-6.60, -5.00, 1.25), cible=(0.0, -5.00, 0.95), lens=42.0),
}


def viser(cam, pos, cible):
    cam.location = pos
    d = (cible - pos)
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = d.to_track_quat('-Z', 'Y')


def rendre_fixe(vue, action, images):
    scn = bpy.context.scene
    arm = bpy.data.objects['Armature']
    cam = bpy.data.objects['Camera']
    if cam.animation_data:
        cam.animation_data_clear()
    cfg = VUES_FIXES[vue]
    cam.data.lens = cfg['lens']
    scn.camera = cam
    scn.render.resolution_x = 640
    scn.render.resolution_y = 380
    scn.render.image_settings.file_format = 'WEBP'
    scn.render.image_settings.quality = 82
    arm.animation_data.action = bpy.data.actions[action]
    viser(cam, Vector(cfg['pos']), Vector(cfg['cible']))
    dossier = os.path.join(SP, vue)
    if not os.path.isdir(dossier):
        os.makedirs(dossier)
    for i in range(images):
        scn.frame_set(i + 1)
        scn.render.filepath = os.path.join(dossier, 'f%04d' % (i + 1))
        bpy.ops.render.render(write_still=True)
    return dossier


def rendre(vue, action, images):
    scn = bpy.context.scene
    arm = bpy.data.objects['Armature']
    cam = bpy.data.objects['Camera']
    if cam.animation_data:
        cam.animation_data_clear()
    cam.data.lens = 52.0
    scn.camera = cam
    scn.render.resolution_x = 640
    scn.render.resolution_y = 380
    scn.render.image_settings.file_format = 'WEBP'
    scn.render.image_settings.quality = 82
    scn.render.film_transparent = False
    arm.animation_data.action = bpy.data.actions[action]
    off, zc = VUES[vue]
    off = Vector(off)
    dossier = os.path.join(SP, vue)
    if not os.path.isdir(dossier):
        os.makedirs(dossier)
    for i in range(images):
        f = i + 1
        scn.frame_set(f)
        bpy.context.view_layer.update()
        B = arm.matrix_world @ arm.pose.bones['CC_Base_Pelvis'].head
        # la camera suit l'avancement mais PAS les oscillations : elle ne
        # reprend que le deplacement moyen, sinon le tangage du bassin se
        # retrouve dans l'image et masque justement ce qu'on veut juger.
        centre = Vector((0.0, B.y, zc))
        viser(cam, centre + off, centre)
        scn.render.filepath = os.path.join(dossier, 'f%04d' % f)
        bpy.ops.render.render(write_still=True)
    return dossier
