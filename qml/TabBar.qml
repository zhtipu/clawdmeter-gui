import QtQuick

// Underline tabs: one row, a hairline under it, and an accent bar that glides to the selected tab.
// Scrolls sideways when the window is too narrow and keeps the selected tab in view.
//   TabBar { model: ["General", "Input", "Network"]; currentIndex: page.tab; onSelected: function (i) { page.tab = i } }
// Optional `dividerBefore` draws a thin separator before one tab to group the tabs after it.
Item {
    id: bar
    property var model: []
    property int currentIndex: 0
    property int dividerBefore: -1
    signal selected(int index)
    implicitHeight: 46

    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: row.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row
            height: parent.height
            Repeater {
                id: rep
                model: bar.model.length
                delegate: Item {
                    readonly property bool sel: bar.currentIndex === index
                    readonly property bool divider: index === bar.dividerBefore
                    height: row.height
                    width: label.implicitWidth + 26 + (divider ? 17 : 0)
                    Rectangle { visible: parent.divider; x: 8; width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: Theme.borderHi }
                    Text {
                        id: label
                        x: parent.divider ? 30 : 13
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: bar.model[index]
                        color: parent.sel || hh.hovered ? Theme.text : Theme.textDim
                        font.family: Theme.font; font.pixelSize: 14; font.weight: parent.sel ? Font.DemiBold : Font.Medium
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: bar.selected(index) }
                }
            }
        }

        Rectangle {
            readonly property Item cur: { var n = rep.count; return rep.itemAt(bar.currentIndex) }
            height: 3; radius: 2; color: Theme.accent
            anchors.bottom: parent.bottom
            x: cur ? cur.x + (cur.divider ? 17 : 0) + 7 : 0
            width: cur ? cur.width - (cur.divider ? 17 : 0) - 14 : 0
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
    }

    onCurrentIndexChanged: {
        var it = rep.itemAt(currentIndex)
        if (!it) return
        if (it.x < flick.contentX) flick.contentX = Math.max(0, it.x - 8)
        else if (it.x + it.width > flick.contentX + flick.width) flick.contentX = Math.min(flick.contentWidth - flick.width, it.x + it.width - flick.width + 8)
    }
}
