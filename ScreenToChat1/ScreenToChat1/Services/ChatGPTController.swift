import AppKit

@MainActor
final class ChatGPTController {
    enum ControllerError: LocalizedError {
        case applicationNotFound, launchFailed, terminationFailed

        var errorDescription: String? {
            switch self {
            case .applicationNotFound: "приложение ChatGPT не найдено"
            case .launchFailed: "ChatGPT не удалось запустить"
            case .terminationFailed: "ChatGPT не удалось полностью закрыть"
            }
        }
    }

    private static let bundleIdentifier = "com.openai.codex"
    private static let arguments = [
        "--force-renderer-accessibility=complete",
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=9222",
        "--remote-allow-origins=*",
        "--inspect-brk=127.0.0.1:9230"
    ]
    private var backgroundLaunchObservers: [NSObjectProtocol] = []
    private weak var previouslyActiveApplication: NSRunningApplication?

    func launchAndPrepare() async throws {
        AppLog.write("CHATGPT launch requested")
        let rendererAvailable = await DevToolsClient.isAvailable()
        let mainAvailable = await ElectronMainClient.isAvailable()
        let alreadyRunning = rendererAvailable && mainAvailable
        if !alreadyRunning { beginBackgroundLaunchGuard() }
        defer { endBackgroundLaunchGuard() }

        if !alreadyRunning {
            _ = try await terminate()
            do {
                let application = try await launchApplication()
                _ = application.hide()
                try await ElectronMainClient.prepareAndResume()
                try await DevToolsClient.waitUntilAvailable()
            } catch {
                _ = try? await terminate()
                throw error
            }
        }

        try await ElectronMainClient.showInBackground()
        do {
            try await DevToolsClient.prepareChat()
            try await ElectronMainClient.restoreWindowBehavior()
        } catch {
            try? await ElectronMainClient.restoreWindowBehavior()
            throw error
        }
        AppLog.write("CHATGPT launch completed; prepared chat ready")
    }

    @discardableResult
    func terminate() async throws -> Bool {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        )
        guard !applications.isEmpty else { return false }

        AppLog.write("CHATGPT termination requested; instances=\(applications.count)")
        applications.forEach { _ = $0.terminate() }
        for _ in 0..<20 {
            if applications.allSatisfy(\.isTerminated) {
                AppLog.write("CHATGPT termination completed")
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        applications.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }
        for _ in 0..<20 {
            if applications.allSatisfy(\.isTerminated) {
                AppLog.write("CHATGPT force termination completed")
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ControllerError.terminationFailed
    }

    private func launchApplication() async throws -> NSRunningApplication {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.bundleIdentifier
        ) else {
            throw ControllerError.applicationNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Self.arguments

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(throwing: ControllerError.launchFailed)
                }
            }
        }
    }

    private func beginBackgroundLaunchGuard() {
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        let center = NSWorkspace.shared.notificationCenter
        let bundleIdentifier = Self.bundleIdentifier
        backgroundLaunchObservers = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      application.bundleIdentifier == bundleIdentifier else { return }
                let shouldRestoreFocus = notification.name == NSWorkspace.didActivateApplicationNotification
                let notificationName = notification.name.rawValue
                Task { @MainActor [weak self, weak application] in
                    guard let self, let application else { return }
                    _ = application.hide()
                    if shouldRestoreFocus,
                       let previous = self.previouslyActiveApplication, !previous.isTerminated {
                        _ = previous.activate(options: [])
                    }
                    AppLog.write("CHATGPT background guard handled \(notificationName)")
                }
            }
        }
    }

    private func endBackgroundLaunchGuard() {
        let center = NSWorkspace.shared.notificationCenter
        backgroundLaunchObservers.forEach(center.removeObserver)
        backgroundLaunchObservers.removeAll()
        previouslyActiveApplication = nil
    }
}
