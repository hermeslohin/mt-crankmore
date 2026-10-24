#!/usr/bin/env python3
"""
Mt. Crankmore <-> Zwift Ride bridge.

Godot has no Bluetooth LE support, so this small program talks BLE and relays over localhost UDP:

  trainer  (FTMS, standard)  -> power / cadence / speed        -> game  (UDP 9871)
  game  -> road grade (town hills, Mt. Crankmore) + virtual gear -> trainer resistance (FTMS simulation)
  Zwift Ride controllers (proprietary, service 0xFC82) -> button presses -> game

Normally the game starts this for you ("Connect Zwift Ride" on the title screen) in --managed mode,
where the game tells it what to scan for and which devices to connect, and the chosen devices are
remembered in devices.json.

Manual usage:
  python zwift_bridge.py              # scan, auto-connect the first trainer + controllers, relay
  python zwift_bridge.py --scan       # list nearby BLE devices and exit
  python zwift_bridge.py --dump       # also print raw controller messages (for debugging)
  python zwift_bridge.py --learn      # teach the bridge your controller's buttons (writes buttons.json)
  python zwift_bridge.py --fake       # fake trainer data, no Bluetooth (tests the game link)

Close the Zwift app (and anything else holding the devices) first: BLE devices accept one connection.
"""
import argparse
import asyncio
import json
import math
import socket
import struct
import sys
import time
from pathlib import Path

try:
    from bleak import BleakClient, BleakScanner
except ImportError:  # --fake works without bleak
    BleakClient = BleakScanner = None

GAME_ADDR = ("127.0.0.1", 9871)
LISTEN_PORT = 9872

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"
FTMS_CONTROL_POINT = "00002ad9-0000-1000-8000-00805f9b34fb"

ZWIFT_SERVICE = "0000fc82-0000-1000-8000-00805f9b34fb"
ZWIFT_ASYNC = "00000002-19ca-4651-86e5-fa29dcdd09d1"      # notifications: buttons
ZWIFT_SYNC_RX = "00000003-19ca-4651-86e5-fa29dcdd09d1"     # write: handshake
ZWIFT_SYNC_TX = "00000004-19ca-4651-86e5-fa29dcdd09d1"     # indications: handshake replies
ZWIFT_COMPANY_ID = 0x094A
HANDSHAKE = b"RideOn"

# Zwift Ride button bits (reported active-low). Reverse-engineered by the community and not
# officially documented: if a button does nothing, run --learn to record your own mapping.
DEFAULT_BITS = {
    0x00001: "LEFT", 0x00002: "UP", 0x00004: "RIGHT", 0x00008: "DOWN",
    0x00010: "A", 0x00020: "B", 0x00040: "Y", 0x00080: "Z",
    0x00100: "LS1", 0x00200: "LS2", 0x00400: "POWERUP_L", 0x00800: "ONOFF_L",       # left shifter
    0x01000: "RS1", 0x02000: "RS2", 0x04000: "POWERUP_R", 0x08000: "ONOFF_R",       # right shifter (RS1 = 0x1000, checked on a real Ride)
}
LEARN_ORDER = ["LEFT", "RIGHT", "UP", "DOWN", "A", "B", "Y", "Z", "LS1", "LS2", "RS1", "RS2",
               "POWERUP_L", "POWERUP_R"]
BUTTONS_FILE = Path(__file__).with_name("buttons.json")
DEVICES_FILE = Path(__file__).with_name("devices.json")
ROLES = ("trainer", "controller")


