import ApplicationServices
import Cocoa

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
            guard AXIsProcessTrusted() else {
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
