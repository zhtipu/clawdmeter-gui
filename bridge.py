"""Bridge between the QML UI and the engine. Usage comes from the official `claude` program (usage_cli.py);
this app never handles a Claude login or token."""
import json
import os
import re
import subprocess
import sys
import threading
import time

import httpx
from PySide6.QtCore import Property, QObject, Signal, Slot

import engine
import plat
import usage_cli
from alerts import Alerts

PREFS_PATH = os.path.join(os.path.expanduser("~"), ".clawdmeter-gui.json")


def _j(obj):
    return json.dumps(obj)


def _hosts(raw):
    items = raw if isinstance(raw, list) else [raw or ""]
    out = []
    for entry in items:
        for it in re.split(r"[,\s;]+", str(entry).strip()):
            if it and it not in out:
                out.append(it)
    return out


def _host_of(url):
    m = re.match(r"https?://([^/]+)", url)
    return m.group(1) if m else url


class Bridge(QObject):
    toast = Signal(str, str)               # message, kind
    testResult = Signal(str)               # JSON from a connection test
    closeToTrayChanged = Signal()
    quittingChanged = Signal()

    def __init__(self, poll=True):
        super().__init__()
        self._prefs = {"closeToTray": True}
        self._quitting = False
        try:
            with open(PREFS_PATH, encoding="utf-8") as f:
                self._prefs.update(json.load(f))
        except (OSError, ValueError):
            pass

        self.notify = lambda title, body, level: None      # set by main once the tray exists
        self.alerts = Alerts(self._prefs, self._save_prefs, lambda t, b, l: self.notify(t, b, l))

        self._claude = {"found": False, "path": "", "signedIn": None, "method": "", "checked": 0}
        self._claude_busy = False

        self._cfg = engine.load_config()
        if not self._cfg.get("push_url"):
            self._cfg["push_url"] = os.environ.get("CLAWDMETER_PUSH_URL", "")
        self._transports = engine.Transports(self._cfg)
        initial = self._cfg.get("transport") or ("push" if self._cfg.get("push_url") else "serve")
        saved = int(self._cfg.get("poll_interval", engine.DEFAULT_POLL_INTERVAL))
        engine.poll_interval = saved if saved >= 120 else engine.DEFAULT_POLL_INTERVAL    # old faster settings are reset
        if poll:    # screenshot runs skip this so they do not start Claude Code or touch the TV
            self._transports.select(initial)
            self._transports.sync_phone()
            threading.Thread(target=engine.poller_loop, args=(engine.poll_interval,), daemon=True).start()
        engine.log("clawdmeter-gui started")

    # ---- prefs -------------------------------------------------------------
    def _save_prefs(self):
        try:
            with open(PREFS_PATH, "w", encoding="utf-8") as f:
                json.dump(self._prefs, f)
        except OSError:
            pass

    @Property(bool, notify=closeToTrayChanged)
    def closeToTray(self):
        return bool(self._prefs.get("closeToTray", True))

    @Property(bool, notify=quittingChanged)
    def quitting(self):
        return self._quitting

    @Slot()
    def markQuitting(self):
        if not self._quitting:
            self._quitting = True
            self.quittingChanged.emit()

    @Slot(bool)
    def setCloseToTray(self, v):
        self._prefs["closeToTray"] = bool(v)
        self._save_prefs()
        self.closeToTrayChanged.emit()

    # ---- usage alerts ------------------------------------------------------
    @Slot(result=str)
    def alertSettings(self):
        return _j(self.alerts.settings())

    @Slot(str, str, result=str)
    def setAlert(self, key, value_json):
        self.alerts.set(key, json.loads(value_json))
        return _j(self.alerts.settings())      # thresholds may have been adjusted to stay in order

    @Slot(str)
    def testAlert(self, level):
        self.alerts.test(level)

    # ---- live state --------------------------------------------------------
    @Slot(result=str)
    def snapshot(self):
        st = engine.state
        with st.lock:
            payload = dict(st.payload)
            status = st.status
            last = st.last_update
            results = dict(st.push_results)
            endpoint = st.endpoint
            port = st.port
        age = (time.time() - last) if last else -1
        devices = []
        owners = engine.state.phone_owners()
        with engine.state.lock:
            names = {ip: c.get("name") or "Phone" for ip, c in engine.state.clients.items()}
        for url in engine._static_push_urls(self._cfg):
            ok, ts, detail = results.get(url, (None, 0, ""))
            held = names.get(owners.get(engine.norm_host(url), ""), "")
            devices.append({"host": _host_of(url), "ok": ok, "age": (time.time() - ts) if ts else -1, "detail": detail, "heldBy": held})
        return _j({
            "ok": bool(payload.get("ok")),
            "s": payload.get("s", 0), "w": payload.get("w", 0),
            "sr": payload.get("sr", 0), "wr": payload.get("wr", 0),
            "st": payload.get("st", ""),
            "status": status, "statusKey": st.get_status_key(),
            "age": age,
            "transport": self._transports.active or "",
            "devices": devices,
            "phones": [p for p in json.loads(self.phones()) if p["state"] != "gone"],
            "endpoint": endpoint, "port": port or "",
        })

    @Slot()
    def refreshNow(self):
        engine.state.refresh_event.set()

    # ---- refresh intervals -------------------------------------------------
    @Slot(result=str)
    def refreshSettings(self):
        return _j({"poll": int(engine.poll_interval),
                   "push": int(self._cfg.get("push_interval", engine.DEFAULT_PUSH_INTERVAL))})

    @Slot(int)
    def setPollInterval(self, sec):
        sec = max(120, int(sec))    # each reading starts Claude Code, so never faster than every 2 minutes
        engine.poll_interval = sec
        self._cfg["poll_interval"] = sec
        engine.save_config(self._cfg)
        engine.state.refresh_event.set()

    @Slot(int)
    def setPushInterval(self, sec):
        self._cfg["push_interval"] = max(5, int(sec))
        engine.save_config(self._cfg)
        if self._transports.active == "push":
            self._transports.reselect()

    @Slot(result=str)
    def localUrls(self):
        """This computer's addresses on its networks, as the URL a phone or TV would open to get the numbers."""
        import socket
        ips = []
        try:                                         # the address used to reach the outside world first
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
        port = int(self._cfg.get("serve_port", engine.DEFAULT_PORT))
        return _j([f"http://{ip}:{port}/" for ip in out])

    @Slot(result=str)
    def phones(self):
        """Phones that have fetched the numbers from this computer, with how they are linked and how fresh they are."""
        now = time.time()
        with engine.state.lock:
            rows = [dict(c, ip=ip) for ip, c in engine.state.clients.items()]
        owners = engine.state.phone_owners()
        out = []
        for c in sorted(rows, key=lambda r: -r["last"]):
            age = int(now - c["last"])
            tvs = []
            for h in sorted(c.get("tvs", ())):
                if engine.state.taken_over(h):
                    st = "taken"                 # the phone failed, this computer sends instead
                elif owners.get(h, c["ip"]) != c["ip"]:
                    st = "other"                 # another phone feeds it
                else:
                    st = c.get("tvok", {}).get(h, "pending")
                tvs.append({"host": h, "state": st})
            out.append({"tvs": tvs, "ip": c["ip"], "name": c.get("name") or "Phone", "link": c.get("link", "network"), "age": age,
                        "state": "connected" if age <= 90 else ("idle" if age <= 600 else "gone"), "count": c["count"]})
        return _j(out)

    # ---- device ------------------------------------------------------------
    @Slot(result=str)
    def deviceConfig(self):
        return _j({
            "transport": self._transports.active or self._cfg.get("transport") or "push",
            "hosts": ", ".join(_hosts(self._cfg.get("push_url"))),
            "discover": bool(self._cfg.get("discover", True)),
            "pushInterval": int(self._cfg.get("push_interval", engine.DEFAULT_PUSH_INTERVAL)),
            "servePort": int(self._cfg.get("serve_port", engine.DEFAULT_PORT)),
            "serialPort": self._cfg.get("serial_port") or "",
        })

    @Slot(str, result=bool)
    def applyDevice(self, params_json):
        p = json.loads(params_json)
        c = self._cfg
        c["push_url"] = ", ".join(_hosts(p.get("hosts", "")))
        c["discover"] = bool(p.get("discover", True))
        c["push_interval"] = max(5, int(p.get("pushInterval", 20)))
        c["serve_port"] = int(p.get("servePort", engine.DEFAULT_PORT))
        c["serial_port"] = (p.get("serialPort") or "").strip() or None
        engine.save_config(c)
        self._transports.sync_phone()
        want = p.get("transport", "push")
        if self._transports.active == want:
            self._transports.reselect()
        else:
            self._transports.select(want)
        self._transports.sync_phone()
        engine.state.refresh_event.set()
        return True

    @Slot(str)
    def copyText(self, text):
        from PySide6.QtGui import QGuiApplication
        QGuiApplication.clipboard().setText(text)
        self.toast.emit("Copied", "good")

    @Slot(result=str)
    def phoneConfig(self):
        serving = self._transports.active == "serve" or bool(self._cfg.get("phone_serve"))
        return _j({"on": serving, "viaServe": self._transports.active == "serve",
                   "port": int(self._cfg.get("serve_port", engine.DEFAULT_PORT))})

    @Slot(bool, int, result=str)
    def setPhone(self, on, port):
        """Turn the phone app server on or off. Returns an error text, or empty when fine."""
        self._cfg["phone_serve"] = bool(on)
        self._cfg["serve_port"] = max(1024, min(65535, int(port)))
        engine.save_config(self._cfg)
        err = self._transports.sync_phone()
        if self._transports.active == "serve":
            self._transports.reselect()
        return err

    @Slot(str)
    def testDevice(self, host):
        def work():
            host_ = host.strip()
            res = {"host": host_, "ok": False, "detail": ""}
            if not host_:
                res["detail"] = "Enter an address first"
            else:
                t0 = time.time()
                try:
                    r = httpx.get(engine.normalize_push_url(host_).rsplit("/api/usage", 1)[0] + "/", timeout=4.0)
                    res["ok"] = True
                    res["detail"] = f"Answered in {int((time.time() - t0) * 1000)} ms"
                except httpx.HTTPError as e:
                    res["detail"] = "No answer (" + type(e).__name__ + ")"
            self.testResult.emit(_j(res))
        threading.Thread(target=work, daemon=True).start()

    # ---- Claude Code ---------------------------------------------------------
    def _check_claude(self):
        if self._claude_busy:
            return
        self._claude_busy = True

        def work():
            try:
                res = usage_cli.auth_status()
                was = self._claude.get("signedIn")
                self._claude = dict(res, checked=time.time())
                if res.get("signedIn") and not was:      # just signed in: read usage right away
                    engine.state.refresh_event.set()
            finally:
                self._claude_busy = False
        threading.Thread(target=work, daemon=True).start()

    @Slot(result=str)
    def claudeStatus(self):
        """Is the official Claude Code program installed, and is it signed in? Asked of the program itself."""
        if time.time() - self._claude.get("checked", 0) > 8:
            self._check_claude()
        c = self._claude
        return _j({"found": c["found"], "path": c["path"], "signedIn": c["signedIn"], "method": c["method"],
                   "connected": bool(engine.state.get_payload().get("ok")), "status": engine.state.status})

    @Slot()
    def signIn(self):
        """Opens a terminal that runs the official `claude auth login`. The sign-in happens in Claude Code, not here."""
        exe = plat.find_claude()
        if not exe:
            self.toast.emit("Claude Code is not installed on this computer. Install it from claude.com/code, then try again", "bad")
            return
        try:
            plat.open_sign_in(exe)
            self.toast.emit("Finish signing in in the terminal window and your browser", "info")
        except OSError as e:
            self.toast.emit(f"Could not open a terminal: {e}", "bad")

    # ---- autostart ---------------------------------------------------------
    @Slot(result=bool)
    def autostartEnabled(self):
        return plat.autostart_enabled()

    @Slot(bool, result=bool)
    def setAutostart(self, on):
        res = plat.autostart_set(on)
        if res is not True:
            self.toast.emit(f"Could not change startup: {res}", "bad")
            return False
        return True

    # ---- log ---------------------------------------------------------------
    @Slot(result=str)
    def logTail(self):
        try:
            with open(engine.LOG_PATH, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()[-120:]
            return "".join(lines)
        except OSError:
            return ""

    @Slot()
    def shutdown(self):
        engine.state.stop_event.set()
        engine.state.refresh_event.set()
        self._transports.shutdown()