class State:
    def __init__(self):
        self.power = 0.0
        self.cadence = 0.0
        self.speed = 0.0
        self.trainer = False
        self.controller = False
        self.trainer_seen = 0.0
        self.pressed = set()
        self.taps = set()           # buttons pressed since the last packet, so a quick tap is never missed
        self.grade = 0.0
        self.gear = 1.0             # virtual gear ratio relative to the neutral gear (1.0 = no change)
        self.mass = 85.0            # rider + bike, kg
        self.mask = None            # last raw button mask (for --learn)
        self.control_ready = False
        # what the game asked for, and what is actually happening
        self.want = {"trainer": None, "controller": None}
        self.conn = {r: {"state": "idle", "name": "", "address": ""} for r in ROLES}
        self.scan_on = False
        self.error = ""
        self.last_ping = time.time()
        self.quit = False


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def load_saved(state: State):
    try:
        d = json.loads(DEVICES_FILE.read_text())
        for r in ROLES:
            if d.get(r):
                state.want[r] = d[r]
    except Exception:
        pass


def save_wanted(state: State):
    try:
        DEVICES_FILE.write_text(json.dumps({r: state.want[r] for r in ROLES}, indent=2))
    except Exception as e:
        log("could not save devices.json:", e)


# ---------------------------------------------------------------- discovery

def uuids(adv):
    return {u.lower() for u in (adv.service_uuids or [])}


def name_of(dev, adv):
    return adv.local_name or dev.name or ""


def is_trainer(dev, adv):
    return FTMS_SERVICE in uuids(adv)


def is_zwift_controller(dev, adv):
    if is_trainer(dev, adv):
        return False
    return (ZWIFT_SERVICE in uuids(adv) or ZWIFT_COMPANY_ID in (adv.manufacturer_data or {})
            or "zwift" in name_of(dev, adv).lower())


class Discovery:
    """One shared scan loop. Scans while the game asks for it, or while a wanted device isn't connected."""

    def __init__(self, state: State, always: bool):
        self.state = state
        self.always = always
        self.seen = {}
        self.busy = set()

    def _needed(self):
        s = self.state
        if self.always or s.scan_on:
            return True
        return any(s.want[r] and s.conn[r]["state"] != "connected" for r in ROLES)

    async def run(self):
        while not self.state.quit:
            if not self._needed():
                await asyncio.sleep(0.5)
                continue
            try:
                found = await BleakScanner.discover(timeout=3.0, return_adv=True)
                now = time.time()
                for addr, (dev, adv) in found.items():
                    self.seen[addr] = (dev, adv, now)
                self.state.error = ""
            except Exception as e:  # Bluetooth off, permissions...
                self.state.error = f"Bluetooth scan failed: {e}"
                log(self.state.error)
                await asyncio.sleep(2.0)
            await asyncio.sleep(0.3)

    def find(self, pred):
        best = None
        for addr, (dev, adv, ts) in self.seen.items():
            if addr in self.busy or time.time() - ts > 30:
                continue
            if pred(dev, adv):
                if best is None or (adv.rssi or -999) > (best[1].rssi or -999):
                    best = (dev, adv)
        return best

    def device_list(self):
        out = []
        for addr, (dev, adv, ts) in self.seen.items():
            if time.time() - ts > 25:
                continue
            trainer = is_trainer(dev, adv)
            controller = is_zwift_controller(dev, adv)
            if not (trainer or controller):
                continue
            out.append({"address": addr, "name": name_of(dev, adv) or "(unnamed)", "rssi": adv.rssi or -99,
                        "kind": "trainer" if trainer else "controller"})
        out.sort(key=lambda d: (d["kind"] != "trainer", -d["rssi"]))
        return out


# ---------------------------------------------------------------- trainer (FTMS)

def parse_indoor_bike_data(data: bytes) -> dict:
    flags = struct.unpack_from("<H", data, 0)[0]
    off = 2
    out = {}
    if not flags & 0x0001:                      # bit 0 == 0: instantaneous speed present
        out["speed"] = struct.unpack_from("<H", data, off)[0] * 0.01
        off += 2
    if flags & 0x0002:
        off += 2                                 # average speed
    if flags & 0x0004:
        out["cadence"] = struct.unpack_from("<H", data, off)[0] * 0.5
        off += 2
    if flags & 0x0008:
        off += 2                                 # average cadence
    if flags & 0x0010:
        off += 3                                 # total distance
    if flags & 0x0020:
        off += 2                                 # resistance level
    if flags & 0x0040:
        out["power"] = struct.unpack_from("<h", data, off)[0]
    return out


