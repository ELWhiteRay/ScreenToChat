import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class ChatGPTBridge {
    private let report: (String) -> Void
    private var baseline: [String: Int] = [:]
    private var baselineCopyButtons = 0
    private var pollTimer: Timer?
    private var startedAt = Date()
    private var previousCandidate = ""
    private var stablePolls = 0

    init(report: @escaping (String) -> Void) {
        self.report = report
    }

    func send(image: NSImage, completion: @escaping () -> Void) {
        guard AXIsProcessTrusted() else {
            report("Разрешите доступ в Системные настройки → Конфиденциальность и безопасность → Универсальный доступ")
            completion()
            return
        }
        guard let app = Accessibility.chatGPTApplication() else {
            report("Сначала откройте приложение ChatGPT и нужный чат")
            completion()
            return
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        let root = Accessibility.activeWindow(of: application)
        let before = Accessibility.descendants(of: root)
        guard let input = Accessibility.messageInput(in: before), Accessibility.focus(input) else {
            report("Не найдено поле ввода открытого чата ChatGPT")
            completion()
            return
        }

        baseline = Self.counts(Accessibility.visibleText(in: before))
        baselineCopyButtons = Self.copyButtonCount(Accessibility.buttonLabels(in: before))
        let snapshot = PasteboardSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        postKey(to: app.processIdentifier, code: 9, flags: .maskCommand)

        submit(app: app, root: root, snapshot: snapshot, attemptsLeft: 12, completion: completion)
    }

    private func submit(
        app: NSRunningApplication,
        root: AXUIElement,
        snapshot: PasteboardSnapshot,
        attemptsLeft: Int,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let elements = Accessibility.descendants(of: root)
            if Accessibility.pressSendButton(in: elements) || attemptsLeft == 0 {
                if attemptsLeft == 0 { postKey(to: app.processIdentifier, code: 36) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    snapshot.restore()
                    self.watchForResponse(app: app, root: root, completion: completion)
                }
            } else {
                self.submit(app: app, root: root, snapshot: snapshot,
                            attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    private func watchForResponse(
        app: NSRunningApplication,
        root: AXUIElement,
        completion: @escaping () -> Void
    ) {
        startedAt = Date()
        previousCandidate = ""
        stablePolls = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll(app: app, root: root, completion: completion)
            }
        }
    }

    private func poll(
        app: NSRunningApplication,
        root: AXUIElement,
        completion: @escaping () -> Void
    ) {
        guard !app.isTerminated else {
            finish("ChatGPT был закрыт", completion: completion)
            return
        }

        let elements = Accessibility.descendants(of: root)
        let labels = Accessibility.buttonLabels(in: elements)
        let candidate = Self.newResponse(from: Accessibility.visibleText(in: elements), baseline: baseline)
        if candidate == previousCandidate, !candidate.isEmpty {
            stablePolls += 1
        } else {
            previousCandidate = candidate
            stablePolls = 0
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let copyAppeared = Self.copyButtonCount(labels) > baselineCopyButtons
        let generating = labels.contains { label in
            let lower = label.lowercased()
            return lower.contains("stop") || lower.contains("останов") || lower.contains("anhalten")
        }
        if !candidate.isEmpty, stablePolls >= 2, copyAppeared || (!generating && elapsed > 4) {
            finish(candidate, completion: completion)
        } else if elapsed > 120 {
            finish(candidate.isEmpty ? "Ответ ChatGPT не удалось прочитать" : candidate,
                   completion: completion)
        }
    }

    private func finish(_ message: String, completion: @escaping () -> Void) {
        pollTimer?.invalidate()
        pollTimer = nil
        report(message)
        completion()
    }

    nonisolated static func counts(_ strings: [String]) -> [String: Int] {
        strings.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    nonisolated static func newResponse(from current: [String], baseline: [String: Int]) -> String {
        var old = baseline
        let ignored = ["image", "изображение", "attached image", "read-to-chat.png"]
        return current.compactMap { text in
            if old[text, default: 0] > 0 {
                old[text, default: 0] -= 1
                return nil
            }
            let lower = text.lowercased()
            return ignored.contains(lower) || lower.contains("read-to-chat.png") ? nil : text
        }.joined(separator: "\n")
    }

    nonisolated static func copyButtonCount(_ labels: [String]) -> Int {
        labels.filter {
            let lower = $0.lowercased()
            return lower.contains("copy") || lower.contains("копир") || lower.contains("kopieren")
        }.count
    }

    nonisolated static func selfTest() {
        let before = counts(["old", "old", "menu"])
        precondition(newResponse(from: ["old", "menu", "old", "answer"], baseline: before) == "answer")
        precondition(newResponse(from: ["old", "read-to-chat.png", "answer"], baseline: ["old": 1]) == "answer")
        precondition(copyButtonCount(["Copy", "Send", "Копировать"]) == 2)
    }
}
