N_CYCLE = 34
# -*- coding: utf-8 -*-
"""Cycle de marche tactique, version souple.

   Ce qui manquait a la v1 et qui la rendait rigide :

   1. AMORTI D'IMPACT. Le centre de gravite ne suit pas une sinusoide : il chute
      vite juste apres l'attaque du talon (reponse a la charge, le genou flechit
      pour absorber) puis remonte lentement jusqu'au milieu d'appui. Sans ca la
      jambe travaille comme un baton.
   2. DECALAGE. Bassin, buste et tete ne bougent pas ensemble. Le buste suit le
      bassin avec quelques images de retard, la tete encore plus. C'est ce
      decalage qui empeche le corps de lire comme un seul bloc.
   3. INERTIE DE L'ARME. Les bras ne sont plus verrouilles sur le buste : la
      crosse suit une cible portee par le buste via un ressort amorti, donc elle
      retarde, depasse legerement et se stabilise. Les bras sont resolus a chaque
      image pour l'accompagner.

   S'y ajoutent une inclinaison laterale du buste vers la jambe d'appui et un
   leger jeu des clavicules, tous deux decales eux aussi."""
import bpy, math, runpy
from mathutils import Vector, Matrix, Quaternion

SP = r"C:\Users\camille\AppData\Local\Temp\claude\c--Users-camille-Games\3c1de467-7e42-4715-976e-32086eff673b\scratchpad"
A = runpy.run_path(SP + r"\pose_aim.py")
Cy = runpy.run_path(SP + r"\pose_carry.py")
K = runpy.run_path(SP + r"\rig_ik.py")

ARM = bpy.data.objects['Armature']
WEAPON = bpy.data.objects['Mesh_0']
MW = ARM.matrix_world
U = bpy.context.view_layer.update
head = A['head']; set_world = A['set_world']; reset = A['reset']
rot_about_head = A['rot_about_head']; solve_leg = A['solve_leg']; twist_bone = A['twist_bone']
CHEST = 'CC_Base_Spine02'

P2 = dict(
    # --- valeurs validees de la marche tactique
    fps=30, frames=34, repeats_sim=3,
    stride=1.15,             # foulee (m) : pas de 57,5 cm
    duty=0.58,               # part du cycle en appui -> 16 % de double appui
    plant_ahead=0.42,        # ou se pose le pied dans sa course d'appui
    foot_side=0.045,         # demi-ecartement des appuis (9 cm au total)
    foot_lift=0.105,         # hauteur de passage du pied
    anticip=0.82,
    calage_iter=8,           # iterations de calage de la hauteur de bassin            # part finale du vol ou le corps s'abaisse deja
    reach_guard=0.994,       # portee max de la jambe en vol
    vel_ripple=0.06,         # fluctuation de vitesse d'avance
    sway=0.021,
    pelvis_yaw=5.0, pelvis_roll=2.6, pelvis_pitch=1.2,
    epaules_niveau=0.70,     # part du roulis de bassin annulee aux epaules
    tete_niveau=0.75,        # idem pour la tete
    clav_swing=2.6,
    spine_counter=0.70,
    lag_spine=3, lag_head=5,
    heel_strike_deg=-13.0, toe_off_deg=32.0,
    toe_out_R=-5.0, toe_out_L=4.0,
    ball_len=0.165, heel_len=0.075,
    weapon_k=190.0, weapon_damp=0.80, weapon_rot_smooth=0.30,
    in_place=False,
    pole_R=None, pole_L=None,   # surchargent la direction de coude en port
    grip_fwd=0.0,               # avance la prise de port (degage l'avant-bras)
    grip_dz=-0.055,
    hip_drop=0.035, bob=0.045, load_dip=0.05,   # non utilises (hauteur deduite du genou)
    action_name='Marche_ArmeHaute',
)

LOWER = ['RL_BoneRoot', 'CC_Base_Hip', 'CC_Base_Pelvis', 'CC_Base_Waist',
         'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_NeckTwist01',
         'CC_Base_NeckTwist02', 'CC_Base_Head']
