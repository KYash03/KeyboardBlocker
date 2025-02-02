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
