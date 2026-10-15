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

    property var acc: ({ login: false, token: false, connected: false, status: "" })
    property bool revealed: false
    property string fullToken: ""
    property string maskedToken: ""
    function load() { acc = JSON.parse(bridge.tokenStatus()); maskedToken = bridge.maskedToken() }
    function toggleReveal() {
        if (revealed) { revealed = false; fullToken = ""; return }
        fullToken = bridge.revealToken(); revealed = true; hideTimer.restart()
    }
    onActiveChanged: { if (active) load(); else { revealed = false; fullToken = "" } }
    Timer { id: hideTimer; interval: 15000; onTriggered: { page.revealed = false; page.fullToken = "" } }
    Component.onCompleted: load()
    Timer { interval: 2000; running: page.active; repeat: true; onTriggered: page.load() }

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader {
            Layout.fillWidth: true
            title: "Account"
            subtitle: "How Clawdmeter reads your Claude usage"
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 0
            RowLayout {
                width: parent.width; spacing: 14
                Icon {
                    text: page.acc.connected ? "" : ""
                    tint: page.acc.connected ? Theme.good : Theme.accent
                    size: 22
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text {
                        text: page.acc.connected ? "Connected to Claude" : page.acc.login ? "Signed in, waiting for a reading" : "Not connected"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                        text: page.acc.connected ? "Usage is being read every minute."
                            : page.acc.status !== "" ? page.acc.status : "Sign in below to start."
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 14
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Sign in with Claude Code"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Opens a terminal that runs claude auth login. Finish signing in in your browser, then come back. Clawdmeter keeps the sign-in fresh by itself."
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Btn { text: page.acc.login ? "Sign in again" : "Sign in"; kind: page.acc.login ? "secondary" : "primary"; glyph: ""; onClicked: bridge.signIn() }
                }
                RowLayout {
                    visible: page.acc.login
                    spacing: 8
                    Chip { text: "Signed in"; tone: "good"; glyph: "" }
                    Text { text: "Found a Claude Code sign-in on this computer."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 2
            ColumnLayout {
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Paste a token instead"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Clawdmeter checks the token with Anthropic before saving it. Tokens made by claude setup-token are refused for usage readings, so use Sign in for those."
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Btn {
                        visible: page.acc.token
                        text: "Remove saved"; kind: "ghost"
                        onClicked: page.app.confirm("Remove the saved token?", "Clawdmeter will stop using it. Your Claude account is not affected.", "Remove", true,
                            function () { bridge.clearToken(); page.load(); page.app.toast("Token removed", "info") })
                    }
                }
                RowLayout {
                    visible: page.acc.token
                    Layout.fillWidth: true; spacing: 10
                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: Theme.radiusSm
                        color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
                        Text {
                            anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: page.revealed ? page.fullToken : page.maskedToken
                            elide: Text.ElideMiddle
                            color: page.revealed ? Theme.text : Theme.textDim
                            font.family: Theme.mono; font.pixelSize: 13
                        }
                    }
                    Btn {
                        text: page.revealed ? "Hide" : "Reveal"; glyph: page.revealed ? "" : ""
                        onClicked: page.toggleReveal()
                    }
                    Btn { text: "Copy"; glyph: ""; onClicked: bridge.copyText("") }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Field { id: tokenField; Layout.fillWidth: true; mono: true; echoMode: showTyped.shown ? TextInput.Normal : TextInput.Password; placeholderText: "Paste token" }
                    Btn {
                        id: showTyped
                        property bool shown: false
                        text: ""; glyph: shown ? "" : ""; kind: "ghost"
                        implicitWidth: 44
                        onClicked: shown = !shown
                    }
                    Btn {
                        text: "Check and save"; kind: "primary"; glyph: ""
                        enabled: tokenField.text.length > 0
                        onClicked: {
                            if (bridge.saveToken(tokenField.text)) {
                                tokenField.text = ""
                                page.load()
                                page.app.toast("Token saved", "good")
                            }
                        }
                    }
                }
                RowLayout {
                    visible: page.acc.token
                    spacing: 8
                    Chip { text: "Token saved"; tone: "good"; glyph: "" }
                    Text { text: page.acc.connected ? "It is working." : "Saved on this computer. A sign-in is used first if you have one."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
                Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Stored in " + bridge.tokenStoreName + " on this computer. It is only ever sent to Anthropic."; color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
    }
}
