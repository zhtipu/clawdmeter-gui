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

    readonly property var modes: ["push", "serve", "serial"]
    property int mode: 0
    property bool discover: true
    property var test: null
    property bool testing: false

    function load() {
        var c = JSON.parse(bridge.deviceConfig())
        mode = Math.max(0, modes.indexOf(c.transport))
        hosts.text = c.hosts
        discover = c.discover
        interval.text = String(c.pushInterval)
        servePort.text = String(c.servePort)
        serialPort.text = c.serialPort
        test = null
    }
    onActiveChanged: if (active) load()
    Component.onCompleted: load()

    Connections {
        target: bridge
        function onTestResult(j) { page.testing = false; page.test = JSON.parse(j) }
    }

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader {
            Layout.fillWidth: true
            title: "Connection"
            subtitle: "Where this computer sends your usage"
            Btn {
                text: "Save and apply"; kind: "primary"; glyph: ""
                onClicked: {
                    bridge.applyDevice(JSON.stringify({
                        transport: page.modes[page.mode], hosts: hosts.text, discover: page.discover,
                        pushInterval: parseInt(interval.text) || 20, servePort: parseInt(servePort.text) || 8787,
                        serialPort: serialPort.text }))
                    page.app.toast("Applied", "good")
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 0
            ColumnLayout {
                width: parent.width; spacing: 14
                Text { text: "How to send"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                UTabs {
                    Layout.fillWidth: true
                    model: ["Push over WiFi", "Serve to device", "USB serial"]
                    currentIndex: page.mode
                    onSelected: function (i) { page.mode = i }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                    text: page.mode === 0 ? "This computer sends the numbers to your SmallTV. Works even when the TV cannot reach your computer."
                        : page.mode === 1 ? "The TV asks this computer for the numbers. Set the TV's Usage daemon URL to this computer's address."
                        : "For the USB Clawdmeter device. The COM port is found automatically."
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: page.mode === 0
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 12
                Text { text: "TV address"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text { text: "An IP address or name. Separate several TVs with commas."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Field { id: hosts; Layout.fillWidth: true; mono: true; placeholderText: "192.168.1.48" }
                    Btn {
                        text: "Test"; busy: page.testing; glyph: ""
                        onClicked: {
                            page.test = null; page.testing = true
                            bridge.testDevice(hosts.text.split(",")[0])
                        }
                    }
                }
                RowLayout {
                    visible: page.test !== null
                    spacing: 8
                    Chip { text: page.test && page.test.ok ? "Reachable" : "Unreachable"; tone: page.test && page.test.ok ? "good" : "bad"; glyph: page.test && page.test.ok ? "" : "" }
                    Text { text: page.test ? page.test.detail : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 4; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Find TVs automatically"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Looks for TVs on this network that advertise themselves. Does not cross routers."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: page.discover; controlled: true; onToggled: function (v) { page.discover = v } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Send every"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Seconds between updates. 5 or more."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Field { id: interval; Layout.preferredWidth: 90; mono: true; inputMethodHints: Qt.ImhDigitsOnly; maximumLength: 3; horizontalAlignment: TextInput.AlignHCenter }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: page.mode === 1
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 12
                Text { text: "Local server"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Port"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Your system may ask to allow this port through the firewall."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Field { id: servePort; Layout.preferredWidth: 100; mono: true; inputMethodHints: Qt.ImhDigitsOnly; maximumLength: 5; horizontalAlignment: TextInput.AlignHCenter }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: page.mode === 2
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 12
                Text { text: "USB device"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text { text: "Leave empty to find the device automatically."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                Field { id: serialPort; Layout.preferredWidth: 160; mono: true; placeholderText: "COM5" }
            }
        }
    }
}