SIM_CRR = 0.004
SIM_CW = 0.51       # kg/m, what we tell the trainer the air drag is (0.5 * rho * CdA)


def virtual_grade(grade_pct: float, ratio: float, speed_kmh: float, mass: float) -> float:
    """Virtual shifting on a plain FTMS trainer: the grade that makes the trainer push back like the
    road would in a gear `ratio` times the neutral one. Pedalling at the trainer's own wheel speed v,
    a gear r means the bike really goes r*v, so the pedal force is r * (climbing + rolling + drag at r*v)."""
    if abs(ratio - 1.0) < 1e-3:
        return grade_pct
    g = 9.81
    v = max(0.0, speed_kmh) / 3.6
    want = ratio * (mass * g * (grade_pct / 100.0 + SIM_CRR) + SIM_CW * (ratio * v) ** 2)
    # what the trainer itself adds for rolling and drag at its wheel speed
    eff = (want - SIM_CW * v * v) / (mass * g) - SIM_CRR
    return max(-10.0, min(20.0, eff * 100.0))


def sim_packet(grade_pct: float) -> bytes:
    grade = max(-20.0, min(20.0, grade_pct))
    # opcode 0x11: wind speed (0.001 m/s), grade (0.01 %), crr (0.0001), cw (0.01 kg/m)
    return struct.pack("<BhhBB", 0x11, 0, int(round(grade * 100)), int(SIM_CRR * 10000), int(SIM_CW * 100))


async def trainer_session(client, state: State, addr: str):
    def on_data(_, data: bytearray):
        try:
            d = parse_indoor_bike_data(bytes(data))
        except Exception:
            return
        state.power = float(d.get("power", state.power))
        state.cadence = float(d.get("cadence", state.cadence))
        state.speed = float(d.get("speed", state.speed))
        state.trainer = True
        state.trainer_seen = time.time()

    # FTMS control point replies: 0x80, request opcode, result (0x01 = success, 0x05 = control not permitted)
    need_control = {"flag": False}

    def on_cp(_, data: bytearray):
        data = bytes(data)
        if len(data) >= 3 and data[0] == 0x80 and data[2] != 0x01:
            log(f"trainer: control point refused opcode 0x{data[1]:02x} (result {data[2]})")
            if data[2] == 0x05:
                need_control["flag"] = True

    async def take_control():
        await client.write_gatt_char(FTMS_CONTROL_POINT, bytes([0x00]), response=True)  # request control
        await client.write_gatt_char(FTMS_CONTROL_POINT, bytes([0x07]), response=True)  # start / resume

    await client.start_notify(INDOOR_BIKE_DATA, on_data)
    try:
        await client.start_notify(FTMS_CONTROL_POINT, on_cp)
        await take_control()
        state.control_ready = True
        log("trainer: resistance control ready (simulation mode)")
    except Exception as e:
        log("trainer: no resistance control (", e, ") - power/cadence still work")
    last_sent = None
    last_time = 0.0
    while client.is_connected and state.want["trainer"] == addr and not state.quit:
        if state.control_ready:
            try:
                if need_control["flag"]:
                    need_control["flag"] = False
                    await take_control()
                    last_sent = None
                # send on every change, and repeat every 2 s: some trainers fall back to a fixed
                # resistance if the app goes quiet
                grade = round(virtual_grade(state.grade, state.gear, state.speed, state.mass), 1)
                if last_sent is None or abs(grade - last_sent) >= 0.2 or time.time() - last_time > 2.0:
                    await client.write_gatt_char(FTMS_CONTROL_POINT, sim_packet(grade), response=True)
                    last_sent = grade
                    last_time = time.time()
            except Exception as e:
                log("trainer: grade write failed:", e)
        await asyncio.sleep(0.25)
    state.trainer = False
    state.control_ready = False


# ---------------------------------------------------------------- Zwift Ride controllers

