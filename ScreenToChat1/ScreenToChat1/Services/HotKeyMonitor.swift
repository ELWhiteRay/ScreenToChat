import AppKit

@MainActor
final class HotKeyMonitor {
    enum Shortcut: UInt16 {
        case closeChatGPT = 18
        case capture = 25
        case launchChatGPT = 26
        case quit = 29
    }

    private var monitor: Any?
    var isRegistered: Bool { monitor != nil }

    func register(handler: @escaping @MainActor @Sendable (Shortcut) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard modifiers == [.command, .shift],
                  !event.isARepeat,
                  let shortcut = Shortcut(rawValue: event.keyCode) else { return }
            Task { @MainActor in handler(shortcut) }
        }
        AppLog.write("HOTKEY monitor registered=\(monitor != nil)")
    }

    func unregister() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
