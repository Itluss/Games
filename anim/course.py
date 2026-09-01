# -*- coding: utf-8 -*-
"""Cycle de course, arme dans la seule main droite.

   Ce n'est PAS la marche acceleree. Deux choses changent de nature :

   1. Le mouvement vertical du bassin est en OPPOSITION DE PHASE. En marche le
      bassin est au plus haut en milieu d'appui (le corps bascule par-dessus une
      jambe tendue) et au plus bas en double appui. En course c'est l'inverse :
      au plus bas en milieu d'appui, quand le genou flechit a 40 deg pour
      amortir la reception, et au plus haut en plein vol. La fonction
      hauteur_bassin() de walk2.py, qui DEDUIT la hauteur de hanche de ce que
      reclame la jambe portante, n'a donc aucun sens ici -- et en plus elle
      n'aurait aucun contributeur pendant le vol, ou aucun pied ne touche.
      Ici la courbe est ecrite : compression sinusoidale en appui, parabole
      balistique en vol.

   2. Il n'y a plus de double appui du tout. La sequence est appui droit, vol,
      appui gauche, vol. Chaque jambe est au sol 36 % du cycle, et il reste
      2 x 14 % pendant lesquels les deux pieds sont en l'air.

   Le reste suit : cadence 180 pas/min contre 106, genou jusqu'a 110 deg en vol
   contre 59, attaque medio-pied au lieu du talon, buste incline de 11 deg,
   coudes a 90 deg qui poussent vraiment.

   Les bras sont en cinematique directe, pas en IK : une main libre n'a pas de
   cible, elle est portee par l'epaule et le coude. L'arme suit la main droite
   par le parentage d'os deja en place.
"""
import bpy, math, os, runpy
from mathutils import Vector, Matrix, Quaternion

SP = os.path.dirname(os.path.abspath(__file__))
A = runpy.run_path(os.path.join(SP, 'pose_aim.py'))
W2 = runpy.run_path(os.path.join(SP, 'walk2.py'))

ARM = bpy.data.objects['Armature']
MW = ARM.matrix_world
MWi = MW.inverted()
U = bpy.context.view_layer.update
head = A['head']; set_world = A['set_world']; reset = A['reset']
rot_about_head = A['rot_about_head']; twist_bone = A['twist_bone']
solve_leg = A['solve_leg']; mat3 = A['mat3']
smooth = W2['smooth']; LOWER = W2['LOWER']; FINGERS = W2['FINGERS']; ALL = W2['ALL']
CHEST = 'CC_Base_Spine02'

