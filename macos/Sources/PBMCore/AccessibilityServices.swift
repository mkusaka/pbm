import AppKit
import ApplicationServices
import Foundation

enum PBMAX {
    private static let axLinkRole = "AXLink"
    private static let axDialogSubrole = "AXDialog"
    private static let axSystemDialogSubrole = "AXSystemDialog"
    private static let axSheetSubrole = "AXSheet"
    private static let axWindowNumberAttribute = "AXWindowNumber"
    private static let axLabelAttribute = "AXLabel"
    private static let axIdentifierAttribute = "AXIdentifier"
    private static let axPlaceholderAttribute = "AXPlaceholderValue"
    private static let axVisibleChildrenAttribute = "AXVisibleChildren"
    private static let axWebAreaChildrenAttribute = "AXWebAreaChildren"

    struct AXSnapshot {
        let elements: [[String: Any]]
        let menus: [[String: Any]]
        let dialogs: [[String: Any]]
        let menubar: [[String: Any]]
        let limits: [String: Any]
        let error: PBMExecutionResult?
    }

    struct TraversalOptions {
        let maxCount: Int
        let maxDepth: Int
        let maxChildrenPerNode: Int
        let timeoutSeconds: Double
        let includeAlternativeChildren: Bool
        let includeApplicationWindows: Bool
        let includeFocusedElement: Bool
        let windowID: Int?
        let windowTitle: String?
        let windowIndex: Int?

        init(config: PBMConfig) {
            maxCount = config.value(at: "snapshot.maxElementCount") as? Int ?? 500
            maxDepth = config.value(at: "snapshot.maxDepth") as? Int ?? 8
            maxChildrenPerNode = config.value(at: "snapshot.maxChildrenPerNode") as? Int ?? 50
            timeoutSeconds = config.value(at: "snapshot.timeoutSeconds") as? Double ?? 8.0
            includeAlternativeChildren = config.value(at: "snapshot.includeAlternativeChildren") as? Bool ?? true
            includeApplicationWindows = config.value(at: "snapshot.includeApplicationWindows") as? Bool ?? true
            includeFocusedElement = config.value(at: "snapshot.includeFocusedElement") as? Bool ?? true
            windowID = config.value(at: "snapshot.windowId") as? Int
            windowTitle = config.value(at: "snapshot.windowTitle") as? String
            windowIndex = config.value(at: "snapshot.windowIndex") as? Int
        }

        var hasWindowTarget: Bool {
            windowID != nil || windowTitle?.isEmpty == false || windowIndex != nil
        }
    }

    private struct AXDescriptor {
        let role: String
        let subrole: String
        let title: String
        let value: String
        let description: String
        let label: String
        let identifier: String
        let placeholder: String
        let help: String
        let roleDescription: String
        let isEnabled: Bool?
        let rect: CGRect?
        let windowNumber: Int?

