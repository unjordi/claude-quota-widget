import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

PlasmoidItem {
    id: root

    // ---------- Data ----------
    property var snapshot: null
    property string snapshotError: ""

    readonly property string stateFilePath: {
        const raw = "" + StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
        const stripped = raw.startsWith("file://") ? raw.substring("file://".length) : raw
        return stripped + "/claude-quota/state.json"
    }

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

    Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: loadSnapshot()
    }

    // ---------- Status derivation ----------
    readonly property string statusKey: {
        if (snapshotError !== "" || snapshot === null) return "error"
        if (snapshot.status) return snapshot.status
        return "error"
    }
    readonly property color statusColor: {
        switch (statusKey) {
            case "ok":    return "#3aa757"  // green
            case "warn":  return "#e0a800"  // amber
            case "crit":  return "#dc3545"  // red
            case "error": return "#666666"  // gray
        }
        return "#666666"
    }
    readonly property string compactText: {
        if (snapshot && snapshot.five_hour)
            return Math.round(snapshot.five_hour.percent) + "%"
        if (snapshotError) return "!"
        return "…"
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: "applications-development"

    // ---------- Compact representation (panel/tray) ----------
    // Self-contained colored pill — no icon-theme dependency. Renders even if
    // Kirigami.Icon fails to resolve (which it does in some Plasma 6 builds for
    // emblem-* names on certain themes).
    compactRepresentation: Item {
        id: compactRoot
        implicitWidth: Math.max(Kirigami.Units.iconSizes.medium, pillText.implicitWidth + Kirigami.Units.smallSpacing * 2)
        implicitHeight: Kirigami.Units.iconSizes.medium

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: Math.max(parent.height, pillText.implicitWidth + Kirigami.Units.smallSpacing * 2)
            height: parent.height
            radius: height / 2
            color: root.statusColor
            border.color: Qt.darker(color, 1.3)
            border.width: 1
        }

        PC3.Label {
            id: pillText
            anchors.centerIn: pill
            text: root.compactText
            color: "white"
            font.pixelSize: Math.max(9, pill.height * 0.55)
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }

    // ---------- Full representation (click-to-expand popup) ----------
    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 14
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 3
            text: "Claude Code quota"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
        }

        // 5-hour block
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
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
                from: 0; to: 100
                value: root.snapshot && root.snapshot.five_hour ? root.snapshot.five_hour.percent : 0
            }
            PC3.Label {
                Layout.fillWidth: true
                opacity: 0.7
                text: {
                    if (!root.snapshot || !root.snapshot.five_hour) return ""
                    const f = root.snapshot.five_hour
                    let s = "resets " + relativeTime(f.resets_at)
                    if (f.cost_usd !== null && f.cost_usd !== undefined)
                        s += " · ≈ $" + f.cost_usd.toFixed(2) + " API equiv."
                    return s
                }
            }
        }

        // Weekly
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
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
                from: 0; to: 100
                value: root.snapshot && root.snapshot.weekly ? root.snapshot.weekly.percent : 0
            }
            PC3.Label {
                Layout.fillWidth: true
                opacity: 0.7
                text: {
                    if (!root.snapshot || !root.snapshot.weekly) return ""
                    const w = root.snapshot.weekly
                    let s = "resets " + relativeTime(w.resets_at)
                    if (w.cost_usd !== null && w.cost_usd !== undefined)
                        s += " · ≈ $" + w.cost_usd.toFixed(2) + " API equiv."
                    return s
                }
            }
        }

        Item { Layout.fillHeight: true }

        PC3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            opacity: 0.5
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: {
                if (root.snapshotError) return "error: " + root.snapshotError
                if (!root.snapshot) return "loading…"
                return "updated " + relativeTime(root.snapshot.updated_at)
            }
        }
    }

    // ---------- Hover tooltip ----------
    toolTipMainText: {
        if (statusKey === "error") return "Claude Code quota — no data"
        const five = snapshot && snapshot.five_hour ? snapshot.five_hour.percent.toFixed(0) + "%" : "—"
        const wk   = snapshot && snapshot.weekly    ? snapshot.weekly.percent.toFixed(0)    + "%" : "—"
        return "Claude Code: 5h " + five + " · wk " + wk
    }
    toolTipSubText: snapshot && snapshot.five_hour
                    ? "resets in " + relativeTime(snapshot.five_hour.resets_at).replace("in ", "")
                    : ""

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
