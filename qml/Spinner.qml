import QtQuick

Item {
    id: sp
    property int size: 20
    property color tint: Theme.accent
    property real thickness: 2.2
    width: size; height: size

    Canvas {
        id: c
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = sp.thickness
            ctx.lineCap = "round"
            ctx.strokeStyle = sp.tint
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2 - sp.thickness, 0, Math.PI * 1.5)
            ctx.stroke()
        }
        Connections { target: sp; function onTintChanged() { c.requestPaint() } }
        RotationAnimator on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: sp.visible }
    }
}
