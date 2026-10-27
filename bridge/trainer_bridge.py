#!/usr/bin/env python3
"""
Mt. Crankmore <-> bicycle trainer bridge.

Godot has no Bluetooth LE support, so this small program talks BLE and relays over localhost UDP:

  trainer  (FTMS, standard)  -> power / cadence / speed        -> game  (UDP 9871)
  game  -> road grade (town hills, Mt. Crankmore) + virtual gear -> trainer resistance (FTMS simulation)
  or a power meter (Cycling Power, 0x1818: pedals, cranks, spiders) -> power / cadence -> game
     (no resistance to control: hills and virtual gears don't change how hard it feels, shift the real bike)
  handlebar controllers (proprietary, service 0xFC82) -> button presses -> game

Wi-Fi / Ethernet trainers (Wahoo KICKR and others with "Direct Connect", a.k.a. DIRCON) work too: they are found over
mDNS (needs the zeroconf package; without it only Bluetooth is used) and carry the same FTMS / Cycling Power services
over TCP, so they are listed, connected, remembered and controlled just like Bluetooth trainers. Their address is
"wifi:<name>" (the name they announce, which stays put when their IP changes).

Normally the game starts this for you ("Connect Trainer" on the title screen) in --managed mode,
where the game tells it what to scan for and which devices to connect, and the chosen devices are
remembered in devices.json.

Manual usage:
  python trainer_bridge.py              # scan, auto-connect the first trainer + controllers, relay
  python trainer_bridge.py --scan       # list nearby BLE devices and Wi-Fi trainers and exit
  python trainer_bridge.py --dump       # also print raw controller messages (for debugging)
  python trainer_bridge.py --learn      # teach the bridge your controller's buttons (writes buttons.json)
  python trainer_bridge.py --inspect --no-trainer   # record what every button / paddle sends (writes inspect.log)
  python trainer_bridge.py --fake       # fake trainer data, no Bluetooth (tests the game link)

Close any other trainer app (and anything else holding the devices) first: BLE devices accept one connection.
"""
import argparse
import asyncio
import json
import math
import socket
import struct
import sys
import time
import uuid
from pathlib import Path

try:
    from bleak import BleakClient, BleakScanner
except ImportError:  # --fake works without bleak
    BleakClient = BleakScanner = None

try:
    from zeroconf import IPVersion, ServiceStateChange
    from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf
except ImportError:  # only needed for Wi-Fi trainers: Bluetooth works without it
    AsyncZeroconf = None

GAME_ADDR = ("127.0.0.1", 9871)
LISTEN_PORT = 9872

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"
FTMS_CONTROL_POINT = "00002ad9-0000-1000-8000-00805f9b34fb"

CPS_SERVICE = "00001818-0000-1000-8000-00805f9b34fb"       # Cycling Power: power meters (and many trainers too)
CP_MEASUREMENT = "00002a63-0000-1000-8000-00805f9b34fb"

CTRL_SERVICE = "0000fc82-0000-1000-8000-00805f9b34fb"
CTRL_ASYNC = "00000002-19ca-4651-86e5-fa29dcdd09d1"      # notifications: buttons
CTRL_SYNC_RX = "00000003-19ca-4651-86e5-fa29dcdd09d1"     # write: handshake
CTRL_SYNC_TX = "00000004-19ca-4651-86e5-fa29dcdd09d1"     # indications: handshake replies
CTRL_COMPANY_ID = 0x094A
HANDSHAKE = b"RideOn"

WIFI_SERVICE = "_wahoo-fitness-tnp._tcp.local."   # what Wi-Fi trainers (Direct Connect / DIRCON) announce over mDNS
WIFI_PREFIX = "wifi:"                             # a Wi-Fi trainer's address: this + its announced name

