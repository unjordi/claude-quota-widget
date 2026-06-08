import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

PlasmoidItem {
    id: root

    // --- Data ---
    property var snapshot: null
    property string snapshotError: ""

    // Qt's StandardPaths.GenericCacheLocation can come back as a path or a
    // file:// URL depending on the Qt minor version — normalize to a plain path
    // so we can hand it to the executable engine below.
    readonly property string stateFilePath: {
        // StandardPaths.writableLocation returns a QUrl in QML; coerce to string first.
        const raw = "" + StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
        const stripped = raw.startsWith("file://") ? raw.substring("file://".length) : raw
        return stripped + "/claude-quota/state.json"
    }

    // Read the cache file via a one-shot `cat` through Plasma's executable
    // DataSource. Qt 6 blocks file:// reads from QML's XMLHttpRequest, so we
    // can't go through XHR.
    P5Support.DataSource {
        id: catSource
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0 && data.stdout) {
                try {
                    root.snapshot = JSON.parse(data.stdout)
                    root.snapshotError = ""
                } catch (e) {
                    root.snapshotError = "parse: " + e
                }
            } else {
                root.snapshotError = "cat rc=" + data["exit code"] +
                    (data.stderr ? " " + data.stderr : "")
            }
            disconnectSource(source)
        }
    }

    function loadSnapshot() {
        catSource.connectSource("cat " + stateFilePath)
    }

    // --- Status derivation ---
    readonly property string statusKey: {
        if (snapshotError !== "" || snapshot === null) return "error"
        if (snapshot.status) return snapshot.status
        return "error"
    }
    readonly property var statusVisuals: ({
        "ok":    { icon: "emblem-success",  label: "OK" },
        "warn":  { icon: "emblem-warning",  label: "Warning" },
        "crit":  { icon: "emblem-error",    label: "Critical" },
        "error": { icon: "dialog-question", label: "No data" }
    })

    // --- Refresh loop: re-read cache file every 10s. The systemd timer
    //     refreshes the cache itself every 5min — this just picks up changes.
    Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: loadSnapshot()
    }

    // --- Compact (panel/tray) representation ---
    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.fill: parent
            source: statusVisuals[statusKey].icon
            active: hoverHandler.hovered
        }
        HoverHandler { id: hoverHandler }
        TapHandler { onTapped: root.expanded = !root.expanded }
    }

    preferredRepresentation: compactRepresentation
    fullRepresentation: null

    // --- Tooltip header (always available) ---
    toolTipMainText: {
        if (statusKey === "error") return "Claude Code quota — no data"
        const five = snapshot && snapshot.five_hour
                     ? snapshot.five_hour.percent.toFixed(0) + "%" : "—"
        const wk   = snapshot && snapshot.weekly
                     ? snapshot.weekly.percent.toFixed(0)    + "%" : "—"
        return "Claude Code: 5h " + five + " · wk " + wk
    }

    // --- Rich hover tooltip body ---
    toolTipItem: ColumnLayout {
        width: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 4
            text: "Claude Code quota"
            Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    text: "5-hour block"
                    Layout.fillWidth: true
                    font.bold: true
                }
                PC3.Label {
                    text: root.snapshot && root.snapshot.five_hour
                          ? root.snapshot.five_hour.percent.toFixed(1) + "%"
                          : "—"
                }
            }
            PC3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.snapshot && root.snapshot.five_hour
                       ? root.snapshot.five_hour.percent : 0
            }
            PC3.Label {
                Layout.fillWidth: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                text: {
                    if (!root.snapshot || !root.snapshot.five_hour) return ""
                    const f = root.snapshot.five_hour
                    return "resets " + relativeTime(f.resets_at) +
                           " · $" + f.cost_usd.toFixed(2)
                }
            }
        }

        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    text: "Weekly"
                    Layout.fillWidth: true
                    font.bold: true
                }
                PC3.Label {
                    text: root.snapshot && root.snapshot.weekly
                          ? root.snapshot.weekly.percent.toFixed(1) + "%"
                          : "—"
                }
            }
            PC3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.snapshot && root.snapshot.weekly
                       ? root.snapshot.weekly.percent : 0
            }
            PC3.Label {
                Layout.fillWidth: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                text: {
                    if (!root.snapshot || !root.snapshot.weekly) return ""
                    const w = root.snapshot.weekly
                    return "resets " + relativeTime(w.resets_at) +
                           " · $" + w.cost_usd.toFixed(2)
                }
            }
        }

        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

        PC3.Label {
            Layout.fillWidth: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.5
            text: {
                if (root.snapshotError) return "error: " + root.snapshotError
                if (!root.snapshot) return "loading…"
                return "updated " + relativeTime(root.snapshot.updated_at)
            }
        }
    }

    function relativeTime(iso) {
        if (!iso) return ""
        const t = Date.parse(iso)
        if (isNaN(t)) return iso
        const diff = Math.round((t - Date.now()) / 1000)
        const abs = Math.abs(diff)
        let val, unit
        if      (abs < 60)    { val = abs;                  unit = "s" }
        else if (abs < 3600)  { val = Math.round(abs/60);   unit = "m" }
        else if (abs < 86400) { val = Math.round(abs/3600); unit = "h" }
        else                  { val = Math.round(abs/86400);unit = "d" }
        return diff < 0 ? (val + unit + " ago") : ("in " + val + unit)
    }
}
