"""Device delivery for Clawdmeter: the usage poller plus the ways to reach a desk device.

Usage comes from usage_cli.py, which runs the official `claude -p /usage` and reads what it prints. Nothing in this
file opens, reads or stores a Claude login or token, and nothing here talks to Anthropic.

Delivery to the device, any of:
  * push    - HTTP POST to the device   (SmallTV behind Wi-Fi client isolation)
  * serve   - HTTP server the device polls
  * serial  - JSON lines over USB CDC (the ESP32-S3 Clawdmeter)

Derived from giovi321/clawdmeter-daemon (WTFPL), with the token handling, tray, autostart and CLI removed.

Payload contract: {"s":29,"sr":142,"w":4,"wr":9876,"st":"allowed","ok":true}
  s/w  = 5h / 7d utilization %     sr/wr = minutes until each window resets
  st   = session limit severity    ok    = false => no data
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import httpx

import usage_cli

# ---- Config ---------------------------------------------------------------

DEFAULT_POLL_INTERVAL = 300    # seconds between usage readings (each one starts Claude Code briefly)
poll_interval = DEFAULT_POLL_INTERVAL   # runtime value, set by the GUI
DEFAULT_PUSH_INTERVAL = 20     # seconds between HTTP pushes to the device
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8787

# Serial auto-detect (the Clawdmeter ESP32-S3 enumerates as Espressif CDC).
ESPRESSIF_VID = 0x303A
DEVICE_PID = 0x1001
BAUD_RATE = 115200
SERIAL_TIMEOUT = 1            # s, non-blocking readline
PORT_CHECK_INTERVAL = 5      # s, re-verify the COM port still exists


# A daemon launched windowless (pythonw) or headless has no visible console, so
# every message also goes to this file — the one place to look when "it didn't
# start". Kept small by a crude size cap (rotate to .1 past ~1 MB).
LOG_PATH = Path.home() / ".clawdmeter-daemon.log"
_LOG_MAX_BYTES = 1_000_000
_log_lock = threading.Lock()


def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    with _log_lock:
        try:
            print(line, flush=True)
        except (OSError, ValueError):
            pass    # no usable stdout (pythonw with a detached console)
        try:
            if LOG_PATH.exists() and LOG_PATH.stat().st_size > _LOG_MAX_BYTES:
                LOG_PATH.replace(LOG_PATH.with_name(LOG_PATH.name + ".1"))
            with LOG_PATH.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass    # never let logging take the daemon down


# Run a child process without flashing a console window on Windows (important when
# launched via pythonw — otherwise spawning `claude` pops a visible window).
_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0  # CREATE_NO_WINDOW


def _run(cmd, **kw):
    if _NO_WINDOW:
        kw["creationflags"] = kw.get("creationflags", 0) | _NO_WINDOW
    return subprocess.run(cmd, **kw)


# ---- Config persistence ---------------------------------------------------
# Remembers the transport you pick in the tray, so it survives restarts.

CONFIG_PATH = Path.home() / ".clawdmeter-daemon.json"


def load_config() -> dict:
    cfg = {
        "transport": None,        # "serial" | "push" | "serve"
        "push_url": "",
        "serve_host": DEFAULT_HOST,
        "serve_port": DEFAULT_PORT,
        "serial_port": None,      # None => auto-detect
        "push_interval": DEFAULT_PUSH_INTERVAL,
    }
    try:
        cfg.update(json.loads(CONFIG_PATH.read_text()))
    except (OSError, json.JSONDecodeError):
        pass
    return cfg


def save_config(cfg: dict) -> None:
    try:
        CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    except OSError as e:
        log(f"Could not save config: {e}")


# ---- Shared state ---------------------------------------------------------

def _push_hosts(target: str) -> list:
    """Turn the stored push target string into bare hosts for display, e.g.
    "http://192.168.1.44/api/usage, http://smalltv.local/api/usage"
    -> ["192.168.1.44", "smalltv.local"]. Keeps the tray text short."""
    hosts = []
    for url in (target or "").split(", "):
        url = url.strip()
        if not url:
            continue
        m = re.match(r"https?://([^/]+)", url)
        hosts.append(m.group(1) if m else url)
    return hosts


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.status = "Starting..."
        self.payload: dict = {"ok": False}
        self.version = 0           # bumped on every set_payload (serial change-detect)
        self.last_update = 0.0
        self.port = None           # serial COM port, if serial transport active
        self.push_target = ""      # device URL, if push transport active
        self.endpoint = ""         # serve URL, if serve transport active
        self.hid_enabled = True
        self.status_key = ""        # ok | error | searching, set by the poller
        self.push_results: dict = {}   # url -> (ok: bool, unix time, detail)
        self.takeover: dict = {}       # tv host -> unix time until which this computer sends instead of a phone that failed
        self.clients: dict = {}        # ip -> {name, link, first, last, count}, phones that fetched in serve mode
        self.stop_event = threading.Event()
        self.refresh_event = threading.Event()

    CLIENT_LIVE_S = 90

    def phone_owners(self) -> dict:
        """TV host -> phone address that is sending to it. One sender per TV: the phone seen first keeps it while it is live."""
        now = time.time()
        with self.lock:
            live = sorted((c["first"], ip, c) for ip, c in self.clients.items() if now - c["last"] <= self.live_window(c))
        owners: dict = {}
        for _, ip, c in live:
            report = c.get("tvok", {})
            since = c.get("since", {})
            for h in c.get("tvs", ()):
                if self.taken_over(h):
                    continue
                # A phone that claims a TV but never reports a push result (its relay is off, or it cannot reach the TV) must not
                # keep this computer from sending: it owns the TV only while it reports success, or for a short grace after claiming it.
                if h in report and report[h] != "ok":
                    continue
                if h not in report and now - since.get(h, now) > self.CLAIM_GRACE_S:
                    continue
                owners.setdefault(h, ip)
        return owners

    def live_window(self, c: dict) -> float:
        """How long after its last contact a phone still counts as live: at least 90 s, longer if it normally calls less often."""
        return max(self.CLIENT_LIVE_S, 2.5 * min(c.get("gap", 0), 3600))

    TAKEOVER_S = 300
    CLAIM_GRACE_S = 60

    def taken_over(self, host: str) -> bool:
        with self.lock:
            return self.takeover.get(host, 0) > time.time()

    def set_status(self, status: str, port: str | None = ..., key: str = "") -> None:
        with self.lock:
            self.status = status
            self.status_key = key
            if port is not ...:
                self.port = port

    def set_payload(self, payload: dict, keep_last_good: bool = True) -> None:
        with self.lock:
            if payload.get("ok") or not (keep_last_good and self.payload.get("ok")):
                self.payload = payload
                self.version += 1
            if payload.get("ok"):
                self.last_update = time.time()

    def get_payload(self) -> dict:
        with self.lock:
            return dict(self.payload)

    def get_payload_versioned(self):
        with self.lock:
            return dict(self.payload), self.version

    def get_tooltip(self) -> str:
        """Full detail for the icon's hover tooltip (multi-line). Push targets are
        trimmed to hosts and capped so even many devices stay readable."""
        with self.lock:
            lines = [f"clawdmeter — {self.status}"]
            p = self.payload
            if p.get("ok"):
                lines.append(f"5h {p['s']}%   7d {p['w']}%")
            if self.port:
                lines.append("serial " + self.port)
            if self.push_target:
                hosts = _push_hosts(self.push_target)
                shown = hosts[:6]
                line = "push -> " + ", ".join(shown)
                if len(hosts) > len(shown):
                    line += f" (+{len(hosts) - len(shown)} more)"
                lines.append(line)
            elif self.endpoint:
                lines.append(self.endpoint)
            return "\n".join(lines)

    def get_menu_header(self) -> str:
        """Compact one-line summary for the tray menu header. Kept narrow on purpose:
        a long push-target list would otherwise stretch the whole popover, so we show
        the first host plus a count and leave the full list to the hover tooltip."""
        with self.lock:
            parts = [f"clawdmeter — {self.status}"]
            p = self.payload
            if p.get("ok"):
                parts.append(f"5h {p['s']}%  7d {p['w']}%")
            if self.port:
                parts.append("serial " + self.port)
            if self.push_target:
                hosts = _push_hosts(self.push_target)
                if len(hosts) == 1:
                    parts.append("push -> " + hosts[0])
                elif hosts:
                    parts.append(f"push -> {hosts[0]} (+{len(hosts) - 1} more)")
            elif self.endpoint:
                parts.append(self.endpoint)
            return "   ".join(parts)

    def get_status_key(self) -> str:
        with self.lock:
            if self.status_key:
                return self.status_key
            s = self.status.lower()
            if "error" in s:
                return "error"
            if self.payload.get("ok"):
                return "ok"
            return "searching"


state = State()

# ---- Reading usage ---------------------------------------------------------
# The official `claude -p /usage`, run on a timer. Each run starts Claude Code briefly, so the pace is slow and a
# failure backs off. When the user needs to act (install, sign in) we just wait for them.

MIN_GAP_S = 30                       # never run twice within this, whatever asked (timer, Refresh now)
RETRY_FIRST_S = 120                  # first retry after a failed run, then doubling up to the normal interval
NEEDS_USER = ("missing", "signed_out", "no_limits")


def do_poll() -> str:
    """One reading. Returns the result kind: ok, missing, signed_out, no_limits or fail."""
    r = usage_cli.read_usage()
    if r.ok:
        state.set_payload(r.payload)
        state.set_status("Connected", key="ok")
        log(f"5h={r.payload['s']}% 7d={r.payload['w']}% st={r.payload['st']}")
    else:
        state.set_status(r.message, key="error" if r.kind in NEEDS_USER else "searching")
        log(f"No reading: {r.kind}")
    return r.kind


def poller_loop(interval: float) -> None:
    log(f"Reading usage with Claude Code every {interval:.0f}s")
    failures = 0
    last = 0.0
    while not state.stop_event.is_set():
        gap = MIN_GAP_S - (time.time() - last)
        if gap > 0 and state.stop_event.wait(gap):
            break
        last = time.time()
        interval = float(poll_interval)          # live setting, changes apply without a restart
        kind = do_poll()
        if kind == "ok" or kind in NEEDS_USER:
            failures = 0
            wait = interval
        else:
            wait = min(interval, RETRY_FIRST_S * (2 ** failures))
            failures += 1
            log(f"Retrying in {wait:.0f}s")
        state.refresh_event.wait(wait)
        state.refresh_event.clear()


# ---- Transport: serial (USB CDC) ------------------------------------------

def find_device_port(explicit: str | None) -> str | None:
    import serial.tools.list_ports
    if explicit:
        return explicit
    ports = serial.tools.list_ports.comports()
    for p in ports:
        if p.vid == ESPRESSIF_VID and p.pid == DEVICE_PID:
            return p.device
    for p in ports:
        desc = (p.description or "").lower() + (p.product or "").lower()
        if "claude controller" in desc or "clawdmeter" in desc:
            return p.device
    return None


def serial_loop(stop: threading.Event, explicit_port: str | None) -> None:
    """Maintain the USB serial link: write the latest payload when it changes, and
    let the device request refreshes. Polling is done by poller_loop; we just ship.
    `stop` is the per-transport event so the tray can switch transports at runtime."""
    import serial
    import serial.tools.list_ports

    backoff = 1
    while not stop.is_set():
        port = find_device_port(explicit_port)
        if not port:
            state.set_status("Searching for serial device...", port=None)
            stop.wait(backoff)
            backoff = min(backoff * 2, 30)
            continue
        try:
            ser = serial.Serial(port, BAUD_RATE, timeout=SERIAL_TIMEOUT)
        except serial.SerialException as e:
            log(f"Serial open failed: {e}")
            state.set_status(f"Serial error: {e}", port=None)
            stop.wait(backoff)
            backoff = min(backoff * 2, 30)
            continue

        log(f"Serial connected: {port}")
        state.set_status("Connected", port=port)
        backoff = 1
        last_sent_version = -1
        last_port_check = time.time()
        state.refresh_event.set()   # ask the poller for fresh data on connect

        if not state.hid_enabled:
            try:
                ser.write((json.dumps({"hid": False}, separators=(",", ":")) + "\n").encode())
                ser.flush()
                log("Sent HID-disabled config to device")
            except serial.SerialException:
                pass

        try:
            while not stop.is_set():
                now = time.time()
                if now - last_port_check >= PORT_CHECK_INTERVAL:
                    last_port_check = now
                    live = {p.device for p in serial.tools.list_ports.comports()}
                    if port not in live:
                        log(f"{port} disappeared - device unplugged")
                        break

                try:
                    line = ser.readline().decode("utf-8", errors="replace").strip()
                except serial.SerialException:
                    log("Serial read error - device disconnected")
                    break
                if line:
                    try:
                        msg = json.loads(line)
                        if msg.get("refresh") or msg.get("ready"):
                            state.refresh_event.set()   # device wants fresh data
                        elif not (msg.get("ack") or msg.get("err")):
                            log(f"Device: {line}")
                    except json.JSONDecodeError:
                        log(f"Device: {line}")

                payload, version = state.get_payload_versioned()
                if version != last_sent_version and payload.get("ok"):
                    try:
                        ser.write((json.dumps(payload, separators=(",", ":")) + "\n").encode())
                        ser.flush()
                        last_sent_version = version
                    except serial.SerialException:
                        log("Serial write error - device disconnected")
                        break
        finally:
            try:
                ser.close()
            except Exception:
                pass
            with state.lock:
                state.port = None
        if not stop.is_set():
            state.set_status("Serial disconnected - reconnecting...", port=None)
            stop.wait(2)


# ---- Transport: HTTP server (device pulls) --------------------------------

import socket as _socket
_PC_NAME = (_socket.gethostname() or "Computer").split(".")[0]


def norm_host(raw: str) -> str:
    """"http://192.168.0.31:80/x" -> "192.168.0.31", for comparing the TV a phone sends to with the TV this computer sends to."""
    v = raw.strip().lower()
    v = v.split("://", 1)[-1].split("/", 1)[0]
    return v.rsplit(":", 1)[0] if v.count(":") == 1 else v


def register_client(key: str, name: str, link: str, tvs: set, report: dict) -> None:
    """Record that a phone just talked to this computer, by Wi-Fi or Bluetooth, with the TVs it feeds and how its last pushes went.
    If it could not reach a TV it was feeding, this computer takes that TV over for a while."""
    now = time.time()
    with state.lock:
        c = state.clients.setdefault(key, {"first": now, "count": 0})
        if "last" in c:
            c["gap"] = now - c["last"]            # how often this phone calls
        if now - c.get("last", now) > state.live_window(c):
            c["first"] = now                      # came back after a gap: it no longer outranks phones that stayed
            c["since"] = {}
        since = c.setdefault("since", {})
        for h in tvs:
            since.setdefault(h, now)              # when this phone first claimed each TV
        for h in list(since):
            if h not in tvs:
                del since[h]
        c.update(name=name or c.get("name", ""), link=link, last=now, tvs=tvs, tvok=report)
        c["count"] += 1
    for h, v in report.items():
        if v == "fail" and h in tvs and not state.taken_over(h):
            with state.lock:
                state.takeover[h] = now + state.TAKEOVER_S
            log(f"Phone {key} could not reach {h}; sending from this computer for {state.TAKEOVER_S // 60} min")


def skip_for(key: str) -> list:
    """TVs this phone must leave alone: another phone feeds them, or this computer took them over after the phone failed."""
    mine = state.clients.get(key, {}).get("tvs", ())
    owners = state.phone_owners()
    return sorted(h for h in mine if owners.get(h, key) != key or state.taken_over(h))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body: dict):
        data = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path.rstrip("/") in ("/healthz", "/health"):
            self._send(200, {"ok": True, "app": "clawdmeter", "pc": _PC_NAME})
            return
        ip = self._note_client()
        body = dict(state.get_payload())
        body["pc"] = _PC_NAME
        body["skip"] = skip_for(ip)
        self._send(200, body)

    def _note_client(self):
        ip = self.client_address[0]
        name = self.headers.get("X-Clawdmeter-Device", "")[:60].strip()
        link = self.headers.get("X-Clawdmeter-Link", "").strip().lower()
        if link not in ("wifi", "bluetooth", "ethernet", "cellular"):
            link = "network"
        tvs = {norm_host(t) for t in self.headers.get("X-Clawdmeter-Tvs", "").split(",") if t.strip()}
        report = {}
        for part in self.headers.get("X-Clawdmeter-Tv-Status", "").split(","):
            h, _, v = part.partition("=")
            if h.strip() and v.strip() in ("ok", "fail"):
                report[norm_host(h)] = v.strip()
        register_client(ip, name, link, tvs, report)
        return ip

    def log_message(self, *args):
        pass


# ---- Transport: HTTP push (daemon POSTs to device) ------------------------

def normalize_push_url(v: str) -> str:
    v = v.strip()
    if not v.startswith(("http://", "https://")):
        v = "http://" + v
    if "/api/usage" not in v:
        v = v.rstrip("/") + "/api/usage"
    return v


def _static_push_urls(cfg: dict) -> list:
    """Normalize the configured push target(s) into a list of URLs.

    cfg['push_url'] may be a single string or a list (from a repeated --push-to).
    A string entry can itself hold several hosts separated by commas/whitespace/
    semicolons, so one CLAWDMETER_PUSH_URL env var or one --push-to can target
    several devices (e.g. "192.168.1.44, 192.168.1.45"). Blank entries and
    duplicates are dropped.
    """
    raw = cfg.get("push_url") or ""
    items = raw if isinstance(raw, list) else [raw]
    out = []
    for entry in items:
        for it in re.split(r"[,\s;]+", (entry or "").strip()):
            it = it.strip()
            if it:
                u = normalize_push_url(it)
                if u not in out:
                    out.append(u)
    return out


# ---- mDNS discovery: find every SmallTV on the LAN ------------------------
# smalltv-mod firmware (2.8.0+) advertises a `_clawdmeter._tcp` service whose TXT
# record carries the push path. Browsing for it lets one daemon push to every
# device with no hardcoded address, so several SmallTVs stay in sync without a
# --push-to per device. zeroconf is optional: without it, push still works with
# explicit --push-to hosts.

class Discovery:
    SERVICE = "_clawdmeter._tcp.local."

    def __init__(self):
        self._lock = threading.Lock()
        self._urls: dict = {}     # mDNS service name -> push URL
        self._zc = None
        self._browser = None

    def start(self) -> bool:
        try:
            from zeroconf import Zeroconf, ServiceBrowser
        except ImportError:
            log("mDNS discovery needs zeroconf (pip install zeroconf) - discovery off")
            return False
        self._zc = Zeroconf()
        self._browser = ServiceBrowser(self._zc, self.SERVICE, handlers=[self._on_change])
        log("mDNS discovery on - browsing for SmallTV devices")
        return True

    def _on_change(self, zeroconf, service_type, name, state_change) -> None:
        from zeroconf import ServiceStateChange
        if state_change is ServiceStateChange.Removed:
            with self._lock:
                if self._urls.pop(name, None):
                    log(f"device left: {name}")
            return
        # Resolve off the browser thread so a slow lookup can't stall discovery.
        threading.Thread(target=self._resolve, args=(zeroconf, service_type, name),
                         daemon=True).start()

    def _resolve(self, zeroconf, service_type, name) -> None:
        try:
            info = zeroconf.get_service_info(service_type, name, timeout=2000)
        except Exception:
            return
        if not info:
            return
        addrs = info.parsed_addresses() if hasattr(info, "parsed_addresses") else []
        if not addrs:
            return
        path = (info.properties or {}).get(b"path") or b"/api/usage"
        if isinstance(path, (bytes, bytearray)):
            path = path.decode(errors="replace")
        url = f"http://{addrs[0]}:{info.port}{path}"
        with self._lock:
            if self._urls.get(name) != url:
                self._urls[name] = url
                log(f"device found: {name} -> {url}")

    def urls(self) -> list:
        with self._lock:
            return list(self._urls.values())

    def stop(self) -> None:
        try:
            if self._zc is not None:
                self._zc.close()
        except Exception:
            pass
        self._zc = None
        self._browser = None


def _tv_accepted(body: str) -> bool:
    try:
        return json.loads(body).get("ok") is True
    except (ValueError, AttributeError):
        return False


def _is_smalltv(push_url: str) -> bool:
    """Does the address answer /api/status the way a SmallTV does (a JSON object with its firmware name)?"""
    base = push_url.split("/api/usage")[0].rstrip("/")
    try:
        r = httpx.get(base + "/api/status", timeout=4.0)
        return r.status_code == 200 and isinstance(r.json(), dict) and "fw" in r.json()
    except (httpx.HTTPError, ValueError):
        return False


def push_loop(stop: threading.Event, targets_fn, interval: float) -> None:
    """POST the latest payload to every current target each interval.

    targets_fn() returns the live list of device push URLs (static --push-to
    hosts plus anything mDNS discovery has found), so devices coming and going
    are handled without restarting the loop. A per-URL failure never blocks the
    others.
    """
    log(f"HTTP push every {interval:.0f}s (static targets + mDNS discovery)")
    ok_urls: set = set()
    while not stop.is_set():
        payload = state.get_payload()
        urls = targets_fn()
        state.push_target = ", ".join(urls)
        if payload.get("ok") and urls:
            owners = state.phone_owners()
            for url in urls:
                if norm_host(url) in owners:        # a phone is already sending to this TV, so only one sender talks to it
                    state.push_results[url] = (None, time.time(), "phone")
                    ok_urls.discard(url)
                    continue
                took = state.taken_over(norm_host(url))
                try:
                    r = httpx.post(url, json=payload, timeout=10.0)
                    if r.status_code != 200 or not _tv_accepted(r.text):
                        # a real SmallTV answers 200 with {"ok":true}; a router page or another device is not the TV. Older firmware may
                        # reply differently, so an address that identifies itself as a SmallTV still counts.
                        odd = r.status_code in (200, 301, 302, 303, 307, 308)
                        if odd and _is_smalltv(url):
                            state.push_results[url] = (True, time.time(), "takeover" if took else "")
                            ok_urls.add(url)
                            continue
                        why = "That address is not the SmallTV" if odd else f"HTTP {r.status_code}"
                        log(f"Push {url}: {why}")
                        state.push_results[url] = (False, time.time(), why)
                        ok_urls.discard(url)
                    else:
                        state.push_results[url] = (True, time.time(), "takeover" if took else "")
                        if url not in ok_urls:
                            log(f"Pushing to {url} OK")
                            ok_urls.add(url)
                except httpx.HTTPError as e:
                    log(f"Push {url} failed: {e}")
                    state.push_results[url] = (False, time.time(), type(e).__name__)
                    ok_urls.discard(url)
        elif payload.get("ok") and not urls:
            state.set_status("Push: waiting for a device (mDNS)")
        stop.wait(interval)


# ---- Transport supervisor (runtime switch from the tray) ------------------

class Transports:
    NAMES = ("serial", "push", "serve")
    LABELS = {
        "serial": "Serial (USB)",
        "push":   "HTTP push to device",
        "serve":  "HTTP serve (device pulls)",
    }

    def __init__(self, cfg: dict):
        self.lock = threading.RLock()
        self.cfg = cfg
        self.active = None
        self._stop = None        # per-transport stop event for the running thread
        self._server = None      # ThreadingHTTPServer while serving
        self._discovery = None   # mDNS Discovery while pushing
        self._phone = None       # ThreadingHTTPServer for the phone app when the main transport is not serve
        self._phone_port = None
        self._advert = None      # (Zeroconf, ServiceInfo) while the phone server or serve mode is advertised

    def select(self, name: str) -> None:
        if name not in self.NAMES:
            return
        with self.lock:
            if name == self.active:
                return
            self._teardown()
            self.active = name
            self.cfg["transport"] = name
            save_config(self.cfg)
            stop = threading.Event()
            self._stop = stop
            if name == "serial":
                threading.Thread(target=serial_loop,
                                 args=(stop, self.cfg.get("serial_port")), daemon=True).start()
            elif name == "push":
                static = _static_push_urls(self.cfg)
                disc = None
                if self.cfg.get("discover", True):
                    disc = Discovery()
                    if not disc.start():
                        disc = None
                self._discovery = disc
                if not static and disc is None:
                    state.set_status("HTTP push: no target and no discovery")
                    log("Push selected but no --push-to host and discovery unavailable")
                else:
                    def targets(_static=tuple(static), _disc=disc):
                        urls = list(_static)
                        if _disc is not None:
                            for u in _disc.urls():
                                if u not in urls:
                                    urls.append(u)
                        return urls
                    threading.Thread(
                        target=push_loop,
                        args=(stop, targets,
                              float(self.cfg.get("push_interval", DEFAULT_PUSH_INTERVAL))),
                        daemon=True).start()
            elif name == "serve":
                host = self.cfg.get("serve_host", DEFAULT_HOST)
                port = int(self.cfg.get("serve_port", DEFAULT_PORT))
                try:
                    self._server = ThreadingHTTPServer((host, port), Handler)
                except OSError as e:
                    state.set_status(f"serve error: {e}")
                    log(f"serve bind failed: {e}")
                    return
                state.endpoint = f"http://{host}:{port}/"
                threading.Thread(target=self._server.serve_forever, daemon=True).start()
            log(f"Transport -> {name}")

    def _teardown(self) -> None:
        if self._stop is not None:
            self._stop.set()
            self._stop = None
        if self._server is not None:
            try:
                self._server.shutdown()
                self._server.server_close()
            except Exception:
                pass
            self._server = None
        if self._discovery is not None:
            self._discovery.stop()
            self._discovery = None
        state.endpoint = ""
        state.push_target = ""
        with state.lock:
            state.port = None
        self.active = None

    def reselect(self) -> None:
        """Re-apply the active transport so a config change (e.g. new push targets)
        takes effect live. select() no-ops on an unchanged name, so tear down first."""
        with self.lock:
            active = self.active
            if not active:
                return
            self._teardown()          # clears self.active so select() will proceed
            self.select(active)

    def _local_ips(self) -> list:
        import socket
        ips = []
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("192.0.2.1", 9))
            ips.append(s.getsockname()[0])
            s.close()
        except OSError:
            pass
        try:
            ips += socket.gethostbyname_ex(socket.gethostname())[2]
        except OSError:
            pass
        out = []
        for ip in ips:
            if not ip.startswith(("127.", "169.254.")) and ip not in out:
                out.append(ip)
        return out

    def _sync_advert(self) -> None:
        """Announce this computer on the local network so the phone app can find it. Needs zeroconf; silent without it."""
        want = bool(self.cfg.get("phone_serve")) or self.active == "serve"
        port = int(self.cfg.get("serve_port", DEFAULT_PORT))
        if self._advert is not None:
            zc, info = self._advert
            if want and info.port == port:
                return
            try:
                zc.unregister_service(info)
                zc.close()
            except Exception:
                pass
            self._advert = None
        if not want:
            return
        try:
            import socket
            from zeroconf import Zeroconf, ServiceInfo
            ips = self._local_ips()
            if not ips:
                return
            host = socket.gethostname().split(".")[0] or "computer"
            info = ServiceInfo("_clawdmeter-pc._tcp.local.", f"{host} (Clawdmeter)._clawdmeter-pc._tcp.local.",
                               addresses=[socket.inet_aton(i) for i in ips], port=port,
                               properties={"name": host}, server=f"{host}-clawdmeter.local.")
            zc = Zeroconf()
            zc.register_service(info)
            self._advert = (zc, info)
        except Exception as e:
            log(f"advertise failed: {type(e).__name__}")

    def sync_phone(self) -> str:
        """Run the small server the phone app reads from, independent of how the TVs are fed.
        Returns "" when fine or a short error. When the main transport is already serve it covers the phone too."""
        with self.lock:
            want = bool(self.cfg.get("phone_serve")) and self.active != "serve"
            port = int(self.cfg.get("serve_port", DEFAULT_PORT))
            if self._phone is not None and (not want or self._phone_port != port):
                try:
                    self._phone.shutdown()
                    self._phone.server_close()
                except Exception:
                    pass
                self._phone = None
            if want and self._phone is None:
                try:
                    self._phone = ThreadingHTTPServer((self.cfg.get("serve_host", DEFAULT_HOST), port), Handler)
                except OSError as e:
                    log(f"phone server bind failed: {e}")
                    return f"Port {port} is busy: {e}"
                self._phone_port = port
                threading.Thread(target=self._phone.serve_forever, daemon=True).start()
                log(f"Phone server on port {port}")
            self._sync_advert()
            return ""

    def shutdown(self) -> None:
        with self.lock:
            self._teardown()
            if self._phone is not None:
                try:
                    self._phone.shutdown()
                    self._phone.server_close()
                except Exception:
                    pass
                self._phone = None
            if self._advert is not None:
                try:
                    self._advert[0].unregister_service(self._advert[1])
                    self._advert[0].close()
                except Exception:
                    pass
                self._advert = None
