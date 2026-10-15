import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Flickable {
    id: page
    required property var app
    property bool active: false
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight + 56
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }

    property bool autostart: false
    property var rs: ({ poll: 60, push: 20 })
    property var al: ({ enabled: true, five: true, week: true, warn: 90, crit: 95, sound: true, resetNote: false, repeatMin: 0 })
    readonly property var repeatOpts: [ { label: "Only once", value: 0 }, { label: "Every 15 minutes", value: 15 }, { label: "Every 30 minutes", value: 30 }, { label: "Every hour", value: 60 } ]
    function setAl(key, v) { al = JSON.parse(bridge.setAlert(key, JSON.stringify(v))) }
    readonly property var pollOpts: [ { label: "2 minutes", value: 120 }, { label: "5 minutes", value: 300 }, { label: "10 minutes", value: 600 }, { label: "15 minutes", value: 900 }, { label: "30 minutes", value: 1800 } ]
    readonly property var pushOpts: [ { label: "10 seconds", value: 10 }, { label: "20 seconds", value: 20 }, { label: "30 seconds", value: 30 }, { label: "1 minute", value: 60 }, { label: "5 minutes", value: 300 } ]
    function idx(opts, v) { for (var i = 0; i < opts.length; i++) if (opts[i].value === v) return i; return -1 }
    function load() { rs = JSON.parse(bridge.refreshSettings()); al = JSON.parse(bridge.alertSettings()); autostart = bridge.autostartEnabled(); logText.text = bridge.logTail(); logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height) }
    onActiveChanged: if (active) load()
    Component.onCompleted: load()

    ColumnLayout {
        id: col
        x: 32; y: 20
        width: page.width - 64
        spacing: 14

        PageHeader { Layout.fillWidth: true; title: "Settings"; subtitle: "How the app behaves on this computer" }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 0
            ColumnLayout {
                width: parent.width; spacing: 18
                Text { text: "Refresh"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Check Claude every"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Each reading starts Claude Code for a few seconds, so it is never faster than every 2 minutes."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Combo {
                        Layout.preferredWidth: 170
                        model: page.pollOpts; controlled: true
                        currentIndex: page.idx(page.pollOpts, page.rs.poll) >= 0 ? page.idx(page.pollOpts, page.rs.poll) : 1
                        onActivated: function (i) { bridge.setPollInterval(page.pollOpts[i].value); page.rs = JSON.parse(bridge.refreshSettings()) }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Update the TV every"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "How often the latest reading is sent to your TV."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Combo {
                        Layout.preferredWidth: 170
                        model: page.pushOpts; controlled: true
                        currentIndex: page.idx(page.pushOpts, page.rs.push) >= 0 ? page.idx(page.pushOpts, page.rs.push) : 1
                        onActivated: function (i) { bridge.setPushInterval(page.pushOpts[i].value); page.rs = JSON.parse(bridge.refreshSettings()) }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 1
            ColumnLayout {
                width: parent.width; spacing: 18
                Text { text: "Usage alerts"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Notify me when usage runs high"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "A system notification at the warning level, and a louder one at the critical level."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: !!page.al.enabled; controlled: true; enabled: true; onToggled: function (v) { page.setAl("enabled", v) } }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Warn at"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Percent used. Applies to each meter on its own."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Field { id: warnF; Layout.preferredWidth: 90; mono: true; maximumLength: 2; horizontalAlignment: TextInput.AlignHCenter; enabled: page.al.enabled
                        Binding { target: warnF; property: "text"; when: !warnF.activeFocus; value: String(page.al.warn) }
                        onEditingFinished: { var n = parseInt(text); if (!isNaN(n)) page.setAl("warn", n) } }
                    Text { text: "%"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14 }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Critical at"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Must be above the warning level. At 100% you get a separate limit reached notice."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Field { id: critF; Layout.preferredWidth: 90; mono: true; maximumLength: 2; horizontalAlignment: TextInput.AlignHCenter; enabled: page.al.enabled
                        Binding { target: critF; property: "text"; when: !critF.activeFocus; value: String(page.al.crit) }
                        onEditingFinished: { var n = parseInt(text); if (!isNaN(n)) page.setAl("crit", n) } }
                    Text { text: "%"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14 }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "5-hour window"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Alert for the session limit."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: !!page.al.five; controlled: true; enabled: true; onToggled: function (v) { page.setAl("five", v) } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "7-day window"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Alert for the weekly limit."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: !!page.al.week; controlled: true; enabled: true; onToggled: function (v) { page.setAl("week", v) } }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Sound for critical alerts"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Warnings stay silent."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: !!page.al.sound; controlled: true; enabled: true; onToggled: function (v) { page.setAl("sound", v) } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Tell me when a window resets"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "A short notice after a critical alert, once your usage is back to normal."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: !!page.al.resetNote; controlled: true; enabled: true; onToggled: function (v) { page.setAl("resetNote", v) } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Repeat the critical alert"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "While usage stays above the critical level."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Combo {
                        Layout.preferredWidth: 190
                        model: page.repeatOpts; controlled: true; enabled: page.al.enabled
                        currentIndex: { for (var i = 0; i < page.repeatOpts.length; i++) if (page.repeatOpts[i].value === page.al.repeatMin) return i; return 0 }
                        onActivated: function (i) { page.setAl("repeatMin", page.repeatOpts[i].value) }
                    }
                }
                RowLayout {
                    spacing: 10
                    Btn { text: "Test warning"; glyph: ""; onClicked: { bridge.testAlert("warning"); page.app.toast("Sent a test warning", "info") } }
                    Btn { text: "Test critical"; glyph: ""; onClicked: { bridge.testAlert("critical"); page.app.toast("Sent a test critical alert", "info") } }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 2
            ColumnLayout {
                width: parent.width; spacing: 18
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Start at login"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Runs quietly in the tray when you sign in."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle {
                        checked: page.autostart; controlled: true
                        onToggled: function (v) {
                            if (bridge.setAutostart(v)) page.autostart = v
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Keep running in the background when closed"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Closing the window keeps sending usage to your TV. Quit from the tray or menu bar icon."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Toggle { checked: bridge.closeToTray; controlled: true; onToggled: function (v) { bridge.setCloseToTray(v) } }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            revealOn: page.active; order: 3
            ColumnLayout {
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Activity log"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Btn { text: "Reload"; kind: "ghost"; glyph: ""; onClicked: page.load() }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 240; radius: Theme.radiusSm
                    color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
                    Flickable {
                        id: logFlick
                        anchors.fill: parent; anchors.margins: 12
                        clip: true
                        contentWidth: width; contentHeight: logText.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { }
                        Text {
                            id: logText
                            width: logFlick.width
                            wrapMode: Text.WrapAnywhere
                            color: Theme.textDim; font.family: Theme.mono; font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
