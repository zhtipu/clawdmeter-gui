"""Bluetooth link to the phone app.

The phone app advertises a small Bluetooth Low Energy service. This computer finds it, connects, writes the usage numbers
and reads back which TVs the phone feeds, so the one-sender rules work the same as over Wi-Fi. Only the usage numbers
travel over this link, never a Claude login.

Service layout (must match the phone app, see BleServer.kt):
  USAGE  write   8 bytes  version, 5-hour %, week %, 5-hour minutes (u16), week minutes (u16), flags
  CTRL   write   JSON     {"pc": "<computer name>", "skip": ["<tv>", ...]}
  STATUS read    JSON     {"name": "<phone>", "tvs": ["<tv>", ...], "ok": {"<tv>": "ok" | "fail"}}
The phone's advertisement carries the service and manufacturer data 0xFFFF = 4 byte phone id, so a phone is recognised even
though its Bluetooth address changes every few minutes. Its name comes in the advertisement reply.
"""
import asyncio
import json
import threading
import time

SERVICE = "c1a0d3e7-0001-4c1a-9a5d-6d6574657201"
USAGE = "c1a0d3e7-0002-4c1a-9a5d-6d6574657201"
CTRL = "c1a0d3e7-0003-4c1a-9a5d-6d6574657201"
STATUS = "c1a0d3e7-0004-4c1a-9a5d-6d6574657201"
COMPANY = 0xFFFF
VERSION = 1


# ---- the wire format ---------------------------------------------------------------------------------------------

def encode_usage(p: dict) -> bytes:
    def clamp(v, hi):
        return max(0, min(hi, int(v or 0)))
    flags = (1 if p.get("ok") else 0) | (2 if p.get("st") == "rejected" else 0)
    return bytes([VERSION, clamp(p.get("s"), 255), clamp(p.get("w"), 255)]) + clamp(p.get("sr"), 65535).to_bytes(2, "little") \
        + clamp(p.get("wr"), 65535).to_bytes(2, "little") + bytes([flags])


def decode_usage(b: bytes) -> dict:
    if len(b) < 8 or b[0] != VERSION:
        return {"ok": False}
    flags = b[7]
    return {"ok": bool(flags & 1), "s": b[1], "w": b[2], "sr": int.from_bytes(b[3:5], "little"), "wr": int.from_bytes(b[5:7], "little"),
            "st": "rejected" if flags & 2 else "allowed"}


def encode_ctrl(pc: str, skip) -> bytes:
    skip = list(skip)
    while True:
        raw = json.dumps({"pc": pc[:30], "skip": skip}, separators=(",", ":")).encode()
        if len(raw) <= 180 or not skip:        # stay inside one Bluetooth packet
            return raw
        skip.pop()


def _host(raw) -> str:
    """"http://192.168.0.31:80/x" -> "192.168.0.31", the form this computer compares TVs in."""
    v = str(raw).strip().lower().split("://", 1)[-1].split("/", 1)[0]
    return v.rsplit(":", 1)[0] if v.count(":") == 1 else v


def parse_status(raw: bytes):
    """-> (phone name, set of TV hosts it feeds, {tv host: "ok" | "fail"})"""
    try:
        j = json.loads(bytes(raw).decode("utf-8", "replace"))
    except ValueError:
        return "", set(), {}
    tvs = {_host(t) for t in j.get("tvs", []) if str(t).strip()}
    report = {_host(k): v for k, v in (j.get("ok") or {}).items() if v in ("ok", "fail")}
    return str(j.get("name", ""))[:60], tvs, report


def parse_advert(manufacturer_data: dict):
    """-> (phone id as hex, phone name) from the advertisement, or None when it is not ours."""
    b = manufacturer_data.get(COMPANY)
    if not b or len(b) < 4:
        return None
    return bytes(b[:4]).hex(), bytes(b[4:]).decode("utf-8", "replace").strip("\x00 ")


# ---- the link ----------------------------------------------------------------------------------------------------