for s in ('R', 'L'):
    LOWER += ['CC_Base_%s_Thigh' % s, 'CC_Base_%s_Calf' % s, 'CC_Base_%s_Foot' % s,
              'CC_Base_%s_ToeBase' % s, 'CC_Base_%s_Clavicle' % s,
              'CC_Base_%s_Upperarm' % s, 'CC_Base_%s_Forearm' % s, 'CC_Base_%s_Hand' % s]
FINGERS = []
for s in ('R', 'L'):
    for f in ('Thumb', 'Index', 'Mid', 'Ring', 'Pinky'):
        FINGERS += ['CC_Base_%s_%s%d' % (s, f, i) for i in (1, 2, 3)]
ALL = LOWER + FINGERS


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def avance(tau):
    """Position d'avancement du corps. Elle n'est PAS lineaire : a la reception
       du pied la jambe avant freine le centre de gravite, puis la poussee de
       cheville le relance. Une vitesse constante donne une marche qui semble
       se bloquer a chaque appui."""
    k = P2['vel_ripple']
    return P2['stride'] * (tau - (k / (4.0 * math.pi))
                           * math.sin(4.0 * math.pi * (tau - 0.05)))


def courbe_genou(q):
    """Angle de flexion du genou de la jambe en appui, en degres, selon
       l'avancement q de sa phase d'appui. Reproduit la 'double action du
       genou' : presque tendu au contact, flechi pour amortir la reception,
       RE-TENDU en milieu d'appui, puis flechi pour le passage. C'est ce
       retour a l'extension qui rend la marche legere."""
    pts = ((0.00, 5.0), (0.09, 20.0), (0.28, 9.0), (0.55, 7.0),
           (0.80, 15.0), (1.00, 40.0))
    for i in range(len(pts) - 1):
        a, va = pts[i]
        b, vb = pts[i + 1]
        if q <= b:
            return va + (vb - va) * smooth((q - a) / (b - a))
    return pts[-1][1]


def hauteur_bassin(tau, sway, y_body, h0):
    """Hauteur de hanche imposee par la courbe de genou de la jambe portante.
       On n'impose plus une oscillation verticale arbitraire : le mouvement du
       bassin DECOULE de ce que fait le genou, comme dans la marche reelle."""
    l1 = P2['_l1']; l2 = P2['_l2']
    duty = P2['duty']
    tot_w = 0.0; tot_z = 0.0
    for side, phase in (('R', 0.0), ('L', 0.5)):
        p = (tau - phase) % 1.0
        att = False
        if p < duty:                       # --- jambe en appui
            q = p / duty
            knee = courbe_genou(q)
            # la charge quitte progressivement la jambe arriere pendant le
            # double appui : son exigence de hauteur s'efface d'autant
            w = 1.0 - smooth((q - 0.72) / 0.28) if q > 0.72 else 1.0
        else:                              # --- jambe en vol
            qs = (p - duty) / (1.0 - duty)
            a0 = P2['anticip']
            if qs < a0:
                continue
            # Fin de vol : le corps s'abaisse EN ANTICIPATION du contact.
            # On raisonne sur le POINT DE POSER, pas sur la position en l'air du
            # pied : sinon un pied haut fait remonter le bassin, la jambe
            # d'appui part en butee et le pied pose DECOLLE du sol.
            knee = courbe_genou(0.0)
            w = smooth((qs - a0) / (1.0 - a0))
            att = True
        if w <= 1e-4:
            continue
        kr = math.radians(knee)
        d = math.sqrt(max(1e-6, l1 * l1 + l2 * l2 - 2 * l1 * l2 * math.cos(math.pi - kr)))
        y, z, _ = foot_state(tau + (1.0 - p) if att else tau, phase)
        if att:
            z = 0.0
        if P2['in_place']:
            y += avance(tau)
        sgn = -1.0 if side == 'R' else 1.0
        dx = (sgn * P2['foot_side']) - (sgn * 0.09 + sway)
        dy = y - y_body
        horiz2 = dx * dx + dy * dy
        tot_z += w * ((0.118 + z) + math.sqrt(max(1e-6, d * d - horiz2)))
        tot_w += w
    return (tot_z / tot_w) if tot_w > 1e-6 else h0


