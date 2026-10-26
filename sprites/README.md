# Rider sprites

PixelLab rider sprites for Mt. Crankmore 90s Edition. These live only in this repo (`mt-crankmore-90sedition`), not in the original mt-crankmore. The folder has a `.gdignore` so Godot doesn't import the thousands of PNGs; the game reads the packed sheets in `art/` instead.

Every character is 48x48 (animation frames are stored on a 60-68 px canvas so the motion has room), drawn from a
high top-down view, in 8 directions: `south`, `south-east`, `east`, `north-east`, `north`, `north-west`, `west`,
`south-west`. In the `south` view the bike points straight at the camera, front wheel directly below the rider.

## Layout

```
characters/<character>/
  metadata.json              the PixelLab export manifest (prompts, ids, sizes, frame paths)
  <State>/
    rotations/<dir>.png      one still per direction
    animations/pedaling/<dir>/frame_000..007.png    8 frames, riding loop
    animations/fall/<dir>/frame_000..012.png        13 frames, riding pose -> lying on the ground
```

The folder names are PixelLab's. `Idle` is the state with the delivery bag on the back, `With_pizza` has a pizza on
top of the bag, and `No_bag` is a plain bike. For Rookie Boy the third state is called `No_pizza`, and its `Idle`
carries a red delivery box instead of a bag.

The `fall` animation starts from the normal riding pose, the bike slips and tips over, and the last frames hold the
rider on the ground. In the `With_pizza` fall the pizza flies off the bag and lands splattered.

## Characters

| Folder | Character | Look |
|---|---|---|
| `rookie-boy` | Rookie Boy (PixelLab name `rookie2`) | red cap, yellow scarf, red delivery box |
| `rookie-girl` | Rookie Girl | green cap, purple shirt, brown ponytail, red bag |
| `gear-grinder-gus` | Gear Grinder Gus (`gus2`) | baker's cap, curled mustache, Hawaiian shirt |
| `cryptic-carl` | Cryptic Carl | purple helmet, Mothman hoodie, orange bag |
| `cadence-carla` | Cadence Carla | big round glasses, mustard vest, calculator in her pocket, teal bag |
| `wheelie-wanda` | Wheelie Wanda | pink dress, sunglasses, long blonde hair, no helmet, white bag |
| `margherita-maya` | Margherita Maya | party hat, gold sequin jacket, gold bag |
| `super-sarah` | Super Sarah | small girl in a superhero costume with a flowing red cape, blue bag |
| `tubeless-tony` | Tubeless Tony | muscle shirt, sweatband, gym shorts, lime-green bag |
| `karate-kim` | Karate Kim | white gi, black belt, bare feet, no helmet, red cape |

PixelLab can't rename a character, so Rookie Boy and Gear Grinder Gus are tagged with those names there and still
show as `rookie2` and `gus2` in the PixelLab character list.

## PixelLab ids

State ids, in the order `Idle` / `With_pizza` / `No_bag` (Rookie Boy: `Idle` / `With_pizza` / `No_pizza`).

| Character | Idle | With pizza | No bag |
|---|---|---|---|
| Rookie Boy | `c20ee589-1930-43be-b9ce-90e04013ded7` | `1117cd0c-19a1-4b7d-8212-004b2916bdaf` | `de5fe38f-eca3-49cb-a844-ba1148804e95` |
| Rookie Girl | `6cd782aa-d8b3-4ab3-a6ca-f1273b8d734d` | `17e7bbb3-72ca-47e5-953a-a5ae78605eb8` | `8d3a0c39-5a57-4935-8139-8bd511cf4e7c` |
| Gear Grinder Gus | `8f582571-5d69-4241-8aaf-f97468a54adc` | `147e0f31-3efb-4533-9525-cfe3a0189cf6` | `bc6a1902-0ae1-423c-bfb9-34767a0fcdab` |
| Cryptic Carl | `ccd0faf4-9f18-4452-ab64-4d31f70d60e9` | `931caa58-9cdd-486b-b516-eb8fa9f75db8` | `0575b96a-141e-445e-ba35-4d3719acc0f2` |
| Cadence Carla | `9aa7ecc2-080d-4e7a-a826-5eb3c48b6045` | `863ef89e-b0b2-4927-a302-ea29e45347ee` | `9eafe03a-9b30-452c-92cb-116ba5a36809` |
| Wheelie Wanda | `92a24a24-7188-4641-aeb8-fe17575d8ce6` | `12ac2604-d722-4267-a014-3dc793fee31c` | `b048ec01-8529-4fcd-8f07-cbf45fbe3c14` |
| Margherita Maya | `a9b2e3f7-05fe-4083-9017-62e6b2180bc6` | `28e72700-1d9f-4520-a5d4-a004bddf9343` | `a8afaeaa-5efb-4e0d-9e51-197597f73a9b` |
| Super Sarah | `137c64ba-52a1-4c5a-91b6-b0adde80bd0f` | `6223dc12-d3fc-4ecf-9e06-155e088a6454` | `bf58edc3-4781-4f5e-9374-455311ed0f8c` |
| Tubeless Tony | `c24f5a17-892a-4f35-b39c-b80583615a13` | `61bba4dc-bd4d-42d1-9353-abfcc12176f7` | `7569f3ce-817c-4b77-9a62-7dae1f71f0ff` |
| Karate Kim | `2e1f7947-16b2-473c-a7b8-1a962a7c1fbb` | `b4bb88d3-df0e-4eb7-b38e-2fe7dd394fab` | `a88325ae-189e-4e74-949e-1e552955e718` |

