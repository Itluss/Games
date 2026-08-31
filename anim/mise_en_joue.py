# -*- coding: utf-8 -*-
"""Mise en joue en marchant : le personnage marche arme haute, deplie les deux
   bras vers l'avant et vise un adversaire devant lui, puis continue a marcher
   en visee.

   Principe : on ne touche pas aux jambes ni au buste, qui continuent le cycle
   de marche. On anime uniquement la CIBLE de la crosse, qui passe de sa
   position de port (solidaire du buste) a une position de visee stabilisee
   dans le monde, alignee sur l'adversaire. Les bras sont resolus a chaque
   image pour suivre cette cible, et le meme ressort amorti qu'en marche
   donne au mouvement son inertie -- le bras ne se deplie pas en bloc, il
   accompagne, depasse legerement et se stabilise."""
import bpy, math, runpy
from mathutils import Vector, Matrix, Quaternion

SP = r"C:\Users\camille\AppData\Local\Temp\claude\c--Users-camille-Games\3c1de467-7e42-4715-976e-32086eff673b\scratchpad"
W2 = runpy.run_path(SP + r"\walk2.py")
A = W2['A']

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world
U = bpy.context.view_layer.update
head = A['head']; set_world = A['set_world']; reset = A['reset']
rot_about_head = A['rot_about_head']
P2 = W2['P2']

J = dict(
    cycles=3,                # duree totale, en cycles de marche
    debut=0.95,              # debut du depliement, en cycles
    duree=0.55,              # duree du depliement, en cycles (~0.6 s)
    portee=0.585,            # distance crosse - epaules en visee (m)
    # Hauteur de crosse. A 1.560 l'arme etait 8 cm AU-DESSUS de la ligne
    # d'epaule : l'avant-bras devait monter vers les mains alors que la main,
    # elle, pointe vers l'avant-bas (une crosse de pistolet est inclinee de
    # 16 deg). Les deux directions se contrariaient et le poignet encaissait
    # l'ecart -- 43 deg de cassure. A 1.470, juste sous l'epaule, l'avant-bras
    # et la main sont presque alignes.
    hauteur=1.430,
    clav_visee=6.0,         # protraction d'epaule en visee
    twist_visee=0.0,         # le buste se met face a la cible
    # Direction du coude en visee. Mesuree sous DEUX contraintes simultanees :
    # poignet le plus droit possible, et humerus a plus de 2 cm du torse. Sans
    # la seconde, l'optimum du poignet rentre le coude jusqu'au sternum -- il
    # passait meme au travers du buste pendant le depliement.
    # Le coude reste donc au niveau de l'epaule, ouvert vers l'exterieur.
    pole_visee_D=(-0.950, -0.294, 0.104),
    pole_visee_G=(0.897, -0.178, -0.405),
    # Retard de la reorientation du coude. La cible de la crosse part tout de
    # suite, mais tant que les mains sont encore devant la poitrine le bras est
    # replie et le coude n'a aucune raison d'avoir deja pris son orientation de
    # visee : l'imposer tot tordait le poignet a 75 deg au milieu du geste.
    # Le coude ne commence a s'ouvrir qu'apres 40 % du depliement.
    pole_retard=0.78,
    action='Marche_MiseEnJoue',
)


