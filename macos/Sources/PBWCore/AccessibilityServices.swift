import AppKit
import ApplicationServices
import Foundation

enum PBWAX {
    private static let axLinkRole = "AXLink"
    private static let axDialogSubrole = "AXDialog"

    struct AXSnapshot {
        let elements: [[String: Any]]
        let menus: [[String: Any]]
        let dialogs: [[String: Any]]
        let menubar: [[String: Any]]
        let limits: [String: Any]
    }

    static func snapshotElements(config: PBWConfig) -> AXSnapshot {
        guard PBWNative.accessibilityAllowed() else {
            return AXSnapshot(elements: [], menus: [], dialogs: [], menubar: [], limits: ["accessibility": "permission_denied"])
        }
        let maxCount = config.value(at: "snapshot.maxElementCount") as? Int ?? 500
        let maxDepth = config.value(at: "snapshot.maxDepth") as? Int ?? 8
        let apps: [NSRunningApplication] = if config.value(at: "snapshot.scope") as? String == "allApps" {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular || $0.isActive }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        } else if let frontmost = NSWorkspace.shared.frontmostApplication {
            [frontmost]
        } else {
            []
        }
        var counters: [String: Int] = [:]
        var elements: [[String: Any]] = []
        var menus: [[String: Any]] = []
        var dialogs: [[String: Any]] = []
        var menubar: [[String: Any]] = []
        var truncated = false