def read_varint(buf: bytes, i: int):
    shift = 0
    val = 0
    while i < len(buf):
        b = buf[i]
        i += 1
        val |= (b & 0x7F) << shift
        if not b & 0x80:
            return val, i
        shift += 7
    raise ValueError("truncated varint")


def parse_pb(buf: bytes):
    fields = []
    i = 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = read_varint(buf, i)
        elif wt == 2:
            ln, i = read_varint(buf, i)
            v = buf[i:i + ln]
            i += ln
        elif wt == 5:
            v = struct.unpack_from("<I", buf, i)[0]
            i += 4
        elif wt == 1:
            v = struct.unpack_from("<Q", buf, i)[0]
            i += 8
        else:
            break
        fields.append((fn, wt, v))
    return fields


def load_buttons():
    if BUTTONS_FILE.exists():
        try:
            d = json.loads(BUTTONS_FILE.read_text())
            return bool(d.get("active_low", True)), {int(k): v for k, v in d["bits"].items()}
        except Exception as e:
            log("could not read buttons.json:", e)
    return True, dict(DEFAULT_BITS)


def decode_mask(mask: int, active_low: bool, bits: dict) -> set:
    pressed = set()
    for bit, name in bits.items():
        if bool(mask & bit) != active_low:
            pressed.add(name)
    return pressed


async def controller_session(client, state: State, addr: str, dump: bool):
    active_low, bits = load_buttons()

    def on_async(_, data: bytearray):
        data = bytes(data)
        if dump:
            log("async", data.hex())
        if len(data) < 2 or data[0] not in (0x23, 0x07):
            return
        try:
            fields = parse_pb(data[1:])
        except Exception:
            return
        for fn, wt, v in fields:
            if fn == 1 and wt == 0:
                state.mask = v
                state.pressed = decode_mask(v, active_low, bits)
                state.taps |= state.pressed
                if dump:
                    log("mask", hex(v), sorted(state.pressed))
                break

    def on_sync(_, data: bytearray):
        if dump:
            log("sync", bytes(data).hex())

    await client.start_notify(ZWIFT_ASYNC, on_async)
    try:
        await client.start_notify(ZWIFT_SYNC_TX, on_sync)
    except Exception:
        pass
    await client.write_gatt_char(ZWIFT_SYNC_RX, HANDSHAKE, response=False)
    state.controller = True
    while client.is_connected and state.want["controller"] == addr and not state.quit:
        await asyncio.sleep(0.3)
    state.controller = False
    state.pressed = set()


# ---------------------------------------------------------------- connection manager

async def role_task(role: str, state: State, disc: Discovery, args):
    """Keeps one device (trainer or controller) connected to whatever the game asked for."""
    auto_pred = is_trainer if role == "trainer" else is_zwift_controller
    name_filter = args.trainer if role == "trainer" else args.controller
    while not state.quit:
        addr = state.want[role]
        if addr is None and not args.managed:
            hit = disc.find(lambda d, a: auto_pred(d, a) and (not name_filter or name_filter.lower() in name_of(d, a).lower()))
            if hit:
                addr = state.want[role] = hit[0].address
        if addr is None:
            state.conn[role] = {"state": "idle", "name": "", "address": ""}
            await asyncio.sleep(0.5)
            continue
        entry = disc.seen.get(addr)
        if entry is None:
            state.conn[role] = {"state": "searching", "name": state.conn[role].get("name", ""), "address": addr}
            await asyncio.sleep(1.0)
            continue
        dev, adv, _ = entry
        nm = name_of(dev, adv) or addr
        state.conn[role] = {"state": "connecting", "name": nm, "address": addr}
        log(f"{role}: connecting to {nm}")
        disc.busy.add(addr)
        try:
            async with BleakClient(dev) as client:
                state.conn[role] = {"state": "connected", "name": nm, "address": addr}
                log(f"{role}: connected")
                if args.managed:
                    save_wanted(state)
                if role == "trainer":
                    await trainer_session(client, state, addr)
                else:
                    await controller_session(client, state, addr, args.dump)
            state.conn[role] = {"state": "idle", "name": "", "address": ""}
            log(f"{role}: disconnected")
        except Exception as e:
            state.conn[role] = {"state": "failed", "name": nm, "address": addr, "error": str(e)}
            log(f"{role}: connection failed/lost: {e}")
            await asyncio.sleep(2.0)
        finally:
            disc.busy.discard(addr)
            if role == "trainer":
                state.trainer = False
            else:
                state.controller = False
                state.pressed = set()
        await asyncio.sleep(0.5)


