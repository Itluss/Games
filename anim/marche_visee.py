# -*- coding: utf-8 -*-
"""Marche en visee : le personnage avance, bras deja deployes, arme pointee
   devant lui a l'horizontale.

   On ne reecrit rien : c'est exactement la mise en joue dont le fondu est
   force a 1 depuis la premiere image. Le buste reste face a la cible
   (_twist_scale = 0), l'epaule garde sa protraction de visee, et l'arme est
   calee en hauteur et en cap pendant que le corps travaille dessous -- ce sont
   les bras qui absorbent l'oscillation de la marche, comme chez un tireur qui
   se deplace. C'est ce qui distingue cette animation d'un simple port : ici la
   ligne de mire ne bouge pas, alors que le bassin monte et descend de 4 cm.

   Deux variantes, comme pour la marche arme haute :
     - sur place, 1 foulee, bouclable   -> pour le moteur
     - qui avance, 3 foulees            -> pour le rendu
"""
import runpy, os

SP = os.path.dirname(os.path.abspath(__file__))


def build(sur_place=True, cycles=1, action='Marche_Visee'):
    MJ = runpy.run_path(os.path.join(SP, 'mise_en_joue.py'))
    J = MJ['J']
    # fondu deja termine avant la premiere image : melange(f) = 1 partout
    J['debut'] = -20.0
    J['duree'] = 0.01
    J['cycles'] = cycles
    J['action'] = action
    MJ['P2']['in_place'] = sur_place
    infos = MJ['build']()
    infos['sur_place'] = sur_place
    return infos
