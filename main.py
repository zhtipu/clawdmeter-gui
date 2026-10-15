import json
import os
import sys

HERE = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))   # works frozen and from source


def main():
    args = sys.argv[1:]

    # Headless helper: Clawdmeter App.exe --autostart on|off|status
    if "--autostart" in args:
        from bridge import Bridge
        mode = args[args.index("--autostart") + 1] if len(args) > args.index("--autostart") + 1 else "status"
        b = Bridge(poll=False)
        if mode in ("on", "off"):
            b.setAutostart(mode == "on")
        print("autostart:", "on" if b.autostartEnabled() else "off")
        return 0

    # Headless helper: Clawdmeter App.exe --ble-selftest result.json. Looks for phones for a few seconds and writes what it saw,
    # so a build can be checked for Bluetooth support without opening a window.
    if "--ble-selftest" in args:
        out = args[args.index("--ble-selftest") + 1]
        try:
            import ble
            found = ble.BleLink(lambda: {}, lambda *a: None, lambda k: [], lambda m: None, "selftest").scan(4.0)
            res = {"ok": True, "phones": found}
        except Exception as e:
            res = {"ok": False, "error": f"{type(e).__name__}: {e}"}
        with open(out, "w", encoding="utf-8") as f:
            json.dump(res, f)
        return 0

    from PySide6.QtCore import QEvent, QObject, QRectF, Qt, QTimer, QUrl
    from PySide6.QtGui import QAction, QColor, QFontDatabase, QIcon, QPainter, QPen, QPixmap
    from PySide6.QtNetwork import QLocalServer, QLocalSocket
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuickControls2 import QQuickStyle
    from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

    SERVER = "clawdmeter-gui-instance"
    shot_mode = "--shot" in args

    # One copy only: a second launch just asks the first to show its window.
    if not shot_mode:
        sock = QLocalSocket()
        sock.connectToServer(SERVER)
        if sock.waitForConnected(300):
            sock.write(b"show")
            sock.waitForBytesWritten(300)
            return 0

    from bridge import Bridge
    from devapi import DeviceApi

    QQuickStyle.setStyle("Basic")
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Clawdmeter")
    icon_path = os.path.join(HERE, "assets", "icon.ico" if sys.platform == "win32" else "icon.png")
    if os.path.isfile(icon_path):
        app.setWindowIcon(QIcon(icon_path))

    # the bundled icon font; every platform uses the same icons
    font_id = QFontDatabase.addApplicationFont(os.path.join(HERE, "assets", "fonts", "lucide.ttf"))
    if font_id < 0:
        print("could not load the icon font", file=sys.stderr)

    bridge = Bridge(poll=not shot_mode)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", bridge)
    dev = DeviceApi()
    engine.rootContext().setContextProperty("dev", dev)
    engine.rootContext().setContextProperty("dumpSave", "--dump-save" in args)
    engine.rootContext().setContextProperty("startTab", int(args[args.index("--tab") + 1]) if "--tab" in args else 0)
    engine.rootContext().setContextProperty("startPage", int(args[args.index("--page") + 1]) if "--page" in args else 0)
    engine.warnings.connect(lambda ws: [print(w.toString(), file=sys.stderr) for w in ws])
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "qml", "Main.qml")))
    if not engine.rootObjects():
        return 1
    win = engine.rootObjects()[0]

    def show_window():
        win.show()
        win.raise_()
        win.requestActivate()

    # Cmd+Q, the Dock menu and system shutdown must really quit even while "keep running in the tray" is on.
    # Closing from the window's own button is a spontaneous event; those other routes are not.
    class QuitWatcher(QObject):
        def eventFilter(self, obj, ev):
            t = ev.type()
            if t == QEvent.Quit or (t == QEvent.Close and obj is win and not ev.spontaneous()):
                bridge.markQuitting()
            return False
    quit_watcher = QuitWatcher()
    app.installEventFilter(quit_watcher)
    win.installEventFilter(quit_watcher)

    # macOS: clicking the Dock icon while the window is hidden should bring it back
    import time as _time
    started = _time.time()

    def on_state(state):
        if sys.platform != "darwin" or state != Qt.ApplicationActive or win.isVisible():
            return
        if "--tray" in args and _time.time() - started < 4:      # a login start must stay hidden
            return
        show_window()
    app.applicationStateChanged.connect(on_state)

    if not shot_mode:
        server = QLocalServer()
        QLocalServer.removeServer(SERVER)
        server.listen(SERVER)

        def on_conn():
            c = server.nextPendingConnection()
            if c:
                c.readyRead.connect(lambda: (c.readAll(), show_window()))
        server.newConnection.connect(on_conn)

    # --tray starts hidden (used by autostart); otherwise show the window.
    if "--tray" in args and not shot_mode:
        win.hide()
    else:
        show_window()

    # ---- tray icon: a ring that tracks the 5 hour usage ----
    def make_icon(pct, color):
        pm = QPixmap(64, 64)
        pm.fill(Qt.transparent)
        p = QPainter(pm)
        p.setRenderHint(QPainter.Antialiasing)
        pen = QPen(QColor("#3A4252"), 8)
        p.setPen(pen)
        r = QRectF(8, 8, 48, 48)
        p.drawArc(r, 0, 360 * 16)
        if pct > 0:
            pen = QPen(QColor(color), 8)
            pen.setCapStyle(Qt.RoundCap)
            p.setPen(pen)
            p.drawArc(r, 90 * 16, -int(360 * min(pct, 100) / 100 * 16))
        p.end()
        return QIcon(pm)

    tray = QSystemTrayIcon(make_icon(0, "#F5A524"))
    menu = QMenu()
    act_show = QAction("Open Clawdmeter")
    act_show.triggered.connect(show_window)
    act_refresh = QAction("Refresh now")
    act_refresh.triggered.connect(bridge.refreshNow)
    act_quit = QAction("Quit")
    menu.addAction(act_show)
    menu.addAction(act_refresh)
    menu.addSeparator()
    menu.addAction(act_quit)
    tray.setContextMenu(menu)
    tray.activated.connect(lambda reason: show_window() if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick) else None)

    def quit_app():
        bridge.shutdown()
        tray.hide()
        app.quit()
    act_quit.triggered.connect(quit_app)
    win.quitRequested.connect(quit_app)

    # ---- usage alerts: tray notifications, a sound only for critical ----
    def notify(title, body, level):
        icon = {0: QSystemTrayIcon.Information, 1: QSystemTrayIcon.Warning, 2: QSystemTrayIcon.Critical, 3: QSystemTrayIcon.Critical}.get(level, QSystemTrayIcon.Information)
        tray.showMessage(title, body, icon, 12000 if level >= 2 else 8000)
        if level >= 2 and bridge.alerts.cfg.get("sound", True):
            import plat
            plat.beep_critical()
    bridge.notify = notify

    def open_usage():
        win.setProperty("cur", 0)
        show_window()
    tray.messageClicked.connect(open_usage)

    last = {"k": None}

    def update_tray():
        s = json.loads(bridge.snapshot())
        pct = s["s"] if s["ok"] else 0
        color = "#F2566F" if s["st"] in ("rejected",) or s["statusKey"] == "error" else \
                "#F5A524" if s["st"] in ("warning", "allowed_warning") or pct >= 80 else "#34C77B"
        key = (pct, color, s["ok"])
        if key != last["k"]:
            last["k"] = key
            tray.setIcon(make_icon(pct, color))
        bridge.alerts.evaluate(s)
        tray.setToolTip("Clawdmeter\n" + (f"5h {s['s']}%   7d {s['w']}%" if s["ok"] else s["status"]))
    t = QTimer()
    t.timeout.connect(update_tray)
    t.start(2000)
    update_tray()
    if not shot_mode and QSystemTrayIcon.isSystemTrayAvailable():
        tray.show()

    if "--test-alert" in args:       # python main.py --test-alert warning|critical : fire a sample, then quit
        lvl = args[args.index("--test-alert") + 1]
        QTimer.singleShot(1500, lambda: bridge.testAlert(lvl))
        QTimer.singleShot(9000, quit_app)

    if shot_mode:
        out = args[args.index("--shot") + 1]
        delay = int(args[args.index("--delay") + 1]) if "--delay" in args else 3500

        def grab():
            win.grabWindow().save(out)
            quit_app()
        QTimer.singleShot(delay, grab)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