async def learn_task(state: State):
    """Interactive: press each button when asked; writes buttons.json."""
    loop = asyncio.get_running_loop()
    log("LEARN MODE: leave the controllers alone until asked...")
    while not state.controller or state.mask is None:
        await asyncio.sleep(0.5)
    await asyncio.sleep(2.0)
    baseline = state.mask
    bits = {}
    active_low = None
    for name in LEARN_ORDER:
        print(f"\n  Press and hold: {name}   (or type 's' + Enter to skip)", flush=True)
        skip = loop.run_in_executor(None, sys.stdin.readline)
        got = None
        while got is None:
            if skip.done():
                break
            if state.mask is not None and state.mask != baseline:
                await asyncio.sleep(0.25)       # let the mask settle
                diff = state.mask ^ baseline
                if diff and bin(diff).count("1") == 1:
                    got = diff
                    if active_low is None:
                        active_low = bool(baseline & diff)
                    bits[got] = name
                    print(f"    got bit {hex(got)}", flush=True)
            await asyncio.sleep(0.05)
        while state.mask != baseline and not skip.done():   # wait for release
            await asyncio.sleep(0.1)
    BUTTONS_FILE.write_text(json.dumps({"active_low": True if active_low is None else active_low,
                                        "bits": {str(k): v for k, v in bits.items()}}, indent=2))
    log("saved", BUTTONS_FILE, "- restart the bridge without --learn")
    state.quit = True


# ---------------------------------------------------------------- game link

async def sender_task(state: State, disc, args):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tick = 0
    while not state.quit:
        if state.trainer and time.time() - state.trainer_seen > 3.0:
            state.trainer = False
        msg = {"type": "data", "power": state.power, "cadence": state.cadence, "speed": state.speed,
               "trainer": state.trainer, "controller": state.controller, "buttons": sorted(state.pressed | state.taps)}
        state.taps = set()
        packets = [msg]
        if tick % 10 == 0:
            packets.append({"type": "status", "scanning": bool(disc and disc._needed()), "devices": disc.device_list() if disc else [],
                            "trainer": state.conn["trainer"], "controller": state.conn["controller"], "error": state.error,
                            "managed": args.managed})
        for p in packets:
            try:
                sock.sendto(json.dumps(p).encode(), GAME_ADDR)
            except OSError:
                pass
        tick += 1
        if args.managed and time.time() - state.last_ping > 10.0:
            log("game went away - exiting")
            state.quit = True
        await asyncio.sleep(0.05)


class CommandProtocol(asyncio.DatagramProtocol):
    """Messages from the game: {"grade": %, "gear": ratio, "mass": kg}, {"cmd": "ping"|"scan"|"connect"|"disconnect"|"quit", ...}."""

    def __init__(self, state: State):
        self.state = state

    def datagram_received(self, data, addr):
        try:
            d = json.loads(data.decode())
        except Exception:
            return
        s = self.state
        s.last_ping = time.time()
        if "grade" in d:
            grade = float(d["grade"])
            if grade != s.grade:
                log(f"grade -> {grade:+.1f}%")
            s.grade = grade
        if "gear" in d:
            gear = float(d["gear"])
            if gear != s.gear:
                log(f"gear ratio -> {gear:.2f}")
            s.gear = gear
        if "mass" in d:
            s.mass = max(30.0, float(d["mass"]))
        cmd = d.get("cmd")
        role = d.get("role")
        if cmd == "scan":
            s.scan_on = bool(d.get("on", True))
        elif cmd == "connect" and role in ROLES:
            s.want[role] = d.get("address")
        elif cmd == "disconnect" and role in ROLES:
            s.want[role] = None
            save_wanted(s)
        elif cmd == "quit":
            s.quit = True