def mesure_roulis_epaules():
    """inclinaison de la ligne d'epaules par rapport a l'horizontale (deg)"""
    U()
    R = MW @ ARM.pose.bones['CC_Base_R_Upperarm'].head
    L = MW @ ARM.pose.bones['CC_Base_L_Upperarm'].head
    return math.degrees(math.atan2(L.z - R.z, L.x - R.x))


def mesure_roulis_tete():
    """roulis de la tete autour de l'axe d'avance (deg)"""
    U()
    M = (MW @ ARM.pose.bones['CC_Base_Head'].matrix).to_3x3()
    M.normalize()
    up = M @ Vector((0, 1, 0))
    return math.degrees(math.atan2(up.x, up.z))


def vert(tau):
    """Deplacement vertical du bassin, 2 fois par cycle, profil asymetrique :
       creux marque juste apres l'attaque du talon, remontee douce."""
    p = (2.0 * tau) % 1.0
    # Le corps est au PLUS BAS juste apres l'attaque du talon (le genou encaisse)
    # et au PLUS HAUT en milieu d'appui, quand la jambe porteuse est tendue sous
    # le bassin. L'inverse donne un personnage qui se souleve a chaque reception.
    q = (p - P2['load_dip']) % 1.0
    if q < 0.30:
        k = smooth(q / 0.30)          # remontee vers le milieu d'appui
    else:
        k = 1.0 - smooth((q - 0.30) / 0.70)   # redescente, plus longue
    return P2['bob'] * k


def foot_state(tau, phase):
    S = P2['stride']; duty = P2['duty']
    # Le pied ne se pose PAS a mi-course de sa phase d'appui. Chez l'humain il
    # se pose assez pres du bassin et finit loin derriere : la jambe arriere
    # s'allonge grace a la poussee de cheville, alors que la jambe avant, elle,
    # doit rester atteignable sans que le corps s'enfonce. Repartir 50/50
    # obligeait a accroupir le personnage.
    half = duty * S * P2['plant_ahead']
    p = (tau - phase) % 1.0
    n = math.floor(tau - phase)
    y_plant = -S * (n + phase) - half
    a0 = math.radians(23.0)
    if p < duty:
        y = y_plant; z = 0.0; q = p / duty
        if q < 0.12:
            pitch = P2['heel_strike_deg'] * (1.0 - smooth(q / 0.12))
            th = math.radians(-pitch)
            z = P2['heel_len'] * ((1.0 - math.cos(th)) + math.sin(th) * 0.35)
        elif q < 0.76:
            pitch = 0.0
        else:
            # Poussee de cheville. Elle ACCELERE jusqu'au decollement : c'est
            # l'instant le plus rapide du pas. Un lissage classique (smooth)
            # s'aplatit au contraire a la fin, et la cheville cessait de monter
            # alors que le pied continuait a reculer -- la jambe se rallongeait
            # de 6 mm sur la derniere image d'appui, d'ou un sursaut du genou.
            u = (q - 0.76) / 0.24
            pitch = P2['toe_off_deg'] * u ** 1.7
            th = math.radians(pitch)
            # Le pied roule sur le coussinet : la cheville decrit un arc autour
            # de lui, elle monte ET avance. Sans ce deuxieme terme la cheville
            # restait figee a son extension maximale.
            z = P2['ball_len'] * (math.sin(a0 + th) - math.sin(a0))
            y = y_plant - P2['ball_len'] * (math.cos(a0) - math.cos(a0 + th))
    else:
        q = (p - duty) / (1.0 - duty)
        # trajectoire cycloidale : le pied part lentement (le genou se plie et
        # ramene le talon sous le bassin), balaye vite au milieu, puis freine
        # avant de se poser. Un simple lissage donnait un pied qui avance a
        # vitesse constante, d'ou une jambe raide.
        # A la sortie d'appui le pied pivote deja sur la pointe : sa cheville
        # monte ET avance. Une cycloide pure la laissait immobile en arriere,
        # donc hors de portee de la jambe, qui se verrouillait en butee.
        y = y_plant - S * (1.0 - (1.0 - q) ** 2.2)
        z = P2['foot_lift'] * math.sin(math.pi * q ** 0.72) ** 0.9
        if q < 0.35:
            pitch = P2['toe_off_deg'] * (1.0 - smooth(q / 0.35))
        else:
            pitch = P2['heel_strike_deg'] * smooth((q - 0.35) / 0.65)
        if pitch > 0:
            th = math.radians(pitch)
            z = max(z, P2['ball_len'] * (math.sin(a0 + th) - math.sin(a0)))
            # meme arc qu'en fin d'appui, pour que la cheville ne saute pas au
            # passage appui -> vol
            y -= P2['ball_len'] * (math.cos(a0) - math.cos(a0 + th))
        else:
            th = math.radians(-pitch)
            z = max(z, P2['heel_len'] * ((1.0 - math.cos(th)) + math.sin(th) * 0.35))
    return y, z, pitch


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


