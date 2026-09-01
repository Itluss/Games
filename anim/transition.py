# -*- coding: utf-8 -*-
"""Transitions marche <-> course.

   Le probleme n'est pas de fondre deux poses, c'est de fondre deux CADENCES.
   La marche fait 34 images par cycle a 1,0 m/s, la course 20 images a 3,6 m/s :
   un fondu entre deux cycles joues chacun a son rythme ferait se battre les
   pieds, l'un posant quand l'autre decolle.

   D'ou un COMPTEUR DE PHASE : au lieu de lire chaque generateur a son propre
   tau, on accumule une phase commune dont l'increment vaut 1/n_cycle, ou
   n_cycle glisse de 34 a 20 images. Les deux generateurs sont alors toujours
   interroges au MEME endroit de leur cycle -- meme pied devant, meme moment
   d'appui -- et le fondu ne porte plus que sur la forme du mouvement.

   L'avancee est integree a part, depuis la vitesse instantanee, et non lue
   dans les generateurs : c'est ce qui permet d'accelerer continument au lieu
   de sauter d'une vitesse a l'autre.

   Les deux extremites sont EXACTES : a k=0 la pose est celle du generateur de
   marche, a k=1 celle du generateur de course.

   Fondre des ROTATIONS ne preserve toutefois ni le contact au sol ni le point
   d'appui : les deux generateurs plantent le pied a des endroits differents,
   et le premier essai donnait 2,25 cm d'enfoncement et 17,4 cm de glissement
   en une image. D'ou le VERROUILLAGE DE PIED : a chaque image on identifie le
   pied porteur, et on recale la racine pour que sa pointe reste exactement la
   ou elle a ete posee. L'avancee du personnage devient alors la consequence
   de ses appuis, et non plus une integration independante -- ce qui est
   l'ordre physique correct.

   Reste un point dur : la marche garde un pied au sol 58 % du cycle, la course
   34 %. Il existe donc une fenetre, entre les deux, ou un generateur pose le
   pied pendant que l'autre le decolle -- fondre la ces deux poses n'a aucun
   sens et produisait 11,5 cm de recalage en une image. Le fondu n'avance donc
   QUE dans les fenetres ou les deux generateurs s'accordent sur l'etat des
   deux jambes ; ailleurs il attend. C'est ce qui rend la transition possible
   sans reecrire un moteur de locomotion parametrique complet.
"""
import bpy, math, os, runpy
from mathutils import Vector, Quaternion

SP = os.path.dirname(os.path.abspath(__file__))

T = dict(
    fps=30,
    images=18,              # duree de la transition
    action_acc='Transition_MarcheCourse',
    action_dec='Transition_CourseMarche',
)


def _charger():
    """instancie les deux generateurs, sur place, et renvoie leurs poseurs"""
    W2 = runpy.run_path(os.path.join(SP, 'walk2.py'))
    W2['P2']['in_place'] = True
    W2['P2']['action_name'] = '__transition_tmp_marche'
    W2['build_walk2'](repeats=1)
    CO = runpy.run_path(os.path.join(SP, 'course.py'))
    CO['C']['in_place'] = True
    CO['C']['action_name'] = '__transition_tmp_course'
    CO['build_course'](repeats=1)
    for n in ('__transition_tmp_marche', '__transition_tmp_course'):
        if n in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[n])
    return W2, CO


def _capture(arm, os_):
    """On releve la racine en coordonnees MONDE : les unites locales d'os
       dependent de l'echelle 0,01 de l'armature, source d'erreurs de 100x."""
    d = {}
    for b in os_:
        d[b] = arm.pose.bones[b].rotation_quaternion.copy()
    m = arm.matrix_world @ arm.pose.bones['RL_BoneRoot'].matrix
    d['__monde'] = m.translation.copy()
    d['__rot'] = m.to_3x3().normalized()
    return d


def _accord(tau, duty_m, duty_c):
    """1 si les deux generateurs s'accordent sur l'etat des DEUX jambes
       (appui ou vol), 0 dans la fenetre ou ils se contredisent."""
    for ph in (0.0, 0.5):
        p = (tau - ph) % 1.0
        if duty_c <= p < duty_m:
            return 0.0
    return 1.0


