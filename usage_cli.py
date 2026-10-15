"""Reads Claude usage by running the official `claude -p /usage` program and parsing what it prints.

This app never opens, reads or stores a Claude login or token, and makes no network calls to Anthropic itself.
Claude Code, signed in by the user, does all of that. We only read the two lines it prints.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Optional

import plat

NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0      # no console flash on Windows

_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
_LINE = re.compile(r"Current\s+(?P<label>session|week[^:\n]*):\s*(?P<pct>\d+(?:\.\d+)?)\s*%\s*used(?P<rest>[^\n]*)", re.I)
_RESETS = re.compile(r"resets?\s+(?P<when>.+?)\s*$", re.I)
_TZ = re.compile(r"\((?P<tz>[A-Za-z_]+(?:/[A-Za-z_+\-0-9]+)+|UTC|GMT)\)\s*$")
_TIME = re.compile(
    r"(?:(?P<mon>[A-Za-z]{3,9})\.?\s+(?P<day>\d{1,2}),?\s*(?:at\s+)?)?(?P<h>\d{1,2})(?::(?P<m>\d{2}))?\s*(?P<ap>am|pm)", re.I)
_MONTHS = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}


@dataclass
class Result:
    kind: str                       # ok | missing | signed_out | no_limits | fail
    message: str = ""
    payload: Optional[dict] = None

    @property
    def ok(self) -> bool:
        return self.kind == "ok"


def _local_tz() -> dt.tzinfo:
    return dt.datetime.now().astimezone().tzinfo


def minutes_until(when: str, now_utc: Optional[dt.datetime] = None) -> int:
    """'Oct 15, 11:29pm (Asia/Dhaka)' or '11:29pm' to whole minutes from now. 0 if it cannot be read or is past."""
    now_utc = now_utc or dt.datetime.now(dt.timezone.utc)
    tz = None
    m = _TZ.search(when)
    if m:
        try:
            from zoneinfo import ZoneInfo
            tz = ZoneInfo(m.group("tz"))
        except Exception:                                   # no tz database here: the printed zone is the machine's own
            tz = None
        when = when[:m.start()].strip()
    tz = tz or _local_tz()
    t = _TIME.search(when)
    if not t:
        return 0
    hour = int(t.group("h")) % 12 + (12 if t.group("ap").lower() == "pm" else 0)
    minute = int(t.group("m") or 0)
    now = now_utc.astimezone(tz)
    try:
        if t.group("mon") and t.group("day"):
            mon = _MONTHS.get(t.group("mon")[:3].lower())
            if not mon:
                return 0
            target = dt.datetime(now.year, mon, int(t.group("day")), hour, minute, tzinfo=tz)
            if target < now - dt.timedelta(days=1):
                target = target.replace(year=now.year + 1)
        else:
            target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if target <= now:
                target += dt.timedelta(days=1)
    except ValueError:
        return 0
    return max(0, int(round((target - now).total_seconds() / 60)))


def parse_usage(text: str, now_utc: Optional[dt.datetime] = None) -> Optional[dict]:
    """The usage payload from the program's output, or None if the two limit lines are not there."""
    text = _ANSI.sub("", text or "")
    five = week = None
    for m in _LINE.finditer(text):
        label = m.group("label").lower()
        pct = int(round(float(m.group("pct"))))
        r = _RESETS.search(m.group("rest"))
        mins = minutes_until(r.group("when"), now_utc) if r else 0
        if label.startswith("session"):
            if five is None:
                five = (pct, mins)
        elif "all models" in label or label.strip() == "week":
            if week is None or "all models" in label:
                week = (pct, mins)
        elif week is None:
            week = (pct, mins)                              # a weekly line with some other label, only if nothing better
    if five is None and week is None:
        return None
    s, sr = five or (0, 0)
    w, wr = week or (0, 0)
    st = "rejected" if s >= 100 else "warning" if s >= 90 else "allowed"
    return {"s": s, "sr": sr, "w": w, "wr": wr, "st": st, "ok": True}


def classify(text: str, exit_code: int) -> Result:
    text = _ANSI.sub("", text or "")
    payload = parse_usage(text)
    if payload:
        return Result("ok", payload=payload)
    low = text.lower()
    if re.search(r"not logged in|please (run )?/?login|/login|sign in|log in|authentication", low):
        return Result("signed_out", "Not signed in to Claude Code. Sign in on the Account page.")
    if "subscription" in low or "api key" in low or "usage limits" in low:
        return Result("no_limits", "Usage limits are only shown when Claude Code is signed in with a Claude subscription.")
    if exit_code != 0:
        return Result("fail", f"Claude Code exited with an error ({exit_code}).")
    return Result("fail", "Claude Code answered, but not with usage lines this app understands.")


def _workdir() -> str:
    d = os.path.join(plat.data_dir(), "work")                # an empty folder, so no project is ever touched
    os.makedirs(d, exist_ok=True)
    return d


def read_usage(timeout: int = 90) -> Result:
    exe = plat.find_claude()
    if not exe:
        return Result("missing", "Claude Code was not found on this computer. Install it, then sign in.")
    try:
        p = subprocess.run([exe, "-p", "/usage"], capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=timeout, cwd=_workdir(), stdin=subprocess.DEVNULL, creationflags=NO_WINDOW)
    except subprocess.TimeoutExpired:
        return Result("fail", "Claude Code did not answer in time.")
    except OSError as e:
        return Result("fail", f"Could not start Claude Code ({type(e).__name__}).")
    return classify((p.stdout or "") + "\n" + (p.stderr or ""), p.returncode)


def auth_status(timeout: int = 30) -> dict:
    """{'found': bool, 'path': str, 'signedIn': bool | None, 'method': str}. Asks the official program; nothing else."""
    exe = plat.find_claude()
    if not exe:
        return {"found": False, "path": "", "signedIn": None, "method": ""}
    out = {"found": True, "path": exe, "signedIn": None, "method": ""}
    try:
        p = subprocess.run([exe, "auth", "status"], capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=timeout, cwd=_workdir(), stdin=subprocess.DEVNULL, creationflags=NO_WINDOW)
        j = json.loads(p.stdout or "{}")
        out["signedIn"] = bool(j.get("loggedIn"))
        out["method"] = str(j.get("authMethod") or "")
    except (subprocess.TimeoutExpired, OSError, ValueError):
        pass
    return out
