import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "tz.js" as Tz

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    readonly property var feat: (form.cfg && form.cfg.features) ? form.cfg.features : ({})
    readonly property bool themeOn: feat.theme === true
    readonly property bool carousel: form.val("mode") === "carousel"

    // Mode choices follow the features this firmware was built with, like the web page.
    readonly property var modeOptions: {
        var o = []
        if (feat.ticker !== false) o.push({ label: "Ticker", value: "stocks" })
        if (feat.usage !== false) o.push({ label: "Clawdmeter", value: "usage" })
        if (feat.radar !== false) o.push({ label: "Radar", value: "radar" })
        if (feat.ha !== false) o.push({ label: "Home Assistant", value: "ha" })
        if (feat.theme === true) o.push({ label: "Theme clock", value: "theme" })
        o.push({ label: "Carousel (rotate modes)", value: "carousel" })
        return o
    }

    // theme clocks
    property var themes: []
    property string themeSelected: ""
    property int themeIdx: 0
    property string themeInfo: "Loading themes..."
    property bool themeBusy: false
    property string themeFile: ""
    readonly property var themeOpts: {
        var o = []
        for (var i = 0; i < themes.length; i++) o.push({ label: themes[i].valid === false ? themes[i].id + " - invalid package" : themes[i].name + " - " + themes[i].version, value: i })
        return o
    }
    readonly property var curTheme: themes.length > themeIdx ? themes[themeIdx] : null
    function themeDetails() {
        var c = curTheme
        if (!c) return "No theme selected"
        if (c.valid === false) return "Invalid package: " + (c.error || "Could not read theme") + ". Remove it and install a corrected package."
        return c.name + (c.version ? " - " + c.version : "") + " - " + Math.ceil(c.bytes / 1024) + " KiB"
    }
    function loadThemes() { if (themeOn) form.call("themes", "GET", "/api/themes", "") }

    Connections {
        target: t.form
        function onResponded(tag, status, data) {
            if (tag === "themes" && status === 200) {
                t.themes = data.themes || []
                t.themeSelected = data.selected || ""
                var ix = 0
                for (var i = 0; i < t.themes.length; i++) if (t.themes[i].id === t.themeSelected) ix = i
                t.themeIdx = ix
                t.themeInfo = t.themes.length + " installed - " + Math.floor((data.freeBytes || 0) / 1024) + " KiB free" + (data.error ? " - " + data.error : "")
            } else if (tag === "themeuse") {
                if (status === 200) { t.form.set("mode", "theme"); t.form.toast("Theme selected", "good"); t.loadThemes() }
                else t.form.toast((data && data.error) || "Could not select the theme", "bad")
            } else if (tag === "themedel") {
                if (status === 200) { t.form.toast("Theme removed", "info"); t.loadThemes() }
                else t.form.toast((data && data.error) || "Could not remove the theme", "bad")
            } else if (tag === "themeinstall") {
                t.themeBusy = false
                if (status === 200) { t.form.toast("Theme installed", "good"); t.themeFile = ""; t.loadThemes() }
                else { t.themeInfo = (data && data.error) || "Install failed"; t.form.toast(t.themeInfo, "bad") }
            }
        }
    }
    Connections { target: t.form; function onConfigLoaded() { t.loadThemes() } }

    DevCard {
        title: "Mode"; tabActive: t.tabActive; index: 0
        DevField { form: t.form; kind: "select"; path: "mode"; label: "What this device shows"; options: t.modeOptions }
        ColumnLayout {
            visible: t.carousel
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "number"; path: "carouselSec"; label: "Switch mode every (s)" }
            DevField { form: t.form; kind: "check"; path: "carouselTicker"; label: "Ticker"; visible: t.feat.ticker !== false }
            DevField { form: t.form; kind: "check"; path: "carouselUsage"; label: "Clawdmeter"; visible: t.feat.usage !== false }
            DevField { form: t.form; kind: "check"; path: "carouselRadar"; label: "Radar"; visible: t.feat.radar !== false }
            DevField { form: t.form; kind: "check"; path: "carouselHa"; label: "Home Assistant"; visible: t.feat.ha !== false }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Each name here is the tab that configures it. Pick the active feature, then set it up in its own tab. Carousel rotates through the ticked features."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        visible: t.themeOn
        title: "Theme clocks"; tabActive: t.tabActive; index: 1
        Text { text: "Installed theme"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        Combo { Layout.fillWidth: true; model: t.themeOpts; controlled: true; currentIndex: t.themeIdx; onActivated: function (i) { t.themeIdx = i } }
        RowLayout {
            spacing: 10
            Btn { text: "Use theme"; kind: "primary"; enabled: !!t.curTheme && t.curTheme.valid !== false
                onClicked: t.form.call("themeuse", "POST", "/api/themes/select", JSON.stringify({ id: t.curTheme.id })) }
            Btn { text: "Remove"; enabled: !!t.curTheme
                onClicked: t.form.confirm("Remove this theme?", "It is deleted from the device. You can install it again later.", "Remove", true,
                    function () { t.form.call("themedel", "POST", "/api/themes/delete", JSON.stringify({ id: t.curTheme.id })) }) }
        }
        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: t.themeDetails(); color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
        Text { text: "Install a theme"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Rectangle {
                Layout.fillWidth: true; height: 40; radius: Theme.radiusSm
                color: Theme.dark ? "#10131A" : "#F6F7FA"; border.width: 1; border.color: Theme.border
                Text { anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter } elide: Text.ElideMiddle
                    text: t.themeFile !== "" ? t.themeFile : "No file chosen"; color: t.themeFile !== "" ? Theme.text : Theme.textFaint; font.family: Theme.mono; font.pixelSize: 12 }
            }
            Btn { text: "Choose"; glyph: ""; onClicked: { var p = dev.pickFile("theme"); if (p) t.themeFile = p } }
            Btn { text: "Install"; kind: "primary"; busy: t.themeBusy; enabled: t.themeFile !== ""
                onClicked: { t.themeBusy = true; t.themeInfo = "Installing..."; dev.upload("themeinstall", "/api/themes/install", "theme", t.themeFile) } }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Btn { text: "Make 12-hour copy"; glyph: ""
                onClicked: {
                    var r = JSON.parse(dev.patch12h(t.themeFile))
                    if (r.ok) { t.themeFile = r.path; t.themeInfo = (r.bundled ? "Pixel Room" : "Your theme") + " now has a 12-hour clock. Click Install, then Use theme."; t.form.toast("12-hour copy ready", "good") }
                    else { t.themeInfo = r.msg; t.form.toast(r.msg, "bad") }
                } }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: t.themeFile === "" ? "No file chosen: uses the Pixel Room theme that comes with this app." : "Patches the chosen file."; color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
        }
        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: t.themeInfo; color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Theme clocks use the timezone below. Install a package, then choose Use theme. Notifications continue to appear above it."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Screen"; tabActive: t.tabActive; index: 2
        DevField { form: t.form; kind: "range"; path: "brightness"; rangeLabel: "Brightness"; unit: "%"; from: 0; to: 100 }
        DevField { form: t.form; kind: "check"; path: "autoBrightness"; label: "Auto-brightness (light sensor on A0)" }
        DevField { form: t.form; kind: "select"; path: "rotation"; label: "Orientation"
            options: [ { label: "0°", value: 0 }, { label: "90°", value: 1 }, { label: "180°", value: 2 }, { label: "270°", value: 3 } ] }
        DevField { form: t.form; kind: "check"; path: "backlightInverted"; label: "Backlight is active-low (try if screen stays dark)" }
    }

    DevCard {
        title: "Colour"; tabActive: t.tabActive; index: 3
        DevField { form: t.form; kind: "select"; path: "display.colorOrder"; label: "Colour order"
            options: [ { label: "Panel default", value: "auto" }, { label: "RGB", value: "rgb" }, { label: "BGR (swap red and blue)", value: "bgr" } ] }
        DevField { form: t.form; kind: "check"; path: "display.invert"; label: "Invert the panel" }
        DevField { form: t.form; kind: "range"; path: "display.rGain"; rangeLabel: "Red"; unit: "%"; from: 50; to: 150 }
        DevField { form: t.form; kind: "range"; path: "display.gGain"; rangeLabel: "Green"; unit: "%"; from: 50; to: 150 }
        DevField { form: t.form; kind: "range"; path: "display.bGain"; rangeLabel: "Blue"; unit: "%"; from: 50; to: 150 }
        RowLayout {
            Btn { text: "Reset to 100%"
                onClicked: { t.form.set("display.rGain", 100); t.form.set("display.gGain", 100); t.form.set("display.bGain", 100); t.form.toast("Gains reset. Press Save settings to apply", "info") } }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "The panels shipped in these devices are not the same part, so the same firmware can look warm on one unit and green on another. Turn a channel down to pull that cast out. If red and blue come out swapped, switch the colour order; if the whole screen looks like a negative, tick Invert."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Clock and night mode"; tabActive: t.tabActive; index: 4
        DevField { form: t.form; kind: "select"; path: "clock.tz"; label: "Timezone"
            options: { var o = [ { label: "UTC", value: "" } ], n = Tz.names(); for (var i = 0; i < n.length; i++) o.push({ label: n[i], value: n[i] }); return o } }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            readonly property var s: t.form.status
            readonly property bool needsClock: !!(t.form.cfg && t.form.cfg.clock && t.form.cfg.clock.nightEnabled) || (t.form.cfg && t.form.cfg.mode === "theme") || !!(t.form.cfg && t.form.cfg.wg && t.form.cfg.wg.enabled)
            text: !needsClock ? "Clock: enable night mode, a theme clock, or WireGuard to start NTP"
                : "Clock: " + (s.synced ? (s.time || "synced") + (s.tz ? " (" + s.tz + ")" : "") : "waiting for NTP...") + (s.night ? "  -  night mode active" : (s.nightHeld ? "  -  night mode waiting for NTP" : ""))
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
        }
        DevField { form: t.form; kind: "check"; path: "clock.nightEnabled"; label: "Dim or blank the screen on a nightly schedule" }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "time"; path: "clock.nightStart"; label: "From" }
            DevField { form: t.form; kind: "time"; path: "clock.nightEnd"; label: "To" }
        }
        DevField { form: t.form; kind: "range"; path: "clock.nightLevel"; rangeLabel: "Night brightness"; unit: "%  (0 = screen off)"; from: 0; to: 100 }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Needs internet once to set the clock over NTP. While the window is active it overrides the brightness and auto-brightness above. Times are local to the selected timezone; DST is handled automatically."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
