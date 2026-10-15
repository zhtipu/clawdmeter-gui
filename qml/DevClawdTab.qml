import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    DevCard {
        title: "Claude usage"; tabActive: t.tabActive; index: 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: note.implicitHeight + 24
            radius: Theme.radiusSm
            color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
            Text {
                id: note
                anchors { left: parent.left; right: parent.right; margins: 12; verticalCenter: parent.verticalCenter }
                wrapMode: Text.WordWrap; textFormat: Text.StyledText
                text: "<b>This app is the companion program.</b> The device cannot read your Claude usage on its own, so Clawdmeter reads it on this computer and sends it here. Leave the Usage daemon URL blank to have it pushed to the device (set the address on the Connection page)."
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15
            }
        }
        DevField { form: t.form; kind: "url"; path: "usage.usageUrl"; label: "Usage daemon URL"; placeholder: "http://192.168.1.10:8787/" }
        DevField { form: t.form; kind: "number"; path: "usage.pollSec"; label: "Refresh data (s)"
            hint: "<b>Pull:</b> set the Usage URL to a daemon the device can reach. <b>Push:</b> leave it blank and let this app send the numbers (for networks where the device cannot reach the computer). Running several SmallTVs? Give each a unique hostname in the WiFi tab so every computer pushes to its own device." }
    }
}