async def fake_task(state: State):
    log("fake mode: pretending to be a trainer (sine-wave power)")
    t0 = time.time()
    state.controller = True
    state.conn["trainer"] = {"state": "connected", "name": "Fake Trainer", "address": "fake"}
    state.conn["controller"] = {"state": "connected", "name": "Fake Controls", "address": "fake"}
    while not state.quit:
        t = time.time() - t0
        state.power = 190 + 70 * math.sin(t * 0.4)
        state.cadence = 85 + 8 * math.sin(t * 0.7)
        state.speed = 20 + 5 * math.sin(t * 0.4)
        state.trainer = True
        state.trainer_seen = time.time()
        await asyncio.sleep(0.1)


async def error_only(state: State, args, message: str):
    """bleak missing: keep telling the game why, so it can show it."""
    state.error = message
    await sender_task(state, None, args)


# ---------------------------------------------------------------- main

async def scan_once():
    log("scanning for 8 s...")
    found = await BleakScanner.discover(timeout=8.0, return_adv=True)
    for addr, (dev, adv) in sorted(found.items(), key=lambda kv: -(kv[1][1].rssi or -999)):
        tags = []
        if is_trainer(dev, adv):
            tags.append("TRAINER(FTMS)")
        if is_zwift_controller(dev, adv):
            tags.append("ZWIFT")
        print(f"  {adv.rssi:>4} dB  {name_of(dev, adv) or '?':<28} {addr}  {' '.join(tags)}")


async def amain(args):
    if args.scan:
        await scan_once()
        return
    state = State()
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(lambda: CommandProtocol(state), local_addr=("127.0.0.1", LISTEN_PORT))
    if args.fake:
        await asyncio.gather(sender_task(state, None, args), fake_task(state))
        return
    if BleakClient is None:
        if args.managed:
            await error_only(state, args, "The Bluetooth library (bleak) is missing. Choose 'Install Bluetooth helper'.")
            return
        sys.exit("bleak is not installed: pip install -r requirements.txt")
    if args.managed:
        load_saved(state)
    disc = Discovery(state, always=not args.managed)
    tasks = [sender_task(state, disc, args), disc.run()]
    if not args.no_trainer:
        tasks.append(role_task("trainer", state, disc, args))
    if not args.no_controller:
        tasks.append(role_task("controller", state, disc, args))
    if args.learn:
        tasks.append(learn_task(state))
    log(f"relaying to game at {GAME_ADDR[0]}:{GAME_ADDR[1]}; listening on {LISTEN_PORT}" + (" (managed by the game)" if args.managed else ""))
    runners = [asyncio.ensure_future(t) for t in tasks]
    while not state.quit:
        await asyncio.sleep(0.2)
    await asyncio.sleep(0.5)  # let sessions notice and disconnect cleanly
    for r in runners:
        r.cancel()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--managed", action="store_true", help="controlled by the game (scan/connect on request)")
    ap.add_argument("--scan", action="store_true", help="list nearby BLE devices and exit")
    ap.add_argument("--dump", action="store_true", help="print raw controller messages")
    ap.add_argument("--learn", action="store_true", help="record your controller's button bits")
    ap.add_argument("--fake", action="store_true", help="send fake trainer data (no Bluetooth)")
    ap.add_argument("--no-trainer", action="store_true")
    ap.add_argument("--no-controller", action="store_true")
    ap.add_argument("--trainer", help="only auto-connect a trainer whose name contains this")
    ap.add_argument("--controller", help="only auto-connect a controller whose name contains this")
    args = ap.parse_args()
    try:
        asyncio.run(amain(args))
    except KeyboardInterrupt:
        pass
    except OSError as e:
        sys.exit(f"bridge could not start: {e} (is another copy already running?)")


if __name__ == "__main__":
    main()
