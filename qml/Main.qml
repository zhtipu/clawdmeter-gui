import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Shell: sidebar with a spring selection indicator, cross-fading pages, shared overlay for sheets, one toast.
ApplicationWindow {
    id: root
    width: 1100; height: 740
    minimumWidth: 940; minimumHeight: 640
    visible: false
    title: "Clawdmeter"
    color: Theme.bg

    signal quitRequested()

    property int cur: typeof startPage !== "undefined" ? startPage : 0
    property var snap: ({ ok: false, s: 0, w: 0, sr: 0, wr: 0, st: "", status: "Starting...", statusKey: "searching", age: -1, transport: "", devices: [], endpoint: "", port: "" })
    readonly property Item overlayRoot: overlay

    function go(i) { cur = i }
    function toast(msg, kind) { toaster.show(msg, kind || "info") }
    function confirm(title, msg, label, danger, cb) { confirmSheet.ask(title, msg, label, danger, cb) }
    function refreshSnap() { root.snap = JSON.parse(bridge.snapshot()) }

    onClosing: function (close) {
        if (bridge.closeToTray && !bridge.quitting) { close.accepted = false; root.hide() }
        else root.quitRequested()
    }

    Shortcut { sequences: [StandardKey.Quit]; onActivated: root.quitRequested() }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshSnap() }
    Connections { target: bridge; function onToast(m, k) { root.toast(m, k) } }

    Row {
        anchors.fill: parent

        Rectangle {
            id: side
            width: 232; height: parent.height
            color: Theme.sidebar
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

            Row {
                x: 22; y: 26; spacing: 10
                Rectangle {
                    width: 28; height: 28; radius: 14; color: "transparent"; border.width: 4; border.color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text { text: "Clawdmeter"; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: 19; font.weight: Font.DemiBold; font.letterSpacing: -0.3; anchors.verticalCenter: parent.verticalCenter }
            }

            Item {
                id: nav
                x: 12; y: 92; width: parent.width - 24; height: model.length * 48
                readonly property var model: [
                    { t: "Usage", g: "" },
                    { t: "Connection", g: "" },
                    { t: "Device Setup", g: "" },
                    { t: "Claude Code", g: "" },
                    { t: "Settings", g: "" }
                ]

                Rectangle {
                    width: parent.width; height: 42; radius: 11
                    y: root.cur * 48 + 3
                    color: Theme.accentSoft; border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                    Behavior on y { SpringAnimation { spring: 4.2; damping: 0.38; mass: 0.7 } }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 3; height: 18; radius: 2; color: Theme.accent }
                }
                Repeater {
                    model: nav.model
                    delegate: Item {
                        y: index * 48; width: nav.width; height: 48
                        Row {
                            x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                            Icon { text: modelData.g; size: 17; tint: root.cur === index ? Theme.accent : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: modelData.t
                                color: root.cur === index || hh.hovered ? Theme.text : Theme.textDim
                                font.family: Theme.font; font.pixelSize: 14; font.weight: root.cur === index ? Font.DemiBold : Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                        }
                        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.cur = index }
                    }
                }
            }

            // Live status footer
            Row {
                x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 24; spacing: 9
                Rectangle {
                    id: dot
                    width: 9; height: 9; radius: 5; anchors.verticalCenter: parent.verticalCenter
                    color: root.snap.statusKey === "ok" ? Theme.good : root.snap.statusKey === "error" ? Theme.bad : Theme.accent
                    Behavior on color { ColorAnimation { duration: Theme.base } }
                    SequentialAnimation on opacity {
                        running: root.snap.statusKey === "searching" && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                Text { text: root.snap.status; width: 170; elide: Text.ElideRight; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        Item {
            width: parent.width - side.width; height: parent.height

            UsagePage { app: root; anchors.fill: parent; active: root.cur === 0; opacity: active ? 1 : 0; visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
            DevicePage { app: root; anchors.fill: parent; active: root.cur === 1; opacity: active ? 1 : 0; visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
            DeviceSetupPage { app: root; anchors.fill: parent; active: root.cur === 2; opacity: active ? 1 : 0; visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
            AccountPage { app: root; anchors.fill: parent; active: root.cur === 3; opacity: active ? 1 : 0; visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
            SettingsPage { app: root; anchors.fill: parent; active: root.cur === 4; opacity: active ? 1 : 0; visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
        }
    }

    Item { id: overlay; anchors.fill: parent; z: 40 }
    ConfirmSheet { id: confirmSheet; parent: overlay }

    Rectangle {
        id: toaster
        property string kind: "info"
        property string msg: ""
        property bool shown: false
        function show(m, k) { msg = m; kind = k; hide.restart(); shown = true }
        z: 100
        anchors.horizontalCenter: parent.horizontalCenter
        y: shown ? parent.height - height - 28 : parent.height + 8
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        height: 44; width: toastRow.implicitWidth + 36; radius: 22
        color: Theme.dark ? "#262C38" : "#1A1D24"; border.width: 1; border.color: Theme.borderHi
        Row {
            id: toastRow; anchors.centerIn: parent; spacing: 10
            Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: toaster.kind === "good" ? Theme.good : toaster.kind === "bad" ? Theme.bad : Theme.info }
            Text { text: toaster.msg; color: "#F2F4F8"; font.family: Theme.font; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
        }
        Timer { id: hide; interval: 3000; onTriggered: toaster.shown = false }
    }
}
