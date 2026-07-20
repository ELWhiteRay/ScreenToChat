import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class ChatGPTBridge {
    private let report: (String) -> Void

    init(report: @escaping (String) -> Void) {
        self.report = report
    }

    func send(imageAt imageURL: URL, completion: @escaping () -> Void) {
        AppLog.write("SEND started; accessibility=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            AppLog.write("SEND blocked: Accessibility permission is missing")
            report("Разрешите доступ в Системные настройки → Конфиденциальность и безопасность → Универсальный доступ")
            completion()
            return
        }
        guard let app = Accessibility.chatGPTApplication() else {
            AppLog.write("SEND blocked: ChatGPT application not found")
            report("Сначала откройте приложение ChatGPT и нужный чат")
            completion()
            return
        }

        AppLog.write("CHATGPT found pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil")")
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let accessibility = Accessibility.enableChromiumAccessibility(for: application)
        AppLog.write("CHATGPT AX enable manual=\(accessibility.manual.rawValue) enhanced=\(accessibility.enhanced.rawValue)")
        let elements = Accessibility.descendants(of: Accessibility.activeWindow(of: application))
        AppLog.write("CHATGPT AX \(Accessibility.diagnosticSummary(in: elements))")

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DevToolsClient.send(imageAt: imageURL)
                AppLog.write("SEND DevTools completed; method=\(result.method)")
                AppLog.write("RESPONSE finished characters=\(result.response.count)")
                self.report(result.response)
            } catch {
                AppLog.write("SEND DevTools failed: \(error.localizedDescription)")
                self.report("Ошибка отправки: \(error.localizedDescription)")
            }
            completion()
        }
    }
}
