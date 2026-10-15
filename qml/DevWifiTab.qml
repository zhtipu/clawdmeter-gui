import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    property var scanList: []
    property bool scanning: false
    readonly property int n: form.listLen("wifi")
    readonly property bool wgOn: !!(form.cfg && form.cfg.features && form.cfg.features.wireguard !== false)

    function wgLine(w) {
        if (!w) return ""
        if (!w.compiledIn) return "WireGuard is not part of this build."
        if (!w.enabled) return "Tunnel off."
        if (w.held) return "Tunnel suspended after repeated reboots. Check the settings and save again to retry."
        if (w.badConfig) return "Tunnel not started: a field below is empty or malformed. Check the tunnel address, which needs a prefix like /32."
        if (w.up) return "Tunnel up."
        if (!w.endpointIp) return "Tunnel on, waiting for the endpoint name to resolve."
        return "Tunnel on, handshakes sent to " + w.endpointIp + " with no reply."
    }
    function pick(ssid) {
        var len = form.listLen("wifi"), at = -1
        for (var i = 0; i < len; i++) if (!form.listGet("wifi", i, "ssid")) { at = i; break }
        if (at < 0) {
            if (len >= 4) { form.toast("Max 4", "info"); return }
            form.listAdd("wifi", { ssid: ssid, passSet: false, pass: "" })
        } else form.listSet("wifi", at, "ssid", ssid)
    }
    function saveWifi() {
        var rows = [], len = form.listLen("wifi")
        for (var i = 0; i < len; i++) {
            var s = (form.listGet("wifi", i, "ssid") || "").trim()
            if (!s) continue
            var e = { ssid: s }, p = form.listGet("wifi", i, "pass")
            if (p) e.pass = p
            rows.push(e)
        }
        form.call("savewifi", "POST", "/api/config", JSON.stringify({ wifi: rows }))
    }

    Connections {
        target: t.form
        function onResponded(tag, status, data) {
            if (tag === "scan") {
                t.scanning = false
                if (status === 200) { var l = data; l.sort(function (a, b) { return b.rssi - a.rssi }); t.scanList = l }
                else t.form.toast("Scan failed", "bad")
            } else if (tag === "savewifi") {
                if (status === 200 && data.ok) { t.form.toast("Saved, rebooting to connect...", "good"); t.form.call("reboot", "POST", "/api/reboot", "") }
                else t.form.toast((data && data.error) || "Save failed", "bad")
            }
        }
    }

    DevCard {
        title: "Saved networks"; tabActive: t.tabActive; index: 0
        RowLayout {
            Layout.fillWidth: true
            Btn { text: "Scan networks"; glyph: ""; busy: t.scanning; onClicked: { t.scanning = true; t.scanList = []; t.form.call("scan", "GET", "/api/scan", "") } }
        }
        ColumnLayout {
            visible: t.scanList.length > 0
            Layout.fillWidth: true; spacing: 4
            Repeater {
                model: t.scanList
                delegate: Rectangle {
                    Layout.fillWidth: true; height: 38; radius: Theme.radiusSm
                    color: hh.hovered ? Theme.surfaceHi : "transparent"
                    border.width: 1; border.color: hh.hovered ? Theme.accent : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                    Text { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: (modelData.enc ? "secured   " : "open   ") + modelData.rssi + " dBm"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: t.pick(modelData.ssid) }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: t.n
                delegate: RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Field {
                        id: ssidF
                        Layout.fillWidth: true; Layout.preferredWidth: 4
                        placeholderText: "SSID"
                        Binding { target: ssidF; property: "text"; when: !ssidF.activeFocus; value: t.form.listGet("wifi", index, "ssid") || "" }
                        onTextEdited: t.form.listSet("wifi", index, "ssid", text)
                    }
                    Field {
                        id: passF
                        Layout.fillWidth: true; Layout.preferredWidth: 5
                        echoMode: TextInput.Password
                        placeholderText: t.form.listGet("wifi", index, "passSet") ? "(unchanged)" : "password"
                        Binding { target: passF; property: "text"; when: !passF.activeFocus; value: t.form.listGet("wifi", index, "pass") || "" }
                        onTextEdited: t.form.listSet("wifi", index, "pass", text)
                    }
                    Btn { kind: "ghost"; text: ""; glyph: ""; implicitWidth: 44; onClicked: t.form.listRemove("wifi", index) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Btn { text: "Add network"; glyph: ""; onClicked: { if (t.form.listLen("wifi") >= 4) t.form.toast("Max 4", "info"); else t.form.listAdd("wifi", { ssid: "", passSet: false, pass: "" }) } }
            Item { Layout.fillWidth: true }
            Btn { text: "Save and connect (reboots)"; kind: "primary"; glyph: ""; onClicked: t.saveWifi() }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "2.4 GHz only. Up to 4 networks; at boot the device joins the strongest one it can see. Click a scan result to fill a row. Leave a password blank to keep the stored one."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Device name"; tabActive: t.tabActive; index: 1
        DevField { form: t.form; path: "hostname"; label: "Hostname"; placeholder: "smalltv"; mono: true
            hint: "Reachable as <b>http://&lt;hostname&gt;.local</b> via mDNS. Running several SmallTVs? Give each its own name so every computer pushes to the right device. Saving a new name reboots the device." }
    }

    DevCard {
        visible: t.wgOn
        title: "WireGuard VPN"; tabActive: t.tabActive; index: 2
        Text { Layout.fillWidth: true; text: t.wgLine(t.form.status.wg); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.WordWrap }
        DevField { form: t.form; kind: "check"; path: "wg.enabled"; label: "Enable the tunnel" }
        DevField { form: t.form; kind: "password"; path: "wg.privateKey"; label: "This device private key"; placeholder: t.form.val("wg.privateKeySet") ? "(unchanged)" : "paste the private key" }
        DevField { form: t.form; path: "wg.peerPublicKey"; label: "Peer public key"; placeholder: "server public key"; mono: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; path: "wg.endpointHost"; label: "Endpoint host"; placeholder: "vpn.example.com"; Layout.preferredWidth: 3 }
            DevField { form: t.form; kind: "number"; path: "wg.endpointPort"; label: "Port"; Layout.preferredWidth: 1 }
        }
        DevField { form: t.form; path: "wg.address"; label: "Tunnel address"; placeholder: "10.6.0.12/32"; mono: true }
        DevField { form: t.form; path: "wg.allowedIps"; label: "Allowed IPs"; placeholder: "10.6.0.0/24"; mono: true }
        DevField { form: t.form; kind: "number"; path: "wg.keepalive"; label: "Keepalive (s, 0 = off)" }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Reaches the device from outside your LAN without forwarding port 80. Allowed IPs decides what the device routes into the tunnel and also sets the tunnel netmask, so a lone /32 address reaches nothing: list the subnet the peer is on. The private key stays on the device; this page never reads it back."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Setup hotspot (AP)"; tabActive: t.tabActive; index: 3
        DevField { form: t.form; path: "apSsid"; label: "AP name" }
        DevField { form: t.form; kind: "password"; path: "apPass"; label: "AP password (min 8 chars)"; disabled: !!t.form.val("_apOpen")
            placeholder: t.form.val("apPassSet") ? "(unchanged)" : "(open)" }
        DevField { form: t.form; kind: "check"; path: "_apOpen"; label: "No password (open hotspot)" }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "The AP appears when no WiFi is configured or the connection fails. Leaving the password blank keeps the stored one; tick the box to clear it and leave the hotspot open."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
