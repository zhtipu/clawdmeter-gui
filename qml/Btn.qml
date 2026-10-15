import QtQuick
import QtQuick.Controls.Basic

// kind: primary | secondary | danger | ghost
Button {
    id: btn
    property string kind: "secondary"
    property string glyph: ""
    property bool busy: false
    implicitHeight: 38
    implicitWidth: row.implicitWidth + 32
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    opacity: enabled ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    readonly property color fill: {
        if (kind === "primary") return down ? Qt.darker(Theme.accent, 1.1) : hovered ? Theme.accentHi : Theme.accent
        if (kind === "danger") return down ? Qt.darker(Theme.bad, 1.15) : hovered ? Qt.lighter(Theme.bad, 1.08) : Theme.bad
        if (kind === "ghost") return hovered ? Theme.surfaceHi : "transparent"
        return hovered ? Theme.surfaceHi : Theme.surface
    }
    readonly property color ink: kind === "primary" ? Theme.accentInk : kind === "danger" ? "#FFFFFF" : Theme.text

    // Pressed state responds on press, not release.
    scale: down ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    background: Rectangle {
        radius: Theme.radiusSm
        color: btn.fill
        border.width: btn.kind === "secondary" ? 1 : 0
        border.color: btn.hovered ? Theme.borderHi : Theme.border
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    leftPadding: 16; rightPadding: 16
    contentItem: Item {
      implicitWidth: row.implicitWidth
      implicitHeight: row.implicitHeight
      Row {
        id: row
        spacing: 8
        anchors.centerIn: parent
        Icon {
            visible: btn.glyph !== "" && !btn.busy
            text: btn.glyph; tint: btn.ink; size: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Spinner {
            visible: btn.busy
            size: 16; tint: btn.ink
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: btn.text
            color: btn.ink
            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
