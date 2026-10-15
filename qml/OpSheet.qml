import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Sheet {
    id: sheet
    panelWidth: 660
    dismissable: false

    property string title: ""
    property var steps: []          // [{ title, state }]  state: pending | run | ok | skip | fail
    property string logText: ""
    property real progress: -1      // -1 = indeterminate
    property string progressLabel: ""
    property bool finished: false
    property bool success: false
    property string message: ""
    property bool dry: false

    function begin(t, isDry) {
        title = t; steps = []; logText = ""; progress = -1; progressLabel = ""
        finished = false; success = false; message = ""; dry = isDry
        open = true
    }
    function handle(ev) {
        if (ev.type === "plan") {
            steps = ev.steps.map(function (s) { return { title: s, state: "pending" } })
        } else if (ev.type === "step") {
            var s = steps.slice()
            s[ev.i] = { title: s[ev.i].title, state: ev.state }
            steps = s
            if (ev.state === "ok" || ev.state === "skip") { progress = -1; progressLabel = "" }
        } else if (ev.type === "log") {
            logText += ev.text + "\n"
            Qt.callLater(function () { logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height) })
        } else if (ev.type === "progress") {
            progress = ev.value; progressLabel = ev.label
        } else if (ev.type === "done") {
            finished = true; success = ev.ok; message = ev.message
        }
    }

    ColumnLayout {
        width: parent.width; spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Text { text: sheet.title; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: 22; font.weight: Font.DemiBold; font.letterSpacing: -0.3; Layout.fillWidth: true }
            Chip { visible: sheet.dry; text: "Preview only"; tone: "accent" }
        }

        Column {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: sheet.steps
                delegate: Row {
                    spacing: 12
                    height: 24
                    Item {
                        width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent; radius: 11; color: "transparent"
                            border.width: 2; border.color: Theme.border
                            visible: modelData.state === "pending"
                        }
                        Spinner { anchors.centerIn: parent; size: 22; visible: modelData.state === "run" }
                        Rectangle {
                            id: okDot
                            anchors.fill: parent; radius: 11; color: Theme.good
                            visible: modelData.state === "ok"
                            scale: visible ? 1 : 0.5
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                            Icon { anchors.centerIn: parent; text: ""; size: 12; tint: "#08170F" }
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 11; color: Theme.surfaceHi
                            visible: modelData.state === "skip"
                            Rectangle { anchors.centerIn: parent; width: 9; height: 2; radius: 1; color: Theme.textFaint }
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 11; color: Theme.bad
                            visible: modelData.state === "fail"
                            Icon { anchors.centerIn: parent; text: ""; size: 11; tint: "#FFFFFF" }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title + (modelData.state === "skip" ? "  ·  skipped" : "")
                        color: modelData.state === "pending" || modelData.state === "skip" ? Theme.textFaint : Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: modelData.state === "run" ? Font.DemiBold : Font.Normal
                        Behavior on color { ColorAnimation { duration: Theme.base } }
                    }
                }
            }
        }

        Column {
            Layout.fillWidth: true; spacing: 6
            visible: !sheet.finished
            Rectangle {
                width: parent.width; height: 6; radius: 3; color: Theme.surfaceHi; clip: true
                Rectangle {
                    height: parent.height; radius: 3; color: Theme.accent
                    width: sheet.progress >= 0 ? parent.width * sheet.progress : parent.width * 0.3
                    x: 0
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    SequentialAnimation on x {
                        running: sheet.progress < 0 && sheet.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: -200; to: 660; duration: 1300; easing.type: Easing.InOutCubic }
                    }
                }
            }
            Text { text: sheet.progressLabel; visible: text !== ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 150
            radius: 12; color: Theme.dark ? "#0B0D11" : "#F4F5F8"; border.width: 1; border.color: Theme.border
            Flickable {
                id: logFlick
                anchors.fill: parent; anchors.margins: 12
                clip: true; contentHeight: logTxt.implicitHeight; contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                Text {
                    id: logTxt
                    width: parent.width - 10
                    text: sheet.logText; wrapMode: Text.WrapAnywhere
                    color: Theme.textDim; font.family: Theme.mono; font.pixelSize: 11
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Rectangle {
                visible: sheet.finished
                Layout.fillWidth: true; implicitHeight: 40; radius: 10
                color: sheet.success ? Theme.goodSoft : Theme.badSoft
                opacity: sheet.finished ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.base } }
                Row {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 12 }
                    spacing: 10
                    Icon { text: sheet.success ? "" : ""; tint: sheet.success ? Theme.good : Theme.bad; size: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: parent.width - 30; text: sheet.message; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Item { Layout.fillWidth: true; visible: !sheet.finished }
            Btn { text: "Close"; kind: sheet.finished ? "primary" : "secondary"; enabled: sheet.finished; onClicked: sheet.open = false }
        }
    }
}
