"""Talks to the SmallTV's own settings API (the same one its web page uses)."""
import json
import os
import re
import struct
import sys
import threading

import httpx
from PySide6.QtCore import QObject, Signal, Slot
from PySide6.QtWidgets import QFileDialog

import engine
import plat


def _hosts(raw):
    items = raw if isinstance(raw, list) else [raw or ""]
    out = []
    for entry in items:
        for it in re.split(r"[,\s;]+", str(entry).strip()):
            if it and it not in out:
                out.append(it)
    return out


class DeviceApi(QObject):
    response = Signal(str, int, str)       # tag, http status (0 = no answer), body text
    progress = Signal(str, int)            # tag, percent
    cashResult = Signal(str)               # JSON list
    authNeeded = Signal()

    def __init__(self):
        super().__init__()
        self._host = ""
        self._auth = None                  # httpx.DigestAuth, kept in memory only

    @Slot(str)
    def debug(self, text):
        import sys
        print(text, file=sys.stderr, flush=True)

    # ---- which TV ----------------------------------------------------------
    @Slot(result=str)
    def hosts(self):
        cfg = engine.load_config()
        return json.dumps(_hosts(cfg.get("push_url")))

    @Slot(str)
    def setHost(self, host):
        self._host = host.strip()

    @Slot(result=str)
    def host(self):
        if not self._host:
            hs = _hosts(engine.load_config().get("push_url"))
            self._host = hs[0] if hs else ""
        return self._host

    @Slot(str, str)
    def setAuth(self, user, password):
        self._auth = httpx.DigestAuth(user, password) if user else None

    def _base(self):
        h = self.host()
        return ("http://" + h) if not h.startswith("http") else h.rstrip("/")

    # ---- plain requests ----------------------------------------------------
    @Slot(str, str, str, str)
    def request(self, tag, method, path, body):
        def work():
            if not self.host():
                self.response.emit(tag, 0, "No TV address is set. Add one on the Connection page.")
                return
            try:
                kw = {"timeout": 25.0 if path in ("/api/scan", "/api/checkupdate") else 12.0}
                if body:
                    kw["content"] = body.encode("utf-8")
                    kw["headers"] = {"Content-Type": "application/json"}
                if self._auth:
                    kw["auth"] = self._auth
                r = httpx.request(method, self._base() + path, **kw)
                if r.status_code == 401:
                    self.authNeeded.emit()
                self.response.emit(tag, r.status_code, r.text)
            except httpx.HTTPError as e:
                self.response.emit(tag, 0, type(e).__name__)
        threading.Thread(target=work, daemon=True).start()

    # ---- files -------------------------------------------------------------
    @Slot(str, result=str)
    def pickFile(self, kind):
        flt = {"bin": "Firmware (*.bin)", "json": "Settings (*.json)", "theme": "Theme (*.stheme)"}.get(kind, "All files (*)")
        path, _ = QFileDialog.getOpenFileName(None, "Choose a file", "", flt)
        return path or ""

    @Slot(str, str, str, str)
    def upload(self, tag, path, field, filepath):
        """multipart upload with progress"""
        def work():
            try:
                with open(filepath, "rb") as f:
                    data = f.read()
                boundary = "----clawdmeter" + os.urandom(8).hex()
                name = os.path.basename(filepath)
                head = (f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{name}"\r\n'
                        f'Content-Type: application/octet-stream\r\n\r\n').encode()
                tail = f"\r\n--{boundary}--\r\n".encode()
                total = len(head) + len(data) + len(tail)

                def gen():
                    sent = 0
                    for chunk in (head, *[data[i:i + 8192] for i in range(0, len(data), 8192)], tail):
                        yield chunk
                        sent += len(chunk)
                        self.progress.emit(tag, int(sent * 100 / total))
                kw = {"content": gen(), "headers": {"Content-Type": f"multipart/form-data; boundary={boundary}",
                                                    "Content-Length": str(total)}, "timeout": 180.0}
                if self._auth:
                    kw["auth"] = self._auth
                r = httpx.post(self._base() + path, **kw)
                self.response.emit(tag, r.status_code, r.text)
            except (OSError, httpx.HTTPError) as e:
                self.response.emit(tag, 0, type(e).__name__)
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def exportSettings(self, tag):
        path, _ = QFileDialog.getSaveFileName(None, "Save settings", "smalltv-config.json", "Settings (*.json)")
        if not path:
            return

        def work():
            try:
                kw = {"timeout": 12.0}
                if self._auth:
                    kw["auth"] = self._auth
                r = httpx.get(self._base() + "/api/export", **kw)
                if r.status_code == 200:
                    with open(path, "wb") as f:
                        f.write(r.content)
                self.response.emit(tag, r.status_code, path)
            except (OSError, httpx.HTTPError) as e:
                self.response.emit(tag, 0, type(e).__name__)
        threading.Thread(target=work, daemon=True).start()

    @Slot(str, str)
    def importSettings(self, tag, filepath):
        def work():
            try:
                with open(filepath, "rb") as f:
                    body = f.read()
                json.loads(body)
                kw = {"content": body, "headers": {"Content-Type": "application/json"}, "timeout": 15.0}
                if self._auth:
                    kw["auth"] = self._auth
                r = httpx.post(self._base() + "/api/import", **kw)
                self.response.emit(tag, r.status_code, r.text)
            except (OSError, ValueError, httpx.HTTPError) as e:
                self.response.emit(tag, 0, type(e).__name__)
        threading.Thread(target=work, daemon=True).start()

    # ---- theme clock: 24 hour -> 12 hour --------------------------------------
    @Slot(str, result=str)
    def patch12h(self, src):
        """Rewrite a .stheme so its clock reads {hh} (1-12) instead of {HH} (0-23). Works on the chosen file,
        or on the Pixel Room package that ships with the app when none is chosen."""
        here = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
        bundled = not src
        path = src or os.path.join(here, "assets", "pixel-room.stheme")
        try:
            with open(path, "rb") as f:
                b = f.read()
            if b[:4] != b"STH1":
                return json.dumps({"ok": False, "msg": "That is not a .stheme file"})
            n, rsv = struct.unpack_from("<HH", b, 4)
            off, entries = 8, []
            for _ in range(n):
                plen, dlen = struct.unpack_from("<HI", b, off)
                off += 6
                p = b[off:off + plen]
                off += plen
                entries.append((p, b[off:off + dlen]))
                off += dlen
            if off != len(b):
                return json.dumps({"ok": False, "msg": "The theme file looks damaged"})
            hits, lower, out = 0, False, []
            for p, data in entries:
                if p == b"theme.json":
                    text = data.decode("utf-8")
                    hits = text.count("{HH}")
                    lower = "{hh}" in text
                    text = text.replace("{HH}", "{hh}")
                    json.loads(text)
                    data = text.encode("utf-8")
                out.append((p, data))
            if not hits:
                return json.dumps({"ok": False, "msg": "This theme is already 12-hour" if lower else "This theme has no 24-hour clock to change"})
            blob = b"STH1" + struct.pack("<HH", len(out), 0)
            for p, data in out:
                blob += struct.pack("<HI", len(p), len(data)) + p + data
            stem = os.path.splitext(os.path.basename(path))[0] + "-12h.stheme"
            dst = os.path.join(os.path.dirname(path), stem)
            if bundled or not os.access(os.path.dirname(path), os.W_OK):
                folder = os.path.join(plat.data_dir(), "themes")
                os.makedirs(folder, exist_ok=True)
                dst = os.path.join(folder, stem)
            with open(dst, "wb") as f:
                f.write(blob)
            return json.dumps({"ok": True, "path": dst, "hits": hits, "bundled": bundled})
        except (OSError, ValueError, struct.error, UnicodeDecodeError) as e:
            return json.dumps({"ok": False, "msg": "Could not read that theme (" + type(e).__name__ + ")"})

    # ---- cash.ch symbol finder (the web page runs this in the browser) -------
    @Slot(str)
    def cashFind(self, q):
        def work():
            q2 = q.strip()
            m = re.match(r"^https?://\S*?(\d{5,12})", q2)
            if m:
                q2 = m.group(1)
            q2 = re.sub(r'["\\]', "", q2)
            gq = ('query{textSearch(publication:CASH,search:"' + q2 + '",sort:Relevance,sortOrder:Descending,limit:10,offset:0){'
                  'equity{items{...on Equity{listingId mName market mCur mIsin}}} fund{items{...on Fund{listingId mName market mCur mIsin}}} '
                  'derivative{items{...on Derivative{listingId mName market mCur mIsin}}} bond{items{...on Bond{listingId mName market mCur mIsin}}} '
                  'index{items{...on Index{listingId mName market mCur}}} diverse{items{...on Diverse{listingId mName market mCur mIsin}}} '
                  'cryptoCurrency{items{...on CryptoCurrency{listingId mName market mCur}}}}}')
            try:
                r = httpx.get("https://www.cash.ch/_/api/graphql/prod", params={"query": gq}, timeout=12.0)
                d = r.json()
                b = ((d.get("data") or {}).get("textSearch")) or {}
                out = []
                for k in ("equity", "derivative", "fund", "bond", "index", "diverse", "cryptoCurrency"):
                    for it in ((b.get(k) or {}).get("items")) or []:
                        if it and it.get("listingId"):
                            out.append({"key": it["listingId"], "name": it.get("mName") or "?", "isin": it.get("mIsin") or "",
                                        "market": it.get("market") or "", "cur": it.get("mCur") or ""})
                self.cashResult.emit(json.dumps({"ok": True, "items": out[:10]}))
            except (httpx.HTTPError, ValueError):
                self.cashResult.emit(json.dumps({"ok": False, "items": []}))
        threading.Thread(target=work, daemon=True).start()
