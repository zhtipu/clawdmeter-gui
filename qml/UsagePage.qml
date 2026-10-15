import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Flickable {
    id: page
    required property var app
    property bool active: false
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight + 56
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }

    readonly property var s: app.snap

    function human(mins, ageSec) {
        var m = Math.max(0, Math.round(mins - (ageSec > 0 ? ageSec / 60 : 0)))
        if (mins <= 0) return "soon"
        var d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), mm = m % 60
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + mm + "m"
        return mm + "m"
    }
    function ago(sec) {
        if (sec < 0) return "never"
        if (sec < 5) return "just now"
        if (sec < 90) return Math.round(sec) + "s ago"
        return Math.round(sec / 60) + "m ago"
    }

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader {
            Layout.fillWidth: true
            title: "Usage"
            subtitle: s.ok ? "Updated " + page.ago(s.age) : "Waiting for the first reading"
            Row {
                spacing: 10
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    text: s.st === "rejected" ? "Limit reached" : (s.st === "warning" || s.st === "allowed_warning") ? "Close to the limit" : s.ok ? "Within limits" : "No data"
                    tone: s.st === "rejected" ? "bad" : (s.st === "warning" || s.st === "allowed_warning") ? "accent" : s.ok ? "good" : "neutral"
                }
                Btn { text: "Refresh"; glyph: ""; onClicked: { bridge.refreshNow(); page.app.toast("Checking now", "info") } }
            }
        }

        // Problem banner: only when there is nothing to show
        Card {
            Layout.fillWidth: true
            visible: !s.ok && s.statusKey === "error"
            revealOn: page.active; order: 0
            RowLayout {
                width: parent.width; spacing: 14
                Icon { text: ""; tint: Theme.bad; size: 22 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: "Usage is not available"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; text: s.status; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                }
                Btn { text: "Set up Claude Code"; kind: "primary"; onClicked: page.app.go(3) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Card {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                revealOn: page.active; order: 1
                RowLayout {
                    width: parent.width; spacing: 22
                    Gauge { value: s.s; valid: s.ok; label: "5 hours" }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 14
                        Text { text: "Session"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        KV { Layout.fillWidth: true; label: "Resets in"; value: s.ok ? page.human(s.sr, s.age) : "--" }
                        KV { Layout.fillWidth: true; label: "Remaining"; value: s.ok ? (100 - s.s) + "% left" : "--" }
                    }
                }
            }
            Card {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                revealOn: page.active; order: 2
                RowLayout {
                    width: parent.width; spacing: 22
                    Gauge { value: s.w; valid: s.ok; label: "7 days" }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 14
                        Text { text: "Week"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        KV { Layout.fillWidth: true; label: "Resets in"; value: s.ok ? page.human(s.wr, s.age) : "--" }
                        KV { Layout.fillWidth: true; label: "Remaining"; value: s.ok ? (100 - s.w) + "% left" : "--" }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 3
            ColumnLayout {
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: s.transport === "push" ? "Sending to" : s.transport === "serve" ? "Serving to" : s.transport === "serial" ? "USB serial" : "Output"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Btn { text: "Manage"; kind: "ghost"; onClicked: page.app.go(1) }
                }

                Repeater {
                    model: s.transport === "push" ? s.devices : []
                    delegate: RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        Icon { text: ""; tint: Theme.textDim; size: 18 }
                        Text { text: modelData.host; color: Theme.text; font.family: Theme.mono; font.pixelSize: 13; Layout.fillWidth: true }
                        Text { visible: modelData.age >= 0; text: page.ago(modelData.age); color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
                        Chip {
                            text: modelData.ok === true ? "Receiving" : modelData.ok === false ? "Not answering" : "Waiting"
                            tone: modelData.ok === true ? "good" : modelData.ok === false ? "bad" : "neutral"
                        }
                    }
                }
                Text {
                    visible: s.transport === "push" && s.devices.length === 0
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: "No device address is set. Devices that advertise themselves on the network are found automatically, or add one on the Connection page."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: s.transport === "serve"
                    text: s.endpoint !== "" ? "Your device can read " + s.endpoint : "Starting the local server"
                    color: Theme.textDim; font.family: Theme.mono; font.pixelSize: 13
                }
                Text {
                    visible: s.transport === "serial"
                    text: s.port !== "" ? "Connected on " + s.port : "Looking for the device"
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
    }
}
