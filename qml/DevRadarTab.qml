import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    readonly property int n: form.listLen("radar.airports")
    readonly property string src: form.val("radar.source") || "adsblol"

    function srcHint() {
        if (src === "adsblol") return "The device fetches <b>adsb.lol</b> directly over HTTPS (no key, ~1 req/s). Recommended on the ESP8266: adsb.lol negotiates a small TLS record size, so the handshake fits in RAM."
        if (src === "adsbfi") return "The device fetches <b>adsb.fi</b> directly over HTTPS (no key, ~1 req/s). Fine on the ESP32, but adsb.fi now sits behind Cloudflare and sends TLS records too large for the ESP8266. Pick adsb.lol or the webhook there."
        return "The device requests <b>?lat=..&amp;lon=..&amp;dist=..</b> from your LAN proxy, which pre-filters the feed to a small JSON. Most reliable on the ESP8266."
    }

    DevCard {
        title: "Home location"; tabActive: t.tabActive; index: 0
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "number"; isFloat: true; path: "radar.lat"; label: "Latitude"; placeholder: "52.3676" }
            DevField { form: t.form; kind: "number"; isFloat: true; path: "radar.lon"; label: "Longitude"; placeholder: "4.9041" }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "The radar centres on this point. Decimal degrees, e.g. 52.3676, 4.9041. Leave at 0 / 0 and the screen prompts you to set it."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Range and data"; tabActive: t.tabActive; index: 1
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "select"; path: "radar.rangeKm"; label: "Range"
                options: [ { label: "5", value: 5 }, { label: "10", value: 10 }, { label: "15", value: 15 }, { label: "20", value: 20 }, { label: "25", value: 25 }, { label: "50", value: 50 } ] }
            DevField { form: t.form; kind: "select"; path: "radar.unitsMi"; label: "Units"
                options: [ { label: "km", value: false }, { label: "mi", value: true } ] }
            DevField { form: t.form; kind: "number"; path: "radar.pollSec"; label: "Refresh (s)" }
        }
        DevField { form: t.form; kind: "select"; path: "radar.source"; label: "Data source"
            options: [ { label: "adsb.lol (direct, no server)", value: "adsblol" }, { label: "adsb.fi (direct, no server)", value: "adsbfi" }, { label: "Custom webhook (LAN proxy)", value: "webhook" } ] }
        DevField { visible: t.src === "webhook"; form: t.form; kind: "url"; path: "radar.webhookUrl"; label: "Webhook URL"; placeholder: "http://n8n.local:5678/webhook/radar" }
        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.StyledText; text: t.srcHint(); color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
    }

    DevCard {
        title: "What to show"; tabActive: t.tabActive; index: 2
        DevField { form: t.form; kind: "select"; path: "radar.uiScale"; label: "Marker and label size"
            options: [ { label: "Small", value: 0 }, { label: "Medium", value: 1 }, { label: "Large", value: 2 } ] }
        DevField { form: t.form; kind: "number"; path: "radar.minAltFt"; label: "Hide aircraft below (ft, 0 = show all)"
            hint: "Drops ground traffic (parked or taxiing) and low flights. Try <b>500</b> to hide anything on or near the ground." }
        DevField { form: t.form; kind: "check"; path: "radar.showLabels"; label: "Callsign and altitude labels" }
        DevField { form: t.form; kind: "check"; path: "radar.showVectors"; label: "Speed / heading vectors" }
        DevField { form: t.form; kind: "check"; path: "radar.showRimDots"; label: "Off-screen traffic dots on the rim" }
    }

    DevCard {
        title: "Airports"; tabActive: t.tabActive; index: 3
        ColumnLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: t.n
                delegate: RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Field { id: icF; Layout.fillWidth: true; Layout.preferredWidth: 2; mono: true; placeholderText: "LSZH"
                        Binding { target: icF; property: "text"; when: !icF.activeFocus; value: t.form.listGet("radar.airports", index, "icao") || "" }
                        onTextEdited: t.form.listSet("radar.airports", index, "icao", text) }
                    Field { id: laF; Layout.fillWidth: true; Layout.preferredWidth: 3; mono: true; placeholderText: "lat"
                        Binding { target: laF; property: "text"; when: !laF.activeFocus; value: { var v = t.form.listGet("radar.airports", index, "lat"); return v === undefined || v === null ? "" : String(v) } }
                        onTextEdited: t.form.listSet("radar.airports", index, "lat", parseFloat(text) || 0) }
                    Field { id: loF; Layout.fillWidth: true; Layout.preferredWidth: 3; mono: true; placeholderText: "lon"
                        Binding { target: loF; property: "text"; when: !loF.activeFocus; value: { var v = t.form.listGet("radar.airports", index, "lon"); return v === undefined || v === null ? "" : String(v) } }
                        onTextEdited: t.form.listSet("radar.airports", index, "lon", parseFloat(text) || 0) }
                    Btn { kind: "ghost"; text: ""; glyph: ""; implicitWidth: 44; onClicked: t.form.listRemove("radar.airports", index) }
                }
            }
        }
        RowLayout { Btn { text: "Add airport"; glyph: ""; onClicked: { if (t.form.listLen("radar.airports") >= 6) t.form.toast("Max 6", "info"); else t.form.listAdd("radar.airports", { icao: "", lat: 0, lon: 0 }) } } }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "A few home-area airports drawn as markers. ICAO code (e.g. LSZH) and its lat/lon. Up to 6."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
