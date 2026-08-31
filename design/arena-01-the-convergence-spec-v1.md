# Arena 01 — The Convergence

Implementation brief accompanying `arena-01-the-convergence-map-v1.png`.

## Core dimensions

- Playable diameter: 180 m
- Outer wall diameter: 190 m
- Central Core plaza: 34 m diameter
- Inner ring corridor: 58–76 m diameter
- Target outer spawn to Core travel time: 30–35 s
- Target full-map crossing time: 60–70 s
- Player count: 12
- Recommended match duration: 8–10 min

## Coordinate system

- Arena center is `(0, 0, 0)`.
- North is positive `Z`; east is positive `X`.
- Base floor is `Y = 0`.
- Standard raised routes are `Y = 3 m`.
- Sniper platforms are `Y = 6 m` maximum.

## Spawn distribution

- Sanctuary / north: S1, S2, S3
- Forge / east: S4, S5, S6
- Barracks / south: S7, S8, S9
- Rift / west: S10, S11, S12
- Keep at least 18 m between adjacent spawn pads.
- No spawn may have direct line of sight to another spawn.
- Each spawn needs two exits and nearby common loot, but no immediate high-tier weapon.

## Arena sectors

### Sanctuary — north

- Long sightlines and elevated bridges.
- Ivory stone, blue markings and angular wing motifs.
- High ground must always have two access routes.

### Forge — east

- Short sightlines, tight bends and heavy cover.
- Dark stone, orange fissures and industrial channels.
- Avoid corridors narrower than 4 m.

### Barracks — south

- Medium-range combat and modular cover clusters.
- Navy structures, orange cloth accents and ruined training yards.
- Provide several lateral rotations toward Sanctuary and Forge.

### Rift — west

- Broken sightlines and two paired traversal gates.
- Violet stone, cyan energy and irregular cover.
- Gates should reposition players, never place them directly behind an enemy spawn.

## Core and circulation

- Four main ramps enter the Core from cardinal directions.
- Add four secondary flanking routes between sectors.
- The Core should be dangerous: limited hard cover and strong visibility from the ring.
- The surrounding ring must let players rotate without entering the Core.
- No combat pocket may have only one exit.

## Loot budget

- 6 high-tier clusters, placed away from spawn pads and exposed to multiple approaches.
- 12 medium-tier clusters, roughly one per player.
- 16 common clusters, concentrated near spawn routes and outer rotations.
- 4 healing stations, one between each pair of faction sectors.
- 1 central supply capsule location plus 4 optional random drop sockets.

## Cover and combat checks

- Standard hard cover height: 1.2–1.5 m.
- Tall line-of-sight blocker height: 3–5 m.
- Provide cover every 8–12 m on primary routes.
- Mix close range (5–12 m), medium range (12–28 m) and long range (28–45 m).
- Cap deliberate sightlines at about 55 m.
- Every sniper platform needs two approaches and at least one exposed angle.

## Battle-royale zone

- First zone guide is the dashed ring shown on the map.
- Final zone center must be selected from multiple sockets, including sector and ring locations; do not always finish at the Core.
- The first contraction should preserve at least three sector-to-sector rotations.

## First graybox acceptance criteria

- Twelve players can leave spawn without immediate crossfire.
- Every sector reaches the Core through at least three routes.
- A player can circle the arena without entering the Core.
- No high ground is reachable by only one route.
- No dead end is longer than 8 m.
- Full-map crossing is 60–70 seconds at normal movement speed.
- Frame rate and navigation are tested with all 12 players active.
