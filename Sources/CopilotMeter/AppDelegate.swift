import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let defaultAllowance = 1_500.0
    private static let allowanceKey = "monthlyAllowance"
    private static let refreshInterval: TimeInterval = 5 * 60

    private let github = GitHubCLI()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var refreshTimer: Timer?
    private var snapshot: UsageSnapshot?
    private var lastError: String?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem.button?.title = "…%"
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

        let allowance = monthlyAllowance
        let github = github

        Task.detached(priority: .utility) { [weak self] in
            let result = Result { try github.fetchSnapshot(allowance: allowance) }
            await self?.finishRefresh(result)
        }
    }

    private func finishRefresh(_ result: Result<UsageSnapshot, Error>) {
        isRefreshing = false

        switch result {
        case .success(let snapshot):
            self.snapshot = snapshot
            lastError = nil
            statusItem.button?.title = "\(snapshot.percentage)%"
            statusItem.button?.toolTip = formatDetail(snapshot)
        case .failure(let error):
            lastError = error.localizedDescription
            statusItem.button?.toolTip = lastError
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else {
            return
        }

        menu.removeAllItems()

        if let snapshot {
            menu.addItem(disabledItem(formatDetail(snapshot)))
            menu.addItem(disabledItem("Updated \(relativeDate(snapshot.fetchedAt))"))
        } else {
            menu.addItem(disabledItem(isRefreshing ? "Refreshing…" : "Usage not available"))
        }

        if let lastError {
            menu.addItem(disabledItem(lastError))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Refresh Now", action: #selector(refresh)))
        menu.addItem(menuItem("Set Monthly Allowance…", action: #selector(editAllowance)))
        menu.addItem(menuItem("Open Usage on GitHub", action: #selector(openGitHubUsage)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Copilot Meter", action: #selector(quit)))
    }

    @objc
    private func editAllowance() {
        let alert = NSAlert()
        alert.messageText = "Monthly AI credit allowance"
        alert.informativeText = "Use the total AI credits included with your current GitHub Copilot plan."
        alert.alertStyle = .informational

        let input = NSTextField(string: formatNumber(monthlyAllowance))
        input.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        input.placeholderString = "1500"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        guard let allowance = Double(input.stringValue), allowance > 0, allowance.isFinite else {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Enter a number greater than zero."
            errorAlert.runModal()
            return
        }

        UserDefaults.standard.set(allowance, forKey: Self.allowanceKey)
        refresh()
    }

    @objc
    private func openGitHubUsage() {
        guard let url = URL(string: "https://github.com/settings/billing/usage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private var monthlyAllowance: Double {
        let stored = UserDefaults.standard.double(forKey: Self.allowanceKey)
        return stored > 0 ? stored : Self.defaultAllowance
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

    private func formatDetail(_ snapshot: UsageSnapshot) -> String {
        "\(formatNumber(snapshot.usedCredits)) / \(formatNumber(snapshot.allowance)) credits · @\(snapshot.account)"
    }

    private func formatNumber(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
