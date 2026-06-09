import AppKit
import SwiftUI

/// One usage bucket (5-hour block or weekly), as written by claude-quota-fetch.
struct Bucket: Codable {
    let percent: Double?
    let cost_usd: Double?
    let cost_cap: Double?
    let resets_at: String?
}

/// The full state.json snapshot.
struct Snapshot: Codable {
    let updated_at: String?
    let status: String?
    let error: String?
    let five_hour: Bucket?
    let weekly: Bucket?
}

/// Reads the cache file every refresh tick and exposes derived view state.
/// Mirrors the status/color logic of the Plasma plasmoid so the two ports
/// behave identically.
final class QuotaModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var loadError: String?

    /// ~/Library/Caches/claude-quota/state.json — same path the fetch script writes.
    static var stateURL: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cache.appendingPathComponent("claude-quota/state.json")
    }

    /// Reload from disk. On read/parse failure we keep the last good snapshot
    /// (so a mid-write torn read doesn't blank the UI) but record the error.
    func reload() {
        do {
            let data = try Data(contentsOf: Self.stateURL)
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Derived state (parallels main.qml)

    var statusKey: String {
        if loadError != nil && snapshot == nil { return "error" }
        guard let snap = snapshot else { return "error" }
        if snap.error != nil { return "error" }
        return snap.status ?? "error"
    }

    var statusColor: NSColor {
        switch statusKey {
        case "ok":   return NSColor(srgbRed: 0x3a/255.0, green: 0xa7/255.0, blue: 0x57/255.0, alpha: 1) // green
        case "warn": return NSColor(srgbRed: 0xe0/255.0, green: 0xa8/255.0, blue: 0x00/255.0, alpha: 1) // amber
        case "crit": return NSColor(srgbRed: 0xdc/255.0, green: 0x35/255.0, blue: 0x45/255.0, alpha: 1) // red
        default:     return NSColor(srgbRed: 0x66/255.0, green: 0x66/255.0, blue: 0x66/255.0, alpha: 1) // gray
        }
    }

    /// Text inside the menu-bar pill: 5-hour %, or a placeholder.
    var compactText: String {
        if let p = snapshot?.five_hour?.percent {
            return "\(Int(p.rounded()))%"
        }
        return loadError != nil ? "!" : "…"
    }

    var tooltip: String {
        if statusKey == "error" { return "Claude Code quota — no data" }
        let five = snapshot?.five_hour?.percent.map { "\(Int($0.rounded()))%" } ?? "—"
        let wk   = snapshot?.weekly?.percent.map { "\(Int($0.rounded()))%" } ?? "—"
        return "Claude Code: 5h \(five) · wk \(wk)"
    }

    /// Age of the snapshot in seconds, or nil if unknown/unparseable.
    var ageSeconds: Double? {
        guard let iso = snapshot?.updated_at,
              let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return -date.timeIntervalSinceNow
    }

    var footerText: String {
        if let err = loadError, snapshot == nil { return "error: \(err)" }
        guard let snap = snapshot else { return "loading…" }
        if let err = snap.error { return "error: \(err)" }
        return "updated \(RelativeTime.format(snap.updated_at))"
    }
}

/// Per-bucket bar tint, keyed off its own percentage (60/85 thresholds,
/// matching the fetch script's default WARN/CRIT).
func bucketColor(_ percent: Double?) -> Color {
    guard let p = percent else { return .gray }
    if p >= 85 { return Color(red: 0xdc/255.0, green: 0x35/255.0, blue: 0x45/255.0) }
    if p >= 60 { return Color(red: 0xe0/255.0, green: 0xa8/255.0, blue: 0x00/255.0) }
    return Color(red: 0x3a/255.0, green: 0xa7/255.0, blue: 0x57/255.0)
}

/// Formats an ISO-8601 timestamp as a relative string: "in 3h", "5m ago".
/// Direct port of relativeTime() in main.qml.
enum RelativeTime {
    // Two parsers: ccusage's 5h block uses fractional seconds
    // ("…T06:00:00.000Z"), the computed weekly boundary does not.
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func format(_ iso: String?) -> String {
        guard let iso else { return "" }
        guard let date = withFraction.date(from: iso) ?? plain.date(from: iso) else { return iso }
        let diff = Int(date.timeIntervalSinceNow.rounded())
        let abs = Swift.abs(diff)
        let val: Int
        let unit: String
        switch abs {
        case ..<60:    val = abs;          unit = "s"
        case ..<3600:  val = abs / 60;     unit = "m"
        case ..<86400: val = abs / 3600;   unit = "h"
        default:       val = abs / 86400;  unit = "d"
        }
        return diff < 0 ? "\(val)\(unit) ago" : "in \(val)\(unit)"
    }
}
