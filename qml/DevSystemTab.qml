import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    readonly property var s: form.status
    property string ghMsg: ""
    property bool newer: false
    property bool busyCheck: false
    property bool updating: false
    property string curVer: ""
    property int polls: 0

    property string fwFile: ""
    property int upPct: 0
    property string upMsg: ""
    property bool upBusy: false
    property string cfgFile: ""

    Timer {
        id: poll
        interval: 3000; repeat: true; running: t.updating
        onTriggered: { t.polls++; if (t.polls > 100) t.updating = false; else t.form.call("selfpoll", "GET", "/api/status", "") }
    }

    Connections {
        target: dev
        function onProgress(tag, pct) { if (tag === "fwup") { t.upPct = pct; t.upMsg = "Uploading " + pct + "%" } }
    }

    Connections {
        target: t.form
        function onResponded(tag, status, data) {
            if (tag === "checkupdate") {
                t.busyCheck = false
                if (status !== 200 || !data.ok) { t.ghMsg = "Check failed" + (data && data.error ? ": " + data.error : ""); t.newer = false; return }
                t.newer = !!data.newer
                t.ghMsg = data.newer ? "Version " + data.latest + " is available (installed " + data.current + ")." : "Up to date (" + data.current + ")."
            } else if (tag === "selfupdate") {
                if (status !== 200) { t.updating = false; t.busyCheck = false; t.ghMsg = "Could not start update"; return }
                t.polls = 0; t.updating = true
            } else if (tag === "selfpoll") {
                if (status !== 200) return
                if (t.curVer && data.version && data.version !== t.curVer) { t.updating = false; t.busyCheck = false; t.ghMsg = "Updated to " + data.version + "."; return }
                var m = data.updateMsg || ""
                if (m && m !== "starting..." && m !== "updating...") { t.updating = false; t.busyCheck = false; t.ghMsg = "Update failed: " + m }
            } else if (tag === "fwup") {
                t.upBusy = false
                if (status === 200) { t.upPct = 100; t.upMsg = "Done. Rebooting..." }
                else t.upMsg = "Failed: " + (status === 0 ? data : "HTTP " + status)
            } else if (tag === "export") {
                if (status === 200) t.form.toast("Settings saved to " + data, "good")
                else if (status !== 0 || data) t.form.toast("Export failed", "bad")
            } else if (tag === "import") {
                if (status === 200) t.form.toast("Imported, rebooting...", "good")
                else t.form.toast("Import failed", "bad")
            } else if (tag === "reboot") {
                if (status === 200) t.form.toast("Rebooting...", "info")
            } else if (tag === "factory") {
                if (status === 200) t.form.toast("Reset, rebooting...", "info")
            }
        }
    }

    DevCard {
        title: "Update from GitHub"; tabActive: t.tabActive; index: 0
        Text {
            text: "Installed: " + (t.s.fw ? t.s.fw + " " + t.s.version : "-")
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        RowLayout {
            spacing: 10
            Btn { text: "Check for latest"; busy: t.busyCheck && !t.updating; enabled: !t.updating
                onClicked: { t.busyCheck = true; t.ghMsg = "Checking GitHub..."; t.form.call("checkupdate", "GET", "/api/checkupdate", "") } }
            Btn { text: "Update now"; kind: "primary"; enabled: t.newer && !t.updating
                onClicked: t.form.confirm("Update from GitHub?", "The newest release is downloaded and flashed. The device reboots if it succeeds, and may reboot twice.", "Update", false, function () {
                    t.curVer = t.s.version || ""; t.busyCheck = true; t.newer = false
                    t.ghMsg = "Downloading and flashing... this can take a couple of minutes."
                    t.form.call("selfupdate", "POST", "/api/selfupdate", "") }) }
        }
        Text { visible: t.ghMsg !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: t.ghMsg; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Pulls the newest release straight from the GitHub repo. HTTPS OTA is tight on the ESP8266; if it fails, use the manual upload below."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Manual update (OTA)"; tabActive: t.tabActive; index: 1
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Rectangle {
                Layout.fillWidth: true; height: 40; radius: Theme.radiusSm
                color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
                Text { anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter } elide: Text.ElideMiddle
                    text: t.fwFile !== "" ? t.fwFile : "No file chosen"; color: t.fwFile !== "" ? Theme.text : Theme.textFaint; font.family: Theme.mono; font.pixelSize: 12 }
            }
            Btn { text: "Choose"; glyph: ""; onClicked: { var p = dev.pickFile("bin"); if (p) t.fwFile = p } }
        }
        RowLayout {
            Btn { text: "Upload and flash"; kind: "primary"; busy: t.upBusy; enabled: t.fwFile !== "" && !t.upBusy
                onClicked: t.form.confirm("Flash this firmware?", "Make sure it is the right file for this device. The device reboots when it finishes.", "Flash", true, function () {
                    t.upBusy = true; t.upPct = 0; t.upMsg = "Uploading 0%"; dev.upload("fwup", "/update", "firmware", t.fwFile) }) }
        }
        Rectangle {
            visible: t.upMsg !== ""
            Layout.fillWidth: true; height: 8; radius: 4; color: Theme.dark ? "#10131A" : "#E3E6ED"
            Rectangle { width: parent.width * t.upPct / 100; height: parent.height; radius: 4; color: Theme.accent
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
        }
        Text { visible: t.upMsg !== ""; text: t.upMsg; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Upload a firmware .bin from the releases page or a local build. The device reboots when done."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Settings backup"; tabActive: t.tabActive; index: 2
        RowLayout { Btn { text: "Export settings"; glyph: ""; onClicked: dev.exportSettings("export") } }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Rectangle {
                Layout.fillWidth: true; height: 40; radius: Theme.radiusSm
                color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
                Text { anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter } elide: Text.ElideMiddle
                    text: t.cfgFile !== "" ? t.cfgFile : "No file chosen"; color: t.cfgFile !== "" ? Theme.text : Theme.textFaint; font.family: Theme.mono; font.pixelSize: 12 }
            }
            Btn { text: "Choose"; glyph: ""; onClicked: { var p = dev.pickFile("json"); if (p) t.cfgFile = p } }
        }
        RowLayout {
            Btn { text: "Import and reboot"; kind: "primary"; enabled: t.cfgFile !== ""
                onClicked: t.form.confirm("Apply this configuration?", "Everything in the file replaces the current settings, then the device reboots.", "Apply", true, function () { dev.importSettings("import", t.cfgFile) }) }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "The export is the device config.json, including WiFi passwords and the WireGuard private key in clear text, so treat the file accordingly. Import applies everything and reboots."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Password"; tabActive: t.tabActive; index: 3
        DevField { form: t.form; kind: "check"; path: "auth.enabled"; label: "Ask for a password to open the device page" }
        DevField { form: t.form; path: "auth.user"; label: "Username"; placeholder: "admin" }
        DevField { form: t.form; kind: "password"; path: "auth.pass"; label: "Password"; placeholder: t.form.val("auth.passSet") ? "(unchanged)" : "set a password" }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.StyledText
            text: "Off by default, which leaves the page open to anyone on your network. Turning it on puts the settings page, the API and the firmware upload behind HTTP digest auth. This app will ask for the password when it needs it. The usage push stays open, because it has no way to send a password. <b>There is no password recovery.</b> Forget it and the only way back in is to reflash the device over USB or the UART header, so write it down before you save."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
        }
    }

    DevCard {
        title: "Maintenance"; tabActive: t.tabActive; index: 4
        RowLayout {
            spacing: 10
            Btn { text: "Reboot"; glyph: ""; onClicked: t.form.confirm("Reboot the device?", "The screen goes blank for a few seconds.", "Reboot", false, function () { t.form.call("reboot", "POST", "/api/reboot", "") }) }
            Btn { text: "Factory reset"; kind: "danger"; glyph: ""
                onClicked: t.form.confirm("Erase ALL settings?", "WiFi, tickers, radar and every other setting on the device are erased, then it reboots into setup mode. This cannot be undone.", "Erase everything", true, function () { t.form.call("factory", "POST", "/api/factory", "") }) }
        }
    }
}
