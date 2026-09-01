# -*- coding: utf-8 -*-
"""Locomotion a vitesse variable : marche <-> course en continu.

   POURQUOI CE MODULE EXISTE
   Fondre deux cycles de locomotion par interpolation de poses ne marche pas.
   Un quaternion ne sait rien du sol : melanger la pose de marche et la pose de
   course donne un pied qui n'est plante ni la ou la marche le pose, ni la ou
   la course le pose. Mesure du premier essai : 2,3 cm d'enfoncement dans le
   sol, 17 cm de glissement en une image, et des vitesses negatives -- le
   personnage reculait. Verrouiller le pied apres coup ne fait que deplacer le
   probleme dans la racine, avec 13 cm de recalage par image.

   La cause est structurelle : la marche garde un pied au sol 58 % du cycle, la
   course 34 %. Entre les deux il existe une fenetre ou un generateur pose le
   pied pendant que l'autre le decolle. Aucun fondu ne peut reconcilier cela.

   CE QUE FAIT CE MODULE
   Les JAMBES sont recalculees, pas fondues. Un planificateur d'appuis suit ou
   chaque pied est reellement pose : quand une jambe entre en appui, on
   enregistre son point de pose dans le MONDE, et elle y reste jusqu'au
   decollement, quelle que soit l'evolution de la vitesse. La longueur de pas
   peut donc changer d'un pas a l'autre sans que le pied glisse.

   Le HAUT DU CORPS, lui, n'a aucune contrainte de contact : il est fondu entre
   les deux generateurs, ce qui conserve gratuitement le port d'arme a deux
   mains d'un cote et le balancement libre de l'autre.

   La hauteur de bassin est melangee entre les deux modeles, ce qui traverse
   proprement l'inversion de phase : au plus haut en milieu d'appui en marche,
   au plus bas en course.
"""
import bpy, math, os, runpy
from mathutils import Vector, Matrix, Quaternion

SP = os.path.dirname(os.path.abspath(__file__))

JAMBES = []
for s in ('R', 'L'):
    JAMBES += ['CC_Base_%s_Thigh' % s, 'CC_Base_%s_Calf' % s,
               'CC_Base_%s_Foot' % s, 'CC_Base_%s_ToeBase' % s]

L = dict(fps=30, calage_iter=8, reach_guard=0.992)


# Prise basse a deux mains, sur le cote droit, canon vers le bas. Reglee sous
# double contrainte : poignets assez proches pour que les deux mains tiennent
# vraiment la crosse, et avant-bras qui ne rentrent pas dans le ventre. Plus
# pres du corps les poignets se rejoignent mais les bras traversent ; plus
# loin les bras se degagent mais la butee de portee ecarte les mains.
PRISE_BASSE = dict(grip_center=(-0.150, -0.360, 1.185), tilt_deg=22.0)


def charger(carry_over=None):
    """instancie les deux generateurs, sur place.
       carry_over : port de l'arme pendant la marche. En sortie de course le
       personnage rassemble d'abord l'arme a deux mains EN BAS ; c'est cette
       pose-la qui doit etre la cible du ralentissement, pas le port haut."""
    W2 = runpy.run_path(os.path.join(SP, 'walk2.py'))
    W2['P2']['in_place'] = True
    W2['P2']['carry_over'] = carry_over
    W2['P2']['action_name'] = '__loco_tmp_m'
    W2['build_walk2'](repeats=1)
    CO = runpy.run_path(os.path.join(SP, 'course.py'))
    CO['C']['in_place'] = True
    CO['C']['action_name'] = '__loco_tmp_c'
    CO['build_course'](repeats=1)
    for n in ('__loco_tmp_m', '__loco_tmp_c'):
        if n in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[n])
    return W2, CO