# Handlebar controller button bits (reported active-low). Reverse-engineered by the community and not
# officially documented: if a button does nothing, run --learn to record your own mapping.
DEFAULT_BITS = {
    0x00001: "LEFT", 0x00002: "UP", 0x00004: "RIGHT", 0x00008: "DOWN",
    0x00010: "A", 0x00020: "B", 0x00040: "Y", 0x00080: "Z",
    0x00100: "LS1", 0x00200: "LS2", 0x00400: "POWERUP_L", 0x00800: "ONOFF_L",       # left shifter
    0x01000: "RS1", 0x02000: "RS2", 0x04000: "POWERUP_R", 0x08000: "ONOFF_R",       # right shifter (RS1 = 0x1000, checked on real hardware)
}
# The paddles are analog, separate from the button bits: each keypad message (0x23) carries field 3 entries
# {1: location (0 = left, 1 = right; 0 is left out), 2: zigzag value 0..100}. Squeezed past PADDLE_ON a paddle
# counts as a held button. (Right paddle checked on a Zwift Ride; left assumed to be location 0.)
PADDLES = {0: "PADDLE_L", 1: "PADDLE_R"}
PADDLE_ON = 30
LEARN_ORDER = ["LEFT", "RIGHT", "UP", "DOWN", "A", "B", "Y", "Z", "LS1", "LS2", "RS1", "RS2",
               "POWERUP_L", "POWERUP_R"]
BUTTONS_FILE = Path(__file__).with_name("buttons.json")
DEVICES_FILE = Path(__file__).with_name("devices.json")
LOG_FILE = Path(__file__).with_name("bridge.log")    # --managed: what happened, for when something goes wrong
STALL_S = 8.0       # no data from the trainer / power meter this long while "connected": drop it and reconnect
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
        self.recorder = None        # --inspect: called with every raw controller message
        self.control_ready = False
        # what the game asked for, and what is actually happening
        self.want = {"trainer": None, "controller": None}
        self.conn = {r: {"state": "idle", "name": "", "address": ""} for r in ROLES}
        self.scan_on = False
        self.error = ""
        self.last_ping = time.time()
        self.quit = False


_log_file = None


def log(*a):
    line = " ".join(str(x) for x in (time.strftime("%H:%M:%S"),) + a)
    print(line, flush=True)
    if _log_file is not None:
        try:
            _log_file.write(line + "\n")
            _log_file.flush()
        except Exception:
            pass


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
    """Anything that can supply the power: a smart trainer (FTMS) or a power meter (Cycling Power)."""
    u = uuids(adv)
    return FTMS_SERVICE in u or CPS_SERVICE in u


def is_power_meter(dev, adv):
    """Power only, no trainer to control. A trainer offering both is used as a trainer."""
    u = uuids(adv)
    return CPS_SERVICE in u and FTMS_SERVICE not in u


def is_controller(dev, adv):
    if is_trainer(dev, adv) or getattr(dev, "wifi", False):
        return False
    return (CTRL_SERVICE in uuids(adv) or CTRL_COMPANY_ID in (adv.manufacturer_data or {})
            or "zwift" in name_of(dev, adv).lower())


class WifiDevice:
    """A Wi-Fi trainer found over mDNS. It stands in for both the BLE device and its advertisement in Discovery.seen,
    so is_trainer, name_of, find and device_list work on it unchanged."""
    wifi = True
    rssi = -50                  # no signal strength over Wi-Fi: rank it like a nearby Bluetooth device
    manufacturer_data = {}

    def __init__(self, name: str, host: str, port: int, service_uuids: list):
        self.name = self.local_name = name
        self.address = WIFI_PREFIX + name
        self.host = host
        self.port = port
        self.service_uuids = service_uuids


