import QtQuick
import QtQuick.Controls.Basic

// model: list of { label, value }. currentValue is the selected entry's value.
Item {
    id: c
    property var model: []
    property int currentIndex: 0
    readonly property var currentValue: model.length > currentIndex && currentIndex >= 0 ? model[currentIndex].value : undefined
    readonly property string currentLabel: model.length > currentIndex && currentIndex >= 0 ? model[currentIndex].label : ""
    property bool controlled: false   // true: the parent owns currentIndex (e.g. a binding)
    signal activated(int index)
    implicitHeight: 40; implicitWidth: 220

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.dark ? "#10131A" : "#F6F7FA"
        border.width: pop.visible ? 2 : 1
        border.color: pop.visible ? Theme.accent : (hh.hovered ? Theme.borderHi : Theme.border)
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
        Text {
            anchors { left: parent.left; right: chev.left; leftMargin: 12; rightMargin: 6; verticalCenter: parent.verticalCenter }
            text: c.currentLabel; elide: Text.ElideRight
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14
        }
        Icon {
            id: chev
            text: ""; tint: Theme.textDim; size: 12
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            rotation: pop.visible ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.base; easing.type: Easing.OutCubic } }
        }
        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pop.visible ? pop.close() : pop.open() }
    }

    Popup {
        id: pop
        y: c.height + 6
        width: c.width
        padding: 6
        height: Math.min(list.contentHeight + 12, 300)
        transformOrigin: Item.Top
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 150; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 100 }
        }
        background: Rectangle {
            radius: Theme.radiusSm; color: Theme.surface
            border.width: 1; border.color: Theme.borderHi
        }
        contentItem: ListView {
            id: list
            clip: true
            model: c.model
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                width: list.width; height: 36; radius: 7
                color: ma.containsMouse ? Theme.surfaceHi : "transparent"
                Text {
                    anchors { left: parent.left; right: tick.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: modelData.label; elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                }
                Icon {
                    id: tick; visible: index === c.currentIndex
                    text: ""; tint: Theme.accent; size: 14
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (!c.controlled) c.currentIndex = index; c.activated(index); pop.close() }
                }
            }
        }
    }
}
