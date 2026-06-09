import AppKit
import SwiftUI

/// Owns the menu-bar status item and the popover. Polls the cache file every
/// 10s (the plasmoid's cadence) and redraws the pill; the launchd agent does
/// the actual ccusage fetch on its own 5-minute floor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = QuotaModel()
    private var timer: Timer?
    private var fetching = false

    // The launchd agent refreshes every 5 min, but its StartInterval doesn't
    // reliably catch up after the machine sleeps. If the cache is older than
    // this, the app kicks off its own fetch — only ever when already stale, so
    // the 5-minute polling floor is preserved.
    private let staleThreshold: Double = 330  // 5.5 min
    private lazy var fetchScript = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/claude-quota-fetch").path

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        model.reload()
        if let button = statusItem.button {
            button.image = PillImage.render(text: model.compactText, color: model.statusColor)
            button.toolTip = model.tooltip
        }
        if let age = model.ageSeconds, age > staleThreshold { fetchIfNeeded() }
    }

    /// Run the fetch script off the main thread; reload the UI when it finishes.
    /// Guarded so only one fetch is ever in flight.
    private func fetchIfNeeded() {
        guard !fetching, FileManager.default.isExecutableFile(atPath: fetchScript) else { return }
        fetching = true
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [fetchScript]
        // GUI apps inherit a minimal PATH; the script needs jq + ccusage/npx.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.fetching = false
                self?.refresh()
            }
        }
        do { try proc.run() } catch { fetching = false }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.reload()
            if let age = model.ageSeconds, age > staleThreshold { fetchIfNeeded() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
