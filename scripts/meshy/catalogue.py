# -*- coding: utf-8 -*-
"""Catalogue des assets du POC port maritime.

   Ce fichier est la SOURCE de verite des prompts. Il produit
   assets/port_poc/prompts/meshy_prompts.json, qui est lui-meme lu par le
   generateur. On garde la forme Python parce qu'un prompt se compose : un
   socle commun, une partie propre a l'objet, et une liste d'interdits
   commune. Ecrire les 35 prompts a la main en JSON garantirait des
   divergences silencieuses entre eux.

   Chaque asset porte un identifiant STABLE : c'est lui qui sert de cle
   d'idempotence. Tant qu'un identifiant existe et que son fichier est
   valide sur disque, le generateur ne le relance pas.
"""
import json, os

RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SORTIE = os.path.join(RACINE, 'assets', 'port_poc', 'prompts', 'meshy_prompts.json')

# Socle commun. Il porte la direction artistique : un vrai terminal portuaire
# mediterraneen photographie en plein jour, pas un objet de jeu video.
SOCLE = ("contemporary European Mediterranean commercial seaport equipment, "
         "exact real-world proportions, photorealistic physically based materials, "
         "realistic manufacturing details, subtle natural wear, "
         "slight dirt accumulation, realistic roughness variation, "
         "authentic industrial construction, functional believable geometry, "
         "neutral daylight appearance, natural saturated realistic colors")

# Interdits communs. Les marques sont exclues explicitement : les marquages
# viendront plus tard sous forme de decals propres.
INTERDITS = ("no logos, no company names, no brand markings, no invented text, "
             "no lettering, no stylization, no cartoon proportions, "
             "no fantasy details, no game-art exaggeration, no military fortification, "
             "isolated single object, clean topology suitable for realtime game use")


def p(specifique):
    return "%s, %s, %s" % (specifique, SOCLE, INTERDITS)


