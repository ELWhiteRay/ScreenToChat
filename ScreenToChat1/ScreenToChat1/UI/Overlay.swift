import AppKit

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
        text.textContainerInset = .zero
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
