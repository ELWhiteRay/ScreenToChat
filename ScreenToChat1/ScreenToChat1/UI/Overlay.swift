import AppKit

@MainActor
final class Overlay {
    private let panel: NSPanel
    private let text = NSTextView()
    private var hideTask: DispatchWorkItem?
    private var presentationID = UUID()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 1),
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
        text.textContainer?.lineFragmentPadding = 0
        text.font = .systemFont(ofSize: 8.5, weight: .medium)
        text.textColor = NSColor(calibratedRed: 0.84, green: 0.81, blue: 0.75, alpha: 1)
        text.shadow = nil
        panel.contentView?.addSubview(text)
    }

    func show(_ message: String, hideAfter delay: TimeInterval? = nil) {
        hideTask?.cancel()
        let presentationID = UUID()
        self.presentationID = presentationID
        text.string = message
        if let screen = NSScreen.main {
            let inset: CGFloat = 3
            let width = min(760, screen.frame.width - inset * 2)
            let bounds = (message as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: text.font!]
            )
            let height = min(ceil(bounds.height), screen.frame.height * 0.4)
            panel.setFrame(NSRect(x: screen.frame.minX + inset,
                                  y: screen.frame.minY + inset,
                                  width: width,
                                  height: max(1, height)),
                           display: true)
            let lines = message.split(separator: "\n", omittingEmptySubsequences: false).count
            AppLog.write("OVERLAY show characters=\(message.count) lines=\(lines) frame=\(panel.frame)")
        }
        panel.orderFrontRegardless()

        guard let delay else { return }
        let task = DispatchWorkItem { [weak self] in
            guard self?.presentationID == presentationID else { return }
            self?.hide()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        presentationID = UUID()
        panel.orderOut(nil)
    }
}
