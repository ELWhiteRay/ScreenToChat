import AppKit

@MainActor
final class StatusMenu: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private let launch: () -> Void
    private let capture: () -> Void
    private let closeChatGPT: () -> Void
    private let openLog: () -> Void
    private let quit: () -> Void

    init(
        launch: @escaping () -> Void,
        capture: @escaping () -> Void,
        closeChatGPT: @escaping () -> Void,
        openLog: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.launch = launch
        self.capture = capture
        self.closeChatGPT = closeChatGPT
        self.openLog = openLog
        self.quit = quit
        super.init()
        setup()
    }

    func update(_ status: String) {
        statusLine.title = status
        statusItem.button?.toolTip = "ScreenToChat1 — \(status)"
    }

    private func setup() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "ScreenToChat1"
        )
        statusItem.button?.toolTip = "ScreenToChat1"

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Запуск и подготовка", #selector(launchAction)))
        menu.addItem(item("Сделать снимок и отправить", #selector(captureAction)))
        menu.addItem(item("Закрыть чат", #selector(closeChatGPTAction)))
        menu.addItem(.separator())
        menu.addItem(item("Открыть лог", #selector(openLogAction), key: "l"))
        menu.addItem(item("Завершить ScreenToChat1", #selector(quitAction), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func launchAction() { launch() }
    @objc private func captureAction() { capture() }
    @objc private func closeChatGPTAction() { closeChatGPT() }
    @objc private func openLogAction() { openLog() }
    @objc private func quitAction() { quit() }
}
