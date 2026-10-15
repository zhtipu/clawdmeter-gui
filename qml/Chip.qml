import QtQuick

// tone: neutral | good | bad | info | accent
Rectangle {
    id: chip
    property string text: ""
    property string tone: "neutral"
    property string glyph: ""
    implicitHeight: 24
    implicitWidth: row.implicitWidth + 18
    radius: height / 2
    color: tone === "good" ? Theme.goodSoft : tone === "bad" ? Theme.badSoft : tone === "info" ? Theme.infoSoft
         : tone === "accent" ? Theme.accentSoft : Theme.surfaceHi
    readonly property color ink: tone === "good" ? Theme.good : tone === "bad" ? Theme.bad : tone === "info" ? Theme.info
         : tone === "accent" ? Theme.accent : Theme.textDim
    Behavior on color { ColorAnimation { duration: Theme.base } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon { visible: chip.glyph !== ""; text: chip.glyph; tint: chip.ink; size: 12; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: chip.text; color: chip.ink
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