def wifi_uuids(txt: str) -> list:
    """The "ble-service-uuids" TXT entry: 16-bit ("1826" or "0x1826") or full UUIDs, comma-separated."""
    out = []
    for u in txt.split(","):
        u = u.strip().lower()
        if u.startswith("0x"):
            u = u[2:]
        if len(u) == 4:
            u = f"0000{u}-0000-1000-8000-00805f9b34fb"
        if u:
            out.append(u)
    return out or [FTMS_SERVICE]   # no hint: it's still a trainer (trainer_session checks what it really offers)


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

    async def run_wifi(self):
        """Wi-Fi trainers: browse mDNS all along, and while scanning re-resolve each one (its IP / port can change)."""
        if AsyncZeroconf is None:
            log("Wi-Fi trainers: off - the zeroconf package is missing (reinstall the helper); Bluetooth still works")
            return
        names = set()

        def changed(zeroconf, service_type, name, state_change):
            if state_change == ServiceStateChange.Removed:
                names.discard(name)
                self.seen.pop(WIFI_PREFIX + name.removesuffix("." + WIFI_SERVICE), None)
            else:
                names.add(name)

        try:
            azc = AsyncZeroconf()
            browser = AsyncServiceBrowser(azc.zeroconf, WIFI_SERVICE, handlers=[changed])
        except Exception as e:   # no network, mDNS port unavailable...
            log("Wi-Fi trainers: mDNS discovery could not start:", e)
            return
        try:
            while not self.state.quit:
                if self._needed() and names:
                    await asyncio.gather(*(self._resolve(azc, n) for n in list(names)))
                await asyncio.sleep(2.0)
        finally:
            await browser.async_cancel()
            await azc.async_close()

    async def _resolve(self, azc, name: str):
        info = AsyncServiceInfo(WIFI_SERVICE, name)
        try:
            if not await info.async_request(azc.zeroconf, 3000):
                return
        except Exception:
            return
        hosts = info.parsed_addresses(IPVersion.V4Only) or info.parsed_scoped_addresses()
        if not hosts or not info.port:
            return
        txt = (info.properties or {}).get(b"ble-service-uuids") or b""
        dev = WifiDevice(name.removesuffix("." + WIFI_SERVICE), hosts[0], info.port,
                         wifi_uuids(txt.decode("utf-8", "replace")))
        self.seen[dev.address] = (dev, dev, time.time())

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
            controller = is_controller(dev, adv)
            if not (trainer or controller):
                continue
            out.append({"address": addr, "name": name_of(dev, adv) or "(unnamed)", "rssi": adv.rssi or -99,
                        "kind": "trainer" if trainer else "controller", "power_meter": is_power_meter(dev, adv),
                        "wifi": getattr(dev, "wifi", False)})
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


# ---------------------------------------------------------------- power meter (Cycling Power)

def parse_cycling_power(data: bytes) -> dict:
    """Cycling Power Measurement: flags, instantaneous power, then optional fields in a fixed order.
    Returns power, and the crank revolution data (count, event time in 1/1024 s) when it's there."""
    flags = struct.unpack_from("<H", data, 0)[0]
    out = {"power": struct.unpack_from("<h", data, 2)[0]}
    off = 4
    if flags & 0x0001:
        off += 1                                 # pedal power balance
    if flags & 0x0004:
        off += 2                                 # accumulated torque
    if flags & 0x0010:
        off += 6                                 # wheel revolutions (u32) + last wheel event time (u16)
    if flags & 0x0020 and len(data) >= off + 4:
        out["crank_revs"], out["crank_time"] = struct.unpack_from("<HH", data, off)
    return out


class Cadence:
    """Cadence from a power meter's crank revolution counter and event clock (both wrap at 65536)."""

    def __init__(self):
        self.last = None
        self.rpm = 0.0
        self.moved_at = 0.0

    def update(self, revs: int, t1024: int, now: float) -> float:
        if self.last is not None:
            dr = (revs - self.last[0]) & 0xFFFF
            dt = ((t1024 - self.last[1]) & 0xFFFF) / 1024.0
            if dr > 0 and dt > 0:
                rpm = dr / dt * 60.0
                if rpm < 250:
                    self.rpm = rpm
                self.moved_at = now
        self.last = (revs, t1024)
        if now - self.moved_at > 3.0:   # no new pedal stroke for a while: stopped
            self.rpm = 0.0
        return self.rpm