C = dict(
    fps=30,
    frames=20,              # 20 images/cycle a 30 fps = 180 pas/min
    stride=2.40,            # avance par cycle (m) -> 3,6 m/s, pas de 120 cm
    duty=0.34,              # part du cycle en appui, PAR jambe. 2 x 0.34 = 0.68,
                            # il reste 32 % de vol, en deux fois. Aucun double appui.
    # Ou le pied se pose dans sa course sous le corps. C'est ce parametre qui
    # partage la course du pied en appui (duty x stride) entre l'avant et
    # l'arriere. Trop haut : le genou reste flechi au contact et le pied tombe
    # DERRIERE le genou -- posture d'educatif, pas de course. Trop bas : la
    # jambe se tend trop tot et freine. A 0.34 avec une foulee de 2,40 m on a
    # 29,8 deg de genou au contact, le pied sous le genou, et surtout la cuisse
    # descend a -18,7 deg derriere : la jambe traine enfin.
    plant_ahead=0.34,
    foot_side=0.028,        # appuis presque sur une ligne
    foot_lift=0.30,         # hauteur de remontee du talon pendant le vol
    lift_peak=0.48,         # exposant : sommet du talon tot dans le vol
    # Profil d'avancee du pied en vol. A 2.6 le pied atteignait 99 % de sa
    # course avant des 84 % du vol, puis restait tendu devant pendant que le
    # bassin passait au sommet de sa parabole : la jambe devait couvrir plus
    # que sa longueur et le solveur figeait le genou a 14 deg pendant quatre
    # images. Un exposant plus bas etale l'avancee sur tout le vol.
    swing_exp=1.10,
    # Depassement avant du pied au milieu du vol. Sans lui le pied monte en
    # arriere (talon-fesse) et redescend sans jamais repasser sous la hanche :
    # la cuisse plafonnait a 46 deg de flexion, la foulee ne s'ouvrait pas.
    # Avec, le pied passe devant au milieu du vol -- le genou monte -- puis
    # revient legerement en arriere avant le contact, ce qui est exactement le
    # geste d'un coureur : le pied recule par rapport au corps a la pose, sinon
    # il freine a chaque foulee.
    swing_overshoot=0.02,
    hip_comp=0.042,         # abaissement du bassin en milieu d'appui (m)
    hip_air=0.024,          # gain balistique en plein vol (m)
    hip_base=0.048,         # abaissement moyen : on court genoux flechis
    # Inclinaison du buste. La valeur est un ANGLE DE COMMANDE reparti sur le
    # bassin et les trois vertebres ; l'inclinaison reellement mesuree entre le
    # bassin et la nuque vaut a peu pres la moitie. 22 donne 11,8 deg reels.
    lean=22.0,
    lean_hip=6.0,           # part prise par le bassin (bascule anterieure)
    pelvis_yaw=8.0,         # rotation du bassin, plus ample qu'en marche
    pelvis_roll=3.2,
    spine_counter=0.85,     # contre-rotation des epaules
    lag_spine=2, lag_head=3,
    epaules_niveau=0.75, tete_niveau=0.80,
    # --- bras
    bras_swing=38.0,        # amplitude avant/arriere de l'humerus (deg)
    bras_avance=8.0,        # decalage moyen vers l'avant (course = bras devant)
    bras_ouvert=25.0,       # ecartement lateral des coudes
    # Retard de l'avant-bras sur l'humerus, en images. Sans lui les deux
    # segments tournent d'un bloc et le bras parait rigide : c'est ce decalage
    # qui donne le fouette. La main arrive donc apres l'epaule, comme un fleau.
    avant_bras_retard=1.6,
    clav_swing=4.5,         # l'epaule avance et recule avec le bras
    # Cant de la main gauche : inclinaison de la normale de paume autour de
    # l'axe de l'avant-bras. 0 = paume strictement vers l'axe du corps.
    main_G_cant=18.0,
    # Poing de la main libre. Un coureur ne serre pas : les doigts sont replies
    # sans force et le pouce repose sur l'index. Les valeurs sont (MCP, PIP,
    # DIP) par doigt, en degres de flexion.
    poing_G=(('Index', (62, 74, 38)), ('Mid', (66, 78, 40)),
             ('Ring', (68, 80, 42)), ('Pinky', (70, 82, 44)),
             ('Thumb', (34, 40, 26))),
    # Garde anatomique de la cheville, en degres (angle tibia-pied ; 90 au
    # repos). Le pied est oriente dans le repere MONDE, ce qui va tant que le
    # genou reste modere : a 124 deg de flexion le tibia part en arriere et le
    # pied se repliait dessus jusqu'a 7,5 deg -- il s'ecrasait litteralement
    # contre le tibia. On borne donc l'angle apres coup.
    cheville_min=74.0,
    cheville_max=138.0,
    # Profil de cheville PENDANT LE VOL, en angle tibia-pied. Se contenter de
    # borner donnait un pied colle a sa butee sur la moitie du cycle, donc
    # raide. Ici il suit son propre mouvement : encore pousse au decollement,
    # pointe relevee au passage sous le bassin pour ne pas racler, puis
    # redescendue juste avant le contact medio-pied.
    cheville_vol=((0.00, 132.0), (0.28, 84.0), (0.62, 92.0), (1.00, 102.0)),
    coude_moy=88.0,         # flexion moyenne du coude (deg)
    coude_amp=22.0,         # le coude se ferme quand la main monte devant
    bras_phase=0.06,        # les bras devancent legerement les jambes
    avance_D=1.0,           # le bras arme monte moins devant que le bras libre
    # Coude du bras arme, regle a part. A 110 deg de flexion en avant du
    # balancement l'avant-bras pointait vers le haut et le canon avec lui :
    # aucune correction de poignet ne pouvait rattraper 90 deg d'ecart.
    coude_moy_D=68.0,
    coude_amp_D=10.0,
    # --- tenue de l'arme pendant la course
    # Sans contrainte, le poignet garde son orientation figee par rapport a
    # l'avant-bras : au milieu du balancement le canon montait a +77 deg
    # d'elevation et -131 deg de lacet, c'est-a-dire que l'arme balayait la
    # tete du personnage. On impose donc une direction de canon, et le poignet
    # la rattrape dans la limite de ce qu'un poignet sait faire.
    canon_elev=-14.0,       # elevation visee du canon (deg, negatif = vers le bas)
    canon_lat=12.0,         # ouverture laterale du canon (deg, vers l'exterieur)
    poignet_max=42.0,       # correction maximale autorisee au poignet (deg)
    # --- pied
    mid_strike_deg=6.0,     # attaque medio-pied : pointe legerement basse
    toe_off_deg=38.0,
    ball_len=0.165, heel_len=0.075,
    toe_out_R=-4.0, toe_out_L=3.0,
    # Hauteur de cheville qui pose la semelle sur le sol. Calee sur la valeur
    # de la marche : prendre la hauteur de cheville AU REPOS (0.1108) enfonce
    # l'orteil de 7 mm sous le sol, le repos n'etant pas une pose plantee.
    ankle_z=0.1187,
    # Garde au sol de la jambe libre, exprimee sur l'OS de l'orteil. Le
    # maillage du pied descend 5 a 7,5 cm sous cet os selon l'orientation :
    # un seuil de quelques millimetres n'attrapait donc rien. La garde
    # s'eteint sur le dernier tiers du vol, sinon elle empecherait la pose.
    garde_sol=0.080,
    calage_iter=8,
    reach_guard=0.992,
    in_place=False,
    action_name='Course',
)

