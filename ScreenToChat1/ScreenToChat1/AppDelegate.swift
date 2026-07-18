import AppKit
import ApplicationServices
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?

    private let overlay = Overlay()
    private lazy var bridge = ChatGPTBridge { [weak self] message in
        Task { @MainActor in self?.overlay.show(message) }
    }
    private var hotKey: EventHotKeyRef?
    private var quitHotKey: EventHotKeyRef?
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        registerHotKeys()
        requestPermissions()
        overlay.show("Готово — нажмите ⇧⌘9")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let quitHotKey { UnregisterEventHotKey(quitHotKey) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func captureAndSend() {
        guard !busy else { return }
        busy = true
        overlay.hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            do {
                let image = try captureMainScreen()
                bridge.send(image: image) { [weak self] in self?.busy = false }
            } catch {
                busy = false
                overlay.show("Не удалось сделать снимок: \(error.localizedDescription)")
            }
        }
    }

    private func requestPermissions() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func registerHotKeys() {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var identifier = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                Task { @MainActor in
                    if identifier.id == 2 { NSApp.terminate(nil) }
                    else { AppDelegate.current?.captureAndSend() }
                }
                return noErr
            },
            1,
            &event,
            nil,
            nil
        )

        let captureID = EventHotKeyID(signature: fourCC("STCH"), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_9), UInt32(cmdKey | shiftKey), captureID,
                            GetApplicationEventTarget(), 0, &hotKey)

        let quitID = EventHotKeyID(signature: fourCC("STCH"), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_0), UInt32(cmdKey | shiftKey), quitID,
                            GetApplicationEventTarget(), 0, &quitHotKey)
    }
}

private func captureMainScreen() throws -> NSImage {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-to-chat.png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-m", "-t", "png", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "ScreenToChat", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "проверьте разрешение «Запись экрана»"])
    }
    return image
}

private func fourCC(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