class Loco(object):
    """Etat de locomotion. On l'avance image par image ; il pose l'armature et
       renvoie de quoi controler ce qu'il a fait."""

    def __init__(self, carry_over=None):
        self.W2, self.CO = charger(carry_over)
        A = self.W2['A']
        self.A = A
        self.arm = bpy.data.objects['Armature']
        self.MW = self.arm.matrix_world
        self.U = bpy.context.view_layer.update
        self.poser_m = self.W2['P2']['_poser']
        self.poser_c = self.CO['C']['_poser']
        self.ALL = self.W2['ALL']
        self.HAUT = [b for b in self.ALL if b not in JAMBES]
        self.smooth = self.W2['smooth']
        P2 = self.W2['P2']; C = self.CO['C']
        self.Nm = float(P2['frames']); self.Nc = float(C['frames'])
        self.Sm = P2['stride']; self.Sc = C['stride']
        self.vm = self.Sm * L['fps'] / self.Nm
        self.vc = self.Sc * L['fps'] / self.Nc
        self.dm = P2['duty']; self.dc = C['duty']
        self.pam = P2['plant_ahead']; self.pac = C['plant_ahead']
        self.doigts_c = C['_doigts_G']
        # geometrie de jambe, relevee au repos
        for b in self.ALL:
            A['reset'](b)
        self.U()
        hd = A['head']
        self.h0 = (hd('CC_Base_R_Thigh').z + hd('CC_Base_L_Thigh').z) * 0.5
        self.l1 = (hd('CC_Base_R_Calf') - hd('CC_Base_R_Thigh')).length
        self.l2 = (hd('CC_Base_R_Foot') - hd('CC_Base_R_Calf')).length
        self.z_ank = C['ankle_z']
        self.root_rest = (self.MW @ self.arm.pose.bones['RL_BoneRoot'].matrix).translation.copy()
        # etat courant
        self.phase = 0.0
        self.y = 0.0                       # position du corps (monde, -y = avant)
        self.appui = {'R': False, 'L': False}
        self.pose_y = {'R': None, 'L': None}    # ou le pied est plante
        self.decol_y = {'R': None, 'L': None}   # d'ou il est parti
        self.glissement = 0.0
        self.k = 0.0

    def changer_port(self, carry_over):
        """Change le port de l'arme sans perdre l'etat de locomotion : la
           phase, l'avancee et les appuis en cours sont conserves. C'est ce qui
           permet d'accelerer avec l'arme en haut puis de ralentir vers la
           prise basse, dans un seul mouvement continu."""
        W2 = runpy.run_path(os.path.join(SP, 'walk2.py'))
        W2['P2']['in_place'] = True
        W2['P2']['carry_over'] = carry_over
        W2['P2']['action_name'] = '__loco_port'
        W2['build_walk2'](repeats=1)
        if '__loco_port' in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions['__loco_port'])
        self.W2 = W2
        self.poser_m = W2['P2']['_poser']
        self.W2 = W2

    # ---------------------------------------------------------------- profils
    def _swing_f(self, q, k):
        """part du chemin parcouru par le pied en vol, 0 au decollement,
           1 au poser. Melange du profil de marche et de celui de course."""
        C = self.CO['C']
        fm = 1.0 - (1.0 - q) ** 2.2
        fc = ((1.0 - (1.0 - q) ** C['swing_exp'])
              + C['swing_overshoot'] * math.sin(math.pi * q) ** 2)
        return fm + (fc - fm) * k

    def _pas(self, k):
        """longueur d'un pas et fraction posee devant, a l'allure courante"""
        duty = self.dm + (self.dc - self.dm) * k
        stride = self.Sm + (self.Sc - self.Sm) * k
        pa = self.pam + (self.pac - self.pam) * k
        return duty, stride, pa

    # ------------------------------------------------------------------ image
    def image(self, k):
        """pose l'armature pour l'allure k (0 marche, 1 course)"""
        A = self.A; hd = A['head']; arm = self.arm; MW = self.MW
        self.k = k
        duty, stride, pa = self._pas(k)
        v = self.vm + (self.vc - self.vm) * k
        n_cycle = self.Nm + (self.Nc - self.Nm) * k
        dt = 1.0 / L['fps']
        tau = self.phase

        # --- 1) les deux poses de reference, au MEME endroit du cycle
        self.poser_m(tau)
        # poser_corps ne fait que le bas du corps et la colonne : sans cet
        # appel les bras restent au repos, donc en croix.
        self.W2['P2']['_bras'](tau)
        pm = {b: arm.pose.bones[b].rotation_quaternion.copy() for b in self.ALL}
        zm = (hd('CC_Base_R_Thigh').z + hd('CC_Base_L_Thigh').z) * 0.5
        rot_m = (MW @ arm.pose.bones['RL_BoneRoot'].matrix).to_3x3().normalized()
        ym, zzm, pim = {}, {}, {}
        for s, ph in (('R', 0.0), ('L', 0.5)):
            ym[s], zzm[s], pim[s] = self.W2['foot_state'](tau, ph)
        self.poser_c(tau)
        pc = {b: arm.pose.bones[b].rotation_quaternion.copy() for b in self.ALL}
        for b, q in self.doigts_c.items():
            pc[b] = q.copy()
        zc = (hd('CC_Base_R_Thigh').z + hd('CC_Base_L_Thigh').z) * 0.5
        yc, zzc, pic = {}, {}, {}
        for s, ph in (('R', 0.0), ('L', 0.5)):
            yc[s], zzc[s], pic[s] = self.CO['foot_state'](tau, ph)

        # --- 2) haut du corps : fondu pur, aucune contrainte de contact
        for b in self.HAUT:
            pb = arm.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = pm[b].normalized().slerp(pc[b].normalized(), k)
        self.U()

        # --- 3) racine : hauteur de bassin melangee entre les deux modeles.
        # C'est ici que se fait le passage de l'inversion de phase.
        z_but = zm + (zc - zm) * k
        A['set_world']('RL_BoneRoot', rot_m,
                       self.root_rest + Vector((0.0, self.y, z_but - self.h0)))
        for _ in range(L['calage_iter']):
            dz = z_but - (hd('CC_Base_R_Thigh').z + hd('CC_Base_L_Thigh').z) * 0.5
            if abs(dz) < 2e-5:
                break
            mr = MW @ arm.pose.bones['RL_BoneRoot'].matrix
            A['set_world']('RL_BoneRoot', mr.to_3x3().normalized(),
                           mr.translation + Vector((0, 0, dz)))

        # --- 4) jambes : planificateur d'appuis
        devant = pa * duty * stride            # ou le pied se pose devant le corps
        for s, ph, toe in (('R', 0.0, self.CO['C']['toe_out_R']),
                           ('L', 0.5, self.CO['C']['toe_out_L'])):
            p = (tau - ph) % 1.0
            en_appui = p < duty
            # hauteur et tangage : melange des deux generateurs, ce sont des
            # quantites locales (elevation au-dessus du sol, angle du pied)
            zl = zzm[s] + (zzc[s] - zzm[s]) * k
            pit = pim[s] + (pic[s] - pim[s]) * k
            if en_appui and not self.appui[s]:
                # nouvel appui : on enregistre le point de pose dans le MONDE
                self.pose_y[s] = self.y - devant
                self.appui[s] = True
            elif not en_appui and self.appui[s]:
                self.decol_y[s] = self.pose_y[s]
                self.appui[s] = False
            if self.pose_y[s] is None:
                self.pose_y[s] = self.y - devant
            # Le pied ROULE sur le coussinet en fin d'appui : la cheville
            # avance autour du point de contact. L'oublier fige la cheville
            # pendant que la pointe pivote, et elle s'enfonce de 3 cm.
            a0 = math.radians(23.0)
            ball = (self.W2['P2']['ball_len']
                    + (self.CO['C']['ball_len'] - self.W2['P2']['ball_len']) * k)
            dy_roul = 0.0
            if pit > 0.0:
                th = math.radians(pit)
                dy_roul = -ball * (math.cos(a0) - math.cos(a0 + th))
            if en_appui:
                y_pied = self.pose_y[s] + dy_roul
            else:
                q = (p - duty) / (1.0 - duty)
                # ou le corps sera au moment du poser, donc ou le pied doit aller
                t_reste = (1.0 - p) * n_cycle * dt
                y_land = (self.y - v * t_reste) - devant
                d0 = self.decol_y[s] if self.decol_y[s] is not None else self.pose_y[s]
                y_pied = d0 + (y_land - d0) * self._swing_f(q, k) + dy_roul
                self.pose_y[s] = y_pied - dy_roul
            sgn = -1.0 if s == 'R' else 1.0
            fs = self.W2['P2']['foot_side'] + (self.CO['C']['foot_side']
                                               - self.W2['P2']['foot_side']) * k
            tb = 'CC_Base_%s_ToeBase' % s
            releve = 0.0
            # Garde au sol de la jambe libre, mesuree sur l'OS de l'orteil : le
            # maillage du pied descend 5 a 7 cm sous cet os, un seuil en
            # millimetres n'attraperait rien. Elle s'eteint avant le poser.
            for _essai in range(3 if not en_appui else 1):
                T = Vector((sgn * fs, y_pied, self.z_ank + zl + releve))
                if not en_appui:
                    H = hd('CC_Base_%s_Thigh' % s)
                    Lmax = (self.l1 + self.l2) * L['reach_guard']
                    dv = T - H
                    if dv.length > Lmax:
                        T = H + dv * (Lmax / dv.length)
                A['solve_leg'](s, T, Vector((sgn * 0.05, -0.999, 0.0)))
                fb = 'CC_Base_%s_Foot' % s
                cur = (MW @ arm.pose.bones[fb].tail) - hd(fb)
                d0v = (Matrix.Rotation(math.radians(toe), 3, 'Z')
                       @ Matrix.Rotation(math.radians(pit), 3, 'X')
                       @ Vector((0, -0.92, -0.39)))
                A['rot_about_head'](fb, cur, d0v)
                if not en_appui:
                    qg = (p - duty) / (1.0 - duty)
                    seuil = 0.080 * (1.0 - self.smooth((qg - 0.66) / 0.34))
                    bas = min((MW @ arm.pose.bones[tb].matrix
                               @ Vector((0, arm.data.bones[tb].length, 0))).z,
                              hd(tb).z)
                    if seuil - bas < 1e-4:
                        break
                    releve += seuil - bas
                else:
                    break
            # garde de cheville : le genou monte beaucoup plus en course
            K = hd('CC_Base_%s_Calf' % s); F = hd(fb)
            vg = (K - F).normalized()
            pied = ((MW @ arm.pose.bones[fb].tail) - F).normalized()
            ch = math.degrees(vg.angle(pied))
            if not en_appui:
                q = (p - duty) / (1.0 - duty)
                cible = self.CO['courbe_cheville'](q)
                w = self.smooth(q / 0.20)
                lim = ch + (cible - ch) * w * k
                ax = vg.cross(pied)
                if ax.length > 1e-6 and abs(lim - ch) > 0.01:
                    A['rot_about_head'](fb, pied,
                                        Matrix.Rotation(math.radians(lim - ch), 3,
                                                        ax.normalized()) @ pied)
            # Contre-rotation de la pointe. La marche l'applique en appui ET en
            # vol, la course seulement en appui. L'omettre en vol laissait la
            # pointe alignee sur un pied flechi a 32 deg : elle plongeait de
            # 3 cm sous le sol. On la pondere donc par l'allure.
            if pit > 0.5:
                # appliquee PLEINEMENT, en appui comme en vol : la ponderer par
                # l'allure laissait la pointe a -0,6 cm sous le sol au milieu
                # de la transition.
                w_toe = 1.0
                if w_toe > 0.01:
                    tb = 'CC_Base_%s_ToeBase' % s
                    c2 = (MW @ arm.pose.bones[tb].tail) - hd(tb)
                    ax = Vector((math.cos(math.radians(toe)),
                                 math.sin(math.radians(toe)), 0))
                    A['rot_about_head'](tb, c2,
                                        Matrix.Rotation(math.radians(-pit * w_toe),
                                                        3, ax) @ c2)
        self.U()

        # --- 5) on avance, et la phase suit la cadence courante
        self.y -= v * dt
        self.phase += 1.0 / n_cycle
        return {'k': k, 'v': v, 'duty': duty, 'stride': stride, 'phase': tau}

    # ------------------------------------------------------------------ cuisson
    def cuire(self, segments, action='Locomotion', sur_place=False):
        """segments : liste de (k_debut, k_fin, nb_images).
           k = 0 marche, k = 1 course ; entre les deux l'allure glisse."""
        scn = bpy.context.scene
        arm = self.arm
        act = self.W2['new_action'](action)
        total = sum(s[2] for s in segments)
        scn.frame_start = 1
        scn.frame_end = total
        f = 0
        trace = []
        y0 = self.y
        for k0, k1, n in segments:
            for i in range(n):
                k = k0 + (k1 - k0) * self.smooth(i / float(max(1, n - 1))) if n > 1 else k0
                f += 1
                scn.frame_set(f)
                info = self.image(k)
                if sur_place:
                    mr = self.MW @ arm.pose.bones['RL_BoneRoot'].matrix
                    self.A['set_world']('RL_BoneRoot', mr.to_3x3().normalized(),
                                        mr.translation - Vector((0, self.y - y0, 0)))
                    self.U()
                info['img'] = f
                trace.append(info)
                for b in self.ALL:
                    pb = arm.pose.bones[b]
                    pb.keyframe_insert('rotation_quaternion', frame=f)
                    if b == 'RL_BoneRoot':
                        pb.keyframe_insert('location', frame=f)
        scn.frame_set(1)
        return {'action': act.name, 'images': total,
                'avance_m': round(-(self.y - y0), 2),
                'vitesse_min': round(min(t['v'] for t in trace), 2),
                'vitesse_max': round(max(t['v'] for t in trace), 2),
                'trace': trace}
