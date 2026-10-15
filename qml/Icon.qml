import QtQuick

// Lucide icon-font glyph: pass the character as text. Same bundled font on every platform.
Text {
    property color tint: Theme.text
    property int size: 18
    color: tint
    font.family: Theme.icons
    font.pixelSize: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