async def power_meter_session(client, state: State, addr: str):
    cad = Cadence()

    def on_data(_, data: bytearray):
        try:
            d = parse_cycling_power(bytes(data))
        except Exception:
            return
        now = time.time()
        state.power = float(max(0, d["power"]))
        if "crank_revs" in d:
            state.cadence = cad.update(d["crank_revs"], d["crank_time"], now)
        state.speed = 0.0                        # a power meter doesn't know; the game works it out from the watts
        state.trainer = True
        state.trainer_seen = now

    await client.start_notify(CP_MEASUREMENT, on_data)
    state.control_ready = False
    log("trainer: power meter (Cycling Power) - power and cadence only, no resistance control")
    state.trainer_seen = time.time()
    while client.is_connected and state.want["trainer"] == addr and not state.quit:
        if time.time() - state.trainer_seen > STALL_S:   # gone quiet (see trainer_session)
            log(f"trainer: power meter sent nothing for {STALL_S:.0f} s - reconnecting")
            break
        await asyncio.sleep(0.25)
    state.trainer = False


async def trainer_session(client, state: State, addr: str):
    if client.services.get_service(FTMS_SERVICE) is None:
        if client.services.get_service(CPS_SERVICE) is not None:
            await power_meter_session(client, state, addr)
            return
        log("trainer: neither a trainer (FTMS) nor a power meter (Cycling Power) service on this device")
        return

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
    state.trainer_seen = time.time()
    while client.is_connected and state.want["trainer"] == addr and not state.quit:
        # a trainer that has gone quiet but still looks connected (it glitched, or slept): drop it and reconnect,
        # rather than sitting on a dead link with the rider stuck at 0 W
        if time.time() - state.trainer_seen > STALL_S:
            log(f"trainer: no data for {STALL_S:.0f} s - reconnecting")
            break
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


# ---------------------------------------------------------------- handlebar controllers

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
        if state.recorder:
            state.recorder(data)
        if dump:
            log("async", data.hex())
        if len(data) < 2 or data[0] not in (0x23, 0x07):
            return
        try:
            fields = parse_pb(data[1:])
        except Exception:
            return
        pressed = None
        paddles = set()
        for fn, wt, v in fields:
            if fn == 1 and wt == 0:
                state.mask = v
                pressed = decode_mask(v, active_low, bits)
            elif fn == 3 and wt == 2:
                try:
                    sub = {f: x for f, w, x in parse_pb(v) if w == 0}
                except Exception:
                    continue
                raw = sub.get(2, 0)
                if abs((raw >> 1) ^ -(raw & 1)) >= PADDLE_ON and sub.get(1, 0) in PADDLES:
                    paddles.add(PADDLES[sub.get(1, 0)])
        if pressed is not None:
            state.pressed = pressed | paddles
            state.taps |= state.pressed
            if dump:
                log("mask", hex(state.mask), sorted(state.pressed))

    def on_sync(_, data: bytearray):
        if dump:
            log("sync", bytes(data).hex())

    await client.start_notify(CTRL_ASYNC, on_async)
    try:
        await client.start_notify(CTRL_SYNC_TX, on_sync)
    except Exception:
        pass
    await client.write_gatt_char(CTRL_SYNC_RX, HANDSHAKE, response=False)
    state.controller = True
    while client.is_connected and state.want["controller"] == addr and not state.quit:
        await asyncio.sleep(0.3)
    state.controller = False
    state.pressed = set()


# ---------------------------------------------------------------- Wi-Fi trainers (Direct Connect / DIRCON)
#
# "BLE over TCP": the trainer serves its usual Bluetooth services on a TCP port (usually 36866) it announces over mDNS.
# Every message is a 6-byte header - version (1), message id, sequence number, response code (0 = ok), payload length
# (u16, big-endian) - then the payload, which starts with a full 16-byte UUID written in its usual reading order (not
# BLE's reversed bytes). A request is answered with the same id and sequence number; id 6 is a notification. There is
# no official spec: see github.com/elfrances/wahoo-fitness-tnp and qdomyos-zwift (src/devices/dircon).