        for app in apps {
            if elements.count >= maxCount {
                truncated = true
                break
            }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            traverse(
                axApp,
                app: app,
                depth: 0,
                maxDepth: maxDepth,
                maxCount: maxCount,
                counters: &counters,
                elements: &elements,
                menus: &menus,
                dialogs: &dialogs,
                menubar: &menubar,
                truncated: &truncated,
            )
        }
        return AXSnapshot(
            elements: elements,
            menus: menus,
            dialogs: dialogs,
            menubar: menubar,
            limits: [
                "maxElementCount": maxCount,
                "maxDepth": maxDepth,
                "truncated": truncated,
                "scope": config.value(at: "snapshot.scope") as? String ?? "frontmost",
            ],
        )
    }

    static func focusedElement() -> AXUIElement? {
        guard PBWNative.accessibilityAllowed() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func setFocusedValue(_ value: String) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        guard let element = focusedElement() else {
            return .failure(code: "target_not_found", message: "No focused accessibility element was found.")
        }
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        if result == .success {
            return .success(["strategy": "accessibility", "attribute": "AXValue"])
        }
        return .failure(
            code: "capability_unavailable.ax_set_value",
            message: "Focused element did not accept AXValue.",
            details: ["axError": String(describing: result)],
        )
    }

    static func performFocusedAction(_ action: String) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        guard let element = focusedElement() else {
            return .failure(code: "target_not_found", message: "No focused accessibility element was found.")
        }
        let axAction = action.isEmpty ? kAXPressAction : action
        let result = AXUIElementPerformAction(element, axAction as CFString)
        if result == .success {
            return .success(["strategy": "accessibility", "action": axAction])
        }
        return .failure(
            code: "capability_unavailable.ax_action",
            message: "Focused element did not accept the requested AX action.",
            details: ["action": axAction, "axError": String(describing: result)],
        )
    }

    static func focusedAppMenuItems() -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure(code: "target_not_found", message: "No frontmost application was found.")
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue
        else {
            return .failure(code: "target_not_found", message: "Frontmost application has no accessible menu bar.")
        }
        var counters: [String: Int] = [:]
        var elements: [[String: Any]] = []
        collectMenuItems(menuBar as! AXUIElement, app: app, depth: 0, counters: &counters, output: &elements)
        return .success(["app": app.localizedName ?? "", "pid": app.processIdentifier, "menus": elements])
    }

    static func clickMenuItem(title: String) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure(code: "target_not_found", message: "No frontmost application was found.")
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let item = findMenuItem(in: axApp, title: title) else {
            return .failure(code: "target_not_found", message: "Menu item was not found.", details: ["title": title])
        }
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        if result == .success {
            return .success(["strategy": "accessibility", "title": title, "action": "AXPress"])
        }
        return .failure(code: "capability_unavailable.menu_press", message: "Menu item did not accept AXPress.", details: ["axError": String(describing: result)])
    }

    static func dialogs() -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        let snapshot = snapshotElements(config: PBWConfig.load())
        return .success(["dialogs": snapshot.dialogs])
    }

    static func permissionDeniedAccessibility() -> PBWExecutionResult {
        .failure(
            code: "permission_denied.accessibility",
            message: "Accessibility permission is required for this command.",
            details: [
                "service": "Accessibility",
                "bundle": Bundle.main.bundleIdentifier ?? "pbw",
                "howToFix": "Grant Accessibility permission to the pbw executable or Bridge app in System Settings.",
            ],
            retryHint: "Run `pbw diagnostics doctor` after granting permission.",
        )
    }

    private static func traverse(
        _ element: AXUIElement,
        app: NSRunningApplication,
        depth: Int,
        maxDepth: Int,
        maxCount: Int,
        counters: inout [String: Int],
        elements: inout [[String: Any]],
        menus: inout [[String: Any]],
        dialogs: inout [[String: Any]],
        menubar: inout [[String: Any]],
        truncated: inout Bool,
    ) {
        guard depth <= maxDepth, elements.count < maxCount else {
            truncated = true
            return
        }
        let role = attributeString(element, kAXRoleAttribute)
        let subrole = attributeString(element, kAXSubroleAttribute)
        let title = attributeString(element, kAXTitleAttribute)
        let value = attributeString(element, kAXValueAttribute)
        let description = attributeString(element, kAXDescriptionAttribute)
        let rect = frame(element)
        let prefix = idPrefix(role: role, title: title)
        counters[prefix, default: 0] += 1
        let id = "\(prefix)\(counters[prefix]!)"
        var item: [String: Any] = [
            "id": id,
            "role": role,
            "title": title,
            "text": [title, value, description].filter { !$0.isEmpty }.joined(separator: " "),
            "app": app.localizedName ?? "",
            "pid": app.processIdentifier,
            "depth": depth,
        ]
        if let rect {
            item["bounds"] = PBWNative.rectDict(rect)
        }
        if !(item.string("text") ?? "").isEmpty || isInteresting(role: role) {
            elements.append(item)
        }
        if role == kAXMenuBarRole || role == kAXMenuBarItemRole || role == kAXMenuItemRole {
            menus.append(item)
            if role == kAXMenuBarItemRole {
                menubar.append(item.merging(["id": "N\(menubar.count + 1)"]) { new, _ in new })
            }
        }
        if subrole == axDialogSubrole || role == kAXSheetRole || role == kAXWindowRole && title.lowercased().contains("dialog") {
            dialogs.append(item.merging(["id": "D\(dialogs.count + 1)"]) { new, _ in new })
        }
        guard let children = children(element) else { return }
        for child in children {
            traverse(
                child,
                app: app,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxCount: maxCount,
                counters: &counters,
                elements: &elements,
                menus: &menus,
                dialogs: &dialogs,
                menubar: &menubar,
                truncated: &truncated,
            )
            if elements.count >= maxCount {
                truncated = true
                return
            }
        }
    }

    private static func collectMenuItems(_ element: AXUIElement, app: NSRunningApplication, depth: Int, counters: inout [String: Int], output: inout [[String: Any]]) {
        let role = attributeString(element, kAXRoleAttribute)
        let title = attributeString(element, kAXTitleAttribute)
        if role == kAXMenuBarItemRole || role == kAXMenuItemRole || role == kAXMenuRole {
            counters["M", default: 0] += 1
            var item: [String: Any] = [
                "id": "M\(counters["M"]!)",
                "role": role,
                "title": title,
                "text": title,
                "app": app.localizedName ?? "",
                "pid": app.processIdentifier,
                "depth": depth,
            ]
            if let rect = frame(element) {
                item["bounds"] = PBWNative.rectDict(rect)
            }
            output.append(item)
        }
        for child in children(element) ?? [] {
            collectMenuItems(child, app: app, depth: depth + 1, counters: &counters, output: &output)
        }
    }

    private static func findMenuItem(in app: AXUIElement, title: String) -> AXUIElement? {
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue
        else {
            return nil
        }
        return findDescendant(menuBar as! AXUIElement) { element in
            attributeString(element, kAXTitleAttribute) == title
        }
    }

    private static func findDescendant(_ element: AXUIElement, matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) {
            return element
        }
        for child in children(element) ?? [] {
            if let found = findDescendant(child, matches: matches) {
                return found
            }
        }
        return nil
    }

    private static func attributeString(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return ""
        }
        return String(describing: value)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else {
            return nil
        }
        return array
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAX = positionValue, let sizeAX = sizeValue
        else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionAX as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func idPrefix(role: String, title: String) -> String {
        switch role {
        case kAXButtonRole:
            return "B"
        case kAXTextFieldRole, kAXTextAreaRole:
            return "T"
        case axLinkRole:
            return "L"
        case kAXCheckBoxRole:
            return "C"
        case kAXRadioButtonRole:
            return "R"
        case kAXMenuItemRole, kAXMenuBarItemRole, kAXMenuRole:
            return "M"
        case kAXWindowRole:
            return "W"
        case axDialogSubrole, kAXSheetRole:
            return "D"
        default:
            if title.lowercased().contains("dock") {
                return "K"
            }
            return "E"
        }
    }

    private static func isInteresting(role: String) -> Bool {
        [
            kAXButtonRole,
            kAXTextFieldRole,
            kAXTextAreaRole,
            axLinkRole,
            kAXCheckBoxRole,
            kAXRadioButtonRole,
            kAXMenuItemRole,
            kAXMenuBarItemRole,
            kAXWindowRole,
            axDialogSubrole,
            kAXSheetRole,
        ].contains(role)
    }
}

enum PBWDock {
    static func publicDockItems() -> [[String: Any]] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        return apps.enumerated().map { index, app in
            [
                "id": "K\(index + 1)",
                "title": app.localizedName ?? "",
                "bundleIdentifier": app.bundleIdentifier ?? "",
                "pid": app.processIdentifier,
                "running": !app.isTerminated,
                "source": "NSWorkspace.runningApplications",
                "capability": [
                    "dockPinnedItems": "capability_unavailable.dock_pinned_items_public_api",
                ],
            ]
        }
    }
}
