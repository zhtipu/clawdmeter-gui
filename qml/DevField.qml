import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// One labelled setting bound to the device config by dotted path (e.g. "ticker.rotateSec").
// Reads go through form.val(path); edits go through form.set(path, value), which marks the field unsaved.
ColumnLayout {
    id: f
    required property var form
    property string kind: "text"          // text | password | number | url | time | select | check | range
    property string path: ""
    property string wpath: ""             // where an edit is written, when it differs from `path` (secrets)
    property string label: ""
    property string hint: ""
    property string placeholder: ""
    property string rangeLabel: ""        // for range: text shown before the live value, e.g. "Brightness"
    property string unit: ""
    property var options: []
    property real from: 0
    property real to: 100
    property bool isFloat: false
    property bool disabled: false
    property bool mono: false

    Layout.fillWidth: true
    spacing: 5
    opacity: disabled ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    readonly property string writePath: wpath !== "" ? wpath : path
    readonly property var cur: form.val(path)

    function parseNum(t) {
        var n = f.isFloat ? parseFloat(t) : parseInt(t)
        return isNaN(n) ? 0 : n
    }
    function optIndex() {
        for (var i = 0; i < f.options.length; i++) if (f.options[i].value === f.cur) return i
        return -1
    }
    // a value the list does not offer (e.g. an imported radar range) is added rather than lost
    readonly property var opts: {
        var o = f.options.slice()
        if (f.kind === "select" && f.cur !== undefined && f.cur !== null && f.optIndex() < 0) o.push({ label: String(f.cur), value: f.cur })
        return o
    }

    Text {
        visible: f.kind !== "check" && (f.label !== "" || f.kind === "range")
        Layout.fillWidth: true
        text: f.kind === "range" ? f.rangeLabel + ": " + Math.round(Number(f.cur || 0)) + f.unit : f.label
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    Loader {
        Layout.fillWidth: true
        sourceComponent: f.kind === "select" ? selectC : f.kind === "check" ? checkC : f.kind === "range" ? rangeC : textC
    }

    Text {
        visible: f.hint !== ""
        Layout.fillWidth: true
        text: f.hint
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        lineHeight: 1.15
    }

    Component {
        id: textC
        Field {
            id: tf
            mono: f.mono || f.kind === "number" || f.kind === "url" || f.kind === "time"
            enabled: !f.disabled
            echoMode: f.kind === "password" ? TextInput.Password : TextInput.Normal
            placeholderText: f.placeholder
            inputMask: f.kind === "time" ? "00:00" : ""
            inputMethodHints: f.kind === "number" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            // follow the config until the user is typing, so a reload never fights the cursor
            Binding { target: tf; property: "text"; when: !tf.activeFocus; value: f.cur === undefined || f.cur === null ? "" : String(f.cur) }
            onTextEdited: {
                if (f.kind === "number") f.form.set(f.writePath, f.parseNum(text))
                else if (f.kind === "time") { if (text.length === 5) f.form.set(f.writePath, text) }
                else f.form.set(f.writePath, text)
            }
        }
    }

    Component {
        id: selectC
        Combo {
            implicitWidth: 100
            enabled: !f.disabled
            model: f.opts
            controlled: true
            currentIndex: f.optIndex()
            onActivated: function (i) { f.form.set(f.writePath, f.opts[i].value) }
        }
    }

    Component {
        id: checkC
        RowLayout {
            spacing: 12
            Toggle {
                controlled: true
                checked: !!f.cur
                enabled: !f.disabled
                onToggled: function (v) { f.form.set(f.writePath, v) }
            }
            Text {
                Layout.fillWidth: true
                text: f.label
                wrapMode: Text.WordWrap
                color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                TapHandler { enabled: !f.disabled; onTapped: f.form.set(f.writePath, !f.cur) }
            }
        }
    }

    Component {
        id: rangeC
        Slider {
            id: sl
            from: f.from; to: f.to; stepSize: 1
            enabled: !f.disabled
            implicitHeight: 28
            Binding { target: sl; property: "value"; when: !sl.pressed; value: Number(f.cur || 0) }
            onMoved: f.form.set(f.writePath, Math.round(value))
            background: Rectangle {
                x: sl.leftPadding; y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: sl.availableWidth; height: 6; radius: 3
                color: Theme.dark ? "#262C38" : "#E3E6ED"
                Rectangle { width: sl.visualPosition * parent.width; height: parent.height; radius: 3; color: Theme.accent }
            }
            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: sl.pressed ? 22 : 18; height: width; radius: width / 2
                color: "#FFFFFF"; border.width: 1; border.color: Theme.borderHi
                Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }
        }
    }
}