DC_DISCOVER_SERVICES = 0x01
DC_DISCOVER_CHARS = 0x02
DC_WRITE = 0x04
DC_ENABLE_NOTIFY = 0x05
DC_NOTIFICATION = 0x06
DC_ERRORS = {1: "unknown message", 2: "error", 3: "service not found", 4: "characteristic not found",
             5: "operation not supported", 6: "write failed"}


class DirconServices:
    def __init__(self, service_uuids):
        self.uuids = set(service_uuids)

    def get_service(self, u: str):
        return u if u.lower() in self.uuids else None


class DirconClient:
    """A Wi-Fi trainer with the parts of BleakClient the sessions use (start_notify, write_gatt_char, is_connected,
    services.get_service), so trainer_session and its watchdog drive it exactly like a Bluetooth one."""

    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.services = DirconServices([])
        self._reader = self._writer = self._task = None
        self._closed = False
        self._lock = asyncio.Lock()
        self._seq = 0
        self._pending = None        # (message id, sequence number, future) of the request waiting for its reply
        self._notify = {}           # characteristic UUID -> callback(sender, data)

    @property
    def is_connected(self) -> bool:
        return self._writer is not None and not self._closed

    async def __aenter__(self):
        self._reader, self._writer = await asyncio.wait_for(asyncio.open_connection(self.host, self.port), 10.0)
        sock = self._writer.get_extra_info("socket")
        if sock is not None:
            try:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)   # tiny messages: send them right away
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            except OSError:
                pass
        self._task = asyncio.ensure_future(self._read_loop())
        try:
            reply = await self._request(DC_DISCOVER_SERVICES, b"")
            found = [str(uuid.UUID(bytes=reply[i:i + 16])) for i in range(0, len(reply) - 15, 16)]
            for s in found:   # discover characteristics too, as a BLE app would: some trainers expect it
                try:
                    await self._request(DC_DISCOVER_CHARS, uuid.UUID(s).bytes)
                except Exception:
                    pass
            self.services = DirconServices(found)
        except BaseException:
            await self.close()
            raise
        return self

    async def __aexit__(self, *exc):
        await self.close()

    async def close(self):
        self._closed = True
        if self._task is not None:
            self._task.cancel()
        if self._writer is not None:
            self._writer.close()
            try:
                await asyncio.wait_for(self._writer.wait_closed(), 2.0)
            except Exception:
                pass

    async def start_notify(self, char: str, callback):
        key = str(uuid.UUID(char))
        self._notify[key] = callback
        try:
            await self._request(DC_ENABLE_NOTIFY, uuid.UUID(char).bytes + b"\x01")
        except Exception:
            self._notify.pop(key, None)
            raise

    async def write_gatt_char(self, char: str, data: bytes, response: bool = True):
        await self._request(DC_WRITE, uuid.UUID(char).bytes + bytes(data))   # always acknowledged over TCP

    async def _request(self, msg: int, payload: bytes) -> bytes:
        async with self._lock:   # one request at a time, like GATT
            if not self.is_connected:
                raise ConnectionError("Wi-Fi trainer connection closed")
            self._seq = (self._seq + 1) & 0xFF
            fut = asyncio.get_running_loop().create_future()
            self._pending = (msg, self._seq, fut)
            try:
                self._writer.write(struct.pack(">BBBBH", 1, msg, self._seq, 0, len(payload)) + payload)
                await self._writer.drain()
                code, data = await asyncio.wait_for(fut, 5.0)
            except asyncio.TimeoutError:
                raise TimeoutError(f"no reply from the Wi-Fi trainer (message {msg})") from None
            finally:
                self._pending = None
        if code:
            raise RuntimeError(f"Wi-Fi trainer refused message {msg}: {DC_ERRORS.get(code, code)}")
        return data

    async def _read_loop(self):
        try:
            while True:
                _, msg, seq, code, n = struct.unpack(">BBBBH", await self._reader.readexactly(6))
                data = await self._reader.readexactly(n) if n else b""
                if msg == DC_NOTIFICATION:
                    cb = self._notify.get(str(uuid.UUID(bytes=data[:16]))) if len(data) >= 16 else None
                    if cb is not None:
                        try:
                            cb(str(uuid.UUID(bytes=data[:16])), bytearray(data[16:]))
                        except Exception as e:
                            log("Wi-Fi trainer: notification handler failed:", e)
                    continue
                p = self._pending
                if p is not None and p[0] == msg and p[1] == seq and not p[2].done():
                    p[2].set_result((code, data))
                # anything else (a late reply, a message id we don't know) is ignored
        except (asyncio.IncompleteReadError, OSError):
            pass
        finally:
            self._closed = True
            p = self._pending
            if p is not None and not p[2].done():
                p[2].set_exception(ConnectionError("Wi-Fi trainer connection closed"))