def build(sens='acc', images=None, phase0=0.0, action=None):
    """sens 'acc' : marche -> course. 'dec' : course -> marche.
       Renvoie la phase finale et l'avancee totale, pour l'enchainement."""
    arm = bpy.data.objects['Armature']
    scn = bpy.context.scene
    U = bpy.context.view_layer.update
    W2, CO = _charger()
    poser_m = W2['P2']['_poser']
    poser_c = CO['C']['_poser']
    ALL = W2['ALL']
    smooth = W2['smooth']
    Nm = float(W2['P2']['frames'])          # images par cycle en marche
    Nc = float(CO['C']['frames'])           # ... et en course
    vm = W2['P2']['stride'] * T['fps'] / Nm  # vitesse de marche (m/s)
    vc = CO['C']['stride'] * T['fps'] / Nc   # vitesse de course
    doigts_c = CO['C']['_doigts_G']         # poing de coureur
    duty_m = W2['P2']['duty']; duty_c = CO['C']['duty']
    n = int(images or T['images'])
    # --- calendrier du fondu : on simule d'abord la phase pour savoir quand
    # les deux generateurs s'accordent, puis on repartit tout l'avancement du
    # fondu sur ces seules fenetres.
    ph_sim = phase0; poids = []
    for i in range(n + 1):
        poids.append(_accord(ph_sim, duty_m, duty_c))
        ph_sim += 1.0 / ((Nm + Nc) * 0.5)
    somme = sum(poids[:-1]) or 1.0
    ks = []; acc = 0.0
    for i in range(n + 1):
        ks.append(min(1.0, acc / somme))
        acc += poids[i]
    act = W2['new_action'](action or (T['action_acc'] if sens == 'acc' else T['action_dec']))
    scn.frame_start = 1
    scn.frame_end = n + 1
    dt = 1.0 / T['fps']
    phase = phase0
    avance = 0.0
    corr = Vector((0.0, 0.0, 0.0))     # recalage cumule de la racine
    porteur = None
    ancre = None
    glissement = 0.0
    infos = {'phase_debut': phase0}

    def pointe(side):
        pb = arm.pose.bones['CC_Base_%s_ToeBase' % side]
        return arm.matrix_world @ (pb.matrix @ Vector((0, pb.bone.length, 0)))
    for i in range(n + 1):
        f = i + 1
        k = smooth(ks[i])
        if sens == 'dec':
            k = 1.0 - k
        scn.frame_set(f)
        # --- pose de marche, puis pose de course, au MEME endroit du cycle
        poser_m(phase)
        pm = _capture(arm, ALL)
        poser_c(phase)
        pc = _capture(arm, ALL)
        # la main gauche de la course a son propre poing : il fait partie
        # de la pose a fondre, pas d'un reglage a part
        for b, q in doigts_c.items():
            pc[b] = q.copy()
        # --- fondu
        for b in ALL:
            pb = arm.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = pm[b].normalized().slerp(pc[b].normalized(), k)
        base = pm['__monde'].lerp(pc['__monde'], k) + Vector((0.0, avance, 0.0))
        W2['A']['set_world']('RL_BoneRoot', pm['__rot'], base + corr)
        U()
        # --- verrouillage du pied porteur
        pD = pointe('R'); pG = pointe('L')
        cote = 'R' if pD.z <= pG.z else 'L'
        p_act = pD if cote == 'R' else pG
        if cote != porteur:
            porteur = cote
            ancre = p_act.copy()
        else:
            d = Vector((0.0, ancre.y - p_act.y, ancre.z - p_act.z))
            glissement = max(glissement, d.length)
            corr = corr + d
            W2['A']['set_world']('RL_BoneRoot', pm['__rot'], base + corr)
            U()
        for b in ALL:
            pb = arm.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=f)
        # --- avancement de la phase a cadence glissante
        n_cycle = Nm + (Nc - Nm) * k
        v = vm + (vc - vm) * k
        phase += 1.0 / n_cycle
        avance -= v * dt
    scn.frame_set(1)
    infos.update({'action': act.name, 'images': n + 1,
                  'phase_fin': round(phase, 4),
                  'cycles_parcourus': round(phase - phase0, 3),
                  'avance_m': round(-(avance + corr.y), 3),
                  'recalage_max_mm': round(glissement * 1000, 1),
                  'vitesse_debut': round(vm if sens == 'acc' else vc, 2),
                  'vitesse_fin': round(vc if sens == 'acc' else vm, 2)})
    return infos