# (id, nom, categorie, dimensions L x l x H en metres, lot, prompt specifique)
ASSETS = [

    # ---------------------------------------------------- A. couverts et modulaires
    ("port_barrier_jersey_01", "Barriere Jersey beton standard", "barriers",
     (3.0, 0.6, 0.81), "poc_test",
     "Standard precast concrete Jersey road barrier, single 3 meter section, "
     "trapezoidal profile with sloped base and flat top, cast concrete surface "
     "with visible formwork seams and small air bubbles, exposed steel lifting "
     "loop on top, light grey concrete with faint tyre scuffs along the lower "
     "slope, fine dust accumulation in the base corners, realistic concrete "
     "roughness with slight variation between faces"),

    ("port_barrier_jersey_worn_01", "Barriere Jersey beton usee", "barriers",
     (3.0, 0.6, 0.81), "poc_core",
     "Weathered precast concrete Jersey road barrier, single 3 meter section, "
     "trapezoidal profile, aged concrete with chipped edges exposing coarse "
     "aggregate, rust streaks running down from the embedded steel lifting "
     "loops, faded and partly worn horizontal paint band, dark grime settled "
     "in the lower slope, uneven weathering stronger on one side"),

    ("port_concrete_block_01", "Bloc beton industriel empilable", "barriers",
     (1.6, 0.8, 0.8), "poc_core",
     "Interlocking precast concrete block, rectangular Lego-style barrier block "
     "with moulded lugs on top and matching recesses underneath, rough cast "
     "concrete faces with formwork texture and small voids, two steel lifting "
     "anchors, chipped corners, grey concrete with mineral staining and dust"),

    ("port_concrete_wall_l_01", "Mur beton court en L", "barriers",
     (2.4, 0.9, 1.2), "poc_core",
     "Short precast L-shaped concrete retaining wall element, vertical panel "
     "with horizontal foot slab, smooth formed faces with visible casting seams "
     "and tie-rod holes, light grey concrete, dirt and gravel dust along the "
     "foot, minor edge chipping, realistic concrete roughness"),

    ("port_barrier_plastic_01", "Barriere plastique de chantier", "barriers",
     (2.0, 0.5, 1.0), "poc_core",
     "Water-fillable plastic road safety barrier, injection moulded high density "
     "polyethylene, interlocking end connectors, moulded ribs and fill cap on "
     "top, bright safety orange and white plastic, matte slightly chalky surface "
     "from sun exposure, scuffs and dust film, realistic plastic roughness"),

    ("port_fence_mesh_temp_01", "Grille metallique temporaire", "barriers",
     (3.5, 0.05, 2.0), "poc_core",
     "Temporary construction site mesh fence panel, galvanised steel tubular "
     "frame with welded wire mesh infill, sitting in two moulded concrete feet, "
     "bright zinc galvanised finish with dull patches, small rust spots at weld "
     "points, slightly bent mesh in one corner, thin realistic wire geometry"),

    ("port_barrier_pedestrian_01", "Barriere metallique pietonne", "barriers",
     (2.0, 0.4, 1.1), "poc_core",
     "Steel pedestrian crowd control barrier, tubular frame with vertical bars "
     "and folding feet, hot dip galvanised steel with matte grey finish, hooking "
     "loops at one end, scratched paint on the top rail, light rust at the foot "
     "welds, slight deformation from handling"),

    ("port_pallets_stack_01", "Palettes industrielles empilees", "cargo",
     (1.2, 0.8, 1.2), "poc_core",
     "Stack of about eight standard EUR wooden pallets, softwood boards with "
     "visible saw grain and nail heads, rounded worn edges, mixed board tones "
     "from grey weathering to fresh timber, dirt and scuffs on the bottom "
     "pallets, slightly irregular stacking, realistic wood roughness"),

    ("port_pallet_boxes_01", "Palette avec caisses industrielles", "cargo",
     (1.2, 0.8, 1.4), "poc_core",
     "Wooden EUR pallet loaded with stacked corrugated cardboard boxes wrapped "
     "in transparent stretch film, boxes slightly uneven and softly deformed, "
     "plain unprinted brown cardboard, film with realistic wrinkles and "
     "specular highlights, dust on the top surfaces, worn pallet underneath"),

    ("port_pallet_tarp_01", "Palette sous bache industrielle", "cargo",
     (1.2, 0.8, 1.3), "poc_core",
     "Wooden pallet load covered by a heavy industrial PVC tarpaulin, olive "
     "green coated fabric with realistic folds and sagging between the load "
     "edges, metal eyelets and black tie-down straps with ratchet buckles, "
     "faded fabric with dirt streaks and water stains, matte vinyl roughness"),

    ("port_wooden_crates_01", "Caisses bois de transport", "cargo",
     (1.2, 1.0, 1.0), "poc_core",
     "Group of industrial plywood shipping crates, braced with softwood battens "
     "and diagonal corner reinforcement, exposed screw and staple heads, plain "
     "untreated plywood with visible grain and edge delamination, scuffed "
     "corners, dust and handling marks, one crate slightly offset"),

    ("port_pallet_sacks_01", "Sacs de materiau sur palette", "cargo",
     (1.2, 0.8, 1.1), "poc_core",
     "Wooden pallet stacked with heavy woven polypropylene bulk sacks of "
     "aggregate, soft irregular sagging shapes conforming to each other, "
     "off-white and beige woven fabric with visible weave texture, dusty "
     "surfaces, one torn corner spilling fine grey powder, worn pallet base"),

    # -------------------------------------------------------------- B. port
    ("port_container_20ft_blue_01", "Container maritime 20 pieds bleu", "containers",
     (6.06, 2.44, 2.59), "poc_test",
     "Standard ISO 20-foot shipping container, generic unbranded, exact "
     "real-world proportions and door construction, corrugated painted steel "
     "panels, realistic locking bars with cams and hinges, corner castings, "
     "forklift pockets, deep marine blue paint, subtle scratches and naturally "
     "distributed edge wear, very light localised oxidation at the door frame "
     "and lower rail, realistic painted metal roughness"),

    ("port_container_20ft_red_01", "Container maritime 20 pieds rouge", "containers",
     (6.06, 2.44, 2.59), "poc_core",
     "Standard ISO 20-foot shipping container, generic unbranded, corrugated "
     "painted steel panels, full set of locking bars, hinges and corner "
     "castings, oxide red paint faded unevenly by sun exposure, chalky "
     "weathered finish on the roof, rust blooms along the bottom rail and "
     "around the door hinges, dents in two corrugation valleys"),

    ("port_container_20ft_green_01", "Container maritime 20 pieds vert", "containers",
     (6.06, 2.44, 2.59), "poc_core",
     "Standard ISO 20-foot shipping container, generic unbranded, corrugated "
     "painted steel panels, locking bars and corner castings, dark industrial "
     "green paint with patchy repainted areas in a slightly different shade, "
     "scratches revealing primer, light surface rust along welds, dust film "
     "settled on horizontal surfaces"),

    ("port_container_reefer_white_01", "Container frigorifique blanc", "containers",
     (6.06, 2.44, 2.59), "poc_core",
     "Refrigerated ISO 20-foot reefer shipping container, generic unbranded, "
     "smooth ribbed white painted steel side panels, integrated refrigeration "
     "unit at one end with protective grille, ventilation louvres, control "
     "panel recess and power cable socket, stainless steel fittings, off-white "
     "paint with grey grime streaks below the unit, light rust at the base rail"),

    ("port_ibc_tank_01", "Cuve IBC sur palette", "cargo",
     (1.2, 1.0, 1.16), "poc_core",
     "Industrial IBC intermediate bulk container, translucent white "
     "polyethylene tank inside a galvanised steel tubular cage, moulded on a "
     "steel pallet base, bottom discharge valve with cap and top filling lid, "
     "faint residue staining inside the tank, dusty cage with light rust at the "
     "weld joints, realistic translucent plastic and galvanised metal"),

    ("port_steel_drums_01", "Futs metalliques industriels", "cargo",
     (1.3, 0.7, 0.88), "poc_core",
     "Group of three 200 litre steel industrial drums, standard rolling hoops "
     "and top bung fittings, painted steel in industrial blue, paint scuffed "
     "down to bare metal on the rolling hoops, rust rings at the base rims, "
     "dents in the upper body, dust and dried liquid streaks running down one "
     "side, realistic painted metal roughness variation"),

    ("port_cable_reel_01", "Bobine industrielle de cable", "cargo",
     (2.0, 2.0, 1.2), "poc_core",
     "Large industrial cable drum, heavy timber construction with radial plank "
     "flanges bolted to a central wooden core, wound with thick black electrical "
     "cable, weathered grey timber with splintered edges and rusted bolt heads, "
     "cable with realistic rubber sheen and slight sag, dust and mud on the "
     "lower flange"),

    ("port_bollard_01", "Bollard d amarrage de quai", "props",
     (0.5, 0.5, 0.7), "poc_core",
     "Cast iron quayside mooring bollard, heavy mushroom head on a flanged base "
     "plate with four large anchor bolts set into concrete, thick layered paint "
     "in weathered yellow flaking away to reveal rusted cast iron underneath, "
     "polished bare metal on the head where mooring lines have rubbed, salt and "
     "grime in the base flange"),

    ("port_handrail_01", "Garde-corps metallique industriel", "structures",
     (2.0, 0.05, 1.1), "poc_core",
     "Industrial steel guardrail section, tubular top rail and mid rail with "
     "vertical posts and welded base plates, kick plate along the bottom, "
     "safety yellow painted steel with chipped paint at the corners and "
     "handling marks, rust starting at the weld seams and bolt holes, matte "
     "worn paint roughness"),

    ("port_stairs_steel_01", "Escalier metallique exterieur", "structures",
     (2.5, 1.0, 2.5), "poc_core",
     "External industrial steel staircase, single straight flight with about "
     "ten open grating treads, steel stringers, tubular handrail on both sides "
     "and a small top landing, hot dip galvanised finish with dull grey patina, "
     "rust at the bolted connections, worn shiny metal on the tread nosings, "
     "realistic grating geometry"),

    ("port_control_cabin_01", "Poste de controle portuaire", "structures",
     (2.5, 2.5, 3.0), "poc_core",
     "Small prefabricated port gate control cabin, single room modular building "
     "with large glazed windows on two sides, sheet metal wall panels with "
     "visible fixing screws, shallow flat roof with drip edge, one steel door "
     "with a step, small wall mounted air conditioning unit, white and blue "
     "painted panels with grime streaks below the windows and rust at the "
     "panel joints"),

    ("port_watch_tower_01", "Tour d observation portuaire", "structures",
     (3.0, 3.0, 5.5), "poc_core",
     "Small elevated port observation post, glazed cabin raised on a steel "
     "frame structure with an external staircase and railed platform, sheet "
     "metal cladding, flat roof with a short antenna mast, galvanised steel "
     "legs, white and blue painted panels with weathering streaks, rust at the "
     "leg base plates, realistic industrial construction"),

    # ------------------------------------------------- C. vehicules et machines
    ("port_van_white_01", "Fourgon utilitaire blanc", "vehicles",
     (5.9, 2.0, 2.6), "poc_core",
     "Generic modern European panel van, medium wheelbase high roof commercial "
     "van body, plain white paint, unmarked flat side panels, black plastic "
     "bumpers and mirrors, steel wheels with plain hub caps, realistic glass "
     "with slight tint, road dust along the lower body and around the wheel "
     "arches, light stone chips on the front, no badges, generic anonymous "
     "front grille design"),

    ("port_pickup_01", "Pick-up utilitaire", "vehicles",
     (5.3, 1.9, 1.8), "poc_core",
     "Generic modern double cab pickup truck, plain silver grey paint, open "
     "cargo bed with plastic bed liner, black plastic bumpers, wheel arch "
     "trims and side steps, all terrain tyres on plain steel wheels, dusty "
     "lower body and mud spray behind the wheels, scratches on the tailgate "
     "top edge, anonymous generic grille, no badges"),

    ("port_flatbed_truck_01", "Petit camion plateau industriel", "vehicles",
     (7.5, 2.4, 3.0), "poc_core",
     "Small generic European flatbed lorry, two axle chassis cab with a flat "
     "steel deck and folding aluminium drop sides, plain white cab with black "
     "bumper, steel wheels, timber deck boards worn and stained, tie-down "
     "hooks along the deck edge, road grime on the chassis and mudguards, "
     "anonymous generic cab front, no badges"),

    ("port_forklift_01", "Chariot elevateur portuaire", "machinery",
     (3.6, 1.3, 2.2), "poc_test",
     "Industrial counterbalance forklift truck, three tonne class diesel yard "
     "forklift, vertical duplex mast with chains and hydraulic cylinders, two "
     "steel forks, overhead protective cage, open operator seat with steering "
     "wheel and control levers, heavy counterweight at the rear, solid rubber "
     "tyres, safety yellow paintwork with chipped edges and grease stains, "
     "hydraulic oil residue on the mast rails, dusty worn appearance"),

    ("port_terminal_tractor_01", "Tracteur de terminal", "machinery",
     (4.5, 2.4, 2.8), "poc_core",
     "Port terminal tractor yard truck, short wheelbase shunting tractor with "
     "a tall narrow cab, single rear axle with dual wheels, flat rear deck "
     "carrying a lifting fifth wheel coupling, access ladder and handrails, "
     "amber beacon on the cab roof, white and grey paintwork with scuffs on "
     "the deck and rust at the chassis welds, anonymous unbranded cab"),

    ("port_light_generator_01", "Groupe electrogene avec projecteurs", "machinery",
     (3.2, 1.6, 2.4), "poc_core",
     "Mobile lighting tower generator on a small two wheel road trailer, boxy "
     "sheet metal enclosure with hinged access doors and louvred vents, "
     "telescopic mast stowed horizontally carrying four rectangular floodlight "
     "heads, stabiliser outriggers, drawbar with jockey wheel, safety yellow "
     "painted body with scratched panels, exhaust soot marks and road dust"),

    # ------------------------------------------------------ extras par priorite
    ("port_reach_stacker_01", "Reach stacker", "machinery",
     (11.0, 4.2, 4.9), "poc_extra",
     "Container handling reach stacker, heavy four wheel yard machine with a "
     "long telescopic boom and a container spreader attachment at the tip, "
     "elevated glazed cab offset to one side, very large ribbed tyres, "
     "hydraulic cylinders and hose routing along the boom, red and dark grey "
     "paintwork with heavy chipping on the boom edges, grease and dust, "
     "unbranded anonymous machine"),

    ("port_container_trailer_01", "Semi-remorque porte-container", "vehicles",
     (12.2, 2.5, 1.5), "poc_extra",
     "Skeletal container semi-trailer chassis, long steel frame with twist "
     "locks for a 40 foot container, three axle bogie with dual wheels, "
     "landing legs, mudguards, rear underrun bar with lights, plain grey "
     "painted steel with rust streaks and road grime, no container loaded, "
     "unbranded"),

    ("port_workshop_building_01", "Petit atelier industriel portuaire", "structures",
     (12.0, 8.0, 5.0), "poc_extra",
     "Small single storey industrial port workshop building, rectangular "
     "structure with profiled sheet metal walls, one large roller shutter door "
     "and a personnel door, shallow pitched roof with rainwater gutter, small "
     "high windows, white upper panels over a blue painted lower band, dirt "
     "streaks below the gutter, rust at the shutter guides, plain concrete "
     "plinth"),

    ("port_flood_light_mast_01", "Grand projecteur sur mat", "props",
     (1.2, 1.2, 9.0), "poc_extra",
     "Tall industrial floodlight mast, galvanised steel tapered pole on a "
     "bolted base plate, crossarm at the top carrying four rectangular "
     "floodlight heads angled downwards, cable routing clipped along the pole, "
     "dull galvanised finish with white efflorescence and rust at the base "
     "bolts, weathered aluminium light housings"),

    ("port_concrete_planter_01", "Jardiniere beton", "props",
     (1.2, 0.6, 0.6), "poc_extra",
     "Rectangular precast concrete planter box, heavy walls with exposed "
     "aggregate finish, slightly tapered sides, filled with soil and low "
     "mediterranean shrubs, water staining down the outer faces, moss in the "
     "lower corners, chipped top edge, realistic concrete and foliage"),
]


