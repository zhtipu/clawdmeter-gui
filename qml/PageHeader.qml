import QtQuick

Item {
    id: h
    property string title: ""
    property string subtitle: ""
    default property alias actions: actionRow.data
    height: 64

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            text: h.title
            color: Theme.text
            font.family: Theme.fontDisplay; font.pixelSize: 28; font.weight: Font.DemiBold
            font.letterSpacing: -0.5   // large type tracks tighter
        }
        Text {
            visible: h.subtitle !== ""
            text: h.subtitle
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14
        }
    }
    Row {
        id: actionRow
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 10
    }
}
