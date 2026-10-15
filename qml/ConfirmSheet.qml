import QtQuick
import QtQuick.Layouts

Sheet {
    id: sheet
    panelWidth: 480
    property string title: ""
    property string message: ""
    property string confirmText: "Confirm"
    property bool danger: false
    property var callback: null

    function ask(t, m, label, isDanger, cb) {
        title = t; message = m; confirmText = label; danger = isDanger; callback = cb
        open = true
    }

    ColumnLayout {
        width: parent.width; spacing: 12
        Text { text: sheet.title; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: 21; font.weight: Font.DemiBold; font.letterSpacing: -0.3 }
        Text { Layout.fillWidth: true; text: sheet.message; wrapMode: Text.Wrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.25 }
        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: 8; spacing: 8
            Item { Layout.fillWidth: true }
            Btn { text: "Cancel"; onClicked: sheet.open = false }
            Btn {
                text: sheet.confirmText; kind: sheet.danger ? "danger" : "primary"
                onClicked: { sheet.open = false; if (sheet.callback) sheet.callback() }
            }
        }
    }
}
