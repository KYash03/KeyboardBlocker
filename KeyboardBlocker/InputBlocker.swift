import ApplicationServices
import Cocoa

final class InputBlocker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    deinit {
        stopBlocking()
    }

    @discardableResult
    func startBlocking() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.systemDefined.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in
            return cachedAccessibilityTrusted
                ? nil
                : Unmanaged.passUnretained(event)
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
                    message: "Unable to Block the Keyboard",
                    info: """
                        The app could not create a keyboard-event tap.
                        Please ensure this app is allowed to control your Mac in:
                        System Settings → Privacy & Security → Accessibility.
                        """
                )
            }
            return false
        }
        eventTap = tap

        if let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, tap, 0)
        {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopBlocking() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
