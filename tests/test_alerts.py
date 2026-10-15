import sys, json, copy, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from alerts import Alerts, WARN, CRIT, LIMIT

def snap(s, w=10, sr=84, wr=3000, st="allowed"):
    return {"ok": True, "s": s, "w": w, "sr": sr, "wr": wr, "st": st, "age": 0}

def make(store=None, **cfg):
    out = []
    store = store if store is not None else {}
    a = Alerts(store, lambda: None, lambda t, b, l: out.append((l, t, b)))
    a.cfg.update(cfg)
    return a, out, store

fails = 0
def check(name, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (" " + str(extra) if not cond else ""))
    if not cond: fails += 1

# 1. normal climb, no repeats, re-arm
a, out, _ = make(); t = 1000.0
for pct in (80, 89, 90, 92, 94, 95, 97, 100, 100):
    a.evaluate(snap(pct), now=t); t += 2
levels = [o[0] for o in out]
check("climb fires warn, crit, limit once each", levels == [WARN, CRIT, LIMIT], levels)
print("  ", out[0][1:], "|", out[1][1:], "|", out[2][1:])
out.clear()
a.evaluate(snap(50), now=t); t += 2           # window reset, resetNote off
check("reset is silent by default", out == [], out)
a.evaluate(snap(91), now=t); t += 2
check("alerts re-arm after a reset", [o[0] for o in out] == [WARN], out)

# 2. start already critical: only critical
a, out, _ = make()
a.evaluate(snap(96), now=1.0)
check("starting at 96 fires only critical", [o[0] for o in out] == [CRIT], out)

# 3. hysteresis: dipping to 88 then back to 91 must not re-alert
a, out, _ = make(); t = 0
for pct in (91, 88, 91, 87, 92):
    a.evaluate(snap(pct), now=t); t += 2
check("no re-alert while still within 5 points of warn", len(out) == 1, out)
for pct in (84, 91):
    a.evaluate(snap(pct), now=t); t += 2
check("re-arms below 85", len(out) == 2, out)

# 4. both meters at once -> one combined notice
a, out, _ = make()
a.evaluate(snap(93, w=91), now=1.0)
check("both meters combine", len(out) == 1 and "5-hour 93%, week 91%" in out[0][2], out)
a, out, _ = make()
a.evaluate(snap(96, w=91), now=1.0)
check("combined takes the higher level", len(out) == 1 and out[0][0] == CRIT and "critical" in out[0][1], out)
a, out, _ = make()
a.evaluate(snap(100, w=91, st="rejected"), now=1.0)
check("a hard limit is not folded into a combined notice", len(out) == 2, out)

# 5. weekly alone
a, out, _ = make()
a.evaluate(snap(10, w=97, wr=3000), now=1.0)
check("weekly critical text", len(out) == 1 and "weekly usage is critical (97%)" in out[0][1] and "2d 2h" in out[0][2], out)

# 6. repeat critical
a, out, _ = make(repeatMin=15); t = 0
a.evaluate(snap(96), now=t)
for step in (60, 600, 900, 1000, 1800, 1801):
    a.evaluate(snap(96), now=step)
check("critical repeats every 15 minutes", len(out) == 3, [o[1] for o in out])

# 7. persistence across restarts inside the same window
a, out, store = make()
a.evaluate(snap(96, sr=60), now=1000.0)
store2 = json.loads(json.dumps(store))
a2, out2, _ = make(store2)
a2.evaluate(snap(96, sr=58), now=1100.0)
check("restart inside the window does not re-alert", out2 == [], out2)
a3, out3, _ = make(json.loads(json.dumps(store)))
a3.evaluate(snap(96, sr=290), now=1000.0 + 3 * 3600)
check("restart after the window ended alerts again", len(out3) == 1, out3)

# 8. reset notice on
a, out, _ = make(resetNote=True); t = 0
a.evaluate(snap(96), now=t); a.evaluate(snap(4), now=t + 2)
check("reset notice when enabled", [o[0] for o in out] == [CRIT, 0] and "reset" in out[1][1], out)

# 9. switches
a, out, _ = make(enabled=False); a.evaluate(snap(99), now=1)
check("master switch off", out == [])
a, out, _ = make(five=False); a.evaluate(snap(99), now=1)
check("5-hour switch off", out == [])
a, out, _ = make(); a.evaluate({"ok": False, "s": 99, "w": 99, "sr": 0, "wr": 0}, now=1)
check("no data, no alert", out == [])

# 10. editable thresholds and their rules
a, out, _ = make()
a.set("warn", 80); a.set("crit", 85)
a.evaluate(snap(82), now=1.0); a.evaluate(snap(86), now=3.0)
check("custom thresholds", [o[0] for o in out] == [WARN, CRIT], out)
a.set("warn", 97)
check("raising warn above crit pushes crit up", a.cfg["crit"] == 98, a.cfg)
a.set("crit", 10)
check("crit cannot sit at or under warn", a.cfg["crit"] == 98, a.cfg)

# 11. test button text
a, out, _ = make(); a.test("warning"); a.test("critical")
print("  ", out[0][1:], "|", out[1][1:])
print("FAILURES:", fails)
