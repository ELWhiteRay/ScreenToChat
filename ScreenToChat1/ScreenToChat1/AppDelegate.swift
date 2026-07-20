import AppKit
import ApplicationServices

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = Overlay()
    private let chatGPT = ChatGPTController()
    private let hotKeys = HotKeyMonitor()
    private lazy var statusMenu = StatusMenu(
        launch: { [weak self] in self?.launchChatGPT() },
        capture: { [weak self] in self?.captureAndSend() },
        closeChatGPT: { [weak self] in self?.closeChatGPT() },
        openLog: {
            AppLog.write("LOG opened from status menu")
            NSWorkspace.shared.open(AppLog.url)
        },
        quit: { NSApp.terminate(nil) }
    )
    private lazy var bridge = ChatGPTBridge { [weak self] message in
        self?.overlay.show(message, hideAfter: 3)
    }
    private var permissionTimer: Timer?
    private var lastMissingPermissions: [String]?
    private var busy = false
    private var operationID = 0
    private var launchTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private static let readyStatus = "Активно — ⇧⌘7 / ⇧⌘9 / ⇧⌘1 / ⇧⌘0"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu.update("Запуск…")
        AppLog.write("START pid=\(ProcessInfo.processInfo.processIdentifier)")
        requestPermissions()
        refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.write("STOP")
        permissionTimer?.invalidate()
        hotKeys.unregister()
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
        operationID += 1
        let currentOperation = operationID
        busy = true
        updateStatus("Снимок и отправка…")
        AppLog.write("CAPTURE requested")
        overlay.hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, currentOperation == operationID else { return }
            do {
                let imageURL = try ScreenCapture.mainScreen()
                AppLog.write("CAPTURE completed; starting ChatGPT automation")
                bridge.send(imageAt: imageURL) { [weak self] in
                    guard let self, currentOperation == self.operationID else { return }
                    self.busy = false
                    self.updateStatus(Self.readyStatus)
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

    private func launchChatGPT() {
        guard !busy else {
            overlay.show("Предыдущая операция ещё выполняется", hideAfter: 3)
            return
        }
        operationID += 1
        let currentOperation = operationID
        busy = true
        updateStatus("Запуск ChatGPT…")
        overlay.show("...")
        AppLog.write("HOTKEY launch flow started")

        launchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if currentOperation == operationID {
                    busy = false
                    updateStatus(Self.readyStatus)
                }
            }
            do {
                try await chatGPT.launchAndPrepare()
                try Task.checkCancellation()
                overlay.show("ChatGPT готов — нажмите ⇧⌘9", hideAfter: 3)
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.write("CHATGPT launch failed: \(error.localizedDescription)")
                overlay.show("Ошибка запуска ChatGPT: \(error.localizedDescription)", hideAfter: 6)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, currentOperation == operationID, busy else { return }
            operationID += 1
            launchTask?.cancel()
            launchTask = nil
            busy = false
            updateStatus(Self.readyStatus)
            AppLog.write("CHATGPT launch timed out after 15 seconds")
            overlay.show("ChatGPT не успел запуститься за 15 секунд", hideAfter: 5)
        }
    }

    private func closeChatGPT() {
        operationID += 1
        let currentOperation = operationID
        launchTask?.cancel()
        launchTask = nil
        bridge.cancel()
        closeTask?.cancel()
        busy = true
        updateStatus("Закрытие ChatGPT…")
        AppLog.write("HOTKEY close ChatGPT flow started")

        closeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if currentOperation == operationID {
                    busy = false
                    updateStatus(Self.readyStatus)
                }
            }
            do {
                let closed = try await chatGPT.terminate()
                try Task.checkCancellation()
                overlay.show(closed ? "ChatGPT закрыт" : "ChatGPT уже закрыт", hideAfter: 3)
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.write("CHATGPT close failed: \(error.localizedDescription)")
                overlay.show("Ошибка закрытия ChatGPT: \(error.localizedDescription)", hideAfter: 6)
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

        if accessibilityGranted, !hotKeys.isRegistered {
            hotKeys.register { [weak self] in self?.handleShortcut($0) }
        }
        if !accessibilityGranted { hotKeys.unregister() }

        var missing: [String] = []
        if !accessibilityGranted { missing.append("«Универсальный доступ»") }
        if !screenCaptureGranted { missing.append("«Запись экрана и системного аудио»") }

        if missing != lastMissingPermissions {
            lastMissingPermissions = missing
            let status = missing.isEmpty ? Self.readyStatus : "Нет доступа: \(missing.joined(separator: ", "))"
            updateStatus(status)
            AppLog.write("PERMISSIONS accessibility=\(accessibilityGranted) screenCapture=\(screenCaptureGranted)")
            overlay.show(missing.isEmpty
                         ? "Готово — ⇧⌘7 запускает ChatGPT, ⇧⌘9 делает снимок"
                         : "Разрешите \(missing.joined(separator: " и ")) в Системных настройках",
                         hideAfter: missing.isEmpty ? 3 : 8)
        }

        if missing.isEmpty {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshPermissions() }
            }
        }
    }

    private func handleShortcut(_ shortcut: HotKeyMonitor.Shortcut) {
        switch shortcut {
        case .launchChatGPT:
            AppLog.write("HOTKEY ⇧⌘7")
            launchChatGPT()
        case .capture:
            AppLog.write("HOTKEY ⇧⌘9")
            captureAndSend()
        case .closeChatGPT:
            AppLog.write("HOTKEY ⇧⌘1")
            closeChatGPT()
        case .quit:
            AppLog.write("HOTKEY ⇧⌘0")
            NSApp.terminate(nil)
        }
    }

    private func updateStatus(_ status: String) {
        statusMenu.update(status)
    }

}
