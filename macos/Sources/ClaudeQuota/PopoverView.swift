import SwiftUI

/// The click-to-open breakdown, hosted in an NSPopover. Mirrors the plasmoid's
/// fullRepresentation: a heading, a section per bucket (percent + progress bar +
/// resets/cost caption), and a footer with the last-refresh time.
struct PopoverView: View {
    @ObservedObject var model: QuotaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("Claude Code usage")
                    .font(.headline)
                Spacer()
                Text("% of limit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            bucket(title: "5-hour block", bucket: model.snapshot?.five_hour)
            bucket(title: "Weekly", bucket: model.snapshot?.weekly)

            Divider()

            HStack {
                Text(model.footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { model.reload() }
                    .controlSize(.small)
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder
    private func bucket(title: String, bucket: Bucket?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(bucket?.percent.map { String(format: "%.1f%%", $0) } ?? "—")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(bucketColor(bucket?.percent))
            }
            ProgressView(value: min(bucket?.percent ?? 0, 100), total: 100)
                .tint(bucketColor(bucket?.percent))
            Text(caption(for: bucket))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func caption(for bucket: Bucket?) -> String {
        guard let bucket else { return "" }
        var parts: [String] = []
        if bucket.resets_at != nil {
            parts.append("Resets \(RelativeTime.format(bucket.resets_at))")
        }
        // The $ is standalone API-equivalent spend (from ccusage) — NOT a
        // budget, so we don't pretend there's a "$X of $Y" ceiling. It's
        // absent when ccusage isn't installed, hence optional.
        if let cost = bucket.cost_usd {
            parts.append("\(money(cost)) API-equiv.")
        }
        return parts.joined(separator: " · ")
    }

    /// "$6.24" under $100, "$642" above — keeps the caption compact.
    private func money(_ value: Double) -> String {
        return value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }
}