class BleLink:
    """Runs its own event loop on a thread. get_payload() gives the latest numbers, register() records a phone, skip_for()
    says which TVs a phone must leave to someone else."""

    def __init__(self, get_payload, register, skip_for, log, pc_name, interval=10.0):
        self.get_payload, self.register, self.skip_for, self.log = get_payload, register, skip_for, log
        self.pc_name, self.interval = pc_name, interval
        self.loop = None
        self.tasks: dict = {}
        self.status: dict = {}           # phone id -> {"state": connecting | connected | missing | error, "detail": str, "last": unix time}
        self._addr: dict = {}            # phone id -> last address seen
        self.last_seen = 0

    def _ensure_loop(self):
        if self.loop is None:
            self.loop = asyncio.new_event_loop()
            threading.Thread(target=self.loop.run_forever, daemon=True, name="ble").start()

    def _set(self, pid, state, detail="", **extra):
        self.status[pid] = dict(self.status.get(pid, {}), state=state, detail=detail, **extra)

    # -- finding phones
    def scan(self, seconds=6.0) -> list:
        self._ensure_loop()
        return asyncio.run_coroutine_threadsafe(self._scan(seconds), self.loop).result(seconds + 15)

    async def _scan(self, seconds):
        from bleak import BleakScanner
        found = await BleakScanner.discover(timeout=seconds, return_adv=True)
        out = []
        for addr, (dev, adv) in found.items():
            ident = parse_advert(adv.manufacturer_data)
            if not ident:
                continue
            self._addr[ident[0]] = dev
            out.append({"id": ident[0], "name": ident[1] or adv.local_name or dev.name or "Phone", "rssi": adv.rssi, "address": addr})
        self.last_seen = len(found)                           # how many Bluetooth devices were heard at all, to tell "no radio" from "no phone"
        return sorted(out, key=lambda d: -d["rssi"])

    # -- keeping saved phones connected
    def sync(self, phones: list) -> None:
        """phones: [{"id": hex, "name": str}]. Starts a connection for each new one and drops removed ones."""
        self._ensure_loop()
        asyncio.run_coroutine_threadsafe(self._sync(phones), self.loop)

    async def _sync(self, phones):
        want = {p["id"]: p for p in phones}
        for pid in list(self.tasks):
            if pid not in want:
                self.tasks.pop(pid).cancel()
                self.status.pop(pid, None)
        for pid, p in want.items():
            if pid not in self.tasks:
                self.tasks[pid] = asyncio.ensure_future(self._run(pid, p.get("name", "Phone")))

    async def _find(self, pid):
        from bleak import BleakScanner

        def match(dev, adv):
            ident = parse_advert(adv.manufacturer_data)
            return bool(ident and ident[0] == pid)
        return await BleakScanner.find_device_by_filter(match, timeout=8.0)

    async def _run(self, pid, saved_name):
        from bleak import BleakClient
        wait = 3.0
        while True:
            self._set(pid, "connecting")
            try:
                dev = await self._find(pid)                  # the address changes every few minutes, so look it up by id
                if dev is None:
                    self._set(pid, "missing", "Not in range, or its Bluetooth or the app is off")
                else:
                    async with BleakClient(dev, timeout=15.0) as c:
                        wait = 3.0
                        key = "ble:" + pid
                        while c.is_connected:
                            payload = self.get_payload()
                            if payload.get("ok"):
                                await c.write_gatt_char(USAGE, encode_usage(payload), response=True)
                            name, tvs, report = parse_status(await c.read_gatt_char(STATUS))
                            self.register(key, name or saved_name, "bluetooth", tvs, report)
                            await c.write_gatt_char(CTRL, encode_ctrl(self.pc_name, self.skip_for(key)), response=True)
                            self._set(pid, "connected", "", last=time.time())
                            await asyncio.sleep(self.interval)
            except asyncio.CancelledError:
                raise
            except Exception as e:                           # out of range, phone app closed, Bluetooth switched off
                self._set(pid, "error", type(e).__name__)
                self.log(f"Bluetooth phone {pid}: {type(e).__name__}")
            await asyncio.sleep(wait)
            wait = min(wait * 2, 30.0)