        var text: String {
            [title, value, description, label, placeholder]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private struct TraversalState {
        var counters: [String: Int] = [:]
        var elements: [[String: Any]] = []
        var menus: [[String: Any]] = []
        var dialogs: [[String: Any]] = []
        var menubar: [[String: Any]] = []
        var visited = Set<Int>()
        var truncated = false
        var timedOut = false
        var deadline: Date

        var shouldContinue: Bool {
            Date() < deadline && !timedOut
        }
    }

    static func snapshotElements(config: PBMConfig) -> AXSnapshot {
        let options = TraversalOptions(config: config)
        let selection = selectedApps(config: config)
        if let error = selection.error {
            return AXSnapshot(elements: [], menus: [], dialogs: [], menubar: [], limits: selection.limits(options: options, truncated: false, timedOut: false, visitedCount: 0), error: error)
        }
        if let error = preflightWindowTarget(options: options, apps: selection.apps) {
            return AXSnapshot(elements: [], menus: [], dialogs: [], menubar: [], limits: selection.limits(options: options, truncated: false, timedOut: false, visitedCount: 0), error: error)
        }
        guard PBMNative.accessibilityAllowed() else {
            var limits = selection.limits(options: options, truncated: false, timedOut: false, visitedCount: 0)
            limits["accessibility"] = "permission_denied"
            return AXSnapshot(elements: [], menus: [], dialogs: [], menubar: [], limits: limits, error: nil)
        }
        var state = TraversalState(deadline: Date().addingTimeInterval(max(0.25, options.timeoutSeconds)))

        for app in selection.apps {
            if state.elements.count >= options.maxCount {
                state.truncated = true
                break
            }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            setMessagingTimeout(axApp, timeoutSeconds: options.timeoutSeconds)
            defer { setMessagingTimeout(axApp, timeoutSeconds: 0) }

            let roots = windowRoots(appElement: axApp, app: app, options: options)
            if let error = roots.error {
                return AXSnapshot(elements: [], menus: [], dialogs: [], menubar: [], limits: selection.limits(options: options, truncated: state.truncated, timedOut: state.timedOut, visitedCount: state.visited.count), error: error)
            }
            for root in roots.elements {
                traverse(root, app: app, depth: 0, options: options, state: &state)
                if state.elements.count >= options.maxCount || state.timedOut {
                    break
                }
            }
            if !state.shouldContinue {
                state.timedOut = true
                break
            }
        }
        return AXSnapshot(
            elements: state.elements,
            menus: state.menus,
            dialogs: state.dialogs,
            menubar: state.menubar,
            limits: selection.limits(options: options, truncated: state.truncated, timedOut: state.timedOut, visitedCount: state.visited.count),
            error: nil,
        )
    }

    private struct AppSelection {
        let apps: [NSRunningApplication]
        let scope: String
        let target: [String: Any]
        let error: PBMExecutionResult?

        func limits(options: TraversalOptions, truncated: Bool, timedOut: Bool, visitedCount: Int) -> [String: Any] {
            var output: [String: Any] = [
                "maxElementCount": options.maxCount,
                "maxDepth": options.maxDepth,
                "maxChildrenPerNode": options.maxChildrenPerNode,
                "timeoutSeconds": options.timeoutSeconds,
                "truncated": truncated,
                "timedOut": timedOut,
                "visitedCount": visitedCount,
                "scope": scope,
                "includeAlternativeChildren": options.includeAlternativeChildren,
                "includeApplicationWindows": options.includeApplicationWindows,
                "includeFocusedElement": options.includeFocusedElement,
                "matchedApplications": apps.map { app in
                    [
                        "pid": app.processIdentifier,
                        "name": app.localizedName ?? "",
                        "bundleIdentifier": app.bundleIdentifier ?? "",
                    ]
                },
            ]
            if !target.isEmpty {
                output["target"] = target
            }
            if options.hasWindowTarget {
                output["windowTarget"] = [
                    "windowId": options.windowID as Any? ?? NSNull(),
                    "windowTitle": options.windowTitle as Any? ?? NSNull(),
                    "windowIndex": options.windowIndex as Any? ?? NSNull(),
                ]
            }
            return output
        }
    }

    private static func selectedApps(config: PBMConfig) -> AppSelection {
        let requestedScope = config.value(at: "snapshot.scope") as? String ?? "frontmost"
        let pid = config.value(at: "snapshot.pid") as? Int
        let bundleIdentifier = config.value(at: "snapshot.bundleIdentifier") as? String
        let appName = config.value(at: "snapshot.appName") as? String
        var selectors: [String] = []
        if pid != nil {
            selectors.append("pid")
        }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            selectors.append("bundleIdentifier")
        }
        if let appName, !appName.isEmpty {
            selectors.append("appName")
        }

        if selectors.count > 1 || !selectors.isEmpty && requestedScope != "frontmost" {
            return AppSelection(
                apps: [],
                scope: requestedScope,
                target: [
                    "selectors": selectors,
                    "scope": requestedScope,
                ],
                error: .failure(
                    code: "invalid_argument.conflicting_snapshot_target",
                    message: "Pass only one snapshot target selector.",
                    details: [
                        "selectors": selectors,
                        "scope": requestedScope,
                    ],
                    exitCode: 2,
                ),
            )
        }

        if let pid {
            let matches = NSWorkspace.shared.runningApplications.filter { Int($0.processIdentifier) == pid }
            return targetedSelection(matches: matches, scope: "app", target: ["pid": pid])
        }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
            return targetedSelection(matches: matches, scope: "app", target: ["bundleIdentifier": bundleIdentifier])
        }
        if let appName, !appName.isEmpty {
            let matches = NSWorkspace.shared.runningApplications.filter {
                ($0.activationPolicy == .regular || $0.isActive) &&
                    ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
            }
            return targetedSelection(matches: matches, scope: "app", target: ["appName": appName])
        }

