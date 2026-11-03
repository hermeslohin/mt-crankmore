#!/usr/bin/env python3
"""Synthesises the game's 16-bit style music into music/<name>.wav (32 kHz, 16-bit stereo, seamless loops).

Plain Python, no dependencies: python3 tools/make_music.py [name ...] (no names: all of them). Each song is a function
below that lays notes onto tracks; the voices are SNES-ish (pulse leads with vibrato and chorus, filtered saw pads,
a plucky bass, noise drums) and the lead runs through a ping-pong echo, which wraps round the loop point so the
song loops without a seam. Tweak one and run this again, then reimport in Godot.

Melodies are written as "note:length" tokens, lengths in 16th notes, e.g. "G5:4 B5:2 r:2" (r = rest).
"""
import math, os, random, struct, sys, wave

RATE = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "music")


# ---- pitch & timing -----------------------------------------------------------------------------------------------

def hz(name):
    """'A4', 'C#5', 'Bb3' -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + name.count("#") - name[1:].count("b") + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def transpose(name, semis):
    f = hz(name) * 2 ** (semis / 12)
    k = round(12 * math.log2(f / 440.0)) + 9 + 48
    return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][k % 12] + str(k // 12)


def parse(line):
    """'G5:4 r:2 B5:2' -> [(note or None, sixteenths)]."""
    out = []
    for tok in line.split():
        nm, ln = tok.split(":")
        out.append((None if nm == "r" else nm, float(ln)))
    return out


class Song:
    def __init__(self, bpm, bars, swing=0.0, beats=4):
        self.bpm, self.bars, self.swing = bpm, bars, swing
        self.bar = beats * 4                             # 16ths in a bar (beats=3 for a waltz)
        self.step = 60.0 / bpm / 4                       # one 16th, in seconds
        self.length = int(round(bars * self.bar * self.step * RATE))
        self.buses = {}                                  # bus -> [left, right]

    def t(self, sixteenths):
        """Seconds at a position in 16ths, with 8th-note swing (0 = straight, 1 = full triplet swing)."""
        beat, f = divmod(sixteenths, 4)
        if self.swing:
            mid = 2 + self.swing * 2 / 3
            f = f * mid / 2 if f < 2 else mid + (f - 2) * (4 - mid) / 2
        return (beat * 4 + f) * self.step

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = [[0.0] * self.length, [0.0] * self.length]
        return self.buses[name]

    def put(self, samples, at, pan=0.0, bus="dry", vol=1.0):
        """Adds samples at `at` 16ths; anything past the end wraps to the start (it's a loop)."""
        L, R = self.bus(bus)
        gl, gr = vol * math.sqrt((1 - pan) / 2) * 1.414, vol * math.sqrt((1 + pan) / 2) * 1.414
        s = int(self.t(at) * RATE)
        n = self.length
        for i, v in enumerate(samples):
            j = (s + i) % n
            L[j] += v * gl
            R[j] += v * gr

    def line(self, voice, text, start=0, pan=0.0, bus="dry", vol=1.0, octave=0, legato=1.0):
        """Plays a melody line; returns where it ended (16ths)."""
        pos = start
        for nm, ln in parse(text):
            if nm:
                if octave:
                    nm = transpose(nm, 12 * octave)
                secs = self.t(pos + ln * legato) - self.t(pos)
                self.put(voice(hz(nm), secs), pos, pan, bus, vol)
            pos += ln
        return pos

    def hits(self, sound, pattern, bars, start_bar=0, pan=0.0, vol=1.0, bus="dry"):
        """A one-bar drum pattern, a char per 16th ('x' hit, 'o' softer, '.' nothing), repeated over `bars` bars."""
        for b in range(bars):
            for k, c in enumerate(pattern):
                if c in "xo":
                    self.put(sound(), (start_bar + b) * self.bar + k, pan, bus, vol * (1.0 if c == "x" else 0.55))


# ---- oscillators & shaping ----------------------------------------------------------------------------------------

def n(secs):
    return max(1, int(secs * RATE))


def osc(kind, f, secs, duty=0.5, vib=0.0, vib_rate=5.5, vib_delay=0.15, detune=0.0, tail=0.0, slide=None):
    """A tone `secs` long plus `tail` seconds; vibrato depth `vib` in semitones, fading in after `vib_delay`."""
    out, ph = [], 0.0
    total = n(secs + tail)
    f0 = f * 2 ** (detune / 1200)
    for i in range(total):
        tt = i / RATE
        ff = f0
        if slide:
            ff *= 2 ** (slide(tt) / 12)
        if vib:
            depth = vib * min(1.0, max(0.0, (tt - vib_delay) / 0.2))
            ff *= 2 ** (depth * math.sin(2 * math.pi * vib_rate * tt) / 12)
        ph = (ph + ff / RATE) % 1.0
        if kind == "pulse":
            v = 1.0 if ph < duty else -1.0
        elif kind == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        elif kind == "saw":
            v = 2.0 * ph - 1.0
        else:
            v = math.sin(2 * math.pi * ph)
        out.append(v)
    return out


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    return [v - w for v, w in zip(x, lowpass(x, cutoff))]


def noise(secs, seed=1, hold=1):
    r = random.Random(seed)
    out, v = [], 0.0
    for i in range(n(secs)):
        if i % hold == 0:
            v = r.uniform(-1.0, 1.0)
        out.append(v)
    return out


def shaped(x, a, d, s, r, secs):
    """ADSR over a note `secs` long that was rendered with r seconds of tail: hold, then release to silence."""
    na, nd, nh, nr = n(a), n(d), n(secs), n(r)
    out = []
    g_end = None
    for i, v in enumerate(x):
        if i < nh:
            g = i / na if i < na else s + (1 - s) * math.exp(-(i - na) / nd)
            g_end = g
        else:
            k = i - nh
            if k >= nr:
                break
            g = (g_end or 0.0) * (1 - k / nr)
        out.append(v * g)
    return out


def mixl(*xs):
    out = [0.0] * max(len(x) for x in xs)
    for x in xs:
        for i, v in enumerate(x):
            out[i] += v
    return out


def gain(x, g):
    return [v * g for v in x]


# ---- voices -------------------------------------------------------------------------------------------------------

def lead(f, secs):
    """The main tune: two slightly detuned 25% pulses (chorus) with delayed vibrato, softened a touch."""
    tail = 0.08
    a = osc("pulse", f, secs, 0.25, vib=0.25, detune=-6, tail=tail)
    b = osc("pulse", f, secs, 0.25, vib=0.25, detune=6, tail=tail)
    return gain(shaped(lowpass(mixl(a, b), 4200), 0.006, 0.25, 0.65, tail, secs), 0.13)


def flute(f, secs):
    """A mellow, breathy lead for the laid-back song."""
    tail = 0.12
    x = mixl(gain(osc("sine", f, secs, vib=0.3, vib_rate=5.0, vib_delay=0.2, tail=tail), 0.8),
             gain(osc("tri", f * 2, secs, vib=0.3, vib_rate=5.0, vib_delay=0.2, tail=tail), 0.15))
    breath = gain(lowpass(highpass(noise(secs + tail, int(f)), 2000), 6000), 0.05)
    x = mixl(x, breath)
    return gain(shaped(x, 0.04, 0.3, 0.8, tail, secs), 0.24)


def chip(f, secs):
    """A thin 12.5% pulse blip for arpeggios."""
    x = osc("pulse", f, secs, 0.125, tail=0.02)
    return gain(shaped(lowpass(x, 5000), 0.002, 0.05, 0.25, 0.02, secs), 0.07)


def bass(f, secs):
    """A plucky synth bass: a filtered square on a triangle sub."""
    tail = 0.03
    sq = lowpass(lowpass(osc("pulse", f, secs, 0.5, tail=tail), 900), 1400)
    sub = osc("tri", f, secs, tail=tail)
    return gain(shaped(mixl(gain(sq, 0.6), sub), 0.003, 0.12, 0.55, tail, secs), 0.24)


def pad(f, secs):
    """A soft string pad: detuned saws through a low-pass, slow in and out."""
    tail = 0.25
    x = mixl(osc("saw", f, secs, detune=-9, tail=tail), osc("saw", f, secs, detune=9, tail=tail))
    return gain(shaped(lowpass(lowpass(x, 1300), 1800), 0.18, 0.5, 0.8, tail, secs), 0.035)


def kick():
    x = osc("sine", 55, 0.22, slide=lambda t: 24 * math.exp(-t * 35))
    click = lowpass(noise(0.006, 3), 3000)
    return gain(mixl(shaped(x, 0.001, 0.07, 0.0, 0.05, 0.17), gain(click, 0.4)), 0.42)


def snare():
    body = shaped(osc("tri", 190, 0.12, slide=lambda t: -6 * t * 10), 0.001, 0.04, 0.0, 0.03, 0.09)
    hiss = shaped(highpass(lowpass(noise(0.2, 9, hold=1), 7000), 900), 0.001, 0.07, 0.0, 0.05, 0.15)
    return gain(mixl(gain(body, 0.5), gain(hiss, 0.6)), 0.3)


def hat():
    return gain(shaped(highpass(noise(0.05, 17), 7000), 0.0005, 0.012, 0.0, 0.01, 0.03), 0.16)


def open_hat():
    return gain(shaped(highpass(noise(0.25, 23), 6000), 0.001, 0.08, 0.0, 0.08, 0.15), 0.12)


def tick():
    """A freewheel-pawl click, for hats in the bike songs."""
    return gain(shaped(highpass(noise(0.01, 41), 4500), 0.0003, 0.004, 0.0, 0.004, 0.006), 0.2)


def bell(f=1850, secs=0.8):
    """A bicycle bell: inharmonic partials, each fading at its own rate."""
    out = [0.0] * n(secs)
    for ratio, amp, dec in [(1.0, 1.0, 0.6), (2.76, 0.5, 0.35), (5.4, 0.3, 0.2), (8.93, 0.18, 0.12)]:
        ph = 0.0
        for i in range(len(out)):
            ph = (ph + f * ratio / RATE) % 1.0
            out[i] += math.sin(2 * math.pi * ph) * amp * math.exp(-(i / RATE) / dec)
    return gain(out, 0.07)


def crash_cym():
    return gain(shaped(lowpass(highpass(noise(1.2, 55), 3500), 9000), 0.002, 0.45, 0.0, 0.4, 0.8), 0.13)


def banjo(f, secs):
    """A twangy pluck: a bright saw with a tiny downward bend at the attack, dying fast."""
    tail = 0.05
    x = osc("saw", f, secs, slide=lambda t: 0.4 * math.exp(-t * 60), tail=tail)
    x = mixl(gain(lowpass(x, 3800), 0.8), gain(osc("pulse", f * 2, secs, 0.3, tail=tail), 0.15))
    return gain(shaped(x, 0.001, 0.09, 0.15, tail, secs), 0.13)


def fiddle(f, secs):
    """A bowed saw: soft attack and a wide, singing vibrato."""
    tail = 0.08
    x = mixl(osc("saw", f, secs, vib=0.35, vib_rate=6.0, vib_delay=0.08, detune=-4, tail=tail),
             osc("saw", f, secs, vib=0.35, vib_rate=6.2, vib_delay=0.08, detune=4, tail=tail))
    return gain(shaped(lowpass(lowpass(x, 3600), 5000), 0.03, 0.3, 0.85, tail, secs), 0.075)


def accordion(f, secs):
    """Musette reeds: three square reeds, one in tune and two a little sharp and flat, beating against each other."""
    tail = 0.04
    x = mixl(osc("pulse", f, secs, 0.5, tail=tail), osc("pulse", f, secs, 0.5, detune=14, tail=tail),
             gain(osc("pulse", f, secs, 0.5, detune=-11, tail=tail), 0.7), gain(osc("saw", f / 2, secs, tail=tail), 0.4))
    return gain(shaped(lowpass(lowpass(x, 2600), 4200), 0.015, 0.2, 0.85, tail, secs), 0.06)


def brass(f, secs):
    """A synth-brass stab: detuned saws swelling in."""
    tail = 0.06
    x = mixl(osc("saw", f, secs, vib=0.2, detune=-7, tail=tail), osc("saw", f, secs, vib=0.2, detune=7, tail=tail))
    return gain(shaped(lowpass(lowpass(x, 2800), 3800), 0.02, 0.2, 0.75, tail, secs), 0.085)


def power(f, secs):
    """A punky power chord: root and fifth on fuzzy squares."""
    tail = 0.02
    x = mixl(osc("pulse", f, secs, 0.5, tail=tail), osc("pulse", f * 1.4983, secs, 0.5, tail=tail),
             gain(osc("pulse", f * 2, secs, 0.5, detune=5, tail=tail), 0.5))
    x = [math.tanh(1.8 * v) for v in lowpass(x, 2200)]
    return gain(shaped(x, 0.002, 0.15, 0.6, tail, secs), 0.06)


def marimba(f, secs):
    """A wooden bar: a sine with a quick high overtone, ringing a short while whatever the note length."""
    secs = max(secs, 0.35)
    m, t4 = osc("sine", f, secs), osc("sine", f * 3.93, secs)
    out = [v * math.exp(-i / RATE / 0.32) + w * 0.35 * math.exp(-i / RATE / 0.03) for i, (v, w) in enumerate(zip(m, t4))]
    return gain(shaped(out, 0.002, 10.0, 1.0, 0.02, secs - 0.02), 0.2)


def epiano(f, secs):
    """An electric piano: a sine with a bell-like tine on the attack and a slow tremolo."""
    tail = 0.3
    base = osc("sine", f, secs, tail=tail)
    oct2 = osc("sine", f * 2, secs, tail=tail)
    tine = osc("sine", f * 7.1, secs, tail=tail)
    out = []
    for i, (a, b, c) in enumerate(zip(base, oct2, tine)):
        t = i / RATE
        out.append((a + 0.25 * b * math.exp(-t / 0.4) + 0.2 * c * math.exp(-t / 0.05)) * (1 + 0.12 * math.sin(2 * math.pi * 4.5 * t)))
    return gain(shaped(out, 0.003, 0.6, 0.45, tail, secs), 0.17)


def rim():
    return gain(shaped(highpass(mixl(osc("tri", 1700, 0.03), gain(noise(0.03, 81), 0.5)), 900), 0.0005, 0.012, 0.0, 0.01, 0.02), 0.22)


def shaker():
    return gain(shaped(highpass(noise(0.06, 91), 5500), 0.01, 0.02, 0.0, 0.02, 0.03), 0.09)


def clap():
    out = [0.0] * n(0.2)
    for k in range(3):                     # three quick slaps, then a short noisy tail
        for i, v in enumerate(highpass(lowpass(noise(0.012, 100 + k), 5000), 1000)):
            out[n(k * 0.009) + i] += v * 0.5
    for i, v in enumerate(highpass(lowpass(noise(0.15, 104), 4500), 900)):
        j = n(0.027) + i
        if j < len(out):
            out[j] += v * 0.5 * math.exp(-i / RATE / 0.04)
    return gain(out, 0.3)


def crowd(secs=2.0):
    """A crowd roaring: band-passed noise swelling and fading with a wobble."""
    x = highpass(lowpass(noise(secs, 61), 1700), 300)
    x = [v * (0.75 + 0.25 * math.sin(i / RATE * 2 * math.pi * 5.3)) for i, v in enumerate(x)]
    return gain(shaped(x, secs * 0.35, 10.0, 1.0, secs * 0.5, secs * 0.5), 0.35)


def thunder():
    """A low rumble for Thunder Thighs."""
    x = lowpass(lowpass(noise(2.0, 7, hold=3), 180), 260)
    return gain(shaped(x, 0.05, 0.6, 0.2, 0.9, 1.1), 1.6)


# ---- harmony helpers ----------------------------------------------------------------------------------------------

CHORDS = {
    "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11], "sus4": [0, 5, 7],
}


def chord(sym, octave=3):
    """'Em' / 'D' / 'Bb' / 'F#m7' -> list of note names from `octave`."""
    root = sym[0] + (sym[1] if len(sym) > 1 and sym[1] in "#b" else "")
    kind = sym[len(root):]
    base = root + str(octave)
    return [transpose(base, s) for s in CHORDS[kind]]


def arpeggiate(song, chords, start_bar, pattern=(0, 1, 2, 3, 2, 1), octave=5, pan=0.0, vol=1.0, every=1, voice=None):
    """16th-note arpeggios over one chord per bar (`every` 16ths between notes), on `voice` (default the chip blip)."""
    voice = voice or chip
    for b, sym in enumerate(chords):
        notes = chord(sym, octave)
        notes = notes + [transpose(notes[0], 12)] if len(notes) == 3 else notes
        for k in range(0, song.bar, every):
            nm = notes[pattern[(k // every) % len(pattern)] % len(notes)]
            song.put(voice(hz(nm), song.step * every * 0.8), (start_bar + b) * song.bar + k, pan, "dry", vol)


def bassline(song, chords, start_bar, rhythm, octave=2, vol=1.0, voice=None):
    """`rhythm`: a char per 16th of a bar; R root, F fifth, O octave, T third, '-' hold, '.' rest."""
    voice = voice or bass
    for b, sym in enumerate(chords):
        notes = chord(sym, octave)
        pick = {"R": notes[0], "T": notes[1], "F": notes[2], "O": transpose(notes[0], 12)}
        k = 0
        while k < song.bar:
            c = rhythm[k]
            if c in pick:
                ln = 1
                while k + ln < song.bar and rhythm[k + ln] == "-":
                    ln += 1
                song.line(voice, "%s:%d" % (pick[c], ln), (start_bar + b) * song.bar + k, vol=vol, legato=0.85)
                k += ln
            else:
                k += 1


def pads(song, chords, start_bar, octave=4, vol=1.0):
    for b, sym in enumerate(chords):
        for i, nm in enumerate(chord(sym, octave)[:3]):
            song.line(pad, "%s:%d" % (nm, song.bar), (start_bar + b) * song.bar, pan=(-0.4, 0.0, 0.4)[i], bus="dry", vol=vol, legato=0.97)


# ---- effects & output ---------------------------------------------------------------------------------------------

def echo(song, bus, delay_16ths, feedback=0.38, wet=0.32, damp=3500):
    """SNES-style ping-pong echo on a bus, computed round the loop a few times so the tail wraps seamlessly."""
    L, R = song.bus(bus)
    n_ = song.length
    d = int(song.step * delay_16ths * RATE)
    a = 1.0 - math.exp(-2 * math.pi * damp / RATE)
    bl, br = [0.0] * n_, [0.0] * n_
    yl = yr = 0.0
    for _ in range(3):                        # run round the loop three times so the buffer reaches steady state
        for i in range(n_):
            j = (i - d) % n_
            inl = (L[i] + R[i]) * 0.5 + br[j] * feedback   # ping-pong: left is fed from the right's past
            inr = bl[j] * feedback
            yl += a * (inl - yl)
            yr += a * (inr - yr)
            bl[i], br[i] = yl, yr
    out = song.bus("dry")
    for i in range(n_):
        out[0][i] += L[i] + bl[i] * wet
        out[1][i] += R[i] + br[i] * wet


def write(name, song):
    L, R = song.bus("dry")
    peak = max(1e-6, max(max(abs(v) for v in L), max(abs(v) for v in R)))
    g = 0.89 / peak
    frames = bytearray()
    for l, r in zip(L, R):
        frames += struct.pack("<hh", int(max(-1.0, min(1.0, l * g)) * 32767), int(max(-1.0, min(1.0, r * g)) * 32767))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    return song.length / RATE


# ---- the songs ----------------------------------------------------------------------------------------------------
# One for the menus, one per race (named after the course, see race_song() in scripts/music.gd), and three for riding
# round town, shuffled.

def title():
    """'Mt. Crankmore': the menu theme. G major, bright and bouncy, with a bike bell at the top of the loop."""
    s = Song(132, 16)
    A = ["G", "D", "Em", "C", "G", "D", "C", "D"]
    B = ["C", "D", "Bm", "Em", "Am", "D", "G", "G"]
    chords = A + B
    s.line(lead, "D5:2 G5:2 B5:4 A5:2 G5:2 B5:4  A5:6 F#5:2 D5:8  E5:2 G5:2 B5:4 C6:2 B5:2 G5:4  E5:4 G5:4 C6:4 B5:2 A5:2"
                 " D5:2 G5:2 B5:4 D6:4 B5:2 G5:2  A5:4 D6:4 F#5:4 A5:4  G5:2 E5:2 C5:4 E5:2 G5:2 C6:4  B5:4 A5:4 F#5:2 G5:2 A5:4"
                 " E6:6 D6:2 C6:4 G5:4  F#5:6 A5:2 D6:8  D6:4 B5:2 A5:2 F#5:4 B5:4  G5:12 r:4"
                 " C6:4 B5:2 A5:2 E5:4 A5:4  F#5:4 A5:4 D6:4 C6:2 A5:2  B5:8 D6:4 B5:4  G5:8 r:8", pan=-0.1, bus="echo")
    arpeggiate(s, chords, 0, pattern=(0, 1, 2, 3), octave=4, pan=0.5, vol=0.9)
    bassline(s, chords, 0, "R-.R..F-O-.RF-R.")
    pads(s, chords, 0, vol=0.8)
    s.hits(kick, "x.....x...x.....", 16)
    s.hits(snare, "....x.......x...", 15)
    s.hits(snare, "....x.......x.xx", 1, start_bar=15)
    s.hits(hat, "x.o.x.o.x.o.x.o.", 16, pan=0.3)
    s.hits(open_hat, "..............x.", 16, pan=0.3)
    s.put(crash_cym(), 0, 0.2)
    s.put(bell(), 15 * 16 + 8, 0.35)          # ding-ding as the tune rests
    s.put(bell(), 15 * 16 + 10, 0.35)
    echo(s, "echo", 3)
    return s


# -- races --

def race_foothill():
    """Foothill Gravel Grind, 'Switchback Hoedown': D mixolydian, 150 bpm, banjo rolls, a fiddle and a boom-chick beat."""
    s = Song(150, 16)
    chords = ["D", "D", "C", "G", "D", "D", "C", "A", "G", "D", "C", "D", "G", "D", "Em", "A"]
    s.line(fiddle, "D5:2 F#5:2 A5:2 F#5:2 D6:4 A5:4  B5:2 A5:2 F#5:2 A5:2 D5:8  E5:2 G5:2 C6:2 G5:2 E5:4 C5:4  D5:2 G5:2 B5:4 A5:2 G5:2 D5:4"
                   " D5:2 F#5:2 A5:2 F#5:2 D6:4 C6:4  A5:2 F#5:2 A5:2 B5:2 A5:4 F#5:4  G5:2 E5:2 C5:2 E5:2 G5:4 E5:4  A5:8 C#6:4 E6:4"
                   " D6:4 B5:4 G5:4 B5:4  A5:4 F#5:4 D5:4 F#5:4  G5:2 A5:2 G5:2 E5:2 C5:4 E5:4  F#5:4 A5:4 D6:8"
                   " B5:3 A5:3 G5:2 D5:4 G5:4  F#5:3 E5:3 D5:2 A4:4 D5:4  E5:4 G5:4 B5:4 E6:4  C#6:4 B5:2 A5:2 E5:4 C#5:4",
           pan=-0.15, bus="echo")
    arpeggiate(s, chords, 0, pattern=(0, 1, 3, 0, 2, 3, 1, 3), octave=4, pan=0.45, vol=1.0, voice=banjo)
    bassline(s, chords, 0, "R...F...R...F...", vol=1.0)
    s.hits(kick, "x.......x.......", 16)
    s.hits(snare, "....o.......o...", 16, vol=0.7)
    s.hits(tick, "..x...x...x...x.", 16, pan=-0.3)
    s.hits(shaker, "xoxoxoxoxoxoxoxo", 16, pan=0.3)
    s.put(bell(), 7 * 16 + 12, 0.4)
    s.put(bell(), 15 * 16 + 12, 0.4)
    s.put(bell(), 15 * 16 + 14, 0.4)
    echo(s, "echo", 3, feedback=0.25, wet=0.2)
    return s


def race_summit():
    """Summit Gravel Showdown, 'Crank It': E minor, 160 bpm, spinning-crank 16th bass and freewheel-tick hats."""
    s = Song(160, 16)
    A = ["Em", "C", "D", "B", "Em", "C", "D", "B7"]
    B = ["Am", "Em", "C", "D", "Em", "C", "D", "B7"]
    chords = A + B
    s.line(lead, "E5:3 B4:3 E5:2 G5:3 F#5:3 E5:2  G5:4 E5:4 C5:4 E5:4  F#5:3 D5:3 F#5:2 A5:3 G5:3 F#5:2  D#5:8 F#5:4 B5:4"
                 " E5:3 B4:3 E5:2 G5:3 B5:3 E6:2  D6:4 C6:4 B5:4 G5:4  A5:3 F#5:3 D5:2 F#5:3 A5:3 C6:2  B5:12 A5:2 F#5:2"
                 " C6:6 B5:2 A5:4 E5:4  G5:6 F#5:2 E5:4 B4:4  E5:4 G5:4 C6:4 E6:4  D6:8 C6:4 A5:4"
                 " B5:6 G5:2 E5:4 G5:4  C6:6 B5:2 G5:4 E5:4  F#5:4 A5:4 D6:4 F#6:4  D#6:8 B5:4 F#5:4", pan=-0.1, bus="echo")
    # a harmony a third-ish below on the B section, quieter, other side
    s.line(lead, "A5:6 G5:2 E5:4 C5:4  E5:6 D5:2 B4:4 G4:4  C5:4 E5:4 G5:4 C6:4  A5:8 A5:4 F#5:4"
                 " G5:6 E5:2 B4:4 E5:4  G5:6 G5:2 E5:4 C5:4  D5:4 F#5:4 A5:4 D6:4  B5:8 F#5:4 D#5:4", start=8 * 16, pan=0.45, vol=0.45)
    arpeggiate(s, chords, 0, pattern=(0, 2, 1, 3), octave=5, pan=0.55, vol=0.8, every=2)
    bassline(s, chords, 0, "ROROROROROROROFO", vol=0.85)   # the cranks going round
    pads(s, chords[8:], 8, vol=0.9)
    s.hits(kick, "x.....x.x.....x.", 15)
    s.hits(kick, "x.x.x.x.x.x.x.xx", 1, start_bar=15)
    s.hits(snare, "....x.......x...", 7)
    s.hits(snare, "....x.......x.xx", 1, start_bar=7)
    s.hits(snare, "....x.......x...", 7, start_bar=8)
    s.hits(snare, "....x..x..x.xxxx", 1, start_bar=15)
    s.hits(tick, "xoxoxoxoxoxoxoxo", 16, pan=0.35)
    s.hits(open_hat, "..x...x...x...x.", 8, start_bar=8, pan=-0.3)
    s.put(crash_cym(), 0, 0.2)
    s.put(crash_cym(), 8 * 16, -0.2)
    echo(s, "echo", 3, feedback=0.3, wet=0.25)
    return s


def race_flour():
    """Flour Run, 'Petal Pushers': C major with a lydian lift, 140 bpm, sunny and skipping through the meadows."""
    s = Song(140, 16)
    chords = ["C", "D", "Em", "C", "Am", "D", "F", "G", "F", "G", "Em", "Am", "Dm", "G", "C", "G"]
    tune = ("E5:4 G5:4 C6:6 B5:2  A5:4 F#5:4 D5:4 F#5:4  G5:2 A5:2 B5:4 E6:4 D6:4  C6:8 G5:4 E5:4"
            " A5:4 C6:4 E6:6 D6:2  C6:2 A5:2 F#5:4 D6:8  C6:4 A5:4 F5:4 A5:4  B5:4 D6:4 G5:8")
    s.line(flute, tune, pan=-0.15, bus="echo")
    s.line(lead, "A5:6 C6:2 F6:8  D6:4 B5:2 G5:2 D6:4 G6:4  E6:6 D6:2 B5:4 G5:4  A5:4 C6:4 E6:8"
                 " F6:4 E6:2 D6:2 A5:4 D6:4  B5:4 G5:4 D5:4 F5:4  E5:4 G5:2 C6:2 E6:4 G6:4  F6:4 D6:4 B5:4 G5:4",
           start=8 * 16, pan=-0.15, bus="echo", vol=0.9)
    arpeggiate(s, chords, 0, pattern=(0, 1, 2, 3, 2, 1), octave=5, pan=0.5, vol=0.75, every=2, voice=marimba)
    bassline(s, chords, 0, "R-.R.-F.R-.R.-O.", vol=0.9)
    pads(s, chords, 0, vol=0.7)
    s.hits(kick, "x.......x.......", 16)
    s.hits(clap, "....x.......x...", 16, vol=0.7)
    s.hits(hat, "..x...x...x...x.", 16, pan=0.3)
    s.hits(shaker, "oxoxoxoxoxoxoxox", 16, pan=-0.3)
    s.put(bell(2100), 15 * 16 + 8, 0.35)
    s.put(bell(2100), 15 * 16 + 10, 0.35)
    echo(s, "echo", 3, feedback=0.35, wet=0.3)
    return s


def race_crit():
    """Crusty Crit, 'Crust Punk Crit': A major, 176 bpm, power chords, a lap-after-lap chant and the crowd going wild."""
    s = Song(176, 16)
    chords = ["A", "F#m", "D", "E", "A", "F#m", "D", "E", "D", "E", "C#m", "F#m", "D", "E", "A", "E"]
    s.line(lead, "E5:2 E5:2 A5:2 E5:2 C#6:4 B5:4  A5:2 A5:2 F#5:2 A5:2 C#6:4 E6:4  D6:4 C#6:4 A5:4 F#5:4  G#5:4 B5:4 E6:8"
                 " E5:2 E5:2 A5:2 E5:2 C#6:4 E6:4  F#6:4 E6:4 C#6:4 A5:4  B5:2 A5:2 F#5:2 A5:2 B5:4 D6:4  E6:12 r:4"
                 " F#5:4 A5:4 D6:4 F#6:4  E6:6 D6:2 B5:8  C#6:4 E6:4 G#6:4 E6:4  F#6:8 C#6:8"
                 " A6:4 F#6:4 D6:4 A5:4  B5:4 E6:4 G#6:4 B6:4  A6:8 E6:4 C#6:4  B5:4 G#5:4 E5:2 F#5:2 G#5:4",
           pan=-0.1, bus="echo", octave=-1)
    bassline(s, chords, 0, "R.R.R.R.R.R.R.R.", octave=3, vol=0.9, voice=power)
    bassline(s, chords, 0, "RRRRRRRRRRRRRRRR", vol=0.7)
    arpeggiate(s, chords[8:], 8, pattern=(0, 1, 2, 3), octave=5, pan=0.5, vol=0.7)
    s.hits(kick, "x.x...x.x.x...x.", 16)
    s.hits(snare, "....x.......x...", 15)
    s.hits(snare, "....x...xxxxxxxx", 1, start_bar=15)
    s.hits(hat, "xoxoxoxoxoxoxoxo", 16, pan=0.3)
    s.hits(clap, "....x.......x...", 4, start_bar=8, vol=0.8)       # the crowd clapping along
    s.put(crash_cym(), 0, 0.2)
    s.put(crash_cym(), 8 * 16, -0.2)
    s.put(crowd(2.2), 14 * 16, 0.0, vol=0.8)
    s.put(bell(1100), 15 * 16 + 12, 0.3)                          # the lap bell
    echo(s, "echo", 3, feedback=0.25, wet=0.2)
    return s


def race_velo():
    """The Velodoughm, 'Thunder Thighs': C minor, 168 bpm, synth brass, four on the floor, and thunder rolling in."""
    s = Song(168, 16)
    chords = ["Cm", "Cm", "Ab", "Bb", "Cm", "Cm", "Ab", "G", "Fm", "Cm", "Ab", "Bb", "Fm", "G", "Cm", "G"]
    s.line(brass, "C5:4 Eb5:2 G5:2 C6:8  Bb5:2 G5:2 Eb5:2 G5:2 Bb5:2 C6:2 D6:4  Eb6:4 C6:4 Ab5:4 Eb5:4  F5:4 Bb5:4 D6:4 F6:4"
                  " Eb6:4 D6:2 C6:2 G5:8  G5:2 Ab5:2 G5:2 F5:2 Eb5:4 G5:4  C6:4 Ab5:4 Eb6:4 C6:4  B5:8 D6:4 G5:4"
                  " Ab5:6 G5:2 F5:4 C5:4  Eb5:6 D5:2 C5:4 G4:4  Ab4:4 C5:4 Eb5:4 Ab5:4  Bb5:8 D6:4 F6:4"
                  " F6:6 Eb6:2 C6:4 Ab5:4  B5:4 D6:4 G6:4 F6:4  Eb6:8 G5:4 C6:4  D6:4 B5:4 G5:4 B5:4", pan=-0.1, bus="echo")
    s.line(lead, "C5:4 Eb5:2 G5:2 C6:8  Bb5:2 G5:2 Eb5:2 G5:2 Bb5:2 C6:2 D6:4  Eb6:4 C6:4 Ab5:4 Eb5:4  F5:4 Bb5:4 D6:4 F6:4",
           start=8 * 16, pan=0.5, vol=0.4, octave=1)          # a high echo of the opening over the B section
    bassline(s, chords, 0, "R.RRR.RRR.RRO.F.", vol=0.9)
    arpeggiate(s, chords, 0, pattern=(0, 1, 2, 1), octave=4, pan=0.55, vol=0.7)
    pads(s, chords, 0, octave=3, vol=0.8)
    s.hits(kick, "x...x...x...x...", 16)
    s.hits(snare, "....x.......x...", 15)
    s.hits(snare, "....x..x.xx.xxxx", 1, start_bar=15)
    s.hits(hat, "oxoxoxoxoxoxoxox", 16, pan=0.3)
    s.hits(open_hat, "..x...x...x...x.", 16, pan=-0.3, vol=0.7)
    s.put(thunder(), 0, -0.2)
    s.put(thunder(), 8 * 16, 0.2)
    s.put(crash_cym(), 0, 0.2)
    echo(s, "echo", 3, feedback=0.3, wet=0.25)
    return s


def race_baguette():
    """Baguette Boulevard, 'Le Tour de Croûte': a fast musette waltz in A minor, accordion over oom-pah-pah."""
    s = Song(184, 32, beats=3)
    chords = ["Am", "Am", "Dm", "Am", "E", "E7", "Am", "Am", "C", "G", "Am", "Dm", "Am", "E", "Am", "E7"] * 2
    tune = ("E5:4 A5:4 C6:4  B5:2 C6:2 B5:4 A5:4  F5:4 A5:4 D6:4  C6:6 B5:2 A5:4"
            " G#5:4 B5:4 E6:4  D6:2 E6:2 D6:4 B5:4  C6:4 A5:4 E5:4  A5:12"
            " G5:4 C6:4 E6:4  D6:2 E6:2 D6:4 B5:4  C6:4 E6:4 A6:4  F6:6 E6:2 D6:4"
            " C6:4 B5:2 A5:2 E5:4  G#5:4 B5:4 D6:4  C6:4 B5:2 C6:2 A5:4  G#5:4 B5:4 E5:4")
    s.line(accordion, tune, pan=-0.15, bus="echo")
    s.line(accordion, tune, start=16 * 12, pan=-0.15, bus="echo")
    s.line(accordion, tune.replace("D6", "B5").replace("C6", "A5").replace("E6", "C6").replace("A6", "E6").replace("F6", "D6"),
           start=16 * 12, pan=0.45, vol=0.55)           # the second time round, a second reed a third or so under
    # oom-pah-pah: bass on the beat, chord stabs on two and three
    for b, sym in enumerate(chords):
        notes = chord(sym, 2)
        s.line(bass, "%s:3" % (notes[0] if b % 2 == 0 else notes[2]), b * 12, vol=1.0, legato=0.9)
        for beat in (1, 2):
            for i, nm in enumerate(chord(sym, 4)[:3]):
                s.put(accordion(hz(nm), s.step * 2.2), b * 12 + beat * 4, pan=0.35, vol=0.35)
    s.hits(kick, "x...........", 32, vol=0.8)
    s.hits(rim, "....x...x...", 32, pan=0.3, vol=0.7)
    s.hits(shaker, "x.o.x.o.x.o.", 32, pan=-0.3)
    s.put(bell(1850), 15 * 12 + 4, 0.4)
    s.put(bell(1850), 15 * 12 + 6, 0.4)
    echo(s, "echo", 2, feedback=0.25, wet=0.22, damp=3000)
    return s


# -- riding round town (one picked at random each time) --

def cruise_1():
    """'Pizza Run': F major, 104 bpm with a swing, a breezy flute and a lazy bass."""
    s = Song(104, 16, swing=0.7)
    A = ["F", "Dm", "Bb", "C", "F", "Am", "Bb", "C"]
    chords = A + ["Fmaj7", "Dm7", "Bb", "C", "F", "Am", "Bb", "Csus4"]
    tune = ("A5:4 C6:2 A5:2 F5:4 r:4  D5:2 F5:2 A5:4 G5:4 F5:4  D6:6 C6:2 Bb5:4 F5:4  G5:8 E5:4 C5:4"
            " A5:4 C6:2 A5:2 F5:4 A5:4  C6:4 E6:4 C6:4 A5:4  Bb5:4 A5:2 G5:2 F5:4 D5:4  E5:4 G5:4 C6:4 Bb5:4")
    s.line(flute, tune, pan=-0.15, bus="echo")
    s.line(lead, tune, start=8 * 16, pan=-0.15, bus="echo", vol=0.8)
    s.line(flute, tune.replace("C6", "A5").replace("E6", "C6").replace("D6", "Bb5"), start=8 * 16, pan=0.4, vol=0.5, octave=-1)
    arpeggiate(s, chords, 0, pattern=(0, 2, 1, 2), octave=4, pan=0.5, vol=0.7, every=2)
    bassline(s, chords, 0, "R--.F-R.O-..F-T.", vol=0.95)
    pads(s, chords, 0, vol=1.0)
    s.hits(kick, "x.......x.x.....", 16)
    s.hits(snare, "....o.......o...", 16, vol=0.8)
    s.hits(tick, "x.x.x.x.x.x.x.x.", 16, pan=0.3)
    s.put(bell(2000), 7 * 16 + 12, 0.4)
    s.put(bell(2000), 15 * 16 + 12, 0.4)
    s.put(bell(2000), 15 * 16 + 14, 0.4)
    echo(s, "echo", 3, feedback=0.42, wet=0.35, damp=2800)
    return s


def cruise_2():
    """'Après-Ride': D major, 96 bpm, a mellow electric piano over a funky little bass, for a lazy loop of the village."""
    s = Song(96, 16, swing=0.3)
    chords = ["Dmaj7", "Bm7", "Em7", "A7", "Dmaj7", "Bm7", "Em7", "A7", "Gmaj7", "F#m7", "Em7", "A7", "Gmaj7", "F#m7", "Em7", "A7"]
    s.line(epiano, "F#5:4 A5:4 C#6:6 A5:2  B5:8 r:4 F#5:4  G5:4 B5:4 D6:4 B5:4  C#6:6 B5:2 A5:8"
                   " F#5:4 A5:2 B5:2 C#6:4 E6:4  D6:8 B5:4 A5:4  G5:2 F#5:2 E5:4 B5:4 G5:4  A5:12 r:4"
                   " B5:4 D6:4 F#6:6 E6:2  C#6:8 A5:4 F#5:4  G5:4 B5:4 E6:4 D6:4  C#6:8 G5:4 A5:4"
                   " B5:4 A5:2 G5:2 F#5:4 D5:4  E5:4 F#5:4 A5:4 C#6:4  B5:6 A5:2 G5:4 E5:4  A5:8 G5:4 E5:4",
           pan=-0.1, bus="echo")
    # soft chord comping on the e-piano, on the 'and' of two and four
    for b, sym in enumerate(chords):
        for at in (6, 14):
            for nm in chord(sym, 4):
                s.put(epiano(hz(nm), s.step * 1.5), b * 16 + at, pan=0.35, vol=0.22)
    bassline(s, chords, 0, "R..R..F.O..F.T..", vol=1.0)
    s.hits(kick, "x......x..x.....", 16)
    s.hits(snare, "....o.......o...", 16, vol=0.75)
    s.hits(tick, "xoxoxoxoxoxoxoxo", 16, pan=0.3, vol=0.7)
    s.put(bell(1950), 15 * 16 + 12, 0.4)
    echo(s, "echo", 3, feedback=0.4, wet=0.3, damp=2600)
    return s


def cruise_3():
    """'Slice of Life': a C major bossa, 112 bpm, marimba and rimshots, sunny-afternoon deliveries."""
    s = Song(112, 16)
    chords = ["Cmaj7", "Am7", "Dm7", "G7", "Em7", "A7", "Dm7", "G7", "Fmaj7", "Fm7", "Em7", "A7", "Dm7", "G7", "Cmaj7", "G7"]
    s.line(marimba, "E5:2 G5:2 B5:4 A5:2 G5:2 E5:4  C6:4 A5:2 E5:2 G5:8  F5:2 A5:2 C6:4 D6:2 C6:2 A5:4  B5:4 D6:4 F5:4 G5:4"
                    " G5:2 B5:2 D6:4 E6:4 D6:4  C#6:4 E6:4 G5:4 A5:4  F5:2 E5:2 D5:4 A5:4 C6:4  B5:12 r:4"
                    " A5:4 C6:4 E6:6 C6:2  Ab5:4 C6:4 Eb6:8  G5:2 B5:2 E6:4 D6:4 B5:4  C#6:4 A5:4 G5:4 E5:4"
                    " F5:4 A5:4 D6:4 C6:4  B5:4 G5:2 F5:2 D5:4 B4:4  C5:4 E5:4 G5:4 B5:4  D6:8 B5:4 G5:4",
           pan=-0.1, bus="echo")
    s.line(flute, "E6:16 C6:16 F6:16 D6:16 G6:16 E6:16 F6:16 D6:16", start=8 * 16, pan=0.45, vol=0.35, octave=-1)
    pads(s, chords, 0, vol=0.8)
    bassline(s, chords, 0, "R-.F--..R-.F--..", vol=1.0)
    s.hits(rim, "x..x..x...x..x..", 16, pan=0.25)
    s.hits(kick, "x..x....x..x....", 16, vol=0.7)
    s.hits(shaker, "xooxxooxxooxxoox", 16, pan=-0.3)
    s.put(bell(2000), 7 * 16 + 12, 0.4)
    s.put(bell(2000), 7 * 16 + 14, 0.4)
    echo(s, "echo", 3, feedback=0.38, wet=0.3, damp=3000)
    return s


SONGS = {name: fn for name, fn in globals().items() if name == "title" or name.startswith(("race_", "cruise_"))}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name in sys.argv[1:] or sorted(SONGS):
        secs = write(name, SONGS[name]())
        print("music/%s.wav  (%.1f s loop)" % (name, secs))
