"""Bridge between the QML UI and the clawdmeter engine (engine.py is the unmodified daemon logic)."""
import json
import os
import re
import subprocess
import sys
import threading
import time

import httpx
from PySide6.QtCore import Property, QObject, Signal, Slot
from PySide6.QtGui import QGuiApplication

import engine
import plat
from alerts import Alerts

TOKEN_VAR = plat.TOKEN_VAR
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

        # A token saved with setx is not in the environment of programs started before it was saved.
        if not os.environ.get(TOKEN_VAR, "").strip():
            tok = plat.token_get()
            if tok:
                os.environ[TOKEN_VAR] = tok

        self._login_seen = self._has_login()
        self._cfg = engine.load_config()
        if not self._cfg.get("push_url"):
            self._cfg["push_url"] = os.environ.get("CLAWDMETER_PUSH_URL", "")
        self._transports = engine.Transports(self._cfg)
        initial = self._cfg.get("transport") or ("push" if self._cfg.get("push_url") else "serve")
        engine.poll_interval = max(30, int(self._cfg.get("poll_interval", engine.DEFAULT_POLL_INTERVAL)))
        if poll:    # screenshot runs skip this so they do not hit Anthropic or the TV
            self._transports.select(initial)
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

    @Property(str, constant=True)
    def tokenStoreName(self):
        return "your Windows user settings" if plat.IS_WIN else ("the macOS Keychain" if plat.IS_MAC else "the system keyring")

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
        for url in engine._static_push_urls(self._cfg):
            ok, ts, detail = results.get(url, (None, 0, ""))
            devices.append({"host": _host_of(url), "ok": ok, "age": (time.time() - ts) if ts else -1, "detail": detail})
        return _j({
            "ok": bool(payload.get("ok")),
            "s": payload.get("s", 0), "w": payload.get("w", 0),
            "sr": payload.get("sr", 0), "wr": payload.get("wr", 0),
            "st": payload.get("st", ""),
            "status": status, "statusKey": st.get_status_key(),
            "age": age,
            "transport": self._transports.active or "",
            "devices": devices,
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
        sec = max(30, int(sec))     # below 30s Anthropic starts rate limiting
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
        want = p.get("transport", "push")
        if self._transports.active == want:
            self._transports.reselect()
        else:
            self._transports.select(want)
        engine.state.refresh_event.set()
        return True

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

    # ---- account / token ---------------------------------------------------
    def _has_login(self):
        return plat.has_login(engine)

    @Slot(result=str)
    def tokenStatus(self):
        saved = bool(os.environ.get(TOKEN_VAR, "").strip()) or bool(plat.token_get())
        login = self._has_login()
        connected = bool(engine.state.get_payload().get("ok"))
        if login and not self._login_seen:      # just signed in: read usage right away
            engine.state.refresh_event.set()
        self._login_seen = login
        return _j({"login": login, "token": saved, "connected": connected,
                   "status": engine.state.status})

    def _saved_token(self):
        return os.environ.get(TOKEN_VAR, "").strip() or plat.token_get()

    @Slot(result=str)
    def maskedToken(self):
        t = self._saved_token()
        if not t:
            return ""
        return t[:12] + "\u2022" * 16 + t[-4:] if len(t) > 20 else "\u2022" * len(t)

    @Slot(result=str)
    def revealToken(self):
        return self._saved_token()

    @Slot(str)
    def copyText(self, text):
        QGuiApplication.clipboard().setText(text or self._saved_token())
        self.toast.emit("Copied to the clipboard", "good")

    @Slot(str, result=bool)
    def saveToken(self, token):
        token = (token or "").strip()
        if not re.fullmatch(r"[A-Za-z0-9_\-\.=]{20,}", token):
            self.toast.emit("That does not look like a token", "bad")
            return False
        try:
            r = httpx.get(engine.USAGE_URL, headers={"Authorization": f"Bearer {token}",
                          "User-Agent": engine.API_HEADERS_TEMPLATE["User-Agent"]}, timeout=8.0)
            if r.status_code == 403 and "user:profile" in r.text:
                self.toast.emit("Anthropic refuses this token for usage. Use Sign in instead", "bad")
                return False
            if r.status_code == 401:
                self.toast.emit("That token was not accepted", "bad")
                return False
        except httpx.HTTPError:
            pass   # offline: save it anyway, the poller will report any problem
        res = plat.token_set(token)
        if res is not True:
            self.toast.emit(f"Could not save the token: {res}", "bad")
            return False
        os.environ[TOKEN_VAR] = token
        engine.log("Token saved")
        engine.state.refresh_event.set()
        return True

    @Slot(result=bool)
    def clearToken(self):
        plat.token_clear()
        os.environ.pop(TOKEN_VAR, None)
        engine.state.refresh_event.set()
        return True

    @Slot()
    def signIn(self):
        """Opens a terminal that runs `claude auth login`. That sign-in carries the scope the usage endpoint needs."""
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
