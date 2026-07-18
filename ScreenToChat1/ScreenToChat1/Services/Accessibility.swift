import AppKit
import ApplicationServices

enum Accessibility {
    static func chatGPTApplication() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared.runningApplications
        return workspace.first { $0.bundleIdentifier == "com.openai.chat" }
            ?? workspace.first { $0.localizedName?.localizedCaseInsensitiveContains("ChatGPT") == true }
    }

    static func descendants(of root: AXUIElement, limit: Int = 4_000) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        var index = 0
        while index < queue.count, result.count < limit {
            let element = queue[index]
            index += 1
            result.append(element)
            if let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: element) {
                queue.append(contentsOf: children)
            }
        }
        return result
    }

    static func activeWindow(of application: AXUIElement) -> AXUIElement {
        attribute(kAXFocusedWindowAttribute, of: application)
            ?? attribute(kAXMainWindowAttribute, of: application)
            ?? application
    }

    static func messageInput(in elements: [AXUIElement]) -> AXUIElement? {
        let editable = elements.filter {
            let role = stringAttribute(kAXRoleAttribute, of: $0)
            return role == kAXTextAreaRole || role == kAXTextFieldRole
        }
        return editable
            .filter { boolAttribute(kAXEnabledAttribute, of: $0) != false }
            .max { inputScore($0) < inputScore($1) }
    }

    static func pressSendButton(in elements: [AXUIElement]) -> Bool {
        for element in elements where stringAttribute(kAXRoleAttribute, of: element) == kAXButtonRole {
            let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .compactMap { stringAttribute($0, of: element) }
                .joined(separator: " ")
                .lowercased()
            let isSend = label.contains("send") || label.contains("отправ") || label.contains("senden")
            if isSend, boolAttribute(kAXEnabledAttribute, of: element) != false,
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return true
            }
        }
        return false
    }

    static func visibleText(in elements: [AXUIElement]) -> [String] {
        elements.compactMap { element in
            let role = stringAttribute(kAXRoleAttribute, of: element)
            guard role == kAXStaticTextRole || role == kAXHeadingRole || role == "AXLink" else {
                return nil
            }
            let raw = stringAttribute(kAXValueAttribute, of: element)
                ?? stringAttribute(kAXTitleAttribute, of: element)
            guard let raw else { return nil }
            let cleaned = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.count > 1 ? cleaned : nil
        }
    }

    static func buttonLabels(in elements: [AXUIElement]) -> [String] {
        elements.compactMap { element in
            guard stringAttribute(kAXRoleAttribute, of: element) == kAXButtonRole else { return nil }
            return stringAttribute(kAXTitleAttribute, of: element)
                ?? stringAttribute(kAXDescriptionAttribute, of: element)
                ?? stringAttribute(kAXHelpAttribute, of: element)
        }
    }

    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    private static func inputScore(_ element: AXUIElement) -> Int {
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute]
            .compactMap { stringAttribute($0, of: element) }
            .joined(separator: " ")
            .lowercased()
        let looksLikeMessage = label.contains("message") || label.contains("ask")
            || label.contains("сообщ") || label.contains("спрос") || label.contains("nachricht")
        let focused = boolAttribute(kAXFocusedAttribute, of: element) == true
        let textArea = stringAttribute(kAXRoleAttribute, of: element) == kAXTextAreaRole
        return (looksLikeMessage ? 10 : 0) + (focused ? 4 : 0) + (textArea ? 2 : 0)
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element)
    }

    private static func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        attribute(name, of: element)
    }
}

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

func postKey(to pid: pid_t, code: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.postToPid(pid)
    up?.postToPid(pid)
}
