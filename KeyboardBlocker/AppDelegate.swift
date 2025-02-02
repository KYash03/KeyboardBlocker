import ApplicationServices
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var blockMenuItems: [NSMenuItem] = []
    private var toggleBlockItem: NSMenuItem?

    private let inputBlocker = InputBlocker()
    private var isBlocking = false

    private var accessibilityCheckTimer: Timer?
    private var wasAccessibilityTrusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissions()
        setupStatusItem()
        wasAccessibilityTrusted = AXIsProcessTrusted()
        updateUIForBlockingState()
        startAccessibilityCheckTimer()
    }

    private func requestAccessibilityPermissions() {
        let options: CFDictionary =
            [
                kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString:
                    true
            ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startAccessibilityCheckTimer() {
        accessibilityCheckTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(checkAccessibilityPermissions),
            userInfo: nil,
            repeats: true
        )
    }

    private func isAccessibilityEffectivelyAvailable() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, _, event, _ in
                    return Unmanaged.passRetained(event)
                },
                userInfo: nil
            )
        else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    @objc private func checkAccessibilityPermissions() {
        let hasAccess = isAccessibilityEffectivelyAvailable()
        if !hasAccess && isBlocking {
            stopBlocking()
            NSAlert.show(
                message: "Accessibility Permission Revoked",
                info:
                    "Blocking has been stopped because accessibility permission was revoked."
            )
        } else if !wasAccessibilityTrusted && hasAccess {
            restartApp()
        }
        wasAccessibilityTrusted = hasAccess
        updateBlockMenuItems()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "KB"
        statusItem.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: "Block Keyboard",
            action: #selector(toggleBlocking(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleBlockItem = toggleItem
        blockMenuItems.append(toggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func updateUIForBlockingState() {
        DispatchQueue.main.async {
            let title = self.isBlocking ? "KB (Blocked)" : "KB"
            self.statusItem.button?.title = title
        }
        updateBlockMenuItems()
    }

    private func updateBlockMenuItems() {
        let effectiveAccess = isAccessibilityEffectivelyAvailable()
        blockMenuItems.forEach { $0.isEnabled = effectiveAccess }
        if let toggleBlockItem = toggleBlockItem {
            toggleBlockItem.title =
                isBlocking ? "Enable Keyboard" : "Block Keyboard"
        }
    }

    @objc private func toggleBlocking(_ sender: NSMenuItem) {
        guard AXIsProcessTrusted() else {
            NSAlert.show(
                message: "Accessibility Not Enabled",
                info:
                    "Please grant accessibility permissions in System Preferences and try again."
            )
            return
        }
        isBlocking.toggle()
        if isBlocking {
            guard inputBlocker.startBlocking() else {
                isBlocking = false
                return
            }
        } else {
            stopBlocking()
        }
        updateUIForBlockingState()
    }

    private func stopBlocking() {
        isBlocking = false
        inputBlocker.stopBlocking()
        updateUIForBlockingState()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func restartApp() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            print("Error restarting app: \(error)")
        }
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
