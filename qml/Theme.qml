pragma Singleton
import QtQuick

QtObject {
    readonly property bool dark: Qt.styleHints.colorScheme !== Qt.ColorScheme.Light

    readonly property color bg: dark ? "#0E1014" : "#F4F5F8"
    readonly property color sidebar: dark ? "#12151B" : "#EBEDF2"
    readonly property color surface: dark ? "#171B22" : "#FFFFFF"
    readonly property color surfaceHi: dark ? "#1F242D" : "#F6F7FA"
    readonly property color border: dark ? "#272D38" : "#E1E4EA"
    readonly property color borderHi: dark ? "#3A4252" : "#CBD0DA"
    readonly property color text: dark ? "#EEF0F5" : "#14171D"
    readonly property color textDim: dark ? "#98A1B1" : "#5C6573"
    readonly property color textFaint: dark ? "#667085" : "#8A93A2"

    readonly property color accent: "#F5A524"
    readonly property color accentHi: "#FFB93E"
    readonly property color accentInk: "#201400"
    readonly property color accentSoft: dark ? "#2A2113" : "#FFF4DD"
    readonly property color good: "#34C77B"
    readonly property color goodSoft: dark ? "#14281D" : "#E3F7EC"
    readonly property color bad: "#F2566F"
    readonly property color badSoft: dark ? "#2C161B" : "#FDE7EB"
    readonly property color info: "#5B8DEF"
    readonly property color infoSoft: dark ? "#16213A" : "#E6EEFD"

    readonly property int radius: 16
    readonly property int radiusSm: 10
    // Windows keeps its own UI fonts; elsewhere the system UI font and a native monospace are used.
    readonly property bool win: Qt.platform.os === "windows"
    readonly property string font: win ? "Segoe UI Variable Text" : Qt.application.font.family
    readonly property string fontDisplay: win ? "Segoe UI Variable Display" : Qt.application.font.family
    readonly property string mono: win ? "Cascadia Mono" : (Qt.platform.os === "osx" ? "Menlo" : "monospace")
    readonly property string icons: "lucide"      // bundled icon font (ISC license), loaded in main.py

    // Strong ease-out: starts fast so the interface feels like it heard the click.
    readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
    readonly property int fast: 140
    readonly property int base: 220
    readonly property int slow: 360
}
