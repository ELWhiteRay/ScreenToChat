import AppKit
import ApplicationServices

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = Overlay()
    private lazy var bridge = ChatGPTBridge { [weak self] message in
        self?.overlay.show(message, hideAfter: 3)
    }
    private var keyMonitor: Any?
    private var permissionTimer: Timer?
    private var lastMissingPermissions: [String]?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        AppLog.write("START pid=\(ProcessInfo.processInfo.processIdentifier)")
        requestPermissions()
        refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.write("STOP")
        permissionTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func captureAndSend() {
        guard !busy else {
            AppLog.write("CAPTURE ignored: previous send is still running")
            overlay.show("Предыдущая отправка ещё выполняется", hideAfter: 3)
            return
        }
        busy = true
        updateStatus("Снимок и отправка…")
        AppLog.write("CAPTURE requested")
        overlay.hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            do {
                let imageURL = try captureMainScreen()
                AppLog.write("CAPTURE completed; starting ChatGPT automation")
                bridge.send(imageAt: imageURL) { [weak self] in
                    self?.busy = false
                    self?.updateStatus("Активно — ⇧⌘9")
                    AppLog.write("SEND flow completed")
                }
            } catch {
                busy = false
                updateStatus("Ошибка снимка")
                AppLog.write("CAPTURE failed: \(error.localizedDescription)")
                overlay.show("Не удалось сделать снимок: \(error.localizedDescription)")
            }
        }
    }

    private func requestPermissions() {
        AppLog.write("PERMISSIONS requesting")
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func refreshPermissions() {
        let accessibilityGranted = AXIsProcessTrusted()
        let screenCaptureGranted = CGPreflightScreenCaptureAccess()

        if accessibilityGranted, keyMonitor == nil { registerHotKeys() }
        if !accessibilityGranted, let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        var missing: [String] = []
        if !accessibilityGranted { missing.append("«Универсальный доступ»") }
        if !screenCaptureGranted { missing.append("«Запись экрана и системного аудио»") }

        if missing != lastMissingPermissions {
            lastMissingPermissions = missing
            let status = missing.isEmpty ? "Активно — ⇧⌘9" : "Нет доступа: \(missing.joined(separator: ", "))"
            updateStatus(status)
            AppLog.write("PERMISSIONS accessibility=\(accessibilityGranted) screenCapture=\(screenCaptureGranted)")
            overlay.show(missing.isEmpty
                         ? "Готово — нажмите ⇧⌘9"
                         : "Разрешите \(missing.joined(separator: " и ")) в Системных настройках",
                         hideAfter: missing.isEmpty ? 3 : 8)
        }

        if missing.isEmpty {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissions() }
            }
        }
    }

    private func registerHotKeys() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleShortcut(event) }
        }
        AppLog.write("HOTKEY monitor registered=\(keyMonitor != nil)")
    }

    private func handleShortcut(_ event: NSEvent) {
        switch Self.hotKey(from: event.keyCode,
                           modifiers: event.modifierFlags,
                           isRepeat: event.isARepeat) {
        case 25:
            AppLog.write("HOTKEY ⇧⌘9")
            captureAndSend() // Physical 9 key.
        case 29:
            AppLog.write("HOTKEY ⇧⌘0")
            NSApp.terminate(nil) // Physical 0 key.
        default: break
        }
    }

    private func setupStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenToChat1")
        statusItem.button?.toolTip = "ScreenToChat1"

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let capture = NSMenuItem(title: "Сделать снимок и отправить", action: #selector(captureFromMenu), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let openLog = NSMenuItem(title: "Открыть лог", action: #selector(openLog), keyEquivalent: "l")
        openLog.target = self
        menu.addItem(openLog)
        let quit = NSMenuItem(title: "Завершить ScreenToChat1", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func updateStatus(_ status: String) {
        statusLine.title = status
        statusItem.button?.toolTip = "ScreenToChat1 — \(status)"
    }

    @objc private func openLog() {
        AppLog.write("LOG opened from status menu")
        NSWorkspace.shared.open(AppLog.url)
    }

    @objc private func captureFromMenu() {
        AppLog.write("MENU capture")
        captureAndSend()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    nonisolated private static func hotKey(
        from keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> UInt16? {
        let shortcutModifiers = modifiers.intersection([.command, .shift, .control, .option])
        guard shortcutModifiers == [.command, .shift],
              !isRepeat, keyCode == 25 || keyCode == 29 else { return nil }
        return keyCode
    }
}

private func captureMainScreen() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-to-chat.png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-m", "-t", "png", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, NSImage(contentsOf: url) != nil else {
        throw NSError(domain: "ScreenToChat", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "проверьте разрешение «Запись экрана»"])
    }
    return url
}
