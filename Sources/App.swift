import AppKit
import ApplicationServices
import Carbon

@main
struct ReadToChatMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            ChatGPTBridge.selfTest()
            print("Self-test passed")
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

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
        registerHotKey()
        requestPermissions()
        overlay.show("Готово — нажмите ⇧⌘9")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let quitHotKey { UnregisterEventHotKey(quitHotKey) }
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
        if #available(macOS 10.15, *), !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func registerHotKey() {
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

        let identifier = EventHotKeyID(signature: fourCC("RTCH"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_9),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        let quitIdentifier = EventHotKeyID(signature: fourCC("RTCH"), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_0),
            UInt32(cmdKey | shiftKey),
            quitIdentifier,
            GetApplicationEventTarget(),
            0,
            &quitHotKey
        )
    }
}

private func captureMainScreen() throws -> NSImage {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("read-to-chat.png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-m", "-t", "png", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "ReadToChat", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "проверьте разрешение «Запись экрана»"])
    }
    return image
}

private func fourCC(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}

@MainActor
final class Overlay {
    private let panel: NSPanel
    private let text = NSTextView()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 24, y: 24, width: 760, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        text.frame = panel.contentView!.bounds
        text.autoresizingMask = [.width, .height]
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 0)
        text.font = .systemFont(ofSize: 17, weight: .medium)
        text.textColor = .white
        text.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            return shadow
        }()
        panel.contentView?.addSubview(text)
    }

    func show(_ message: String) {
        text.string = message
        if let screen = NSScreen.main {
            let width = min(760, screen.visibleFrame.width - 48)
            panel.setFrame(NSRect(x: screen.visibleFrame.minX + 24,
                                  y: screen.visibleFrame.minY + 24,
                                  width: width,
                                  height: min(300, screen.visibleFrame.height * 0.4)),
                           display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
