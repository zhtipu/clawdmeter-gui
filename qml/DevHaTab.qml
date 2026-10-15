import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    Connections {
        target: t.form
        function onResponded(tag, status, data) {
            if (tag !== "haclear") return
            if (status === 200) t.form.toast("Cleared " + data.cleared + " screen(s)" + (data.broker ? "" : ", device only, broker not connected"), "good")
            else t.form.toast("Could not clear the screens", "bad")
        }
    }

    DevCard {
        title: "MQTT"; tabActive: t.tabActive; index: 0
        DevField { form: t.form; path: "ha.brokerHost"; label: "Broker host"; placeholder: "broker.local or 192.168.1.10"; mono: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "number"; path: "ha.brokerPort"; label: "Port" }
            DevField { form: t.form; kind: "number"; path: "ha.dwellSec"; label: "Show each screen (s)" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; path: "ha.brokerUser"; label: "Username (optional)" }
            DevField { form: t.form; kind: "password"; path: "ha.brokerPass"; label: "Password (optional)"; placeholder: t.form.val("ha.passSet") ? "(unchanged)" : "(optional)" }
        }
        RowLayout {
            Btn { text: "Clear screens"
                onClicked: t.form.confirm("Clear all HA screens?", "This wipes every screen off the device and deletes the broker retained copies, so screens from a deleted automation stop coming back.", "Clear", true,
                    function () { t.form.call("haclear", "POST", "/api/ha/clear", "") }) }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.StyledText
            text: "Plain TCP, not TLS, so keep the broker on your LAN. Leave the host blank to switch the feature off. The device subscribes to <b>smalltv/&lt;hostname&gt;/screen/&lt;slot&gt;</b>: publish a screen there as <b>retained</b> JSON and it joins the on-screen rotation; an empty retained payload deletes it. Screens survive a reboot, and the broker retained copies repopulate them on reconnect. A blank password field keeps the stored one."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.StyledText
            text: "<b>Clear screens</b> only covers slots the device currently knows about. If the broker is unreachable the device side is still wiped."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
