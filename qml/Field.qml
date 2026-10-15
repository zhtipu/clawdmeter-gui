import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: f
    property bool mono: false
    property bool invalid: false
    implicitHeight: 40
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentInk
    font.family: mono ? Theme.mono : Theme.font
    font.pixelSize: 14
    leftPadding: 12; rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radiusSm
        color: Theme.dark ? "#10131A" : "#F6F7FA"
        border.width: f.activeFocus ? 2 : 1
        border.color: f.invalid ? Theme.bad : f.activeFocus ? Theme.accent : (f.hovered ? Theme.borderHi : Theme.border)
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    }
}
