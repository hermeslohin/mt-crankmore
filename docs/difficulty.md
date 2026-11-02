# Difficulty & watts

Everything in Mt. Crankmore is measured against **your** FTP and weight. The rivals, the champion, Thunder Thighs McGee and every town challenge are set from them, so a race is a race whether your FTP is 150 W or 350 W. This page explains how. (For working on the game itself see [development.md](development.md).)

- [The basics](#the-basics)
- [Speed from watts](#speed-from-watts)
- [Rivals' watts](#rivals-watts)
- [Drafting, fatigue and attacks](#drafting-fatigue-and-attacks)
- [Maillot Max and Thunder Thighs McGee](#maillot-max-and-thunder-thighs-mcgee)
- [Example: what it takes to win](#example-what-it-takes-to-win)
- [Town challenges](#town-challenges)
- [Keyboard riding](#keyboard-riding)

## The basics

In **Rider setup** you enter your **FTP** (the power you can hold for about an hour) and your **weight**. The game works out your power-to-weight:

```
your W/kg = FTP ÷ weight
```

Rivals are set from your W/kg, and the **difficulty** decides what share of their FTP they ride at:

| Difficulty | Rivals ride at | Rival bikes |
|---|---|---|
| Easy | 50% of their FTP | Club Racer |
| Medium (default) | 65% | Club Racer |
| Hard | 80% | Club Racer |
| Ludicrous | 100% | Club Racer |

Every rival rides the same middle-of-the-road **Club Racer** on every difficulty, so a better bike only ever makes *you* faster. Your weight goes into the physics too: climbs are as hard as they would be outside.

## Speed from watts

Everyone's speed (yours, the rivals', the quarry in a chase) comes from the same formula. The game finds the speed `v` at which the power put out balances rolling resistance, gravity and air drag:

```
power × 0.975 = v × ( m·g·(sin θ + Crr·cos θ) + ½·ρ·CdA·v² )

m     rider + bike mass (kg)            g    9.81 m/s²
θ     the road's slope (atan of grade)   ρ    1.2 kg/m³ (air)
Crr   the bike's rolling resistance      CdA  the bike's drag area (m²)
0.975 drivetrain loss (2.5%)
```

- **Gravel.** The gravel race courses (Foothill, Summit, Flour Run) add `0.014 × the bike's gravel factor` to its Crr. Town roads and the Crusty Crit are tarmac: just the bike's own Crr.
- **The Velodoughm's boards** roll like a real velodrome: Crr is `0.002` for everyone, whatever the bike.
- **Creeks.** Wading through a ford adds 0.05 to Crr while you're in the water.
- **Speed caps.** 16 m/s (57.6 km/h) in races, 13 m/s (46.8 km/h) in town, so descents stay sane.
- **A battered bike.** Below 30% of its HP, a bike goes 8% slower.
- **Drafting** makes the same watts go further (see [below](#drafting-fatigue-and-attacks)): in a slipstream your watts count as `watts ÷ (1 − saving)`.

### The bikes

Speeds at 200 W for a 79.4 kg (175 lb) rider. The bikes are spread so that the slowest is never more than about 20% slower than the best.

| Bike | Mass | CdA | Crr | Gravel × | Flat | 7% climb | Gravel |
|---|---|---|---|---|---|---|---|
| Rusty Trash Bike | 11.8 kg | 0.384 | 0.0084 | 0.73 | 29.9 km/h | 9.8 km/h | 25.2 km/h |
| Garage Sale Commuter | 9.7 kg | 0.352 | 0.0066 | 0.73 | 31.7 | 10.3 | 26.7 |
| Gravel Grinder | 8.3 kg | 0.320 | 0.0056 | 0.43 | 33.2 | 10.6 | 30.0 |
| Carbon Crit Machine | 7.2 kg | 0.293 | 0.0047 | 0.68 | 34.6 | 10.8 | 29.4 |
| Golden Pepperoni Pro | 6.6 kg | 0.275 | 0.0043 | 0.55 | 35.6 | 11.0 | 31.2 |
| Fixie | 7.5 kg | 0.311 | 0.0052 | 0.77 | 33.7 | 10.7 | 28.1 |
| Hoofy Bike (gift) | 11.1 kg | 0.371 | 0.0077 | 0.71 | 30.6 | 10.0 | 25.9 |
| Champion's Bike (prize) | 6.5 kg | 0.270 | 0.0045 | 0.50 | 35.7 | 10.9 | 31.6 |
| **Club Racer** (every rival) | 8.3 kg | 0.320 | 0.0056 | 0.68 | 33.2 | 10.6 | 28.3 |

## Rivals' watts

Each rival has a weight of their own (68, 71 or 74 kg, by their place in the field) and an FTP worked out from **your** W/kg:

```
rival FTP    = your W/kg × rival weight × (1 + spread) × trim
spread       = clamp((roster FTP − 245) ÷ 30, −1, 1) × 5%
riding watts = rival FTP × difficulty share × (1 ± 4%, a slow wobble)
```

The roster FTP only sets where each rival sits in the field: at most 5% above or below your W/kg. Gear Grinder Gus is the strongest and Tubeless Tony the weakest; Cadence Carla is trimmed to 90% on top of that. The **attack** trait (0 to 1) sets how often they go off the front.

Example: FTP 200 W at 79.4 kg (2.52 W/kg), each rival at 71 kg.

| Rival | Spread | FTP | Easy | Medium | Hard | Ludicrous | Attacks every |
|---|---|---|---|---|---|---|---|
| Gear Grinder Gus | +5.0% | 188 W | 94 W | 122 W | 150 W | 188 W | ~170 s |
| Karate Kim | +2.2% | 183 W | 91 | 119 | 146 | 183 | ~100 s |
| Margherita Maya | +1.2% | 181 W | 90 | 118 | 145 | 181 | ~150 s |
| Wheelie Wanda | +0.2% | 179 W | 90 | 116 | 143 | 179 | ~85 s |
| Cryptic Carl | −1.2% | 177 W | 88 | 115 | 141 | 177 | ~140 s |
| Super Sarah | −3.8% | 172 W | 86 | 112 | 138 | 172 | ~125 s |
| Tubeless Tony | −5.0% | 170 W | 85 | 110 | 136 | 170 | ~205 s |
| Cadence Carla | +2.8%, ×0.9 | 166 W | 83 | 108 | 132 | 166 | ~190 s |

In town, rivals cruise at the same riding watts on the Club Racer, chasing pizza orders against you; they slow down on climbs and fly down the other side just like you.

## Drafting, fatigue and attacks

In a race the rivals ride like a bunch. These rules decide how hard each one is pushing at any moment.

### Drafting

Anyone (you included) riding 1 to 9 m behind another rider, in the same line, saves a share of their watts. The saving grows with speed, linearly in between:

| Speed | 0 km/h | 13 km/h | 17 km/h | 40 km/h and up |
|---|---|---|---|---|
| Watts saved | 0% | 18% | 24% | 30% |

There's no drafting at the Velodoughm: it's a test of legs.

### How a rival's watts change

| Situation | Watts |
|---|---|
| Riding in the wind (not drafting) | −3% for every km ridden that way, down to 70% at the most. You never tire like this. |
| On the front with riders on their wheel | Takes a 12–25 s turn, then swings off for 6 s at ×0.85 |
| A group within 40 m up the road | ×1.08 to bridge across |
| Attacking | ×1.25 for 12–22 s, every 60 s (attack trait 1) to 220 s (trait 0), ±30% |
| **The finale** (last 2 km; the crit's last 2 minutes) | Attacks 3× as often, ×1.35 for 25–45 s, turns on the front half as long |
| More than 300 m ahead of you | ×0.95 |
| More than 300 m behind you | ×1.05 |

A rival sits 2.5 m behind the wheel they follow, unless that wheel is much slower than they'd ride alone; then they go round. The bear on the mountain runs as fast as you would at **110% of your FTP** on your bike: hold that and it can't catch you.

## Maillot Max and Thunder Thighs McGee

### Maillot Max, the champion

When he's in town, Max joins every racer for one race at Race HQ. He rides like a rival (attack trait 0.6) at the difficulty's share, but with more FTP than anyone:

```
Max's FTP = max(strongest rival's W/kg, your W/kg) × 1.1 × 68 kg
```

For FTP 200 W at 79.4 kg that's about 198 W: 99 W on Easy, 129 W on Medium, 158 W on Hard, 198 W on Ludicrous. Beat him and you win his bike.

### Thunder Thighs McGee, the Velodoughm

One flying lap, 750 m, just you and him, no drafting and no power-ups. McGee isn't affected by the difficulty:

```
McGee's watts = 150% of your FTP, on a Club Racer, at 75 kg, on the boards
to beat him   = the watts that hold his speed on your bike at your weight
```

For FTP 200 W he pushes 300 W and goes about 40.5 km/h on the boards. At 79.4 kg on the Carbon Crit Machine you need about 277 W for the lap. The Velodoughm's door tells you the number for the bike you're on, and he won't race the Rusty Trash Bike at all.

## Example: what it takes to win

Simulated races (with [`tools/race_sim.py`](../tools/race_sim.py)) for a rider with **FTP 200 W at 175 lb (79.4 kg) on the Carbon Crit Machine**, holding one steady wattage for the whole race. Each number is the lowest steady power that won every run (3 to 4 runs per wattage, each with different random rival behaviour).

| Race | Easy | Medium | Hard | Ludicrous |
|---|---|---|---|---|
| Foothill Gravel Grind | 114 W | 155 W | 195 W | 230 W |
| Summit Gravel Showdown | 120 W | 160 W | 200 W | 235 W |
| Flour Run | 130 W | 175 W | 210 W | 240 W |
| Crusty Crit | 105 W | 130 W | 160 W | 180 W |
| Foothill vs Maillot Max | 122 W | 170 W | 205 W | 245 W |
| Summit vs Maillot Max | 131 W | 180 W | 215 W | 265 W |
| Flour Run vs Maillot Max | 145 W | 185 W | 210 W | 265 W |
| The Velodoughm (McGee) | 280 W | 280 W | 280 W | 280 W |

- **To win every race on a level**, hold the highest number in its column, leaving out the Velodoughm: about **145 W on Easy, 185 W on Medium, 215 W on Hard and 265 W on Ludicrous** (73%, 93%, 108% and 133% of FTP).
- **The Velodoughm** takes about 280 W (140% of FTP) whatever the difficulty, because McGee is set from your FTP, not the difficulty. It's one lap: about 70 seconds.
- **Why more than the rivals' watts?** They draft each other (saving up to 30%), take turns, and attack at 125–135%. A steady rider who doesn't pick a wheel ends up doing more of the work in the wind.
- **The short races are the hardest** to win (the Flour Run and the champion's races): the late attacks count for more over a short distance.
- **The Crusty Crit is the noisiest**: it's decided by bunch sprints, so a few watts under its number sometimes still wins.
- **Riding it for real**, with surges, drafting and power-ups, you can win with less.

Rivals scale with your W/kg, so for another FTP or weight the numbers scale too: as a share of FTP they stay about the same.

## Town challenges

Out delivering, the town asks for real efforts. Each challenge has a target share of your FTP. In a chase, the quarry goes exactly as fast as **you** would at that share, on your bike, on the same grade, so the watts on the panel are what you need whatever bike you ride: above them you close the gap, below them it gets away.

| Challenge | % of FTP | At 200 W | How it works | Reward |
|---|---|---|---|---|
| Stop the bike thief | **130%** | 260 W | 14 m head start. Get within 2 m. He escapes at 55 m or after 100 s. | $300 |
| Beat the hot rod | **120%** | 240 W | A countdown, then a sprint to a chequered line along the roads. It pulls away from the start no faster than 4 m/s². | $300 |
| Catch the thief | 110% | 220 W | 12 m head start. Get within 2 m. He escapes at 45 m or after 80 s. | $150 |
| Hill sprint | 105% | 210 W | Ride up a named hill faster than the target time: your own time up it at 105% of FTP on your bike. Every 2.5–5 minutes. | $60 |
| Seagulls! | 90% | 180 W | 15 m head start. Get 40 m clear or hold them off for 90 s. Caught carrying a pizza: they steal it. | – |
| Pizza rush | 80% | 160 W | 12% of orders: five stops in a row. Average 80% of FTP across them for the bonus. | $120 |
| Catch the dog | 80% | 160 W | 10 m head start. Get within 1.5 m. It's gone at 40 m or after 75 s. | $50 |
| Race the kid | 60% | 120 W | A sprint to a line, like the hot rod, against a kid on a BMX. | $20 |
| Zombie kids! (fall) | 50% | 100 W | 6 m head start. Get 25 m clear or last 45 s. Caught: they take $10 of candy money. | – |

A challenge ends (lost) if you're hit by a car on the way. Only one runs at a time.

## Keyboard riding

- **W** rides at 85% of your FTP and **Shift** sprints at 175%, in gear 11. Easier gears make fewer watts at a higher cadence (watts × ratio^0.75), harder gears more.
- Power ramps up at 125% of FTP per second and eases off at 70% per second.
- In races, keyboard riders have **legs**: above 110% of FTP they drain 10% a second, and when they're empty you're held to your FTP until they refill (6% a second below 110%). Riders on a trainer don't have legs: your real ones do the job.
- Keyboard riding never logs watts to Strava: only speed and distance.