def build():
    N = P2['frames']
    fps = P2['fps']
    dt = 1.0 / fps
    TOT = int(N * J['cycles'])
    f0 = J['debut'] * N
    fd = J['duree'] * N

    # ---- 1) etat de reference : prise, doigts, crosse liee au buste
    W2['build_walk2']()                      # met en place le contexte
    ctx = P2['_ctx']
    fingers = ctx['fingers']
    grip_local = ctx['grip_local']
    grip_rot0 = ctx['grip_rot0']
    Rc0 = ctx['Rc0']
    rpole_port = Vector(ctx['rpole']); lpole_port = Vector(ctx['lpole'])
    # en visee les coudes ne sont pas verrouilles : ils restent legerement
    # flechis et tombent vers le bas, comme chez un tireur
    rpole_vis = Vector(J['pole_visee_D']); lpole_vis = Vector(J['pole_visee_G'])
    poser = P2['_poser']
    A['reset_swivel']()

    def melange(f):
        """0 = port arme haute, 1 = bras tendus en visee"""
        return W2['smooth']((f - f0) / fd)

    def cible(f, tau, Mc):
        """position et orientation de la crosse pour l'image f"""
        k = melange(f)
        # --- port : la crosse est solidaire du buste
        p_port = Mc @ grip_local
        Rc = Mc.to_3x3(); Rc.normalize()
        q_port = ((Rc @ Rc0.inverted()).to_quaternion() @ grip_rot0).normalized()
        if k <= 0.0:
            return p_port, q_port
        # --- visee : la crosse est calee dans le monde, sur l'axe de l'adversaire.
        # Elle ne suit plus les oscillations du corps : c'est le propre d'un
        # tireur, l'arme reste sur la cible pendant que le corps travaille dessous.
        y_corps = 0.0 if P2['in_place'] else -W2['avance'](tau)
        p_vis = Vector((0.0, y_corps - J['portee'], J['hauteur']))
        q_vis = Quaternion((1, 0, 0), 0.0)
        return p_port.lerp(p_vis, k), q_port.slerp(q_vis, k)

    # ---- 2) simulation du ressort sur toute la duree, avec pre-roll
    kk = P2['weapon_k']
    cc = 2.0 * math.sqrt(kk) * P2['weapon_damp']
    pos = None; vel = Vector((0, 0, 0)); rot = None
    traj = []
    # La simulation tourne TOUJOURS sur place, et on stocke l'ECART a la cible,
    # jamais la position absolue. Sinon le ressort court derriere un objectif
    # qui avance a 1 m/s et prend un retard permanent de 8 cm : l'arme se
    # retrouvait plaquee contre la poitrine, avant-bras dans le gilet, et la
    # phase de port ne coincidait plus avec l'animation de marche.
    _ip = P2['in_place']
    P2['in_place'] = True
    for i in range(-N, TOT + 1):
        f = max(0, i)
        tau = f / float(N)
        P2['_twist_scale'] = 1.0 - melange(f)
        A['P']['clavicle_deg'] = (ctx['clav_port']
                                  + (J['clav_visee'] - ctx['clav_port']) * melange(f))
        Mc = poser(tau)
        tgt, qt = cible(f, tau, Mc)
        if pos is None:
            pos = tgt.copy(); rot = qt.copy()
        else:
            vel += ((tgt - pos) * kk - vel * cc) * dt
            pos = pos + vel * dt
            rot = rot.slerp(qt, P2['weapon_rot_smooth']).normalized()
        if i >= 0:
            traj.append(((pos - tgt).copy(), rot.copy()))
    P2['in_place'] = _ip

    # ---- 3) cuisson
    scn = bpy.context.scene
    act = W2['new_action'](J['action'])
    scn.frame_start = 1; scn.frame_end = TOT + 1
    infos = {'coude_min': 999.0, 'coude_max': 0.0}
    for i in range(TOT + 1):
        fr = i + 1
        tau = i / float(N)
        scn.frame_set(fr)
        k = melange(i)
        # le buste se remet face a la cible et l'epaule avance : a regler AVANT
        # de poser le corps, sinon le reglage ne s'applique qu'a l'image suivante
        P2['_twist_scale'] = 1.0 - k
        A['P']['clavicle_deg'] = ctx['clav_port'] + (J['clav_visee'] - ctx['clav_port']) * k
        Mc = poser(tau)
        goff, gr = traj[i]
        tgt, _q = cible(i, tau, Mc)
        A['P']['grip_center'] = tgt + goff
        A['P']['grip_rot'] = gr.copy()
        A['apply_grip_rot']()
        XR, YR, ZR = A['hand_axes']('R', A['P']['r_palm_hint'])
        XL, YL, ZL = A['hand_axes']('L', A['P']['l_palm_hint'])
        # bras tendus : on passe au solveur qui teste la collision avec le
        # torse, l'epaule etant alors tres proche du buste
        # direction de coude interpolee, jamais rebalayee : mouvement continu
        r = J['pole_retard']
        kp = W2['smooth']((k - r) / (1.0 - r)) if k > r else 0.0
        A['solve_arm']('R', A['tfs'](*A['P']['r_wrist_tfs']), rpole_port.lerp(rpole_vis, kp))
        A['solve_arm']('L', A['tfs'](*A['P']['l_wrist_tfs']), lpole_port.lerp(lpole_vis, kp))
        set_world('CC_Base_R_Hand', A['mat3'](XR, YR, ZR), head('CC_Base_R_Hand'))
        set_world('CC_Base_L_Hand', A['mat3'](XL, YL, ZL), head('CC_Base_L_Hand'))
        for b, q in fingers.items():
            pb = ARM.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()
        for s in ('R', 'L'):
            S = head('CC_Base_%s_Upperarm' % s); E = head('CC_Base_%s_Forearm' % s)
            Wp = head('CC_Base_%s_Hand' % s)
            ang = math.degrees((S - E).angle(Wp - E))
            infos['coude_min'] = min(infos['coude_min'], ang)
            infos['coude_max'] = max(infos['coude_max'], ang)
        for b in W2['ALL']:
            pb = ARM.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=fr)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=fr)
    scn.frame_set(1)
    infos.update({'action': J['action'], 'images': TOT + 1,
                  'debut_geste_img': int(f0) + 1,
                  'fin_geste_img': int(f0 + fd) + 1,
                  'duree_geste_s': round(fd / fps, 2)})
    return infos
