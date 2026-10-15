import QtQuick

Item {
    id: t
    property bool checked: false
    property bool controlled: false   // true: the parent owns `checked` (e.g. a binding)
    signal toggled(bool value)
    implicitWidth: 44; implicitHeight: 26
    width: implicitWidth; height: implicitHeight

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: t.checked ? Theme.accent : (Theme.dark ? "#2B3240" : "#CED3DD")
        Behavior on color { ColorAnimation { duration: Theme.base } }
    }
    Rectangle {
        id: knob
        width: ma.pressed ? 26 : 20; height: 20; radius: 10
        y: 3
        x: t.checked ? t.width - width - 3 : 3
        color: "#FFFFFF"
        // Springs keep the knob interruptible if it is clicked again mid-travel.
        Behavior on x { SpringAnimation { spring: 4.5; damping: 0.34; mass: 0.8 } }
        Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { var v = !t.checked; if (!t.controlled) t.checked = v; t.toggled(v) }
    }
}
