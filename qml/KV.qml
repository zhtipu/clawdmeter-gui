import QtQuick

Column {
    property string label: ""
    property string value: ""
    property bool mono: false
    property color tint: Theme.text
    spacing: 3
    Text {
        text: parent.label.toUpperCase()
        color: Theme.textFaint
        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8
    }
    Text {
        width: parent.width
        text: parent.value
        color: parent.tint
        elide: parent.mono ? Text.ElideMiddle : Text.ElideRight
        font.family: parent.mono ? Theme.mono : Theme.font
        font.pixelSize: parent.mono ? 13 : 15
        font.weight: parent.mono ? Font.Normal : Font.Medium
    }
}
