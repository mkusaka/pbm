import AppKit
import Foundation

enum PBWCapability {
    static func unavailable(_ code: String, _ message: String, details: [String: Any] = [:]) -> PBWExecutionResult {
        .failure(code: "capability_unavailable.\(code)", message: message, details: details)
    }
}

enum PBWDockCommands {
    static func handle(command: String, args: PBWArguments) -> PBWExecutionResult {
        switch command {
        case "dock.list":
            .success(["dock": PBWDock.publicDockItems(), "source": "NSWorkspace.runningApplications"])
        case "dock.launch":
            PBWApp.launch(args: args)
        case "dock.status":
            .success([
                "publicAPI": false,
                "runningAppsAvailable": true,
                "pinnedItems": "capability_unavailable.dock_pinned_items_public_api",
                "autohideMutation": "capability_unavailable.dock_autohide_public_api",
            ])
        case "dock.click", "dock.right-click":
            PBWCapability.unavailable("dock_click_public_api", "macOS does not provide a stable public API for clicking arbitrary Dock items from a CLI.", details: ["alternative": "Use app.launch/app.focus for application targets."])
        case "dock.hide", "dock.show", "dock.autohide":
            PBWCapability.unavailable("dock_mutation_public_api", "Dock visibility/autohide changes are not implemented without private APIs or user-owned scripts.", details: ["destructive": true])
        default:
            .failure(code: "invalid_argument.dock_command", message: "Unknown Dock command.", exitCode: 2)
        }
    }
}

enum PBWSpace {
    static func handle(command: String, args: PBWArguments) -> PBWExecutionResult {
        switch command {
        case "space.switch":
            guard let index = args.int("index") ?? args.int("space") else {
                return .failure(code: "invalid_argument.missing_space", message: "--index is required.", exitCode: 2)
            }
            guard index >= 1, index <= 9, let key = PBWInput.keyCode(String(index)) else {
                return .failure(code: "invalid_argument.space_index", message: "Only Space indexes 1-9 can be requested through keyboard shortcuts.", exitCode: 2)
            }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
            down?.flags = .maskControl
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
            up?.flags = .maskControl
            up?.post(tap: .cghidEventTap)
            return .success(["requestedIndex": index, "strategy": "control-number-keyboard-shortcut", "requiresUserShortcut": true])
        case "space.move-window":
            return PBWCapability.unavailable("space_move", "Moving a window to a Space is not exposed through stable public macOS APIs.", details: ["publicAPI": false])
        case "space.list", "space.current":
            return PBWCapability.unavailable("space_list", "Enumerating Spaces/current Space is not exposed through stable public macOS APIs.", details: ["publicAPI": false])
        default:
            return .failure(code: "invalid_argument.space_command", message: "Unknown Space command.", exitCode: 2)
        }
    }
}

enum PBWOverlay {
    static func handle(command: String) -> PBWExecutionResult {
        switch command {
        case "overlay.status":
            .success(["visible": false, "mode": "direct", "capability": "capability_unavailable.overlay_requires_app_runtime"])
        case "overlay.show", "overlay.hide":
            PBWCapability.unavailable("overlay_requires_app_runtime", "A persistent transparent overlay requires a Bridge/AppKit app runtime; direct CLI mode does not fake it.")
        default:
            .failure(code: "invalid_argument.overlay_command", message: "Unknown overlay command.", exitCode: 2)
        }
    }
}

enum PBWConfigCommands {
    static func handle(command: String, args: PBWArguments) -> PBWExecutionResult {
        switch command {
        case "config.init":
            let overwrite = args.bool("force")
            if FileManager.default.fileExists(atPath: PBWPaths.config.path), !overwrite {
                return .success(["created": false, "path": PBWPaths.config.path, "reason": "already_exists"])
            }
            do {
                try PBWConfig().save()
                return .success(["created": true, "path": PBWPaths.config.path])
            } catch {
                return .failure(code: "internal.config_init", message: error.localizedDescription)
            }
        case "config.show":
            return .success(PBWConfig.load().raw)
        case "config.validate":
            return .success(PBWConfig.load().validate())
        case "config.get":
            guard let path = args.string("path") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_path", message: "--path is required.", exitCode: 2)
            }
            return .success(["path": path, "value": PBWConfig.load().value(at: path) ?? NSNull()])
        case "config.set":
            guard let path = args.string("path") ?? args.positionals.first,
                  let value = args.string("value") ?? args.positionals.dropFirst().first
            else {
                return .failure(code: "invalid_argument.config_set", message: "--path and --value are required.", exitCode: 2)
            }
            do {
                var config = PBWConfig.load()
                config.set(value: coerce(value), at: path)
                try config.save()
                return .success(["path": path, "value": config.value(at: path) ?? NSNull()])
            } catch {
                return .failure(code: "internal.config_set", message: error.localizedDescription)
            }
        default:
            return .failure(code: "invalid_argument.config_command", message: "Unknown config command.", exitCode: 2)
        }
    }

    private static func coerce(_ value: String) -> Any {
        if ["true", "yes", "on"].contains(value.lowercased()) { return true }
        if ["false", "no", "off"].contains(value.lowercased()) { return false }
        if let int = Int(value) { return int }
        if let double = Double(value), value.contains(".") { return double }
        return value
    }
}

enum PBWDiagnostics {
    static func doctor() -> PBWExecutionResult {
        let config = PBWConfig.load()
        let validation = config.validate()
        let swiftVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return .success([
            "platform": "macos",
            "os": swiftVersion,
            "schemaVersion": pbwStableSchemaVersion,
            "paths": [
                "home": PBWPaths.home.path,
                "config": PBWPaths.config.path,
                "snapshots": PBWPaths.snapshots.path,
                "captures": PBWPaths.captures.path,
                "daemonSocket": PBWPaths.daemonSocket.path,
            ],
            "permissions": [
                "accessibility": PBWNative.accessibilityAllowed(),
                "screenRecording": PBWNative.screenRecordingAllowed(),
                "postEvent": PBWNative.postEventAllowed(),
            ],
            "config": validation,
            "capabilities": [
                "captureImage": PBWNative.screenRecordingAllowed(),
                "accessibilityActions": PBWNative.accessibilityAllowed(),
                "dockPinnedItems": "capability_unavailable.dock_pinned_items_public_api",
                "spacesEnumeration": "capability_unavailable.space_list",
                "bridge": "capability_unavailable.bridge_bundle",
                "overlayDirectMode": "capability_unavailable.overlay_requires_app_runtime",
            ],
            "network": [
                "remotePublicListener": false,
                "transport": "stdio or same-user unix-domain-socket",
            ],
            "ai": [
                "enabled": false,
                "providers": [],
            ],
        ])
    }
}
