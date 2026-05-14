import AppKit
import ApplicationServices
import Foundation

enum PBWClipboard {
    static func get() -> PBWExecutionResult {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        return .success([
            "types": pasteboard.types?.map(\.rawValue) ?? [],
            "text": text as Any? ?? NSNull(),
            "hasText": text != nil,
        ])
    }

    static func set(args: PBWArguments) -> PBWExecutionResult {
        guard let text = args.string("text") ?? args.positionals.first else {
            return .failure(code: "invalid_argument.missing_text", message: "--text is required.", exitCode: 2)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .success(["types": ["public.utf8-plain-text"], "characters": text.count])
    }

    static func clear() -> PBWExecutionResult {
        NSPasteboard.general.clearContents()
        return .success(["cleared": true])
    }
}

enum PBWApp {
    static func list() -> PBWExecutionResult {
        let apps = NSWorkspace.shared.runningApplications
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map(appData)
        return .success(["apps": apps])
    }

    static func launch(args: PBWArguments) -> PBWExecutionResult {
        guard let target = args.string("bundle-id") ?? args.string("bundleId") ?? args.string("path") ?? args.string("name") ?? args.positionals.first else {
            return .failure(code: "invalid_argument.missing_app", message: "--bundle-id, --path, or --name is required.", exitCode: 2)
        }
        guard let url = applicationURL(target: target, args: args) else {
            return .failure(code: "target_not_found", message: "Application was not found.", details: ["target": target])
        }
        let semaphore = DispatchSemaphore(value: 0)
        final class LaunchBox: @unchecked Sendable {
            var launched: NSRunningApplication?
            var launchError: Error?
        }
        let box = LaunchBox()
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            box.launched = app
            box.launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        if let launchError = box.launchError {
            return .failure(code: "internal.app_launch", message: launchError.localizedDescription, details: ["url": url.path])
        }
        return .success(["app": box.launched.map(appData) ?? ["path": url.path], "strategy": "NSWorkspace"])
    }

    static func focus(args: PBWArguments) -> PBWExecutionResult {
        guard let app = find(args: args) else {
            return .failure(code: "target_not_found", message: "Application was not found.")
        }
        let ok = app.activate(options: [.activateAllWindows])
        return .success(["focused": ok, "app": appData(app), "strategy": "NSRunningApplication.activate"])
    }

    static func quit(args: PBWArguments) -> PBWExecutionResult {
        guard let app = find(args: args) else {
            return .failure(code: "target_not_found", message: "Application was not found.")
        }
        let ok = app.terminate()
        return .success(["requested": ok, "app": appData(app), "strategy": "NSRunningApplication.terminate"])
    }

    static func hide(args: PBWArguments, hidden: Bool) -> PBWExecutionResult {
        guard let app = find(args: args) else {
            return .failure(code: "target_not_found", message: "Application was not found.")
        }
        let ok = hidden ? app.hide() : app.unhide()
        return .success(["hidden": hidden, "performed": ok, "app": appData(app)])
    }

    static func open(args: PBWArguments) -> PBWExecutionResult {
        guard let target = args.string("url") ?? args.string("path") ?? args.positionals.first else {
            return .failure(code: "invalid_argument.missing_target", message: "--url or --path is required.", exitCode: 2)
        }
        let url = URL(string: target) ?? URL(fileURLWithPath: target)
        let ok = NSWorkspace.shared.open(url)
        return .success(["opened": ok, "url": url.absoluteString, "strategy": "NSWorkspace.open"])
    }

    static func relaunch(args: PBWArguments) -> PBWExecutionResult {
        guard let app = find(args: args) else {
            return .failure(code: "target_not_found", message: "Application was not found.")
        }
        let bundleID = app.bundleIdentifier
        let path = app.bundleURL?.path
        _ = app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        let launchArgs = PBWArguments(options: ["bundle-id": bundleID ?? "", "path": path ?? ""], positionals: [])
        return launch(args: launchArgs)
    }

