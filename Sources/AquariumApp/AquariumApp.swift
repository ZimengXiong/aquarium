import SwiftUI

@main
struct AquariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = AquariumController.shared
    private var settingsWindow: NSWindow?
    private var configPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusIcon(for: item)
        item.menu = makeMenu()
        statusItem = item
        configPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.controller.reload()
                self?.refreshStatusIcon()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.openSettings()
            self.controller.installHelperIfNeeded()
            if #available(macOS 13.0, *) {
                LaunchAtLoginManager.sync(with: self.controller.config.launchAtLogin)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configPollTimer?.invalidate()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.showsStateColumn = false
        menu.addItem(menuItem("Open Settings", action: #selector(openSettings)))
        menu.addItem(menuItem("Enable", action: #selector(enable)))
        menu.addItem(menuItem("Disable", action: #selector(disable)))
        menu.addItem(.separator())
        menu.addItem(menuItem("GitHub", action: #selector(openGitHub)))
        menu.addItem(versionMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Aquarium", action: #selector(NSApplication.terminate(_:)), target: NSApp))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.keyEquivalentModifierMask = []
        item.target = target ?? self
        item.image = nil
        item.onStateImage = nil
        item.offStateImage = nil
        item.mixedStateImage = nil
        item.indentationLevel = 0
        return item
    }

    private func versionMenuItem() -> NSMenuItem {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let suffix = build.map { " (\($0))" } ?? ""
        let item = NSMenuItem(title: "Version \(version)\(suffix)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = nil
        item.onStateImage = nil
        item.offStateImage = nil
        item.mixedStateImage = nil
        item.indentationLevel = 0
        return item
    }

    private func configureStatusIcon(for item: NSStatusItem) {
        item.button?.title = ""
        refreshStatusIcon(item: item)
    }

    private func refreshStatusIcon(item: NSStatusItem? = nil) {
        let item = item ?? statusItem
        let imageName = controller.config.enabled ? "fish.fill" : "fish"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Aquarium")
            ?? NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Aquarium")
        image?.isTemplate = true
        item?.button?.image = image
        item?.button?.imagePosition = .imageOnly
        item?.button?.toolTip = controller.config.enabled ? "Aquarium is enabled" : "Aquarium is disabled"
        // Leave the icon as a pure template image (no tint) so it follows the
        // menu bar appearance — white in dark mode, black in light mode — like
        // every other menu bar icon. Enabled/disabled is conveyed by fish.fill vs fish.
        item?.button?.contentTintColor = nil
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Aquarium"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enable() {
        controller.update { config in
            config.enabled = true
        }
        refreshStatusIcon()
    }

    @objc private func disable() {
        controller.update { config in
            config.enabled = false
        }
        refreshStatusIcon()
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/ZimengXiong/aquarium") else { return }
        NSWorkspace.shared.open(url)
    }
}
