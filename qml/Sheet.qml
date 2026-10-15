import QtQuick

// Modal sheet: dims the window, then the panel scales up from 0.96 with a fade. Never from zero.
Item {
    id: sheet
    property bool open: false
    property int panelWidth: 560
    property bool dismissable: true
    property int panelHeight: 0   // 0 = size to content
    default property alias content: holder.data
    signal dismissed()

    anchors.fill: parent
    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: open ? 200 : 140; easing.type: Easing.OutCubic } }
    z: 50

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#B0000000" : "#80101420"
        MouseArea {
            anchors.fill: parent
            onClicked: if (sheet.dismissable) { sheet.open = false; sheet.dismissed() }
            onWheel: function (w) { w.accepted = true }   // never scroll the page behind the dialog
        }
    }

    Rectangle {
        id: panel
        width: Math.min(sheet.panelWidth, sheet.width - 48)
        height: Math.min(sheet.panelHeight > 0 ? sheet.panelHeight : holder.childrenRect.height + 48, sheet.height - 48)
        anchors.centerIn: parent
        radius: 20
        color: Theme.surface
        border.width: 1; border.color: Theme.borderHi
        scale: sheet.open ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onWheel: function (w) { w.accepted = true } }   // swallow clicks and wheel so nothing behind reacts
        Item {
            id: holder
            x: 24; y: 24
            width: panel.width - 48
            height: panel.height - 48
        }
    }
}