def build_walk2(repeats=1):
    global N_CYCLE
    global N_CYCLE
    scn = bpy.context.scene
    scn.render.fps = P2['fps']
    N = P2['frames']
    N_CYCLE = N
    dt = 1.0 / P2['fps']

    # ---------- 1) pose de port : elle fixe la prise, les doigts et la crosse.
    # On applique les parametres sur NOTRE instance de pose_aim : chaque script
    # charge sa propre copie du module, passer par pose_carry ecrirait ailleurs.
    C = Cy['C']
    P = A['P']
    P['grip_rot'] = (Quaternion((0, 1, 0), math.radians(C['roll_deg']))
                     @ Quaternion((0, 0, 1), math.radians(C['yaw_deg']))
                     @ Quaternion((1, 0, 0), math.radians(C['tilt_deg'])))
    P['grip_center'] = (Vector(C['grip_center'])
                        + Vector((0, -P2['grip_fwd'], P2['grip_dz'])))
    P['r_pole'] = tuple(P2.get('pole_R') or C['r_pole'])
    P['l_pole'] = tuple(P2.get('pole_L') or C['l_pole'])
    for key in ('hip_fwd', 'lean', 'r_ankle', 'l_ankle', 'r_knee_dir', 'l_knee_dir',
                'r_foot_deg', 'l_foot_deg', 'clavicle_deg', 'spine_twist_deg'):
        P[key] = C[key]
    P['hip_drop'] = C['hip_drop']
    A['build']()
    K['parent_weapon']()
    U()
    fingers = {b: ARM.pose.bones[b].rotation_quaternion.copy() for b in FINGERS}
    rpole = Vector(A['P']['r_pole']); lpole = Vector(A['P']['l_pole'])
    carry_twist = A['P'].get('spine_twist_deg', 0.0)
    lean = A['P']['lean']
    grip_rot0 = A['P']['grip_rot'].copy()
    Mc0 = (MW @ ARM.pose.bones[CHEST].matrix)
    Rc0 = Mc0.to_3x3(); Rc0.normalize()
    grip_local = Mc0.inverted() @ Vector(A['P']['grip_center'])

    for b in LOWER:
        reset(b)
    U()
    root_rest = (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).translation.copy()
    # references geometriques de la jambe, mesurees au repos
    P2['_h0'] = head('CC_Base_R_Thigh').z
    P2['_l1'] = (head('CC_Base_R_Calf') - head('CC_Base_R_Thigh')).length
    P2['_l2'] = (head('CC_Base_R_Foot') - head('CC_Base_R_Calf')).length
    # courbe de hauteur de bassin, precalculee sur le cycle puis LISSEE.
    # Le lissage est circulaire, donc la boucle reste exacte.
    brut = []
    for i in range(N):
        t = i / float(N)
        sw = -P2['sway'] * math.sin(2 * math.pi * t)
        yb = 0.0 if P2['in_place'] else -avance(t)
        brut.append(hauteur_bassin(t, sw, yb, P2['_h0']))
    noyau = (1.0, 4.0, 6.0, 4.0, 1.0)
    P2['_hz'] = [sum(wj * brut[(i + j - 2) % N] for j, wj in enumerate(noyau)) / sum(noyau)
                 for i in range(N)]
    # courbe de hauteur de bassin, precalculee sur le cycle puis lissee
    brut = []
    for i in range(N):
        t = i / float(N)
        sw = -P2['sway'] * math.sin(2 * math.pi * t)
        yb = 0.0 if P2['in_place'] else -avance(t)
        brut.append(hauteur_bassin(t, sw, yb, P2['_h0']))
    noyau = (1.0, 4.0, 6.0, 4.0, 1.0)
    liss = []
    for i in range(N):
        acc = 0.0
        for j, wj in enumerate(noyau):
            acc += wj * brut[(i + j - 2) % N]
        liss.append(acc / sum(noyau))
    P2['_hz'] = liss

    # ---------- 2) corps + colonne pour une image donnee, puis cible d'arme
    def poser_corps(tau):
        for b in LOWER:
            reset(b)
        U()
        adv = avance(tau)
        tl_s = tau - P2['lag_spine'] / float(N)      # buste en retard
        tl_h = tau - P2['lag_head'] / float(N)       # tete encore plus
        y_body = 0.0 if P2['in_place'] else -adv
        sway = -P2['sway'] * math.sin(2 * math.pi * tau)
        # la hauteur du bassin n'est plus une courbe imposee : elle est deduite
        # de l'angle de genou voulu sur la jambe portante
        z_hanche = hauteur_bassin(tau, sway, y_body, P2['_h0'])
        set_world('RL_BoneRoot', (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).to_3x3().normalized(),
                  root_rest + Vector((sway, y_body, z_hanche - P2['_h0'])))
        yaw = -P2['pelvis_yaw'] * math.sin(2 * math.pi * tau)
        roll = P2['pelvis_roll'] * math.sin(2 * math.pi * tau)
        pitch = P2['pelvis_pitch'] * math.sin(4 * math.pi * tau)
        Mw = MW @ ARM.pose.bones['CC_Base_Hip'].matrix
        R = Mw.to_3x3(); R.normalize()
        set_world('CC_Base_Hip',
                  Matrix.Rotation(math.radians(yaw), 3, 'Z')
                  @ Matrix.Rotation(math.radians(roll), 3, 'Y')
                  @ Matrix.Rotation(math.radians(pitch), 3, 'X') @ R, Mw.translation)
        # --- calage fin de la hauteur de bassin sur la courbe lissee.
        # Pendant le double appui les deux jambes reclament des hauteurs
        # differentes et non monotones : leur moyenne ponderee zigzague de
        # +/- 5 mm, ce qui se voit comme un tremblement au poser du pied.
        # On precalcule la courbe sur le cycle et on la lisse circulairement,
        # ce qui conserve la boucle exacte.
        z_but = P2['_hz'][int(round(tau * N_CYCLE)) % N_CYCLE]
        for _ in range(P2['calage_iter']):
            HR = head('CC_Base_R_Thigh'); HL = head('CC_Base_L_Thigh')
            dz = z_but - (HR.z + HL.z) * 0.5
            if abs(dz) < 2e-5:
                break
            mroot = MW @ ARM.pose.bones['RL_BoneRoot'].matrix
            set_world('RL_BoneRoot', mroot.to_3x3().normalized(),
                      mroot.translation + Vector((0, 0, dz)))

        for side, phase, toe in (('R', 0.0, P2['toe_out_R']), ('L', 0.5, P2['toe_out_L'])):
            y, z, fpitch = foot_state(tau, phase)
            if P2['in_place']:
                y += adv
            sgn = -1.0 if side == 'R' else 1.0
            T = Vector((sgn * P2['foot_side'], y, 0.118 + z))
            # garde de portee : si la cible sort du rayon de la jambe, le
            # solveur verrouillerait le genou a 5 deg -- c'est le "claquement".
            # On rapproche la cible pour que le genou reste libre.
            # ... uniquement en phase de VOL : en appui le pied doit rester
            # exactement ou il est pose, quitte a tendre la jambe.
            if ((tau - phase) % 1.0) >= P2['duty']:
                H = head('CC_Base_%s_Thigh' % side)
                Lmax = (P2['_l1'] + P2['_l2']) * P2['reach_guard']
                dv = T - H
                if dv.length > Lmax:
                    T = H + dv * (Lmax / dv.length)
            solve_leg(side, T, Vector((sgn * 0.06, -0.998, 0.0)))
            fb = 'CC_Base_%s_Foot' % side
            cur = (MW @ ARM.pose.bones[fb].tail) - head(fb)
            d0 = (Matrix.Rotation(math.radians(toe), 3, 'Z')
                  @ Matrix.Rotation(math.radians(fpitch), 3, 'X') @ Vector((0, -0.92, -0.39)))
            rot_about_head(fb, cur, d0)
            if fpitch > 0.5:
                tb = 'CC_Base_%s_ToeBase' % side
                cur2 = (MW @ ARM.pose.bones[tb].tail) - head(tb)
                axis = Vector((math.cos(math.radians(toe)), math.sin(math.radians(toe)), 0))
                rot_about_head(tb, cur2, Matrix.Rotation(math.radians(-fpitch), 3, axis) @ cur2)
        # colonne : inclinaison vers l'avant
        for bn, part in (('CC_Base_Waist', 0.3), ('CC_Base_Spine01', 0.35), ('CC_Base_Spine02', 0.35)):
            cur = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            tgt = Matrix.Rotation(math.radians(lean * part), 3, 'X') @ cur
            rot_about_head(bn, cur, tgt)
        # STABILISATION LATERALE. Le bassin bascule d'un pas a l'autre ; sans
        # compensation ce roulis remonte tel quel dans les epaules et la tete,
        # et c'est exactement ce qui donne le dandinement. On mesure le roulis
        # reel de la ligne d'epaules et on le corrige dans la colonne.
        for _ in range(2):
            r = mesure_roulis_epaules()
            if abs(r) < 0.05:
                break
            # attention : la mesure "ligne d'epaules" a la convention de signe
            # inverse de la mesure "axe vertical de la tete" plus bas
            corr = r * P2['epaules_niveau']
            for bn, part in (('CC_Base_Waist', 0.25), ('CC_Base_Spine01', 0.35),
                             ('CC_Base_Spine02', 0.40)):
                cur = (MW @ ARM.pose.bones[bn].tail) - head(bn)
                rot_about_head(bn, cur,
                               Matrix.Rotation(math.radians(corr * part), 3, 'Y') @ cur)
        # rotation axiale : port de l'arme + contre-rotation retardee
        yaw_lag = -P2['pelvis_yaw'] * math.sin(2 * math.pi * tl_s)
        # _twist_scale permet de remettre le buste face a la cible pendant
        # la mise en joue, sans toucher au reste du cycle
        tw = carry_twist * P2.get('_twist_scale', 1.0) - P2['spine_counter'] * yaw_lag
        twist_bone('CC_Base_Spine01', tw * 0.4)
        twist_bone('CC_Base_Spine02', tw * 0.6)
        yaw_h = -P2['pelvis_yaw'] * math.sin(2 * math.pi * tl_h)
        twh = carry_twist * P2.get('_twist_scale', 1.0) - P2['spine_counter'] * yaw_h
        twist_bone('CC_Base_NeckTwist01', -twh * 0.5)
        twist_bone('CC_Base_NeckTwist02', -twh * 0.5)
        for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0, Matrix.Rotation(math.radians(-lean * 0.5), 3, 'X') @ d0)
        # la tete est le segment le plus stabilise du corps : on annule son roulis
        for _ in range(2):
            r = mesure_roulis_tete()
            if abs(r) < 0.05:
                break
            corr = -r * P2['tete_niveau']
            for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
                d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
                rot_about_head(bn, d0, Matrix.Rotation(math.radians(corr * 0.5), 3, 'Y') @ d0)
        # clavicules : protraction de base + petit jeu decale
        sw = P2['clav_swing'] * math.sin(2 * math.pi * tl_s)
        for s_, sg in (('R', -1), ('L', 1)):
            h = head('CC_Base_%s_Clavicle' % s_)
            dirv = head('CC_Base_%s_Upperarm' % s_) - h
            ang = A['P']['clavicle_deg'] * sg + (sw if s_ == 'R' else -sw)
            rot_about_head('CC_Base_%s_Clavicle' % s_, dirv,
                           Matrix.Rotation(math.radians(ang), 3, 'Z') @ dirv)
        Mc = MW @ ARM.pose.bones[CHEST].matrix
        return Mc

    # runpy renvoie une COPIE des globals du module : on passe la fonction
    # par le dictionnaire P2, qui lui est partage par reference.
    P2['_poser'] = poser_corps
    P2['_ctx'] = dict(fingers=fingers, rpole=rpole, lpole=lpole,
                      grip_local=grip_local, grip_rot0=grip_rot0, Rc0=Rc0,
                      clav_port=A['P']['clavicle_deg'])

    # ---------- 3) simulation : l'arme suit le buste par un ressort amorti
    TOT = N * P2['repeats_sim']
    k = P2['weapon_k']
    c = 2.0 * math.sqrt(k) * P2['weapon_damp']
    pos = None; vel = Vector((0, 0, 0)); rot = None
    traj = []
    # la simulation tourne toujours sur place : une vitesse d'avance constante ne
    # doit produire aucun retard, seules les accelerations du corps en creent
    _ip = P2['in_place']
    P2['in_place'] = True
    for i in range(TOT):
        tau = i / float(N)
        Mc = poser_corps(tau)
        target = Mc @ grip_local
        Rc = Mc.to_3x3(); Rc.normalize()
        qt = ((Rc @ Rc0.inverted()).to_quaternion() @ grip_rot0).normalized()
        if pos is None:
            pos = target.copy(); rot = qt.copy()
        else:
            vel += ((target - pos) * k - vel * c) * dt
            pos = pos + vel * dt
            rot = rot.slerp(qt, P2['weapon_rot_smooth']).normalized()
        if i >= TOT - N:
            # on stocke l'ECART a la cible, pas la position absolue : ainsi le
            # retard reste valable quel que soit l'avancement du personnage
            traj.append(((pos - target).copy(), rot.copy()))

    P2['in_place'] = _ip

    # ---------- 4) cuisson
    A['reset_swivel']()
    act = new_action(P2['action_name'])
    TOTB = N * repeats
    scn.frame_start = 1; scn.frame_end = TOTB + 1
    XR = YR = ZR = XL = YL = ZL = None
    ecart_arme = []
    for i in range(TOTB + 1):
        f = i + 1
        idx = i % N
        tau = i / float(N)
        scn.frame_set(f)
        Mc = poser_corps(tau)
        goff, gr = traj[idx]
        gp = (Mc @ grip_local) + goff
        A['P']['grip_center'] = gp.copy()
        A['P']['grip_rot'] = gr.copy()
        A['apply_grip_rot']()
        XR, YR, ZR = A['hand_axes']('R', A['P']['r_palm_hint'])
        XL, YL, ZL = A['hand_axes']('L', A['P']['l_palm_hint'])
        # Direction de coude FIXE. Un solveur qui rebalaye l'orbite du coude a
        # chaque image choisit parfois un autre optimum d'une image a l'autre :
        # le coude part alors en soubresauts. Ici la direction est constante,
        # donc le mouvement est continu par construction ; c'est le reglage des
        # poles qui garantit le degagement du torse.
        A['solve_arm']('R', A['tfs'](*A['P']['r_wrist_tfs']), rpole)
        A['solve_arm']('L', A['tfs'](*A['P']['l_wrist_tfs']), lpole)
        set_world('CC_Base_R_Hand', A['mat3'](XR, YR, ZR), head('CC_Base_R_Hand'))
        set_world('CC_Base_L_Hand', A['mat3'](XL, YL, ZL), head('CC_Base_L_Hand'))
        for b, q in fingers.items():
            pb = ARM.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()
        ecart_arme.append(((Mc @ grip_local) - gp).length)
        for b in ALL:
            pb = ARM.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=f)
    scn.frame_set(1)
    return {'images': TOTB + 1, 'fps': P2['fps'],
            'duree_s': round(N / float(P2['fps']), 2),
            'vitesse_m_s': round(P2['stride'] / (N / float(P2['fps'])), 2),
            'longueur_pas_cm': round(P2['stride'] / 2 * 100, 1),
            'cadence': round(2 * 60.0 / (N / float(P2['fps']))),
            'retard_arme_mm': round(max(ecart_arme) * 1000, 1),
            'action': P2['action_name']}