def construire():
    data = {
        "version": 1,
        "projet": "POC port maritime",
        "unite": "metre",
        "note": ("Dimensions reelles approximatives, en metres (longueur, largeur, "
                 "hauteur). Elles servent de reference de mise a l'echelle a "
                 "l'import : Meshy ne garantit aucune echelle absolue."),
        "socle_commun": SOCLE,
        "interdits_communs": INTERDITS,
        "lots": {
            "poc_test": "Les trois assets de validation du pipeline.",
            "poc_core": "Les 30 assets principaux du POC.",
            "poc_extra": "Assets supplementaires, par ordre de priorite.",
        },
        "assets": [],
    }
    for aid, nom, cat, dim, lot, spec in ASSETS:
        data["assets"].append({
            "id": aid,
            "nom": nom,
            "categorie": cat,
            "lot": lot,
            "dimensions_m": {"longueur": dim[0], "largeur": dim[1], "hauteur": dim[2]},
            "prompt": p(spec),
        })
    return data


def par_id():
    return {a["id"]: a for a in construire()["assets"]}


if __name__ == '__main__':
    d = construire()
    os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
    with open(SORTIE, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    n = len(d["assets"])
    lots = {}
    for a in d["assets"]:
        lots[a["lot"]] = lots.get(a["lot"], 0) + 1
    print("%s ecrit : %d assets" % (SORTIE, n))
    for k in sorted(lots):
        print("   %-10s %2d" % (k, lots[k]))