N_CYCLE = 20


# ------------------------------------------------------------------ avancement
def avance(tau):
    """En course la vitesse d'avance est bien plus reguliere qu'en marche : il
       n'y a pas de jambe avant tendue qui freine le corps a chaque reception."""
    return C['stride'] * tau


# ------------------------------------------------------- hauteur du bassin
def hauteur_bassin(tau):
    """Ecart de hauteur du bassin par rapport a sa reference, en metres.

       Un demi-cycle = un appui puis un vol. u est la position dans le
       demi-cycle. La compression d'appui et la parabole de vol valent toutes
       deux zero a la jonction, donc la courbe est continue et periodique par
       construction -- pas besoin de la recoller."""
    ds = C['duty'] / 0.5                      # part du DEMI-cycle passee en appui
    u = (tau % 0.5) / 0.5
    if u < ds:
        q = u / ds
        # creux d'amortissement, minimum vers 44 % de l'appui
        return -C['hip_comp'] * math.sin(math.pi * q ** 0.85)
    v = (u - ds) / (1.0 - ds)
    # vol : parabole balistique, sommet au milieu
    return C['hip_air'] * 4.0 * v * (1.0 - v)


def courbe_cheville(q):
    """angle tibia-pied voulu pendant le vol, interpole en douceur"""
    pts = C['cheville_vol']
    q = max(0.0, min(1.0, q))
    for i in range(len(pts) - 1):
        a, va = pts[i]; b, vb = pts[i + 1]
        if q <= b:
            u = smooth((q - a) / (b - a)) if b > a else 0.0
            return va + (vb - va) * u
    return pts[-1][1]


