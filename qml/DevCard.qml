import QtQuick
import QtQuick.Layouts

// A titled settings card. Entrance replays whenever its tab becomes the visible one.
Card {
    id: c
    property string title: ""
    property bool tabActive: true
    property int index: 0
    default property alias body: col.data
    Layout.fillWidth: true
    revealOn: tabActive
    order: index

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12
        Text {
            visible: c.title !== ""
            text: c.title
            color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
        }
    }
}
