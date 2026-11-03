#!/usr/bin/env python3
"""Synthesises the game's chiptune sound effects into sounds/<name>.wav (22.05 kHz, 16-bit mono).

Plain Python, no dependencies: python3 tools/make_sfx.py [name ...] (no names: all of them). Each effect is a
function below that returns a list of samples in -1..1; tweak one and run this again, then reimport in Godot.
"""
import math, os, random, struct, sys, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")


# ---- building blocks ----------------------------------------------------------------------------------------------

def n(secs):
    return int(secs * RATE)


def osc(kind, freq, secs, duty=0.5, phase=0.0):
    """A tone; `freq` is a number or a function of time (s) for slides. kind: square, tri, saw, sine."""
    out, ph = [], phase
    for i in range(n(secs)):
        f = freq(i / RATE) if callable(freq) else freq
        ph = (ph + f / RATE) % 1.0
        if kind == "square":
            v = 1.0 if ph < duty else -1.0
        elif kind == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        elif kind == "saw":
            v = 2.0 * ph - 1.0
        else:
            v = math.sin(2 * math.pi * ph)
        out.append(v)
    return out


def noise(secs, seed=1, hold=1):
    """White noise; `hold` > 1 repeats each value that many samples (a cruder, lower 'NES' noise)."""
    r = random.Random(seed)
    out, v = [], 0.0
    for i in range(n(secs)):
        if i % hold == 0:
            v = r.uniform(-1.0, 1.0)
        out.append(v)
    return out


def lowpass(x, cutoff):
    """One-pole low-pass; `cutoff` (Hz) is a number or a function of time (s)."""
    out, y = [], 0.0
    for i, v in enumerate(x):
        c = cutoff(i / RATE) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-2 * math.pi * c / RATE)
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, lp)]


def env(x, attack=0.005, decay=None, sustain=1.0, release=0.05, curve=1.0):
    """Attack / (optional exponential-ish) decay / release envelope over the whole clip."""
    total = len(x)
    a, r = max(1, n(attack)), max(1, n(release))
    out = []
    for i, v in enumerate(x):
        g = 1.0
        if i < a:
            g = i / a
        elif decay is not None:
            g = sustain + (1.0 - sustain) * math.exp(-(i - a) / max(1, n(decay)))
        else:
            g = sustain
        if i > total - r:
            g *= max(0.0, (total - i) / r)
        out.append(v * g ** curve)
    return out


def gain(x, g):
    return [v * g for v in x]


def mix(*parts):
    """Adds (offset_seconds, samples) parts together."""
    end = max(n(o) + len(p) for o, p in parts)
    out = [0.0] * end
    for o, p in parts:
        s = n(o)
        for i, v in enumerate(p):
            out[s + i] += v
    return out


def cat(*parts):
    out = []
    for p in parts:
        out += p
    return out


def silence(secs):
    return [0.0] * n(secs)