        switch requestedScope {
        case "frontmost":
            return AppSelection(apps: NSWorkspace.shared.frontmostApplication.map { [$0] } ?? [], scope: "frontmost", target: [:], error: nil)
        case "allApps":
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular || $0.isActive }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            return AppSelection(apps: apps, scope: "allApps", target: [:], error: nil)
        default:
            return AppSelection(
                apps: [],
                scope: requestedScope,
                target: ["scope": requestedScope],
                error: .failure(
                    code: "invalid_argument.snapshot_scope",
                    message: "Snapshot scope must be frontmost or allApps.",
                    details: ["scope": requestedScope],
                    exitCode: 2,
                ),
            )
        }
    }

    private static func targetedSelection(matches: [NSRunningApplication], scope: String, target: [String: Any]) -> AppSelection {
        let apps = matches.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if apps.isEmpty {
            return AppSelection(
                apps: [],
                scope: scope,
                target: target,
                error: .failure(
                    code: "target_not_found",
                    message: "No running application matched the snapshot target.",
                    details: ["target": target],
                ),
            )
        }
        if apps.count > 1 {
            return AppSelection(
                apps: apps,
                scope: scope,
                target: target,
                error: .failure(
                    code: "target_ambiguous",
                    message: "Multiple running applications matched the snapshot target.",
                    details: [
                        "target": target,
                        "matches": apps.map { app in
                            [
                                "pid": app.processIdentifier,
                                "name": app.localizedName ?? "",
                                "bundleIdentifier": app.bundleIdentifier ?? "",
                            ]
                        },
                    ],
                ),
            )
        }
        return AppSelection(apps: apps, scope: scope, target: target, error: nil)
    }

    private static func preflightWindowTarget(options: TraversalOptions, apps: [NSRunningApplication]) -> PBMExecutionResult? {
        guard options.hasWindowTarget else { return nil }
        if let index = options.windowIndex, index < 0 {
            return .failure(code: "invalid_argument.window_index", message: "--window-index must be zero or greater.", exitCode: 2)
        }

        let appPIDs = Set(apps.map { Int($0.processIdentifier) })
        var windows = PBMNative.windowList(onScreenOnly: false)
        if !appPIDs.isEmpty {
            windows = windows.filter { item in
                guard let ownerPID = item["ownerPID"] as? Int else { return false }
                return appPIDs.contains(ownerPID)
            }
        }

        if let windowID = options.windowID {
            if windows.contains(where: { ($0["windowId"] as? Int) == windowID || ($0["handle"] as? Int) == windowID }) {
                return nil
            }
            return .failure(code: "target_not_found", message: "Window was not found.", details: ["windowId": windowID])
        }

        if let title = options.windowTitle, !title.isEmpty {
            let matches = windows.filter { ($0["title"] as? String ?? "").localizedCaseInsensitiveContains(title) }
            if matches.isEmpty {
                return .failure(code: "target_not_found", message: "Window title was not found.", details: ["title": title])
            }
            if matches.count > 1 {
                return .failure(
                    code: "target_ambiguous",
                    message: "Window title matched multiple windows.",
                    details: [
                        "title": title,
                        "matches": matches.map {
                            [
                                "id": $0["id"] ?? "",
                                "windowId": $0["windowId"] ?? 0,
                                "title": $0["title"] ?? "",
                                "app": $0["app"] ?? "",
                            ]
                        },
                    ],
                )
            }
        }
        return nil
    }

    static func focusedElement() -> AXUIElement? {
        guard PBMNative.accessibilityAllowed() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func setFocusedValue(_ value: String) -> PBMExecutionResult {
        guard PBMNative.accessibilityAllowed() else {
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

    static func performFocusedAction(_ action: String) -> PBMExecutionResult {
        guard PBMNative.accessibilityAllowed() else {
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

    static func focusedAppMenuItems() -> PBMExecutionResult {
        guard PBMNative.accessibilityAllowed() else {
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

    static func clickMenuItem(title: String) -> PBMExecutionResult {
        guard PBMNative.accessibilityAllowed() else {
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

    static func dialogs() -> PBMExecutionResult {
        guard PBMNative.accessibilityAllowed() else {
            return permissionDeniedAccessibility()
        }
        let snapshot = snapshotElements(config: PBMConfig.load())
        return .success(["dialogs": snapshot.dialogs])
    }

    static func permissionDeniedAccessibility() -> PBMExecutionResult {
        .failure(
            code: "permission_denied.accessibility",
            message: "Accessibility permission is required for this command.",
            details: [
                "service": "Accessibility",
                "bundle": Bundle.main.bundleIdentifier ?? "pbm",
                "howToFix": "Grant Accessibility permission to the pbm executable or Bridge app in System Settings.",
            ],
            retryHint: "Run `pbm diagnostics doctor` after granting permission.",
        )
    }

    private static func traverse(
        _ element: AXUIElement,
        app: NSRunningApplication,
        depth: Int,
        options: TraversalOptions,
        state: inout TraversalState,
    ) {
        guard state.shouldContinue else {
            state.timedOut = true
            return
        }
        guard depth <= options.maxDepth, state.elements.count < options.maxCount else {
            state.truncated = true
            return
        }
        let identity = elementIdentity(element)
        guard state.visited.insert(identity).inserted else { return }
        let descriptor = describe(element)
        let prefix = idPrefix(role: descriptor.role, subrole: descriptor.subrole, title: descriptor.title)
        state.counters[prefix, default: 0] += 1
        let id = "\(prefix)\(state.counters[prefix]!)"
        var item: [String: Any] = [
            "id": id,
            "role": descriptor.role,
            "title": descriptor.title,
            "text": descriptor.text,
            "app": app.localizedName ?? "",
            "pid": app.processIdentifier,
            "depth": depth,
        ]
        if let identifier = optionalNonEmpty(descriptor.identifier) {
            item["automationId"] = identifier
        }
        if let enabled = descriptor.isEnabled {
            item["enabled"] = enabled
        }
        if let windowNumber = descriptor.windowNumber {
            item["windowId"] = windowNumber
            item["handle"] = windowNumber
        }
        if let rect = descriptor.rect {
            item["bounds"] = PBMNative.rectDict(rect)
        }
        if !(item.string("text") ?? "").isEmpty || isInteresting(role: descriptor.role, subrole: descriptor.subrole) {
            state.elements.append(item)
        }
        if descriptor.role == kAXMenuBarRole || descriptor.role == kAXMenuBarItemRole || descriptor.role == kAXMenuItemRole {
            state.menus.append(item)
            if descriptor.role == kAXMenuBarItemRole {
                state.menubar.append(item.merging(["id": "N\(state.menubar.count + 1)"]) { new, _ in new })
            }
        }
        if isDialog(role: descriptor.role, subrole: descriptor.subrole, title: descriptor.title) {
            state.dialogs.append(item.merging(["id": "D\(state.dialogs.count + 1)"]) { new, _ in new })
        }
        guard let children = children(element, options: options) else { return }
        for child in children {
            traverse(
                child,
                app: app,
                depth: depth + 1,
                options: options,
                state: &state,
            )
            if state.elements.count >= options.maxCount {
                state.truncated = true
                return
            }
            if state.timedOut {
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
                item["bounds"] = PBMNative.rectDict(rect)
            }
            output.append(item)
        }
        for child in directChildren(element) ?? [] {
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
        for child in directChildren(element) ?? [] {
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

    private static func children(_ element: AXUIElement, options: TraversalOptions) -> [AXUIElement]? {
        var output: [AXUIElement] = []
        var seen = Set<Int>()
        func append(_ children: [AXUIElement]) {
            for child in children {
                guard output.count < options.maxChildrenPerNode else { return }
                if seen.insert(elementIdentity(child)).inserted {
                    output.append(child)
                }
            }
        }

        if let direct = copyArrayAttribute(element, kAXChildrenAttribute) {
            append(direct)
        }
        if options.includeAlternativeChildren {
            for attribute in alternativeChildAttributes {
                if let children = copyArrayAttribute(element, attribute) {
                    append(children)
                }
            }
        }
        if options.includeApplicationWindows, attributeString(element, kAXRoleAttribute) == kAXApplicationRole,
           let windows = copyArrayAttribute(element, kAXWindowsAttribute)
        {
            append(windows)
        }
        if options.includeFocusedElement, attributeString(element, kAXRoleAttribute) == kAXApplicationRole,
           let focused = copyElementAttribute(element, kAXFocusedUIElementAttribute)
        {
            append([focused])
        }
        return output.isEmpty ? nil : output
    }

    private static let alternativeChildAttributes: [String] = [
        axVisibleChildrenAttribute,
        axWebAreaChildrenAttribute,
        "AXApplicationNavigation",
        "AXApplicationElements",
        "AXBodyArea",
        "AXSplitGroupContents",
        "AXLayoutAreaChildren",
        "AXGroupChildren",
        "AXContents",
        "AXChildrenInNavigationOrder",
        "AXSelectedChildren",
        "AXRows",
        "AXColumns",
        "AXTabs",
    ]

    private static func copyArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let array = value as? [AXUIElement] {
            return array
        }
        if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }
        return nil
    }

    private static func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func directChildren(_ element: AXUIElement) -> [AXUIElement]? {
        copyArrayAttribute(element, kAXChildrenAttribute)
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

    private static func idPrefix(role: String, subrole: String = "", title: String) -> String {
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
        case kAXSheetRole:
            return "D"
        default:
            if [axDialogSubrole, axSystemDialogSubrole, axSheetSubrole].contains(subrole) {
                return "D"
            }
            if title.lowercased().contains("dock") {
                return "K"
            }
            return "E"
        }
    }

    private static func isInteresting(role: String, subrole: String) -> Bool {
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
            kAXSheetRole,
        ].contains(role) || [axDialogSubrole, axSystemDialogSubrole, axSheetSubrole].contains(subrole)
    }

    private static func isDialog(role: String, subrole: String, title: String) -> Bool {
        [axDialogSubrole, axSystemDialogSubrole, axSheetSubrole].contains(subrole) ||
            role == kAXSheetRole ||
            role == kAXWindowRole && (
                title.localizedCaseInsensitiveContains("dialog") ||
                    ["Open", "Save", "Export", "Import"].contains(title) ||
                    title.hasPrefix("Save As")
            )
    }

    private static func optionalNonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func elementIdentity(_ element: AXUIElement) -> Int {
        Int(bitPattern: CFHash(element))
    }

    private static func setMessagingTimeout(_ element: AXUIElement, timeoutSeconds: Double) {
        _ = AXUIElementSetMessagingTimeout(element, Float(timeoutSeconds))
    }

    private static let descriptorAttributes: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXValueAttribute,
        kAXDescriptionAttribute,
        axLabelAttribute,
        axIdentifierAttribute,
        axPlaceholderAttribute,
        kAXHelpAttribute,
        kAXRoleDescriptionAttribute,
        kAXEnabledAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
        axWindowNumberAttribute,
    ]

    private static func describe(_ element: AXUIElement) -> AXDescriptor {
        var values: [String: Any] = [:]
        var raw: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, descriptorAttributes as CFArray, [], &raw)
        if result == .success, let array = raw as? [Any], array.count == descriptorAttributes.count {
            for (attribute, value) in zip(descriptorAttributes, array) {
                values[attribute] = value
            }
        }

        let role = stringValue(values[kAXRoleAttribute]) ?? attributeString(element, kAXRoleAttribute)
        let subrole = stringValue(values[kAXSubroleAttribute]) ?? attributeString(element, kAXSubroleAttribute)
        let title = stringValue(values[kAXTitleAttribute]) ?? attributeString(element, kAXTitleAttribute)
        let value = stringValue(values[kAXValueAttribute]) ?? attributeString(element, kAXValueAttribute)
        let description = stringValue(values[kAXDescriptionAttribute]) ?? attributeString(element, kAXDescriptionAttribute)
        let position = pointValue(values[kAXPositionAttribute])
        let size = sizeValue(values[kAXSizeAttribute])
        let rect = position.flatMap { origin in size.map { CGRect(origin: origin, size: $0) } } ?? frame(element)

        return AXDescriptor(
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            description: description,
            label: stringValue(values[axLabelAttribute]) ?? "",
            identifier: stringValue(values[axIdentifierAttribute]) ?? "",
            placeholder: stringValue(values[axPlaceholderAttribute]) ?? "",
            help: stringValue(values[kAXHelpAttribute]) ?? "",
            roleDescription: stringValue(values[kAXRoleDescriptionAttribute]) ?? "",
            isEnabled: boolValue(values[kAXEnabledAttribute]),
            rect: rect,
            windowNumber: intValue(values[axWindowNumberAttribute]),
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        let cfValue = value as CFTypeRef
        if CFGetTypeID(cfValue) == AXValueGetTypeID() {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func pointValue(_ value: Any?) -> CGPoint? {
        guard let axValue = axValue(value),
              AXValueGetType(axValue) == .cgPoint
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeValue(_ value: Any?) -> CGSize? {
        guard let axValue = axValue(value),
              AXValueGetType(axValue) == .cgSize
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static func axValue(_ value: Any?) -> AXValue? {
        guard let value else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(cfValue, to: AXValue.self)
    }

    private static func windowRoots(
        appElement: AXUIElement,
        app: NSRunningApplication,
        options: TraversalOptions,
    ) -> (elements: [AXUIElement], error: PBMExecutionResult?) {
        guard options.hasWindowTarget else {
            return ([appElement], nil)
        }

        let windows = copyArrayAttribute(appElement, kAXWindowsAttribute) ?? []
        let renderable = windows.filter { window in
            guard let rect = describe(window).rect else { return false }
            return rect.width >= 50 && rect.height >= 50
        }
        let candidates = renderable.isEmpty ? windows : renderable

        if let windowID = options.windowID {
            if let window = candidates.first(where: { describe($0).windowNumber == windowID }) {
                return ([window], nil)
            }
            return ([], .failure(
                code: "target_not_found",
                message: "Accessible window was not found.",
                details: ["windowId": windowID, "app": app.localizedName ?? ""],
            ))
        }

        if let title = options.windowTitle, !title.isEmpty {
            let matches = candidates.filter { describe($0).title.localizedCaseInsensitiveContains(title) }
            if matches.count > 1 {
                return ([], .failure(
                    code: "target_ambiguous",
                    message: "Accessible window title matched multiple windows.",
                    details: [
                        "title": title,
                        "matches": matches.enumerated().map { index, window in
                            let descriptor = describe(window)
                            return [
                                "index": index,
                                "title": descriptor.title,
                                "windowId": descriptor.windowNumber as Any? ?? NSNull(),
                            ]
                        },
                    ],
                ))
            }
            if let match = matches.first {
                return ([match], nil)
            }
            return ([], .failure(code: "target_not_found", message: "Accessible window title was not found.", details: ["title": title]))
        }

        if let index = options.windowIndex {
            guard index < candidates.count else {
                return ([], .failure(code: "target_not_found", message: "Accessible window index was not found.", details: ["windowIndex": index, "count": candidates.count]))
            }
            return ([candidates[index]], nil)
        }

        return ([appElement], nil)
    }
}

enum PBMDock {
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
