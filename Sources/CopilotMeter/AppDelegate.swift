import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let refreshInterval: TimeInterval = 5 * 60

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var refreshTimer: Timer?
    private var quota: AccountQuota?
    private var updatedAt: Date?
    private var lastError: String?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem.button?.title = "—"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem.button?.toolTip = "Loading Copilot usage…"

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc
    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        statusItem.button?.toolTip = "Refreshing Copilot usage…"

        Task.detached(priority: .utility) { [weak self] in
            let result = Result { try CopilotCLI().fetchQuota() }
            await self?.finishRefresh(result)
        }
    }

    private func finishRefresh(_ result: Result<AccountQuota, Error>) {
        isRefreshing = false

        switch result {
        case .success(let quota):
            self.quota = quota
            updatedAt = Date()
            lastError = nil
            statusItem.button?.title = quota.plan.title
            statusItem.button?.toolTip = describe(quota)
        case .failure(let error):
            lastError = error.localizedDescription
            statusItem.button?.title = "—"
            statusItem.button?.toolTip = lastError
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else {
            return
        }

        menu.removeAllItems()

        if let quota, let updatedAt {
            let prefix = lastError == nil ? "" : "Last known: "
            menu.addItem(disabledItem(prefix + describe(quota)))
            menu.addItem(disabledItem("Updated \(relativeDate(updatedAt))"))
        } else {
            menu.addItem(disabledItem(isRefreshing ? "Refreshing…" : "Usage not available"))
        }

        if let lastError {
            menu.addItem(disabledItem(lastError))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Refresh Now", action: #selector(refresh)))
        if let quota {
            menu.addItem(menuItem("Open Copilot Settings on \(quota.host.name)", action: #selector(openGitHubUsage)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Copilot Meter", action: #selector(quit)))
    }

    @objc
    private func openGitHubUsage() {
        guard let url = quota?.host.settingsURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func describe(_ quota: AccountQuota) -> String {
        let usage = quota.plan.isUnlimitedEntitlement ? "No metered quota" : "\(quota.plan.title) used"
        return "\(quota.host.name): \(usage)"
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
