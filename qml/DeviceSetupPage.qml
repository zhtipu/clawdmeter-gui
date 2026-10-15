import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "tz.js" as Tz

// The TV's own settings, rebuilt natively. Same tabs, same fields, same API as its web page.
Flickable {
    id: page
    required property var app
    property bool active: false
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight + 56
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }

    // ---- form state shared with the tabs ------------------------------------
    property var cfg: ({})
    property var status: ({})
    property int rev: 0
    property var dirty: ({})
    property int dirtyCount: 0
    property bool loaded: false
    property bool loading: false
    property string loadError: ""
    property int tab: typeof startTab !== "undefined" ? startTab : 0
    property var hostList: []
    property string host: ""
    property bool saving: false

    signal responded(string tag, int status, var data)
    signal configLoaded()

    readonly property var tabNames: ["Status", "WiFi", "Display", "Ticker", "Clawdmeter", "Radar", "Home Assistant", "System"]
    readonly property var feat: cfg.features || ({})
    readonly property var visibleTabs: {
        var out = []
        for (var i = 0; i < tabNames.length; i++) {
            if (i === 3 && feat.ticker === false) continue
            if (i === 4 && feat.usage === false) continue
            if (i === 5 && feat.radar === false) continue
            if (i === 6 && feat.ha === false) continue
            out.push(i)
        }
        return out
    }

    function toast(m, k) { app.toast(m, k) }
    function confirm(t, m, l, d, cb) { app.confirm(t, m, l, d, cb) }

    function getPath(o, path) {
        var parts = path.split("."), v = o
        for (var i = 0; i < parts.length; i++) { if (v === undefined || v === null) return undefined; v = v[parts[i]] }
        return v
    }
    function setPath(o, path, val) {
        var parts = path.split("."), v = o
        for (var i = 0; i < parts.length - 1; i++) { if (typeof v[parts[i]] !== "object" || v[parts[i]] === null) v[parts[i]] = {}; v = v[parts[i]] }
        v[parts[parts.length - 1]] = val
    }
    function val(path) { var r = rev; return getPath(cfg, path) }
    function markDirty(path) {
        if (!dirty[path]) { dirty[path] = true; dirtyCount = Object.keys(dirty).length }
    }
    function set(path, v) {
        setPath(cfg, path, v)
        markDirty(path)
        rev++
    }
    function listLen(path) { var r = rev; var a = getPath(cfg, path); return a ? a.length : 0 }
    function listGet(path, i, key) { var r = rev; var a = getPath(cfg, path); return (a && a[i]) ? a[i][key] : undefined }
    function listSet(path, i, key, v) { var a = getPath(cfg, path); if (a && a[i]) { a[i][key] = v; markDirty(path); rev++ } }
    function listAdd(path, o) { var a = getPath(cfg, path); if (!a) { setPath(cfg, path, []); a = getPath(cfg, path) } a.push(o); markDirty(path); rev++ }
    function listRemove(path, i) { var a = getPath(cfg, path); if (a) { a.splice(i, 1); markDirty(path); rev++ } }

    function call(tag, method, path, body) { dev.request(tag, method, path, body || "") }

    function loadAll() {
        if (!host) { loadError = "No TV address is set. Add one on the Connection page."; loaded = false; return }
        loading = true; loadError = ""
        call("config", "GET", "/api/config", "")
        call("status", "GET", "/api/status", "")
    }
    function reloadHosts() {
        hostList = JSON.parse(dev.hosts())
        var h = dev.host()
        if (hostList.length && hostList.indexOf(h) < 0) { dev.setHost(hostList[0]); h = hostList[0] }
        host = h
    }

    // ---- save: the same object the web page sends ---------------------------
    function collect() {
        var c = cfg, f = feat
        function I(v, d) { var n = parseInt(v); return isNaN(n) ? (d === undefined ? 0 : d) : n }
        var o = {
            mode: c.mode, carouselSec: I(c.carouselSec) || 30,
            carouselTicker: !!c.carouselTicker, carouselUsage: !!c.carouselUsage, carouselRadar: !!c.carouselRadar, carouselHa: !!c.carouselHa,
            brightness: I(c.brightness), rotation: I(c.rotation), autoBrightness: !!c.autoBrightness, backlightInverted: !!c.backlightInverted,
            hostname: c.hostname || "", apSsid: c.apSsid || ""
        }
        var d = c.display || {}
        o.display = { colorOrder: d.colorOrder || "auto", invert: !!d.invert, rGain: I(d.rGain, 100) || 100, gGain: I(d.gGain, 100) || 100, bGain: I(d.bGain, 100) || 100 }
        o.wifi = []
        var w = c.wifi || []
        for (var i = 0; i < w.length; i++) {
            var s = (w[i].ssid || "").trim()
            if (!s) continue
            var e = { ssid: s }
            if (w[i].pass) e.pass = w[i].pass
            o.wifi.push(e)
        }
        var au = c.auth || {}
        o.auth = { enabled: !!au.enabled, user: au.user || "admin" }
        if (au.pass) o.auth.pass = au.pass
        if (c._apOpen) o.apPass = ""
        else if (c.apPass) o.apPass = c.apPass
        if (f.wireguard !== false) {
            var g = c.wg || {}
            o.wg = { enabled: !!g.enabled, peerPublicKey: g.peerPublicKey || "", endpointHost: g.endpointHost || "", endpointPort: I(g.endpointPort) || 51820,
                     address: g.address || "", allowedIps: g.allowedIps || "", keepalive: I(g.keepalive) }
            if (g.privateKey) o.wg.privateKey = g.privateKey
        }
        if (f.ticker !== false) {
            var t = c.ticker || {}
            o.ticker = { colorInverted: !!t.colorInverted, changeOnRange: t.changeOnRange !== false, webhookUrl: t.webhookUrl || "", range: t.range || "1d",
                         rotateSec: I(t.rotateSec), pollSec: I(t.pollSec), points: I(t.points),
                         showName: !!t.showName, showPrice: !!t.showPrice, showChange: !!t.showChange, showChart: !!t.showChart,
                         showRangeLabel: !!t.showRangeLabel, showUpdatedAgo: !!t.showUpdatedAgo, showPageDots: !!t.showPageDots, showPortfolio: !!t.showPortfolio, symbols: [] }
            var sy = t.symbols || []
            for (var j = 0; j < sy.length; j++) {
                var sym = (sy[j].symbol || "").trim()
                if (sym) o.ticker.symbols.push({ symbol: sym, name: (sy[j].name || "").trim(), source: sy[j].source || "yahoo", qty: parseFloat(sy[j].qty) || 0, cost: parseFloat(sy[j].cost) || 0 })
            }
        }
        if (f.usage !== false) { var u = c.usage || {}; o.usage = { usageUrl: u.usageUrl || "", pollSec: I(u.pollSec) } }
        if (f.ha !== false) {
            var h = c.ha || {}
            o.ha = { brokerHost: h.brokerHost || "", brokerPort: I(h.brokerPort) || 1883, brokerUser: h.brokerUser || "", dwellSec: I(h.dwellSec) || 15 }
            if (h.brokerPass) o.ha.brokerPass = h.brokerPass
        }
        var ck = c.clock || {}
        var tzn = ck.tz || ""
        var posix = Tz.MAP.hasOwnProperty(tzn) ? Tz.MAP[tzn] : (ck.tzPosix || "UTC0")
        o.clock = { tz: tzn, tzPosix: posix, nightEnabled: !!ck.nightEnabled, nightStart: ck.nightStart || "22:00", nightEnd: ck.nightEnd || "07:00", nightLevel: I(ck.nightLevel) }
        if (f.radar !== false) {
            var r = c.radar || {}
            o.radar = { lat: parseFloat(r.lat) || 0, lon: parseFloat(r.lon) || 0, rangeKm: I(r.rangeKm) || 20, unitsMi: !!r.unitsMi, pollSec: I(r.pollSec), source: r.source || "adsblol",
                        webhookUrl: r.webhookUrl || "", showLabels: !!r.showLabels, showVectors: !!r.showVectors, showRimDots: !!r.showRimDots,
                        uiScale: I(r.uiScale), minAltFt: I(r.minAltFt), airports: [] }
            var ap = r.airports || []
            for (var k = 0; k < ap.length; k++) {
                var ic = (ap[k].icao || "").trim()
                if (ic) o.radar.airports.push({ icao: ic, lat: parseFloat(ap[k].lat) || 0, lon: parseFloat(ap[k].lon) || 0 })
            }
        }
        return o
    }
    function saveAll() {
        saving = true
        call("save", "POST", "/api/config", JSON.stringify(collect()))
    }

    function parse(text) { try { return JSON.parse(text) } catch (e) { return text } }

    Connections {
        target: dev
        function onResponse(tag, status, text) {
            var data = page.parse(text)
            if (tag === "config") {
                page.loading = false
                if (status === 200 && typeof data === "object") {
                    data._apOpen = !data.apPassSet
                    page.cfg = data
                    page.dirty = ({}); page.dirtyCount = 0
                    page.rev++
                    page.loaded = true; page.loadError = ""
                    page.configLoaded()
                    if (typeof dumpSave !== "undefined" && dumpSave) dev.debug("SAVE_PAYLOAD " + JSON.stringify(page.collect()))
                } else if (status !== 401) {
                    page.loaded = false
                    page.loadError = "Could not reach the TV at " + page.host + (status ? " (HTTP " + status + ")" : "") + ". Check the address on the Connection page and that the computer is on the same network."
                }
            } else if (tag === "status") {
                if (status === 200 && typeof data === "object") page.status = data
            } else if (tag === "save") {
                page.saving = false
                if (status === 200 && data && data.ok) {
                    page.toast(data.reboot ? "Saved, the device is rebooting..." : "Saved", "good")
                    page.dirty = ({}); page.dirtyCount = 0
                    if (data.reboot) reloadTimer.restart(); else page.loadAll()
                } else page.toast((data && data.error) || "Save failed", "bad")
            }
            page.responded(tag, status, data)
        }
        function onAuthNeeded() { authSheet.open = true }
    }

    Timer { id: reloadTimer; interval: 7000; onTriggered: page.loadAll() }
    Timer { interval: 5000; repeat: true; running: page.active && page.loaded; onTriggered: page.call("status", "GET", "/api/status", "") }

    onActiveChanged: if (active) { reloadHosts(); if (!loaded || dirtyCount === 0) loadAll() }
    Component.onCompleted: { reloadHosts() }

    // ---- layout ---------------------------------------------------------------
    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        // Header, like the web page: dot, name, chip, address
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Layout.preferredHeight: 52
            Icon { text: ""; size: 24; tint: Theme.good; Layout.alignment: Qt.AlignVCenter }
            Rectangle {
                width: 9; height: 9; radius: 5; Layout.alignment: Qt.AlignVCenter
                color: page.status.connected ? Theme.good : Theme.textFaint
                Behavior on color { ColorAnimation { duration: Theme.base } }
            }
            Text { text: "SmallTV"; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: 24; font.weight: Font.DemiBold; font.letterSpacing: -0.4; Layout.alignment: Qt.AlignVCenter }
            Chip { visible: !!page.cfg.chip; text: page.cfg.chip === "esp8266" ? "ESP8266" : page.cfg.chip === "esp32c2" ? "ESP32-C2" : page.cfg.chip === "esp32" ? "ESP32" : ""; tone: "info"; Layout.alignment: Qt.AlignVCenter }
            Text { text: page.status.mode === "ap" ? "setup mode" : (page.status.ip || ""); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
            Item { Layout.fillWidth: true }
            Combo {
                visible: page.hostList.length > 1
                Layout.preferredWidth: 190
                model: page.hostList.map(function (h) { return { label: h, value: h } })
                controlled: true
                currentIndex: Math.max(0, page.hostList.indexOf(page.host))
                onActivated: function (i) { dev.setHost(page.hostList[i]); page.host = page.hostList[i]; page.loaded = false; page.loadAll() }
            }
            Chip { visible: page.dirtyCount > 0; text: "Unsaved changes"; tone: "accent"; Layout.alignment: Qt.AlignVCenter }
            Btn { text: "Save settings"; kind: "primary"; glyph: ""; busy: page.saving; enabled: page.loaded && !page.saving; onClicked: page.saveAll() }
        }

        // Pill tabs, same names and order as the web page
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: "transparent"
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
            Flickable {
                anchors.fill: parent
                contentWidth: pills.width; contentHeight: height
                clip: true; boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: pills
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: page.visibleTabs
                        delegate: Rectangle {
                            readonly property bool sel: page.tab === modelData
                            width: lab.implicitWidth + 28; height: 38; radius: 9
                            color: sel ? Theme.surface : (hh.hovered ? Theme.surfaceHi : "transparent")
                            border.width: sel ? 1 : 0; border.color: Theme.border
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            scale: tap.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Text {
                                id: lab; anchors.centerIn: parent
                                text: page.tabNames[modelData]
                                color: parent.sel || hh.hovered ? Theme.text : Theme.textDim
                                font.family: Theme.font; font.pixelSize: 14; font.weight: parent.sel ? Font.DemiBold : Font.Medium
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                            HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: tap; onTapped: page.tab = modelData }
                        }
                    }
                }
            }
        }

        // Offline / loading state
        Card {
            Layout.fillWidth: true
            visible: !page.loaded
            revealOn: page.active
            RowLayout {
                width: parent.width; spacing: 14
                Spinner { visible: page.loading; size: 22; tint: Theme.accent }
                Icon { visible: !page.loading; text: ""; tint: Theme.accent; size: 22 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: page.loading ? "Connecting to the TV..." : "Cannot reach the TV"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { visible: !page.loading; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: page.loadError; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                }
                Btn { visible: !page.loading; text: "Try again"; onClicked: { page.reloadHosts(); page.loadAll() } }
            }
        }

        // All tabs stay alive so edits survive switching, like the web page
        DevStatusTab { form: page; visible: page.loaded && page.tab === 0; tabActive: visible; Layout.fillWidth: true }
        DevWifiTab { form: page; visible: page.loaded && page.tab === 1; tabActive: visible; Layout.fillWidth: true }
        DevDisplayTab { form: page; visible: page.loaded && page.tab === 2; tabActive: visible; Layout.fillWidth: true }
        DevTickerTab { form: page; visible: page.loaded && page.tab === 3; tabActive: visible; Layout.fillWidth: true }
        DevClawdTab { form: page; visible: page.loaded && page.tab === 4; tabActive: visible; Layout.fillWidth: true }
        DevRadarTab { form: page; visible: page.loaded && page.tab === 5; tabActive: visible; Layout.fillWidth: true }
        DevHaTab { form: page; visible: page.loaded && page.tab === 6; tabActive: visible; Layout.fillWidth: true }
        DevSystemTab { form: page; visible: page.loaded && page.tab === 7; tabActive: visible; Layout.fillWidth: true }
    }

    // The TV can be set to ask for a password; this app keeps it in memory only.
    Sheet {
        id: authSheet
        parent: page.app.overlayRoot
        panelWidth: 440
        ColumnLayout {
            width: parent.width; spacing: 12
            Text { text: "The TV asks for a password"; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: 21; font.weight: Font.DemiBold; font.letterSpacing: -0.3 }
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Enter the username and password set on the device. They are kept in memory while the app runs and never saved."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14 }
            Field { id: au; Layout.fillWidth: true; placeholderText: "Username"; text: "admin" }
            Field { id: ap; Layout.fillWidth: true; placeholderText: "Password"; echoMode: TextInput.Password; onAccepted: go.clicked() }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 8; spacing: 8
                Item { Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: authSheet.open = false }
                Btn { id: go; text: "Sign in"; kind: "primary"; onClicked: { dev.setAuth(au.text, ap.text); ap.text = ""; authSheet.open = false; page.loadAll() } }
            }
        }
    }
}
