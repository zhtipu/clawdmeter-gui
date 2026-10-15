"""Checks that run on every platform in CI (and locally): python ci_check.py
Exits non-zero if something that must work does not."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

failures = 0


def check(name, ok, detail=""):
    global failures
    print(("PASS " if ok else "FAIL ") + name + ((" - " + str(detail)) if detail and not ok else ""))
    if not ok:
        failures += 1


# 1. alert logic, usage parser, and the guard that keeps token and API code out of the app
for name, label in (("test_alerts.py", "alert logic tests"), ("test_usage_cli.py", "usage parser tests"), ("test_compliance.py", "no token or API code in the app")):
    r = subprocess.run([sys.executable, os.path.join(HERE, "tests", name)], capture_output=True, text=True)
    check(label, r.returncode == 0 and "FAILURES: 0" in r.stdout, r.stdout[-400:] + r.stderr[-400:])

# 2. platform layer, with HOME pointed at a temp folder so nothing real is touched
tmp = tempfile.mkdtemp()
os.environ["HOME"] = tmp
os.environ["USERPROFILE"] = tmp
import importlib
import plat
importlib.reload(plat)
import engine

check("data folder is creatable", os.path.isdir(plat.data_dir()))
check("finding claude does not crash", isinstance(plat.find_claude(), str))
check("app command is a list", isinstance(plat.app_command(), list) and plat.app_command())
if plat.IS_MAC:
    check("login item turns on", plat.autostart_set(True) is True and plat.autostart_enabled())
    check("login item file is a valid plist", __import__("plistlib").load(open(plat._mac_plist(plat.MAC_LABEL), "rb"))["RunAtLoad"] is True)
    check("login item turns off", plat.autostart_set(False) is True and not plat.autostart_enabled())

# 3. theme patch on the bundled Pixel Room
from PySide6.QtWidgets import QApplication
app = QApplication([])
from devapi import DeviceApi
res = json.loads(DeviceApi().patch12h(""))
check("12-hour patch on the bundled theme", res.get("ok") is True, res)
if res.get("ok"):
    a = open(os.path.join(HERE, "assets", "pixel-room.stheme"), "rb").read()
    b = open(res["path"], "rb").read()
    check("12-hour patch changes exactly the hour token", len(a) == len(b) and sum(x != y for x, y in zip(a, b)) == 2)

# 4. the icon font loads and the whole UI renders
from PySide6.QtGui import QFontDatabase
fid = QFontDatabase.addApplicationFont(os.path.join(HERE, "assets", "fonts", "lucide.ttf"))
check("icon font loads", fid >= 0 and "lucide" in QFontDatabase.applicationFontFamilies(fid))
shot = os.path.join(tmp, "ui.png")
env = dict(os.environ, QT_QUICK_BACKEND="software")
for page in (0, 2, 3, 5):
    out = shot.replace(".png", f"{page}.png")
    p = subprocess.run([sys.executable, os.path.join(HERE, "main.py"), "--page", str(page), "--shot", out, "--delay", "2500"],
                       capture_output=True, text=True, env=env, timeout=120)
    qml_errors = [l for l in (p.stderr or "").splitlines() if "qml" in l.lower() and "error" in l.lower() or "unavailable" in l.lower()]
    check(f"page {page} renders", os.path.isfile(out) and os.path.getsize(out) > 5000 and not qml_errors, (qml_errors or p.stderr)[:3])
    if os.path.isfile(out) and os.environ.get("SHOT_DIR"):
        os.makedirs(os.environ["SHOT_DIR"], exist_ok=True)
        os.replace(out, os.path.join(os.environ["SHOT_DIR"], f"page{page}.png"))

print("FAILURES:", failures)
sys.exit(1 if failures else 0)
