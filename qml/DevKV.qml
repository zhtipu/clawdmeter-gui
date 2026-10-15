import QtQuick
import QtQuick.Layouts

// Label on the left, value on the right, hairline below. Same rhythm as the TV's own status list.
Item {
    id: r
    property string label: ""
    property string value: ""
    property color tint: Theme.text
    property bool last: false
    Layout.fillWidth: true
    implicitHeight: 38
    Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: r.label; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
    Text {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; left: parent.horizontalCenter; leftMargin: -60 }
        horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
        text: r.value; color: r.tint; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
    }
    Rectangle { visible: !r.last; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
}