    static func find(args: PBWArguments) -> NSRunningApplication? {
        if let pid = args.int("pid") {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        let bundleID = args.string("bundle-id") ?? args.string("bundleId")
        let name = args.string("name") ?? args.positionals.first
        return NSWorkspace.shared.runningApplications.first { app in
            if let bundleID, app.bundleIdentifier == bundleID { return true }
            if let name, (app.localizedName ?? "").localizedCaseInsensitiveContains(name) { return true }
            return false
        }
    }

    private static func applicationURL(target: String, args: PBWArguments) -> URL? {
        if args.string("path") != nil || target.hasPrefix("/") {
            return URL(fileURLWithPath: target)
        }
        if args.string("bundle-id") != nil || target.contains(".") {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
            ?? NSWorkspace.shared.runningApplications.first { ($0.localizedName ?? "").localizedCaseInsensitiveContains(target) }?.bundleURL
    }

    private static func appData(_ app: NSRunningApplication) -> [String: Any] {
        [
            "pid": app.processIdentifier,
            "name": app.localizedName ?? "",
            "bundleIdentifier": app.bundleIdentifier ?? "",
            "bundleURL": app.bundleURL?.path ?? NSNull(),
            "executableURL": app.executableURL?.path ?? NSNull(),
            "isActive": app.isActive,
            "isHidden": app.isHidden,
            "activationPolicy": String(describing: app.activationPolicy.rawValue),
        ]
    }
}

enum PBWWindow {
    static func list() -> PBWExecutionResult {
        .success(["windows": PBWNative.windowList()])
    }

    static func focus(args: PBWArguments) -> PBWExecutionResult {
        let resolved = resolveWindow(args: args)
        if let error = resolved.error { return error }
        guard let target = resolved.target else {
            return .failure(code: "target_not_found", message: "Window was not found.")
        }
        if let pid = target["ownerPID"] as? Int, let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            _ = app.activate(options: [.activateAllWindows])
        }
        if PBWNative.accessibilityAllowed(), let axWindow = axWindow(args: args, target: target) {
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        return .success(["window": target, "strategy": "NSRunningApplication.activate+AXRaise"])
    }

    static func setBounds(args: PBWArguments, moveOnly: Bool = false, resizeOnly: Bool = false) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return PBWAX.permissionDeniedAccessibility()
        }
        let resolved = resolveWindow(args: args)
        if let error = resolved.error { return error }
        guard let target = resolved.target, let axWindow = axWindow(args: args, target: target) else {
            return .failure(code: "target_not_found", message: "Window was not found.")
        }
        var performed: [String] = []
        if !resizeOnly, let x = args.double("x"), let y = args.double("y") {
            var point = CGPoint(x: x, y: y)
            if let value = AXValueCreate(.cgPoint, &point) {
                let result = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value)
                if result == .success { performed.append("position") }
            }
        }
        if !moveOnly, let width = args.double("width"), let height = args.double("height") {
            var size = CGSize(width: width, height: height)
            if let value = AXValueCreate(.cgSize, &size) {
                let result = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, value)
                if result == .success { performed.append("size") }
            }
        }
        if performed.isEmpty {
            return .failure(code: "invalid_argument.missing_bounds", message: "Bounds options were not provided or were rejected.", exitCode: 2)
        }
        return .success(["performed": performed, "strategy": "Accessibility"])
    }

    static func minimize(args: PBWArguments, minimized: Bool) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return PBWAX.permissionDeniedAccessibility()
        }
        let resolved = resolveWindow(args: args)
        if let error = resolved.error { return error }
        guard let target = resolved.target, let axWindow = axWindow(args: args, target: target) else {
            return .failure(code: "target_not_found", message: "Window was not found.")
        }
        let result = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, minimized as CFTypeRef)
        if result == .success {
            return .success(["minimized": minimized, "strategy": "Accessibility"])
        }
        return .failure(code: "capability_unavailable.window_minimize", message: "Window did not accept AXMinimized.", details: ["axError": String(describing: result)])
    }

    static func maximize(args: PBWArguments, fullScreen: Bool) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return PBWAX.permissionDeniedAccessibility()
        }
        let resolved = resolveWindow(args: args)
        if let error = resolved.error { return error }
        guard let target = resolved.target, let axWindow = axWindow(args: args, target: target) else {
            return .failure(code: "target_not_found", message: "Window was not found.")
        }
        let result = AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, fullScreen as CFTypeRef)
        if result == .success {
            return .success(["fullscreen": fullScreen, "strategy": "Accessibility"])
        }
        return .failure(code: "capability_unavailable.window_fullscreen", message: "Window did not accept AXFullScreen.", details: ["axError": String(describing: result)])
    }

    static func close(args: PBWArguments) -> PBWExecutionResult {
        guard PBWNative.accessibilityAllowed() else {
            return PBWAX.permissionDeniedAccessibility()
        }
        let resolved = resolveWindow(args: args)
        if let error = resolved.error { return error }
        guard let target = resolved.target, let axWindow = axWindow(args: args, target: target) else {
            return .failure(code: "target_not_found", message: "Window was not found.")
        }
        var closeButton: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
           let closeButton
        {
            let result = AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
            if result == .success {
                return .success(["closed": true, "strategy": "Accessibility AXCloseButton"])
            }
        }
        let result = AXUIElementPerformAction(axWindow, kAXPressAction as CFString)
        if result == .success {
            return .success(["closed": true, "strategy": "Accessibility AXPress"])
        }
        return .failure(code: "capability_unavailable.window_close", message: "Window did not expose a public close action.", details: ["axError": String(describing: result)])
    }

    private static func resolveWindow(args: PBWArguments) -> (target: [String: Any]?, error: PBWExecutionResult?) {
        let windows = PBWNative.windowList()
        if let windowID = args.int("window-id") ?? args.int("windowId") ?? args.int("handle") {
            return (windows.first { ($0["windowId"] as? Int) == windowID || ($0["handle"] as? Int) == windowID }, nil)
        }
        if let title = args.string("title") ?? args.positionals.first {
            let matches = windows.filter { ($0["title"] as? String ?? "").localizedCaseInsensitiveContains(title) }
            if matches.count > 1 {
                return (nil, .failure(
                    code: "target_ambiguous",
                    message: "Window title matched multiple windows.",
                    details: [
                        "title": title,
                        "matches": matches.map { ["id": $0["id"] ?? "", "title": $0["title"] ?? "", "app": $0["app"] ?? "", "windowId": $0["windowId"] ?? 0] },
                    ],
                ))
            }
            return (matches.first, nil)
        }
        return (windows.first, nil)
    }

    private static func axWindow(args _: PBWArguments, target: [String: Any]) -> AXUIElement? {
        guard let pid = target["ownerPID"] as? Int else { return nil }
        let app = AXUIElementCreateApplication(pid_t(pid))
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }
        let targetID = target["windowId"] as? Int
        let targetTitle = target["title"] as? String ?? ""
        for window in windows {
            if let targetID {
                var numberValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberValue) == .success,
                   let number = numberValue as? Int, number == targetID
                {
                    return window
                }
            }
            var titleValue: CFTypeRef?
            if !targetTitle.isEmpty,
               AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               String(describing: titleValue ?? "" as CFTypeRef) == targetTitle
            {
                return window
            }
        }
        return windows.first
    }
}
