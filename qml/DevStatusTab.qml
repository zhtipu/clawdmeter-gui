import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    readonly property var s: form.status

    function fmtUp(sec) {
        var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m"
    }
    function radarLine(r) {
        if (!r) return ""
        var x = r.stage || "idle"
        if (r.count) x = r.count + " aircraft"
        else if (r.stage === "ok" || r.stage === "all filtered out") x = r.stage + " (" + (r.seenAc || 0) + " in feed)"
        if (r.http) x += ", HTTP " + r.http
        if (r.tlsRx) x += ", TLS rx " + r.tlsRx + " B"
        if (r.triedAgo !== undefined && r.triedAgo !== null) x += ", tried " + r.triedAgo + "s ago"
        if (r.okAgo !== undefined && r.okAgo !== null) x += ", last ok " + r.okAgo + "s ago"
        else if (r.stage !== "idle") x += ", never succeeded"
        return x
    }

    DevCard {
        title: "Device"; tabActive: t.tabActive; index: 0
        Text { visible: !t.s.fw; text: "Loading..."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        ColumnLayout {
            visible: !!t.s.fw
            Layout.fillWidth: true; spacing: 0
            DevKV { label: "Firmware"; value: (t.s.fw || "") + " " + (t.s.version || "") + (t.s.variant ? " (" + t.s.variant + ")" : "") }
            DevKV { label: "Mode"; value: (t.s.mode || "").toUpperCase() }
            DevKV { label: "Network"; value: t.s.ssid || "-" }
            DevKV { label: "IP"; value: t.s.ip || "-" }
            DevKV { label: "mDNS"; value: "http://" + ((t.form.cfg && t.form.cfg.hostname) || "smalltv") + ".local" }
            DevKV { label: "Signal"; value: t.s.rssi ? t.s.rssi + " dBm" : "-" }
            DevKV { label: "Free heap"; value: (t.s.heap || 0) + " B" + (t.s.maxblk ? " (" + t.s.maxblk + " B largest block)" : "") }
            DevKV { label: "Uptime"; value: t.fmtUp(t.s.uptime || 0) }
            DevKV { label: "Last reset"; value: t.s.reset || "-"; last: !(t.s.wg && t.s.wg.compiledIn) && !t.s.radar }
            DevKV {
                visible: !!(t.s.wg && t.s.wg.compiledIn)
                label: "VPN"; last: !t.s.radar
                value: t.s.wg ? (t.s.wg.held ? "held" : (t.s.wg.up ? "up" : (t.s.wg.enabled ? "connecting" : "off"))) : ""
            }
            DevKV { visible: !!t.s.radar; label: "Radar"; value: t.radarLine(t.s.radar); last: true }
        }
    }
}
