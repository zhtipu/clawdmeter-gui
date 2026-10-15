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

    property bool on: false
    property bool viaServe: false
    property string error: ""
    property var urls: []
    property var phones: []

    function load() {
        var c = JSON.parse(bridge.phoneConfig())
        on = c.on; viaServe = c.viaServe
        port.text = String(c.port)
        urls = JSON.parse(bridge.localUrls())
        error = ""
    }
    function apply(v) {
        var p = parseInt(port.text)
        page.error = bridge.setPhone(v, isNaN(p) ? 8787 : p)
        load()
    }
    onActiveChanged: if (active) load()
    Component.onCompleted: load()

    Timer {
        interval: 3000; repeat: true; running: page.active; triggeredOnStart: true
        onTriggered: page.phones = JSON.parse(bridge.phones())
    }

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader { Layout.fillWidth: true; title: "Phone app"; subtitle: "Let the Clawdmeter phone app read your usage from this computer" }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 0
            ColumnLayout {
                width: parent.width; spacing: 14
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Allow the phone app"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: page.viaServe ? "On, because this computer is set to Serve to device on the Connection page."
                                : page.on ? "On. The phone can read the numbers from the addresses below."
                                : "Off. Turn it on, then type one of the addresses below into the phone app."
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Toggle { checked: page.on; controlled: true; enabled: !page.viaServe; onToggled: function (v) { page.apply(v) } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Port"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Your system may ask to allow this port through the firewall."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Field { id: port; Layout.preferredWidth: 100; mono: true; inputMethodHints: Qt.ImhDigitsOnly; maximumLength: 5; horizontalAlignment: TextInput.AlignHCenter; enabled: !page.viaServe; onEditingFinished: if (page.on) page.apply(true) }
                }
                Text { visible: page.error !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: page.error; color: Theme.bad; font.family: Theme.font; font.pixelSize: 13 }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: page.on
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 10
                Text { text: "Address for the phone app"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Copy one into the phone app, or let the phone find this computer. Pick the one that starts like your phone's own address."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                Repeater {
                    model: page.urls
                    delegate: RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Text { Layout.fillWidth: true; text: modelData.replace("http://", "").replace(/\/$/, ""); color: Theme.accent; font.family: Theme.mono; font.pixelSize: 16; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Btn { text: "Copy"; glyph: ""; onClicked: bridge.copyText(modelData.replace("http://", "").replace(/\/$/, "")) }
                    }
                }
                Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "The phone app can also find this computer by itself: open it, go to Connection and tap Find computers."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Text { visible: page.urls.length === 0; text: "No network address found. Connect this computer to Wi-Fi or Ethernet."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 2
            ColumnLayout {
                width: parent.width; spacing: 12
                Text { text: "Phones"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text {
                    visible: page.phones.length === 0; Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: page.on ? "No phone has connected yet." : "Turn the phone app on to see phones here."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: page.phones
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: phoneCol.implicitHeight + 28
                        radius: 14; color: Theme.surfaceHi; border.width: 1; border.color: Theme.border
                        ColumnLayout {
                            id: phoneCol
                            x: 16; y: 14; width: parent.width - 32; spacing: 10
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text {
                                        text: modelData.ip + "  -  " + (modelData.state === "gone" ? "last seen " + Math.round(modelData.age / 60) + " min ago" : "updated " + modelData.age + " s ago")
                                        color: Theme.textDim; font.family: Theme.mono; font.pixelSize: 12
                                    }
                                }
                                Item { Layout.fillWidth: true; height: 1 }
                                Chip { text: ({wifi: "Wi-Fi", bluetooth: "Bluetooth", ethernet: "Ethernet", cellular: "Mobile data", network: "Network"})[modelData.link] || "Network"; tone: "info" }
                                Chip { text: modelData.state === "connected" ? "Connected" : (modelData.state === "idle" ? "Idle" : "Gone"); tone: modelData.state === "connected" ? "good" : (modelData.state === "idle" ? "accent" : "bad") }
                            }
                            Repeater {
                                model: modelData.tvs
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 40; radius: 10; color: Theme.surface; border.width: 1; border.color: Theme.border
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                                        spacing: 10
                                        Icon { text: ""; size: 15; tint: Theme.textDim }
                                        Text { Layout.fillWidth: true; text: modelData.host; color: Theme.text; font.family: Theme.mono; font.pixelSize: 13; elide: Text.ElideRight }
                                        Chip {
                                            text: ({ok: "Phone is sending", fail: "Phone cannot reach it", taken: "Phone failed, this computer sends", other: "Another phone sends", pending: "Waiting for the phone"})[modelData.state] || ""
                                            tone: modelData.state === "ok" ? "good" : (modelData.state === "fail" || modelData.state === "taken" ? "bad" : "neutral")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: "The phone app only ever receives the usage numbers. It never gets your Claude login."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }
}
