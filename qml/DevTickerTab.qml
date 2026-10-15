import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: t
    required property var form
    property bool tabActive: false
    spacing: 14

    readonly property var s: form.status
    readonly property int n: form.listLen("ticker.symbols")
    property string hintSrc: "yahoo"
    property var cashItems: []
    property string cashMsg: ""
    property bool cashBusy: false
    property string cashQ: ""
    readonly property string chip: (form.cfg && form.cfg.chip) ? form.cfg.chip : ""

    readonly property var srcOpts: [ { label: "Yahoo Finance", value: "yahoo" }, { label: "cash.ch", value: "cash" }, { label: "GitHub", value: "github" }, { label: "Webhook", value: "webhook" } ]

    function symHint(v) {
        var tail = " Name is optional; if set it overrides the source name. Qty and per-unit cost are optional too: set both and the ticker shows your P/L plus a portfolio summary page."
        if (v === "cash") return "<b>cash.ch</b>: fetched directly by the device. The symbol is a listing key like <b>123456789-246-333</b>; the finder below turns a cash.ch link, ISIN, or name into one." + (t.chip === "esp8266" ? " On this ESP8266, cash.ch TLS is tight on this chip. If it proves unstable, use the <b>GitHub</b> source for the same listing key instead." : "") + tail
        if (v === "github") return "<b>GitHub</b>: reads a listing key quote from a small static JSON published to a repo data branch (a proxy for cash.ch on chips that cannot reach it directly). The symbol is the cash.ch listing key." + tail
        if (v === "webhook") return "<b>Webhook</b>: the device asks the webhook URL above and passes the symbol through as-is, so use whatever your endpoint understands." + tail
        return "<b>Yahoo Finance</b>: fetched directly by the device. Use Yahoo symbols: <b>AAPL</b>, <b>NESN.SW</b> (Swiss stocks end in .SW), <b>BTC-USD</b>, <b>EURUSD=X</b>." + tail
    }
    function addTicker(o) {
        if (form.listLen("ticker.symbols") >= 8) { form.toast("Max 8", "info"); return false }
        form.listAdd("ticker.symbols", o || { symbol: "", name: "", source: "yahoo", qty: 0, cost: 0 })
        return true
    }
    function cashPick(key) {
        var len = form.listLen("ticker.symbols"), at = -1
        for (var i = 0; i < len; i++) if (!(form.listGet("ticker.symbols", i, "symbol") || "").trim()) { at = i; break }
        if (at < 0) { if (!addTicker({ symbol: key, name: "", source: "cash", qty: 0, cost: 0 })) return }
        else { form.listSet("ticker.symbols", at, "symbol", key); form.listSet("ticker.symbols", at, "source", "cash") }
        hintSrc = "cash"
        form.toast("Added " + key + ". Set a name, then Save.", "info")
    }

    Connections {
        target: dev
        function onCashResult(j) {
            var r = JSON.parse(j)
            t.cashBusy = false
            t.cashItems = r.items
            t.cashMsg = !r.ok ? "cash.ch not reachable from this computer" : (r.items.length ? "" : "Nothing found on cash.ch")
        }
    }
    Connections {
        target: t.form
        function onResponded(tag, status, data) { if (tag === "refresh" && status === 200) t.form.toast("Refreshing...", "info") }
    }

    DevCard {
        title: "Live data"; tabActive: t.tabActive; index: 0
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Repeater {
                model: t.s.tickers || []
                delegate: DevKV {
                    label: modelData.symbol
                    tint: modelData.error ? Theme.bad : (modelData.valid ? Theme.good : Theme.textDim)
                    value: modelData.valid ? (modelData.price + "   " + (modelData.changePct !== undefined && modelData.changePct !== null ? (modelData.changePct >= 0 ? "+" : "") + modelData.changePct.toFixed(2) + "%" : ""))
                        : (modelData.error ? "error" + (modelData.retryIn !== undefined ? " (retry " + modelData.retryIn + "s)" : "") : "...")
                }
            }
        }
        Text { visible: !(t.s.tickers && t.s.tickers.length); text: "No tickers configured"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        RowLayout { Btn { text: "Refresh data now"; glyph: ""; onClicked: t.form.call("refresh", "POST", "/api/refresh", "") } }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "What the device holds right now for each ticker. Green is a good fetch, red means the last fetch failed and the device is retrying it on its own."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }

    DevCard {
        title: "Rotation and data"; tabActive: t.tabActive; index: 1
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "number"; path: "ticker.rotateSec"; label: "Show each ticker (s)" }
            DevField { form: t.form; kind: "number"; path: "ticker.pollSec"; label: "Refresh data (s)" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            DevField { form: t.form; kind: "select"; path: "ticker.range"; label: "Chart timeframe"
                options: [ { label: "1 day", value: "1d" }, { label: "5 days", value: "5d" }, { label: "1 month", value: "1mo" }, { label: "3 months", value: "3mo" },
                           { label: "6 months", value: "6mo" }, { label: "Year to date", value: "ytd" }, { label: "1 year", value: "1y" }, { label: "2 years", value: "2y" },
                           { label: "5 years", value: "5y" }, { label: "Max", value: "max" } ] }
            DevField { form: t.form; kind: "number"; path: "ticker.points"; label: "Chart points" }
        }
        DevField { form: t.form; kind: "select"; path: "ticker.changeOnRange"; label: "Change and % basis"
            options: [ { label: "Chart timeframe", value: true }, { label: "1 day", value: false } ]
            hint: "Chart timeframe: the change, arrow, colours and chart cover the same span, so they agree. Needs chart data (2+ points); without it the device falls back to the 1-day change. 1 day: the classic change vs the previous close, which can point the other way than a longer chart." }
        DevField { form: t.form; kind: "url"; path: "ticker.webhookUrl"; label: "Webhook URL (only for tickers set to Webhook)"; placeholder: "http://n8n.local:5678/webhook/stock" }
    }

    DevCard {
        title: "Colour scheme"; tabActive: t.tabActive; index: 2
        DevField { form: t.form; kind: "select"; path: "ticker.colorInverted"
            options: [ { label: "Green up / Red down", value: false }, { label: "Red up / Green down", value: true } ] }
    }

    DevCard {
        title: "What to show"; tabActive: t.tabActive; index: 3
        DevField { form: t.form; kind: "check"; path: "ticker.showName"; label: "Name / symbol" }
        DevField { form: t.form; kind: "check"; path: "ticker.showPrice"; label: "Price" }
        DevField { form: t.form; kind: "check"; path: "ticker.showChange"; label: "Change and % change" }
        DevField { form: t.form; kind: "check"; path: "ticker.showChart"; label: "Sparkline chart" }
        DevField { form: t.form; kind: "check"; path: "ticker.showRangeLabel"; label: "Timeframe label" }
        DevField { form: t.form; kind: "check"; path: "ticker.showUpdatedAgo"; label: "\"Updated N s ago\"" }
        DevField { form: t.form; kind: "check"; path: "ticker.showPageDots"; label: "Rotation dots" }
        DevField { form: t.form; kind: "check"; path: "ticker.showPortfolio"; label: "Position P/L and portfolio page" }
    }

    DevCard {
        title: "Tickers (rotate on screen)"; tabActive: t.tabActive; index: 4
        ColumnLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: t.n
                delegate: RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Field { id: symF; Layout.fillWidth: true; Layout.preferredWidth: 3; mono: true; placeholderText: "AAPL"
                        Binding { target: symF; property: "text"; when: !symF.activeFocus; value: t.form.listGet("ticker.symbols", index, "symbol") || "" }
                        onTextEdited: t.form.listSet("ticker.symbols", index, "symbol", text) }
                    Field { id: nmF; Layout.fillWidth: true; Layout.preferredWidth: 3; placeholderText: "name"
                        Binding { target: nmF; property: "text"; when: !nmF.activeFocus; value: t.form.listGet("ticker.symbols", index, "name") || "" }
                        onTextEdited: t.form.listSet("ticker.symbols", index, "name", text) }
                    Combo { Layout.preferredWidth: 140; model: t.srcOpts; controlled: true
                        currentIndex: { var v = t.form.listGet("ticker.symbols", index, "source") || "yahoo"; for (var i = 0; i < t.srcOpts.length; i++) if (t.srcOpts[i].value === v) return i; return 0 }
                        onActivated: function (i) { t.form.listSet("ticker.symbols", index, "source", t.srcOpts[i].value); t.hintSrc = t.srcOpts[i].value } }
                    Field { id: qF; Layout.preferredWidth: 64; mono: true; placeholderText: "qty"
                        Binding { target: qF; property: "text"; when: !qF.activeFocus; value: { var q = t.form.listGet("ticker.symbols", index, "qty"); return q > 0 ? String(q) : "" } }
                        onTextEdited: t.form.listSet("ticker.symbols", index, "qty", parseFloat(text) || 0) }
                    Field { id: cF; Layout.preferredWidth: 74; mono: true; placeholderText: "cost"
                        Binding { target: cF; property: "text"; when: !cF.activeFocus; value: { var c = t.form.listGet("ticker.symbols", index, "cost"); return c > 0 ? String(c) : "" } }
                        onTextEdited: t.form.listSet("ticker.symbols", index, "cost", parseFloat(text) || 0) }
                    Btn { kind: "ghost"; text: ""; glyph: ""; implicitWidth: 44; onClicked: t.form.listRemove("ticker.symbols", index) }
                }
            }
        }
        RowLayout { Btn { text: "Add ticker"; glyph: ""; onClicked: t.addTicker(null) } }
        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.StyledText; text: t.symHint(t.hintSrc); color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12 }
    }

    DevCard {
        title: "cash.ch symbol finder"; tabActive: t.tabActive; index: 5
        Text { text: "Instrument (paste a cash.ch link, ISIN, valor, or a name)"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Field { id: cq; Layout.fillWidth: true; placeholderText: "https://www.cash.ch/... or EU0009654078"
                onAccepted: finder.clicked()
                onTextEdited: t.cashQ = text }
            Btn { id: finder; text: "Find"; glyph: ""; busy: t.cashBusy
                onClicked: { if (!cq.text.trim()) { t.form.toast("Paste a link, ISIN, or name first", "info"); return } t.cashBusy = true; t.cashMsg = ""; t.cashItems = []; dev.cashFind(cq.text) } }
        }
        Text { visible: t.cashMsg !== ""; text: t.cashMsg; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4
            Repeater {
                model: t.cashItems
                delegate: Rectangle {
                    Layout.fillWidth: true; height: 40; radius: Theme.radiusSm
                    color: hh.hovered ? Theme.surfaceHi : "transparent"
                    border.width: 1; border.color: hh.hovered ? Theme.accent : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 150; elide: Text.ElideRight
                        text: modelData.name + "   " + modelData.isin; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    Text { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: modelData.market + " " + modelData.cur; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: t.cashPick(modelData.key) }
                }
            }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Searches cash.ch from this computer and turns the result into the listing key the ticker needs. Click a match to add it as a ticker."
            color: Theme.textFaint; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
