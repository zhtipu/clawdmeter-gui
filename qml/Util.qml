pragma Singleton
import QtQuick

// Small formatting helpers shared by pages. Add app-specific ones next to these.
QtObject {
    function bytes(n) {
        if (n === undefined || n === null) return "-"
        if (n < 1024) return n + " B"
        if (n < 1048576) return (n / 1024).toFixed(1) + " KB"
        if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB"
        return (n / 1073741824).toFixed(2) + " GB"
    }
    // positive when version a is newer than b ("2026.914.1" vs "2026.516.9")
    function cmp(a, b) {
        var x = String(a || "").match(/\d+/g) || [0], y = String(b || "").match(/\d+/g) || [0]
        for (var i = 0; i < Math.max(x.length, y.length); i++) {
            var d = (Number(x[i]) || 0) - (Number(y[i]) || 0)
            if (d !== 0) return d
        }
        return 0
    }
    function when(iso) {
        if (!iso) return ""
        var d = new Date(iso)
        return d.toLocaleDateString(Qt.locale(), "d MMM yyyy") + ", " + d.toLocaleTimeString(Qt.locale(), "h:mm AP")
    }
    // Local or remote image path to a URL Image can load. Files default to the app's assets folder.
    function imageUrl(p, root) {
        if (!p) return ""
        var s = String(p).split("\\").join("/")
        if (s.indexOf("http://") === 0 || s.indexOf("https://") === 0) return s
        if (!/^[A-Za-z]:[/]/.test(s)) s = String(root || "").split("\\").join("/") + "/assets/" + s
        return "file:///" + s
    }
}
