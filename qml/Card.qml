import QtQuick

// Surface with a staggered entrance. Set revealOn to the page's active state so cards
// re-enter every time the page is shown.
Rectangle {
    id: card
    property bool revealOn: true
    property int order: 0
    property bool hoverable: false
    property alias hovered: hover.hovered
    default property alias content: holder.data
    property int pad: 20

    implicitHeight: holder.childrenRect.height + pad * 2
    radius: Theme.radius
    color: hoverable && hover.hovered ? Theme.surfaceHi : Theme.surface
    border.width: 1
    border.color: hoverable && hover.hovered ? Theme.borderHi : Theme.border
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

    opacity: 0
    transform: Translate { id: lift; y: 14 }

    HoverHandler { id: hover; enabled: card.hoverable }

    Item {
        id: holder
        x: card.pad; y: card.pad
        width: card.width - card.pad * 2
        height: childrenRect.height
    }

    ParallelAnimation {
        id: enter
        PauseAnimation { duration: card.order * 45 }
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: Theme.slow; easing.type: Easing.OutCubic }
        }
    }

    function replay() {
        enter.stop()
        card.opacity = 0
        lift.y = 14
        enter.start()
    }

    onRevealOnChanged: {
        if (revealOn) replay()
        else { enter.stop(); card.opacity = 0; lift.y = 14 }
    }
    Component.onCompleted: if (revealOn) replay()
}