## Notes

- The PixelLab diagonals are true 45 degree views, while the game's isometric roads run at about 27 degrees, so
  diagonal riders look a little steeper than the road.
- Not every animation has been checked frame by frame. A few directions have a blank or off-colour frame in some
  falls (for example Cryptic Carl's bag fall and bike-only fall); regenerate those in PixelLab if they show in game.
- The game packs these into its 8-row bike sheets with `tools/import_rider.gd` (see the top-level README); `rows=`
  picks which export direction goes on each sheet row and `anim=` which animation (`pedaling` or `fall`).

## Other sprites

| Folder | What | Game art |
|---|---|---|
| `bakers/<shop>/` | one baker per pizza shop (`Idle` state with a `tap` animation, `Holding_pizza` state with a `dance` animation, south view) | `art/chef_<shop>_tap.png`, `art/chef_<shop>_dance.png` |
| `mascot/pizza-mascot/` | the Walkie Talkie's dancing pizza-slice mascot (`dance` animation, south view) | `art/mascot_dance.png` |
| `props/pizza-spin/` | the thrown pizza, spinning (8 frames) | `art/pizza_spin.png` |
| `vehicles/<kind>/` | the traffic in 8 directions (`rotations/`): `car` and `truck` (white, painted in game), `motorcycle`, and 27 coloured `sedan_*`, `truck_*` and `van_*` | `art/vehicle_<kind>.png` |
| `buildings/hospital.png` | St. Pedro's Hospital with a helicopter pad on the roof (a 192x176 image) | `art/hospital.png` |
| `buildings/landmarks/` | the 7 pizza shops, 2 bike shops, race HQ and gondola base (192x176) | `art/building_<name>.png` |
| `buildings/shops/` | one themed shop per shop name (128x128) | `art/building_<name>.png` |
| `buildings/hotels/` | one themed hotel per hotel name (192x208) | `art/building_<name>.png` |
| `buildings/condos/` | the six condo blocks (160x160) | `art/building_<name>.png` |
| `buildings/chalets/` | 16 chalet designs (128x112) | `art/building_chalet_NN.png` |
| `animals/<kind>/` | the race-course wildlife: bear (`idle`, `run`, `roar`), deer, moose, goat, fox, marmot, rabbit, squirrel, elk, wolf, raccoon, hedgehog, chipmunk, skunk, bighorn, badger (`idle`, `run`), all east-facing; `eagle` (`fly`) and `butterfly` (`flutter`) | `art/animal_<kind>_<anim>.png` |
| `people/<slug>/` | twelve pedestrians (`ped_*`: `walk` in 8 directions, `cheer` facing south), two gift-givers (`giver_*`: `wave`), a skier and a skater (stills) | `art/ped_<d>_walk.png`, `_cheer.png`, `giver_*_wave.png`, `person_*.png` |
| `scenery/` | trees (pine, oak, birch, snag in their seasons), bushes, rocks, flower beds, pumpkins, leaf piles, hay, snowmen, scarecrow, kites, picnics, volleyball net, market stalls, umbrellas, lamp, fountain, dock, signs, clouds and power-up icons (single images) | `art/scenery_<name>.png` |
| `objects/<slug>/` | rowboat, canoe, duck, duckling, gondola cabin, dirt jump, fallen log, race arch, in 8 directions (`rotations/`) | `art/obj_<name>.png` |