# ---------------------------------------------------------------- connection manager

async def role_task(role: str, state: State, disc: Discovery, args):
    """Keeps one device (trainer or controller) connected to whatever the game asked for."""
    auto_pred = is_trainer if role == "trainer" else is_controller
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
        wifi = getattr(dev, "wifi", False)
        state.conn[role] = {"state": "connecting", "name": nm, "address": addr}
        log(f"{role}: connecting to {nm}" + (f" over Wi-Fi ({dev.host}:{dev.port})" if wifi else ""))
        disc.busy.add(addr)
        try:
            async with (DirconClient(dev.host, dev.port) if wifi else BleakClient(dev)) as client:
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


def describe_pb(buf: bytes, depth: int = 0) -> str:
    """Every protobuf field in a message, nested ones in braces; varints also shown zigzag-decoded (z=...)."""
    try:
        fields = parse_pb(buf)
    except Exception:
        return buf.hex()
    out = []
    for fn, wt, v in fields:
        if wt == 0:
            out.append(f"{fn}={v:#x}" + (f"(z={(v >> 1) ^ -(v & 1)})" if v < 0x10000 else ""))
        elif wt == 2 and depth < 3 and v:
            out.append(f"{fn}{{{describe_pb(v, depth + 1)}}}")
        else:
            out.append(f"{fn}:{v.hex() if isinstance(v, bytes) else v}")
    return " ".join(out)


INSPECT_STEPS = [
    ("leave everything alone", 5),
    ("press and release LS1 (left shift) a few times", 6),
    ("press and release RS1 (right shift) a few times", 6),
    ("squeeze the LEFT paddle slowly all the way, then let go", 6),
    ("squeeze the RIGHT paddle slowly all the way, then let go", 6),
    ("press and release LS2", 5),
    ("press and release RS2", 5),
    ("press each of the D-pad buttons", 6),
]
INSPECT_FILE = Path(__file__).with_name("inspect.log")


async def inspect_task(state: State):
    """Guided: asks for one button / paddle at a time and records every distinct message it sends to inspect.log."""
    lines = []
    step = ["(connecting)"]
    seen = set()

    def note(text):
        print(text, flush=True)
        lines.append(text)

    def rec(data: bytes):
        key = (step[0], data)
        if key in seen:
            return
        seen.add(key)
        mask = None
        for fn, wt, v in parse_pb(data[1:]) if len(data) > 1 else []:
            if fn == 1 and wt == 0:
                mask = v
        names = sorted(decode_mask(mask, True, dict(DEFAULT_BITS))) if mask is not None else []
        note(f"    {data.hex()}   type {data[0]:#04x}   {describe_pb(data[1:])}   buttons {names}")

    log("INSPECT MODE: waiting for the controller (pedal / press a button to wake it)...")
    while not state.controller:
        await asyncio.sleep(0.5)
    state.recorder = rec
    for text, secs in INSPECT_STEPS:
        step[0] = text
        note(f"\n>>> {text.upper()}  ({secs} s)")
        await asyncio.sleep(secs)
    state.recorder = None
    INSPECT_FILE.write_text("\n".join(lines) + "\n")
    log("saved", INSPECT_FILE)
    state.quit = True


