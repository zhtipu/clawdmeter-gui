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

    property var cc: ({ found: false, path: "", signedIn: null, method: "", connected: false, status: "" })
    function load() { cc = JSON.parse(bridge.claudeStatus()) }
    onActiveChanged: if (active) load()
    Component.onCompleted: load()
    Timer { interval: 2000; running: page.active; repeat: true; onTriggered: page.load() }

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader {
            Layout.fillWidth: true
            title: "Claude Code"
            subtitle: "Where your usage numbers come from"
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 0
            ColumnLayout {
                width: parent.width; spacing: 12
                RowLayout {
                    width: parent.width; spacing: 14
                    Icon {
                        text: page.cc.connected ? "" : ""
                        tint: page.cc.connected ? Theme.good : Theme.accent
                        size: 22
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text {
                            text: page.cc.connected ? "Reading your usage" : !page.cc.found ? "Claude Code not found" : page.cc.signedIn === false ? "Not signed in" : "Waiting for a reading"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                            text: page.cc.connected ? "Each reading is taken by Claude Code itself."
                                : page.cc.status !== "" ? page.cc.status : "Checking Claude Code..."
                        }
                    }
                }
                RowLayout {
                    spacing: 8
                    Chip { text: page.cc.found ? "Installed" : "Not installed"; tone: page.cc.found ? "good" : "bad"; glyph: page.cc.found ? "" : "" }
                    Chip { visible: page.cc.found; text: page.cc.signedIn === true ? "Signed in" : page.cc.signedIn === false ? "Signed out" : "Unknown"
                           tone: page.cc.signedIn === true ? "good" : page.cc.signedIn === false ? "bad" : "neutral" }
                }
                Text {
                    visible: page.cc.found
                    Layout.fillWidth: true; elide: Text.ElideMiddle
                    text: page.cc.path; color: Theme.textFaint; font.family: Theme.mono; font.pixelSize: 11
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: page.cc.signedIn === true ? "Sign in again" : "Sign in to Claude Code"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Opens a terminal that runs Claude Code's own login. Finish signing in in your browser, then come back."
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Btn { text: page.cc.signedIn === true ? "Sign in again" : "Sign in"; kind: page.cc.signedIn === true ? "secondary" : "primary"; glyph: ""; enabled: page.cc.found; onClicked: bridge.signIn() }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 2
            ColumnLayout {
                width: parent.width; spacing: 10
                Text { text: "How this works"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; lineHeight: 1.2
                    text: "Clawdmeter runs the official Claude Code program with its usage command, and reads the two limit lines it prints. That is all it does."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; lineHeight: 1.2
                    text: "Clawdmeter never opens, copies or stores your Claude login or any token, and it does not talk to Anthropic itself. Signing in always happens inside Claude Code."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; lineHeight: 1.2
                    text: "Each reading starts Claude Code for a few seconds, so readings are a few minutes apart. You can change that in Settings."
                    color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }
}