# ------------------------------------------------------------- trajectoire pied
def foot_state(tau, phase):
    """Position de la cheville et tangage du pied.
       phase 0.0 = jambe droite, 0.5 = jambe gauche."""
    S = C['stride']; duty = C['duty']
    half = duty * S * C['plant_ahead']
    p = (tau - phase) % 1.0
    n = math.floor(tau - phase)
    y_plant = -S * (n + phase) - half
    a0 = math.radians(23.0)
    if p < duty:
        # ---------------- appui
        q = p / duty
        y = y_plant; z = 0.0
        if q < 0.18:
            # attaque medio-pied : le pied est deja presque a plat, il ne
            # deroule pas depuis le talon comme en marche
            pitch = C['mid_strike_deg'] * (1.0 - smooth(q / 0.18))
            th = math.radians(pitch)
            z = C['ball_len'] * (math.sin(a0 + th) - math.sin(a0))
            y = y_plant - C['ball_len'] * (math.cos(a0) - math.cos(a0 + th))
        elif q < 0.62:
            pitch = 0.0
        else:
            # poussee : elle accelere jusqu'au decollement, et la cheville
            # decrit un arc autour du coussinet -- elle monte ET avance
            u = (q - 0.62) / 0.38
            pitch = C['toe_off_deg'] * u ** 1.6
            th = math.radians(pitch)
            z = C['ball_len'] * (math.sin(a0 + th) - math.sin(a0))
            y = y_plant - C['ball_len'] * (math.cos(a0) - math.cos(a0 + th))
    else:
        # ---------------- vol
        q = (p - duty) / (1.0 - duty)
        # Le pied part vite vers l'arriere-haut (le talon claque sous la fesse)
        # puis se ramene sous le corps. Il ne se tend jamais loin devant : en
        # course il se pose presque a l'aplomb du bassin.
        f = ((1.0 - (1.0 - q) ** C['swing_exp'])
             + C['swing_overshoot'] * math.sin(math.pi * q) ** 2)
        y = y_plant - S * f
        z = C['foot_lift'] * math.sin(math.pi * q ** C['lift_peak']) ** 1.3
        if q < 0.30:
            pitch = C['toe_off_deg'] * (1.0 - smooth(q / 0.30))
        else:
            pitch = C['mid_strike_deg'] * smooth((q - 0.30) / 0.70)
        th = math.radians(pitch)
        zp = C['ball_len'] * (math.sin(a0 + th) - math.sin(a0))
        if zp > z:
            z = zp
        y -= C['ball_len'] * (math.cos(a0) - math.cos(a0 + th))
    return y, z, pitch


def new_action(name):
    return W2['new_action'](name)