def note(name):
    """'A4', 'C#5' ... -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def blip(freq, secs, kind="square", duty=0.5, vol=0.5, release=0.03):
    return gain(env(osc(kind, freq, secs, duty), attack=0.002, release=release), vol)


def bell_tone(freq, secs, vol=0.5, seed=0):
    """A bicycle-bell-ish metallic ring: inharmonic sine partials, each dying away at its own rate."""
    parts = [(1.0, 1.0, 0.6), (2.76, 0.5, 0.35), (5.4, 0.3, 0.2), (8.93, 0.18, 0.12)]
    out = [0.0] * n(secs)
    for ratio, amp, dec in parts:
        tone = osc("sine", freq * ratio, secs, phase=seed * 0.13 * ratio)
        for i, v in enumerate(tone):
            out[i] += v * amp * math.exp(-(i / RATE) / dec)
    strike = gain(env(highpass(noise(0.01, seed + 7), 3000), attack=0.0005, release=0.008), 0.4)
    return gain(env(mix((0, out), (0, strike)), attack=0.001, release=0.05), vol / 1.6)


def arp(notes, step, kind="square", duty=0.5, vol=0.4, tail=0.1):
    """Notes one after another, the last one held for `tail`."""
    out = []
    for k, nm in enumerate(notes):
        secs = step + (tail if k == len(notes) - 1 else 0.0)
        out += blip(note(nm), secs, kind, duty, vol, release=min(0.04, secs * 0.5))
    return out


# ---- the effects --------------------------------------------------------------------------------------------------

def menu_move():
    return blip(note("E6"), 0.035, duty=0.25, vol=0.22)


def menu_select():
    return cat(blip(note("C6"), 0.045, duty=0.25, vol=0.25), blip(note("G6"), 0.07, duty=0.25, vol=0.25))


def menu_back():
    return cat(blip(note("G5"), 0.045, duty=0.25, vol=0.22), blip(note("C5"), 0.07, duty=0.25, vol=0.22))


def menu_adjust():
    return blip(note("A5"), 0.025, kind="tri", vol=0.3)


def shift():
    """A crisp derailleur click: two tiny noise ticks."""
    tick = lambda s: gain(env(highpass(noise(0.012, s), 2500), attack=0.0005, release=0.01), 0.55)
    return mix((0, tick(3)), (0.035, gain(tick(4), 0.7)))


def bell():
    """Ding-ding."""
    return mix((0, bell_tone(1850, 0.55, 0.55, 1)), (0.16, bell_tone(1850, 0.7, 0.5, 2)))


def order_pickup():
    return arp(["C5", "E5", "G5", "C6"], 0.06, duty=0.25, vol=0.3, tail=0.12)


def deliver():
    """Ka-ching: a coin chirp over a bright little chord."""
    coin = cat(blip(note("B5"), 0.06, duty=0.25, vol=0.3), blip(note("E6"), 0.28, duty=0.25, vol=0.3, release=0.2))
    chord = gain(env(mix((0, osc("tri", note("C5"), 0.4)), (0, osc("tri", note("E5"), 0.4)), (0, osc("tri", note("G5"), 0.4))),
                     attack=0.005, decay=0.15, sustain=0.0, release=0.05), 0.18)
    return mix((0, coin), (0.06, chord))


def cash():
    """Buying something: a cash-register 'chk-ching'."""
    chk = gain(env(lowpass(noise(0.05, 11, hold=2), 4000), attack=0.001, release=0.04), 0.45)
    return mix((0, chk), (0.05, bell_tone(2600, 0.5, 0.4, 5)))


def throw():
    """A whoosh: noise swept up through a low-pass, swelling then gone."""
    sw = lowpass(noise(0.28, 21), lambda t: 400 + 5000 * t / 0.28)
    return gain(env(sw, attack=0.12, release=0.12), 0.7)


def crash():
    """Going down: a thump, a scrape and some rattling."""
    thud = gain(env(osc("sine", lambda t: 120 - 300 * t, 0.18), attack=0.001, decay=0.05, sustain=0.0, release=0.03), 0.9)
    scrape = gain(env(lowpass(noise(0.45, 31, hold=2), 2500), attack=0.005, decay=0.15, sustain=0.0, release=0.1), 0.5)
    rattle = []
    r = random.Random(5)
    parts = [(0, thud), (0.02, scrape)]
    for k in range(6):
        parts.append((0.08 + k * 0.06 + r.uniform(0, 0.02),
                      gain(env(highpass(noise(0.02, 40 + k), 1500), attack=0.0005, release=0.015), 0.35 * (1 - k / 7))))
    return mix(*parts)


def car_hit():
    """Hit by a car: a tyre screech into a crash."""
    screech = gain(env(mix((0, osc("square", lambda t: 1400 - 500 * t, 0.35, 0.3)), (0, osc("square", lambda t: 1460 - 520 * t, 0.35, 0.3))),
                       attack=0.01, release=0.05), 0.15)
    return mix((0, screech), (0.3, gain(crash(), 1.1)))


def knocked():
    """A rival knocks you off: a bonk and a fall."""
    bonk = blip(lambda t: 600 - 1200 * t, 0.12, kind="square", duty=0.5, vol=0.3)
    return mix((0, bonk), (0.08, gain(crash(), 0.8)))


def siren():
    """The ambulance: two-tone wail, twice."""
    hi, lo = 960, 720
    out = []
    for f in (hi, lo, hi, lo):
        out += osc("square", f, 0.3, 0.5)
    return gain(env(lowpass(out, 2500), attack=0.05, release=0.2), 0.22)


def powerup_get():
    return arp(["E5", "G5", "B5", "E6", "G6"], 0.045, duty=0.125, vol=0.28, tail=0.1)


def powerup_use():
    """A zap: a fast downward square sweep with a sparkle."""
    zap = gain(env(osc("square", lambda t: 1800 * math.exp(-t * 9), 0.25, 0.25), attack=0.002, release=0.05), 0.3)
    return mix((0, zap), (0.02, gain(env(highpass(noise(0.15, 51), 4000), attack=0.002, release=0.1), 0.15)))


def frisbee_hit():
    return mix((0, blip(lambda t: 900 - 1500 * t, 0.1, duty=0.5, vol=0.3)), (0.05, gain(crash(), 0.5)))


def count_beep():
    return blip(note("A5"), 0.16, duty=0.5, vol=0.3, release=0.04)


def go_beep():
    return blip(note("A6"), 0.45, duty=0.5, vol=0.3, release=0.15)


def lap_bell():
    """The last-lap bell: a heavier, lower bell rung three times."""
    return mix(*[(k * 0.22, bell_tone(1100, 0.6, 0.5, 10 + k)) for k in range(3)])


def cheer():
    """A crowd cheering: band-passed noise swelling and fading, with a few whistles."""
    body = highpass(lowpass(noise(1.6, 61), 1800), 300)
    wobble = [v * (0.75 + 0.25 * math.sin(i / RATE * 2 * math.pi * 5.3)) for i, v in enumerate(body)]
    crowd = gain(env(wobble, attack=0.25, release=0.7), 0.9)
    whistle = lambda f, s: gain(env(osc("sine", lambda t: f + 250 * math.sin(t * 30) + 400 * t, s), attack=0.03, release=0.05), 0.1)
    return mix((0, crowd), (0.25, whistle(2400, 0.25)), (0.7, whistle(2700, 0.2)))


def win():
    melody = arp(["C5", "E5", "G5", "C6", "G5", "C6"], 0.1, duty=0.5, vol=0.28, tail=0.35)
    bass = gain(env(cat(osc("tri", note("C3"), 0.4), osc("tri", note("G3"), 0.2), osc("tri", note("C4"), 0.45)), attack=0.005, release=0.1), 0.35)
    return mix((0, melody), (0, bass))


def lose():
    return arp(["G4", "F#4", "F4", "E4"], 0.16, kind="tri", vol=0.4, tail=0.4)


def challenge():
    """A challenge starts: a call to arms."""
    return arp(["G4", "C5", "G4", "C5", "E5"], 0.07, duty=0.25, vol=0.28, tail=0.15)


def boost():
    """Fire Socks / Breadsticks kicking in: a rising whoosh-tone."""
    tone = gain(env(osc("square", lambda t: 300 + 1200 * t, 0.35, 0.25), attack=0.005, release=0.06), 0.2)
    return mix((0, tone), (0, throw()))


def freewheel():
    """One loop of a freewheel ticking: 8 pawl clicks, evenly spaced, for looping while you coast."""
    loop = 0.5
    parts = []
    for k in range(8):
        parts.append((k * loop / 8, gain(env(highpass(noise(0.006, 70 + k), 4000), attack=0.0003, release=0.005), 0.28 * (0.85 + 0.15 * (k % 2)))))
    out = mix(*parts)
    return out + [0.0] * (n(loop) - len(out))


SOUNDS = {name: fn for name, fn in globals().items()
          if callable(fn) and not name.startswith("_") and fn.__module__ == __name__ and fn.__code__.co_argcount == 0 and not fn.__code__.co_flags & 0x04}


def write(name, samples):
    peak = max(1e-6, max(abs(v) for v in samples))
    if peak > 1.0:
        samples = [v / peak for v in samples]
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in samples))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name in sys.argv[1:] or sorted(SOUNDS):
        write(name, SOUNDS[name]())
        print("sounds/%s.wav" % name)
