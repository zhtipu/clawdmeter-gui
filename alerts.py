"""Usage alert logic: decides when to notify. Delivery (the tray balloon, the sound) is supplied by the caller."""
import time

DEFAULTS = {
    "enabled": True,
    "five": True,          # watch the 5 hour window
    "week": True,          # watch the 7 day window
    "warn": 90,
    "crit": 95,
    "sound": True,         # sound for critical alerts only
    "resetNote": False,    # tell me when a window resets
    "repeatMin": 0,        # repeat the critical alert every N minutes while still above it (0 = once)
}

# alert levels
NONE, WARN, CRIT, LIMIT = 0, 1, 2, 3
REARM_GAP = 5              # usage must fall this far below the warning level to re-arm
RESET_DROP = 20            # a fall this big in one step means the window reset

METERS = {
    "five": {"pct": "s", "mins": "sr", "name": "5-hour", "noun": "window"},
    "week": {"pct": "w", "mins": "wr", "name": "weekly", "noun": "week"},
}


def fmt_mins(m):
    m = max(0, int(round(m)))
    d, h, mm = m // 1440, (m % 1440) // 60, m % 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {mm}m"
    return f"{mm}m"


def message(meter, level, pct, left_mins):
    """(title, body) for one meter at one level."""
    m = METERS[meter]
    left = max(0, 100 - pct)
    r = fmt_mins(left_mins)
    five = meter == "five"
    if level == LIMIT:
        return ("Claude limit reached",
                f"Your 5-hour window is full. It resets in {r}." if five else f"Your weekly limit is full. It resets in {r}.")
    if level == CRIT:
        return (f"Claude {m['name']} usage is critical ({pct}%)",
                f"Only {left}% left. Claude may stop replying soon. Resets in {r}." if five
                else f"Only {left}% left for the week. Resets in {r}, so go easy.")
    return (f"Claude {m['name']} usage at {pct}%",
            f"{left}% of this window is left. It resets in {r}." if five else f"{left}% of this week is left. It resets in {r}.")


def reset_message(meter):
    if meter == "five":
        return ("Claude 5-hour window reset", "You are back to a fresh window.")
    return ("Claude weekly window reset", "You have a fresh week of usage.")


class Alerts:
    def __init__(self, store, save, notify):
        """store: dict persisted by the caller; save(): persist it; notify(title, body, level)."""
        self.store = store
        self.save = save
        self.notify = notify
        st = store.setdefault("alerts", {})
        for k, v in DEFAULTS.items():
            st.setdefault(k, v)
        self.state = store.setdefault("alertState", {})      # meter -> {level, expires, fired}
        self.prev = {}                                        # meter -> last pct seen this run

    # ---- settings ---------------------------------------------------------
    @property
    def cfg(self):
        return self.store["alerts"]

    def settings(self):
        return dict(self.cfg)

    def set(self, key, value):
        if key not in DEFAULTS:
            return False
        if key in ("warn", "crit", "repeatMin"):
            value = int(value)
        else:
            value = bool(value)
        if key == "warn":
            value = max(50, min(98, value))
            if value >= self.cfg["crit"]:
                self.cfg["crit"] = min(99, value + 1)
        elif key == "crit":
            value = max(self.cfg["warn"] + 1, min(99, value))
        elif key == "repeatMin":
            value = max(0, min(240, value))
        self.cfg[key] = value
        self.save()
        return True

    # ---- the decision -------------------------------------------------------
    def target(self, meter, pct, status):
        c = self.cfg
        if pct >= 100 or (meter == "five" and status == "rejected"):
            return LIMIT
        if pct >= c["crit"]:
            return CRIT
        if pct >= c["warn"]:
            return WARN
        return NONE

    def evaluate(self, snap, now=None):
        """snap: the app snapshot (ok, s, w, sr, wr, st, age). Call every couple of seconds."""
        c = self.cfg
        if not c["enabled"] or not snap.get("ok"):
            return
        now = now if now is not None else time.time()
        age = max(0, snap.get("age", 0) or 0)
        events = []                                           # (meter, level, pct, left_mins)
        for meter, spec in METERS.items():
            if not c[meter]:
                continue
            pct = int(snap.get(spec["pct"], 0))
            left = max(0, snap.get(spec["mins"], 0) - age / 60.0)
            s = self.state.setdefault(meter, {"level": NONE, "expires": 0, "fired": 0})

            # a stored level from an earlier run only counts while that window is still open
            if s["level"] and s["expires"] and now > s["expires"]:
                s["level"] = NONE
            prev = self.prev.get(meter)
            self.prev[meter] = pct

            # window reset: usage fell a long way in one step
            if prev is not None and prev - pct >= RESET_DROP and s["level"] >= CRIT:
                if c["resetNote"]:
                    t, b = reset_message(meter)
                    self.notify(t, b, NONE)
                s["level"] = NONE

            tgt = self.target(meter, pct, snap.get("st", ""))
            if tgt == NONE and pct < c["warn"] - REARM_GAP:
                if s["level"]:
                    s["level"] = NONE
                continue
            if tgt > s["level"]:
                events.append((meter, tgt, pct, left))
                s["level"] = tgt
                s["fired"] = now
                s["expires"] = now + left * 60
            elif (c["repeatMin"] > 0 and tgt >= CRIT and s["level"] >= CRIT
                  and now - s["fired"] >= c["repeatMin"] * 60):
                events.append((meter, tgt, pct, left))
                s["fired"] = now

        if not events:
            self.save()
            return
        # two meters crossing at once read better as one notice, unless one is a hard limit
        if len(events) == 2 and all(e[1] in (WARN, CRIT) for e in events):
            lvl = max(e[1] for e in events)
            d = {e[0]: e for e in events}
            title = "Claude usage is critical" if lvl == CRIT else "Claude usage is high"
            body = f"5-hour {d['five'][2]}%, week {d['week'][2]}%. The 5-hour window resets in {fmt_mins(d['five'][3])}."
            self.notify(title, body, lvl)
        else:
            for meter, lvl, pct, left in events:
                t, b = message(meter, lvl, pct, left)
                self.notify(t, b, lvl)
        self.save()

    def test(self, level):
        """Fire a sample so you can see what an alert looks like."""
        lvl = CRIT if level == "critical" else WARN
        pct = 96 if lvl == CRIT else 90
        t, b = message("five", lvl, pct, 84)
        self.notify(t, b, lvl)