async def record_task(state: State):
    """Logs every change in what the controller sends, with a timestamp, to inspect.log until stopped."""
    f = INSPECT_FILE.open("w")
    last = [b""]

    def rec(data: bytes):
        if data == last[0]:
            return
        last[0] = data
        mask = None
        for fn, wt, v in parse_pb(data[1:]) if len(data) > 1 else []:
            if fn == 1 and wt == 0:
                mask = v
        names = sorted(decode_mask(mask, True, dict(DEFAULT_BITS))) if mask is not None else []
        f.write(f"{time.strftime('%H:%M:%S')}  {data.hex()}   {describe_pb(data[1:])}   buttons {names}\n")
        f.flush()

    while not state.controller:
        await asyncio.sleep(0.5)
    f.write(f"{time.strftime('%H:%M:%S')}  controller connected\n")
    f.flush()
    state.recorder = rec
    while not state.quit:
        await asyncio.sleep(0.5)


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
    disc = Discovery(State(), always=True)   # Wi-Fi trainers: browse mDNS meanwhile
    wifi = asyncio.ensure_future(disc.run_wifi())
    found = await BleakScanner.discover(timeout=8.0, return_adv=True)
    disc.state.quit = True
    await wifi
    found.update({addr: (dev, adv) for addr, (dev, adv, _) in disc.seen.items()})
    for addr, (dev, adv) in sorted(found.items(), key=lambda kv: -(kv[1][1].rssi or -999)):
        tags = []
        if is_power_meter(dev, adv):
            tags.append("POWER METER")
        elif is_trainer(dev, adv):
            tags.append("TRAINER(FTMS)")
        if is_controller(dev, adv):
            tags.append("CONTROLLER")
        if getattr(dev, "wifi", False):
            print(f"  Wi-Fi    {name_of(dev, adv):<28} {addr} ({dev.host}:{dev.port})  {' '.join(tags)}")
        else:
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
        tasks.append(disc.run_wifi())
        tasks.append(role_task("trainer", state, disc, args))
    if not args.no_controller:
        tasks.append(role_task("controller", state, disc, args))
    if args.learn:
        tasks.append(learn_task(state))
    if args.inspect:
        tasks.append(inspect_task(state))
    if args.record:
        tasks.append(record_task(state))
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
    ap.add_argument("--scan", action="store_true", help="list nearby BLE devices and Wi-Fi trainers and exit")
    ap.add_argument("--dump", action="store_true", help="print raw controller messages")
    ap.add_argument("--learn", action="store_true", help="record your controller's button bits")
    ap.add_argument("--record", action="store_true", help="log every controller message with a timestamp to inspect.log until stopped")
    ap.add_argument("--inspect", action="store_true", help="guided: record what each button and paddle sends (writes inspect.log)")
    ap.add_argument("--fake", action="store_true", help="send fake trainer data (no Bluetooth)")
    ap.add_argument("--no-trainer", action="store_true")
    ap.add_argument("--no-controller", action="store_true")
    ap.add_argument("--trainer", help="only auto-connect a trainer whose name contains this")
    ap.add_argument("--controller", help="only auto-connect a controller whose name contains this")
    args = ap.parse_args()
    if args.managed:
        global _log_file
        try:
            _log_file = open(LOG_FILE, "w")   # a fresh log each time the game starts the helper
        except OSError:
            pass
    try:
        asyncio.run(amain(args))
    except KeyboardInterrupt:
        pass
    except OSError as e:
        sys.exit(f"bridge could not start: {e} (is another copy already running?)")


if __name__ == "__main__":
    main()