# ----------------------------------------------------------------- construction
def build_course(repeats=1):
    global N_CYCLE
    scn = bpy.context.scene
    scn.render.fps = C['fps']
    N = C['frames']; N_CYCLE = N

    # ---------- 1) prise : on rejoue la pose de port pour recuperer la prise de
    # la main droite, les doigts et le parentage de l'arme. Seule la main droite
    # tient l'arme en course, mais la prise elle-meme ne change pas.
    Cy = runpy.run_path(os.path.join(SP, 'pose_carry.py'))
    K = runpy.run_path(os.path.join(SP, 'rig_ik.py'))
    Cc = Cy['C']; P = A['P']
    P['grip_rot'] = (Quaternion((0, 1, 0), math.radians(Cc['roll_deg']))
                     @ Quaternion((0, 0, 1), math.radians(Cc['yaw_deg']))
                     @ Quaternion((1, 0, 0), math.radians(Cc['tilt_deg'])))
    P['grip_center'] = Vector(Cc['grip_center'])
    for key in ('hip_fwd', 'r_ankle', 'l_ankle', 'r_knee_dir', 'l_knee_dir',
                'r_foot_deg', 'l_foot_deg', 'clavicle_deg'):
        P[key] = Cc[key]
    P['r_pole'] = tuple(Cc['r_pole']); P['l_pole'] = tuple(Cc['l_pole'])
    P['lean'] = Cc['lean']; P['hip_drop'] = Cc['hip_drop']; P['spine_twist_deg'] = 0.0
    A['build']()
    K['parent_weapon']()
    U()
    doigts_D = {b: ARM.pose.bones[b].rotation_quaternion.copy()
                for b in FINGERS if '_R_' in b}
    # main droite : on retient son orientation RELATIVE a l'avant-bras, pour que
    # le poignet reste naturel quand le bras balance librement
    Rf = (MW @ ARM.pose.bones['CC_Base_R_Forearm'].matrix).to_3x3(); Rf.normalize()
    Rh = (MW @ ARM.pose.bones['CC_Base_R_Hand'].matrix).to_3x3(); Rh.normalize()
    main_D_locale = Rf.inverted() @ Rh
    # axe du canon, exprime dans le repere de l'os de la main : l'arme y est
    # rigidement parentee, donc cette direction ne change plus
    ARME = bpy.data.objects['Mesh_0']
    bore_monde = (-ARME.matrix_world.to_3x3().normalized().col[0]).normalized()
    bore_local = (Rh.inverted() @ bore_monde).normalized()

    for b in ALL:
        reset(b)
    U()
    root_rest = (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).translation.copy()
    Rc0 = (MW @ ARM.pose.bones[CHEST].matrix).to_3x3(); Rc0.normalize()
    h0 = (head('CC_Base_R_Thigh').z + head('CC_Base_L_Thigh').z) * 0.5
    l1 = (head('CC_Base_R_Calf') - head('CC_Base_R_Thigh')).length
    l2 = (head('CC_Base_R_Foot') - head('CC_Base_R_Calf')).length
    C['_h0'] = h0; C['_l1'] = l1; C['_l2'] = l2
    z_sol = C['ankle_z']

    # main gauche : poing relache de coureur, ni ouvert ni serre
    curl = A['curl']
    doigts_G = {}
    for f, ang in C['poing_G']:
        for i, a_ in enumerate(ang, start=1):
            b = 'CC_Base_L_%s%d' % (f, i)
            curl(b, a_, 'L')
            doigts_G[b] = ARM.pose.bones[b].rotation_quaternion.copy()
    for b in FINGERS:
        reset(b)
    U()

    # ---------- 2) pose du corps pour une image
    def poser(tau):
        for b in LOWER:
            reset(b)
        U()
        adv = avance(tau)
        y_body = 0.0 if C['in_place'] else -adv
        tl_s = tau - C['lag_spine'] / float(N)
        tl_h = tau - C['lag_head'] / float(N)
        z_but = h0 - C['hip_base'] + hauteur_bassin(tau)
        set_world('RL_BoneRoot',
                  (MW @ ARM.pose.bones['RL_BoneRoot'].matrix).to_3x3().normalized(),
                  root_rest + Vector((0.0, y_body, z_but - h0)))
        yaw = -C['pelvis_yaw'] * math.sin(2 * math.pi * tau)
        roll = C['pelvis_roll'] * math.sin(2 * math.pi * tau)
        Mw = MW @ ARM.pose.bones['CC_Base_Hip'].matrix
        R = Mw.to_3x3(); R.normalize()
        set_world('CC_Base_Hip',
                  Matrix.Rotation(math.radians(yaw), 3, 'Z')
                  @ Matrix.Rotation(math.radians(roll), 3, 'Y')
                  @ Matrix.Rotation(math.radians(C['lean_hip']), 3, 'X') @ R,
                  Mw.translation)
        # calage : la hauteur de hanche visee est une COURBE ECRITE, pas une
        # deduction de la jambe portante -- c'est toute la difference avec la
        # marche, ou le bassin est au plus haut quand ici il est au plus bas.
        for _ in range(C['calage_iter']):
            dz = z_but - (head('CC_Base_R_Thigh').z + head('CC_Base_L_Thigh').z) * 0.5
            if abs(dz) < 2e-5:
                break
            mr = MW @ ARM.pose.bones['RL_BoneRoot'].matrix
            set_world('RL_BoneRoot', mr.to_3x3().normalized(),
                      mr.translation + Vector((0, 0, dz)))

        # ---------- jambes
        for side, phase, toe in (('R', 0.0, C['toe_out_R']), ('L', 0.5, C['toe_out_L'])):
            y, z, fpitch = foot_state(tau, phase)
            if C['in_place']:
                y += adv
            sgn = -1.0 if side == 'R' else 1.0
            fb = 'CC_Base_%s_Foot' % side
            tb = 'CC_Base_%s_ToeBase' % side
            en_vol = ((tau - phase) % 1.0) >= C['duty']
            releve = 0.0
            # Garde au sol de la jambe libre. Abaisser la hauteur de talon fait
            # passer la pointe SOUS le plancher : le pied ne pivote pas autour
            # de sa cheville comme le suppose la trajectoire. On mesure donc la
            # pointe et on remonte la cheville de l'exces, en deux passes.
            for _essai in range(3 if en_vol else 1):
                T = Vector((sgn * C['foot_side'], y, z_sol + z + releve))
                if en_vol:
                    H = head('CC_Base_%s_Thigh' % side)
                    Lmax = (l1 + l2) * C['reach_guard']
                    dv = T - H
                    if dv.length > Lmax:
                        T = H + dv * (Lmax / dv.length)
                solve_leg(side, T, Vector((sgn * 0.05, -0.999, 0.0)))
                cur = (MW @ ARM.pose.bones[fb].tail) - head(fb)
                d0 = (Matrix.Rotation(math.radians(toe), 3, 'Z')
                      @ Matrix.Rotation(math.radians(fpitch), 3, 'X')
                      @ Vector((0, -0.92, -0.39)))
                rot_about_head(fb, cur, d0)
                if not en_vol:
                    break
                bas = min((MW @ ARM.pose.bones[tb].matrix
                           @ Vector((0, ARM.data.bones[tb].length, 0))).z,
                          head(tb).z)
                q_g = (((tau - phase) % 1.0) - C['duty']) / (1.0 - C['duty'])
                seuil = C['garde_sol'] * (1.0 - smooth((q_g - 0.66) / 0.34))
                manque = seuil - bas
                if manque < 1e-4:
                    break
                releve += manque
            # --- cheville : profil impose en vol, garde anatomique en appui
            K = head('CC_Base_%s_Calf' % side); F = head(fb)
            vers_genou = (K - F).normalized()
            pied = ((MW @ ARM.pose.bones[fb].tail) - F).normalized()
            chev = math.degrees(vers_genou.angle(pied))
            # En APPUI on ne touche a rien : c'est le sol qui impose
            # l'orientation du pied, et l'angle de cheville qui en resulte est
            # physiologique -- un coureur atteint reellement 60 deg en milieu
            # d'appui. Vouloir l'y brider enfoncait la pointe de 4 cm dans le sol.
            lim = None
            p_ = (tau - phase) % 1.0
            if p_ >= C['duty']:
                q_ = (p_ - C['duty']) / (1.0 - C['duty'])
                # Le profil ne prend pas la main d'un coup : juste apres le
                # decollement le pied rase encore le sol, lui imposer 132 deg
                # de flexion plantaire y replantait la pointe de 4 cm.
                w = smooth(q_ / 0.20)
                lim = chev + (courbe_cheville(q_) - chev) * w
            if lim is not None:
                ax = vers_genou.cross(pied)
                if ax.length > 1e-6:
                    rot_about_head(fb, pied,
                                   Matrix.Rotation(math.radians(lim - chev), 3,
                                                   ax.normalized()) @ pied)
            # le deroule d'orteil n'a de sens qu'en appui ; en vol il ferait
            # pivoter la pointe dans le vide
            if fpitch > 0.5 and ((tau - phase) % 1.0) < C['duty']:
                tb = 'CC_Base_%s_ToeBase' % side
                c2 = (MW @ ARM.pose.bones[tb].tail) - head(tb)
                ax = Vector((math.cos(math.radians(toe)), math.sin(math.radians(toe)), 0))
                rot_about_head(tb, c2, Matrix.Rotation(math.radians(-fpitch), 3, ax) @ c2)

        # ---------- colonne : inclinaison vers l'avant, nettement plus marquee
        lean_buste = C['lean'] - C['lean_hip']
        for bn, part in (('CC_Base_Waist', 0.30), ('CC_Base_Spine01', 0.35),
                         ('CC_Base_Spine02', 0.35)):
            cur = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, cur,
                           Matrix.Rotation(math.radians(lean_buste * part), 3, 'X') @ cur)
        for _ in range(2):
            r = W2['mesure_roulis_epaules']()
            if abs(r) < 0.05:
                break
            corr = r * C['epaules_niveau']
            for bn, part in (('CC_Base_Waist', 0.25), ('CC_Base_Spine01', 0.35),
                             ('CC_Base_Spine02', 0.40)):
                cur = (MW @ ARM.pose.bones[bn].tail) - head(bn)
                rot_about_head(bn, cur,
                               Matrix.Rotation(math.radians(corr * part), 3, 'Y') @ cur)
        yaw_lag = -C['pelvis_yaw'] * math.sin(2 * math.pi * tl_s)
        tw = -C['spine_counter'] * yaw_lag
        twist_bone('CC_Base_Spine01', tw * 0.4)
        twist_bone('CC_Base_Spine02', tw * 0.6)
        yaw_h = -C['pelvis_yaw'] * math.sin(2 * math.pi * tl_h)
        twh = -C['spine_counter'] * yaw_h
        twist_bone('CC_Base_NeckTwist01', -twh * 0.5)
        twist_bone('CC_Base_NeckTwist02', -twh * 0.5)
        # le regard reste a l'horizontale alors que le buste est penche
        for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
            d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
            rot_about_head(bn, d0,
                           Matrix.Rotation(math.radians(-lean_buste * 0.55), 3, 'X') @ d0)
        for _ in range(2):
            r = W2['mesure_roulis_tete']()
            if abs(r) < 0.05:
                break
            corr = -r * C['tete_niveau']
            for bn in ('CC_Base_NeckTwist01', 'CC_Base_NeckTwist02'):
                d0 = (MW @ ARM.pose.bones[bn].tail) - head(bn)
                rot_about_head(bn, d0,
                               Matrix.Rotation(math.radians(corr * 0.5), 3, 'Y') @ d0)

        # ---------- bras, en cinematique directe
        # Une main libre n'a pas de cible : elle est portee par l'epaule et le
        # coude. Le bras droit balance moins que le gauche -- il porte l'arme.
        Rc = (MW @ ARM.pose.bones[CHEST].matrix).to_3x3(); Rc.normalize()
        dRc = Rc @ Rc0.inverted()
        ta = tau + C['bras_phase']
        op = math.radians(C['bras_ouvert'])
        for side, sgn, sens, mult in (('R', -1.0, -1.0, 0.78), ('L', 1.0, 1.0, 1.0)):
            av = C['avance_D'] if side == 'R' else C['bras_avance']
            a = math.radians(av
                             + sens * C['bras_swing'] * mult * math.cos(2 * math.pi * ta))
            # direction de l'humerus : vers le bas, balancee d'avant en arriere,
            # et un peu ecartee du corps
            d_hum = dRc @ Vector((sgn * math.sin(op),
                                  -math.sin(a) * math.cos(op),
                                  -math.cos(a) * math.cos(op)))
            # l'epaule accompagne le bras : sans elle le buste est une planche
            cb = 'CC_Base_%s_Clavicle' % side
            dcl = head('CC_Base_%s_Upperarm' % side) - head(cb)
            rot_about_head(cb, dcl,
                           Matrix.Rotation(math.radians(-sens * C['clav_swing']
                                                        * math.cos(2 * math.pi * ta)),
                                           3, 'Z') @ dcl)
            ub = 'CC_Base_%s_Upperarm' % side
            cur = (MW @ ARM.pose.bones[ub].tail) - head(ub)
            rot_about_head(ub, cur, d_hum)
            # Coude : il se ferme quand la main passe devant, et il est EN
            # RETARD sur l'humerus. Sans ce retard les deux segments tournent
            # d'un bloc et le bras parait rigide -- c'est le decalage qui donne
            # le fouette du bras de coureur.
            tf = ta - C['avant_bras_retard'] / float(N)
            if side == 'R':
                flex = C['coude_moy_D'] + sens * C['coude_amp_D'] * math.cos(2 * math.pi * tf)
            else:
                flex = C['coude_moy'] + sens * C['coude_amp'] * math.cos(2 * math.pi * tf)
            lat = (dRc @ Vector((1.0, 0.0, 0.0))).normalized()
            d_fore = Matrix.Rotation(math.radians(-flex), 3, lat) @ d_hum
            fb2 = 'CC_Base_%s_Forearm' % side
            cur = (MW @ ARM.pose.bones[fb2].tail) - head(fb2)
            rot_about_head(fb2, cur, d_fore)
        U()
        # main droite : orientation rendue relative a l'avant-bras, la prise
        # sur l'arme reste donc exactement celle de la pose de port
        # Main gauche. Elle n'etait pas pilotee du tout : elle heritait du
        # roulis produit par la rotation minimale appliquee a l'avant-bras, et
        # la normale de paume tournait dans tous les sens au fil du cycle.
        # On la construit donc : l'os prolonge l'avant-bras, et la paume
        # regarde vers l'axe du corps, comme un poing de coureur.
        Ef = head('CC_Base_L_Forearm'); Hf = head('CC_Base_L_Hand')
        Yh = (Hf - Ef).normalized()
        med = dRc @ Vector((-math.cos(math.radians(C['main_G_cant'])), 0.0,
                            math.sin(math.radians(C['main_G_cant']))))
        Xh = (med - Yh * med.dot(Yh)).normalized()
        set_world('CC_Base_L_Hand', mat3(Xh, Yh, Xh.cross(Yh)), Hf)

        Rf2 = (MW @ ARM.pose.bones['CC_Base_R_Forearm'].matrix).to_3x3(); Rf2.normalize()
        Rh_nat = Rf2 @ main_D_locale
        # Direction de canon voulue, exprimee dans le repere du buste pour
        # qu'elle suive l'inclinaison et la rotation du tronc.
        el = math.radians(C['canon_elev']); la = math.radians(C['canon_lat'])
        but = (dRc @ Vector((-math.sin(la) * math.cos(el),
                             -math.cos(la) * math.cos(el),
                             math.sin(el)))).normalized()
        bore = (Rh_nat @ bore_local).normalized()
        ecart = bore.angle(but)
        if ecart > 1e-4:
            ax = bore.cross(but)
            if ax.length > 1e-6:
                # on ne corrige que dans la limite de ce qu'un poignet accepte :
                # au-dela l'arme continue de suivre le bras, mais elle ne pointe
                # plus jamais vers la tete
                ecart = min(ecart, math.radians(C['poignet_max']))
                Rh_nat = Matrix.Rotation(ecart, 3, ax.normalized()) @ Rh_nat
        set_world('CC_Base_R_Hand', Rh_nat, head('CC_Base_R_Hand'))
        U()
        return MW @ ARM.pose.bones[CHEST].matrix

    C['_poser'] = poser
    C['_doigts_G'] = doigts_G
    C['_doigts_D'] = doigts_D

    # ---------- 3) cuisson
    act = new_action(C['action_name'])
    TOT = N * repeats
    scn.frame_start = 1; scn.frame_end = TOT + 1
    for i in range(TOT + 1):
        f = i + 1
        scn.frame_set(f)
        poser(i / float(N))
        for b, q in doigts_D.items():
            pb = ARM.pose.bones[b]; pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        for b, q in doigts_G.items():
            pb = ARM.pose.bones[b]; pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q.copy()
        U()
        for b in ALL:
            pb = ARM.pose.bones[b]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if b == 'RL_BoneRoot':
                pb.keyframe_insert('location', frame=f)
    scn.frame_set(1)
    return {'action': C['action_name'], 'images': TOT + 1,
            'cadence_pas_min': round(2 * 60.0 * C['fps'] / N, 1),
            'vitesse_m_s': round(C['stride'] * C['fps'] / N, 2),
            'longueur_de_pas_cm': round(C['stride'] * 50, 1),
            'vol_pct': round((1.0 - 2 * C['duty']) * 100, 1)}
