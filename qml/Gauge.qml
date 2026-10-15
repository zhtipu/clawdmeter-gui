import QtQuick

// Ring gauge. `value` is 0-100. The arc eases to new values, so a poll never makes the number jump.
Item {
    id: g
    property real value: 0
    property bool valid: true
    property string label: ""
    property color tint: value >= 85 ? Theme.bad : value >= 60 ? Theme.accent : Theme.good
    property real shown: 0
    implicitWidth: 168; implicitHeight: 168
    width: implicitWidth; height: implicitHeight

    Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    Behavior on tint { ColorAnimation { duration: Theme.base } }
    onValueChanged: shown = valid ? value : 0
    onValidChanged: shown = valid ? value : 0
    onShownChanged: cv.requestPaint()
    onTintChanged: cv.requestPaint()
    Component.onCompleted: shown = valid ? value : 0
    Connections { target: Theme; function onDarkChanged() { cv.requestPaint() } }

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var lw = 14, r = (width - lw) / 2, cx = width / 2, cy = height / 2
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.strokeStyle = Theme.dark ? "#262C38" : "#E3E6ED"
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
            if (g.shown > 0.4) {
                ctx.strokeStyle = g.tint.toString()
                ctx.beginPath()
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(g.shown, 100) / 100)
                ctx.stroke()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: g.valid ? Math.round(g.shown) + "%" : "--"
            color: g.valid ? Theme.text : Theme.textFaint
            font.family: Theme.fontDisplay; font.pixelSize: 38; font.weight: Font.DemiBold; font.letterSpacing: -1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: g.label.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8
        }
    }
}
