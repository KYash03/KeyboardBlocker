import ApplicationServices
import Cocoa

extension CGEventType {
    static let systemDefined: CGEventType = CGEventType(rawValue: 14)!
}

extension NSAlert {
    static func show(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private enum UIConstants {
        static let windowSize = NSSize(width: 300, height: 500)
        static let padding: CGFloat = 20
        static let spacing: CGFloat = 12
    }

    private var window: NSWindow!
    private var timerLabel: NSTextField!
    private let inputBlocker = InputBlocker()

    private var timer: Timer?
    private var remainingSeconds: Int = 0
    private var isIndefiniteBlocking: Bool = false

    private var accessibilityCheckTimer: Timer?
    private var wasAccessibilityTrusted: Bool = false
    private var blockButtons: [NSButton] = []

    private var indefiniteBlockButton: NSButton!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        promptForAccessibilityPermission()
        setupMainWindow()
        setupWindowUI()

        wasAccessibilityTrusted = AXIsProcessTrusted()
        updateBlockButtons()
        startAccessibilityCheckTimer()
    }

    private func promptForAccessibilityPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func setupMainWindow() {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: UIConstants.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Keyboard Blocker"
        window.makeKeyAndOrderFront(nil)
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

    @objc private func checkAccessibilityPermissions() {
        let effectiveAccess = isAccessibilityEffectivelyAvailable()

        if !effectiveAccess && (timer != nil || isIndefiniteBlocking) {
            stopBlocking()
            NSAlert.show(
                message: "Accessibility Permission Revoked",
                info:
                    "Blocking has been stopped because accessibility permission was revoked."
            )
        } else if !wasAccessibilityTrusted && effectiveAccess {
            restartApp()
        }

        wasAccessibilityTrusted = effectiveAccess
        updateBlockButtons()
    }

    private func setupWindowUI() {
        guard let contentView = window.contentView else { return }

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.distribution = .gravityAreas
        stackView.spacing = UIConstants.spacing

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: UIConstants.padding),
            stackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -UIConstants.padding),
            stackView.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: UIConstants.padding),
            stackView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -UIConstants.padding),
        ])

        timerLabel = NSTextField(labelWithString: "Keyboard Blocker")
        timerLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        timerLabel.alignment = .center
        stackView.addArrangedSubview(timerLabel)

        let accessibilityButton = makeButton(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings)
        )
        stackView.addArrangedSubview(accessibilityButton)

        addBlockButton("Block for 30 seconds", seconds: 30, to: stackView)
        addBlockButton("Block for 60 seconds", seconds: 60, to: stackView)

        let customButton = makeButton(
            title: "Custom Block Duration",
            action: #selector(startBlockCustom)
        )
        stackView.addArrangedSubview(customButton)
        blockButtons.append(customButton)

        indefiniteBlockButton = makeButton(
            title: "Disable Keyboard Indefinitely",
            action: #selector(toggleIndefiniteBlocking)
        )
        stackView.addArrangedSubview(indefiniteBlockButton)
        blockButtons.append(indefiniteBlockButton)

        let stopButton = makeButton(
            title: "Stop Blocking",
            action: #selector(stopBlocking)
        )
        stackView.addArrangedSubview(stopButton)

        let quitButton = makeButton(
            title: "Quit",
            action: #selector(quitApp)
        )
        stackView.addArrangedSubview(quitButton)
    }

    private func addBlockButton(
        _ title: String, seconds: Int, to stackView: NSStackView
    ) {
        let button = makeButton(
            title: title,
            action: #selector(handleBlockButton(_:))
        )
        button.tag = seconds
        stackView.addArrangedSubview(button)
        blockButtons.append(button)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func isAccessibilityEffectivelyAvailable() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
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

    @objc private func handleBlockButton(_ sender: NSButton) {
        if isIndefiniteBlocking {
            return
        }
        startBlocking(for: sender.tag)
    }

    @objc private func startBlockCustom() {
        let alert = NSAlert()
        alert.messageText = "Custom Blocking Duration"
        alert.informativeText = "Enter duration in seconds:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Block")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.placeholderString = "Seconds"
        alert.accessoryView = inputField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
            let seconds = Int(inputField.stringValue), seconds > 0
        {
            startBlocking(for: seconds)
        } else if response == .alertFirstButtonReturn {
            NSAlert.show(
                message: "Invalid Duration",
                info: "Please enter a valid number of seconds."
            )
        }
    }

    private func startBlocking(for seconds: Int) {
        guard AXIsProcessTrusted() else {
            NSAlert.show(
                message: "Accessibility Not Enabled",
                info:
                    "Please grant accessibility permissions in System Preferences and try again."
            )
            return
        }

        if isIndefiniteBlocking { return }

        if timer != nil {
            remainingSeconds += seconds
            updateStatusLabel()
            return
        }

        guard inputBlocker.startBlocking() else { return }

        remainingSeconds = seconds
        updateStatusLabel()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if !self.isAccessibilityEffectivelyAvailable() {
                self.stopBlocking()
                NSAlert.show(
                    message: "Accessibility Permission Revoked",
                    info:
                        "Blocking has been stopped because accessibility permission was revoked."
                )
                return
            }

            self.remainingSeconds -= 1
            self.updateStatusLabel()
            if self.remainingSeconds <= 0 {
                self.stopBlocking()
            }
        }
    }

    @objc private func toggleIndefiniteBlocking(_ sender: NSButton) {
        guard AXIsProcessTrusted() else {
            NSAlert.show(
                message: "Accessibility Not Enabled",
                info:
                    "Please grant accessibility permissions in System Preferences and try again."
            )
            return
        }

        if !isIndefiniteBlocking {
            if timer != nil {
                timer?.invalidate()
                timer = nil
                remainingSeconds = 0
            }
            guard inputBlocker.startBlocking() else { return }
            isIndefiniteBlocking = true
            sender.title = "Enable Keyboard"
            timerLabel.stringValue = "Keyboard Blocker (Indefinite)"
        } else {
            stopBlocking()
            sender.title = "Disable Keyboard Indefinitely"
        }
    }

    @objc func stopBlocking() {
        timer?.invalidate()
        timer = nil
        remainingSeconds = 0
        isIndefiniteBlocking = false
        inputBlocker.stopBlocking()
        updateStatusLabel()
        indefiniteBlockButton.title = "Disable Keyboard Indefinitely"
    }

    private func updateStatusLabel() {
        DispatchQueue.main.async {
            if self.isIndefiniteBlocking {
                self.timerLabel.stringValue = "Keyboard Blocker (Indefinite)"
            } else if self.timer != nil {
                self.timerLabel.stringValue =
                    "Keyboard Blocker (\(self.remainingSeconds)s)"
            } else {
                self.timerLabel.stringValue = "Keyboard Blocker"
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateBlockButtons() {
        let effectiveAccess = isAccessibilityEffectivelyAvailable()
        blockButtons.forEach { $0.isEnabled = effectiveAccess }

        DispatchQueue.main.async {
            if !effectiveAccess {
                self.timerLabel.stringValue =
                    "Accessibility permission required"
            } else if self.isIndefiniteBlocking {
                self.timerLabel.stringValue = "Keyboard Blocker (Indefinite)"
            } else if self.timer != nil {
                self.timerLabel.stringValue =
                    "Keyboard Blocker (\(self.remainingSeconds)s)"
            } else {
                self.timerLabel.stringValue = "Keyboard Blocker"
            }
        }
    }
}

class InputBlocker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func startBlocking() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.systemDefined.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, _ in
            if !AXIsProcessTrusted() {
                return Unmanaged.passRetained(event)
            }
            return nil
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: nil
            )
        else {
            DispatchQueue.main.async {
                NSAlert.show(
                    message: "Failed to create event tap",
                    info:
                        "Please ensure the app has accessibility permissions in System Preferences."
                )
            }
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopBlocking() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
