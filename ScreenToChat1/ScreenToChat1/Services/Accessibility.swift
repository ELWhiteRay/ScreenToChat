import AppKit
import ApplicationServices

enum Accessibility {
    static func chatGPTApplication() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared.runningApplications
        return workspace.first { $0.bundleIdentifier == "com.openai.codex" }
            ?? workspace.first { $0.bundleIdentifier == "com.openai.chat" }
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

    static func enableChromiumAccessibility(
        for application: AXUIElement
    ) -> (manual: AXError, enhanced: AXError) {
        let manual = AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        let enhanced = AXUIElementSetAttributeValue(
            activeWindow(of: application), "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
        )
        return (manual, enhanced)
    }

    static func diagnosticSummary(in elements: [AXUIElement]) -> String {
        let roles = elements.reduce(into: [String: Int]()) {
            $0[stringAttribute(kAXRoleAttribute, of: $1) ?? "unknown", default: 0] += 1
        }
        let roleSummary = roles.sorted { $0.value > $1.value }.prefix(12)
            .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let editableCount = elements.filter { isSettable(kAXValueAttribute, of: $0) }.count
        let labels = elements.compactMap { element -> String? in
            let label = inputLabel(element).joined(separator: " ")
            guard !label.isEmpty else { return nil }
            return "\(stringAttribute(kAXRoleAttribute, of: element) ?? "unknown"):\(label.prefix(100))"
        }.prefix(12).joined(separator: " | ")
        return "elements=\(elements.count); roles=[\(roleSummary)]; editableValues=\(editableCount); labels=[\(labels)]"
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

    private static func inputLabel(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute,
         kAXPlaceholderValueAttribute, kAXRoleDescriptionAttribute]
            .compactMap { stringAttribute($0, of: element)?.lowercased() }
    }

    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
            && settable.boolValue
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
