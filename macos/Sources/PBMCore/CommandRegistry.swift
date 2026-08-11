import Foundation

public struct PBMCommandSpec: Sendable {
    public let name: String
    public let cliPaths: [[String]]
    public let summary: String
    public let destructive: Bool

    public init(_ name: String, _ cliPaths: [[String]], _ summary: String, destructive: Bool = false) {
        self.name = name
        self.cliPaths = cliPaths
        self.summary = summary
        self.destructive = destructive
    }

    public var group: String {
        String(name.split(separator: ".").first ?? "")
    }
}

public enum PBMCommandRegistry {
    public static let commands: [PBMCommandSpec] = [
        .init("help", [["help"], ["--help"], ["-h"]], "Show command help."),
        .init("mcp", [["mcp"]], "Run the MCP stdio server."),

        .init("observe.see", [["observe", "see"], ["see"]], "Create a macOS snapshot and return observed UI metadata."),
        .init("observe.image", [["observe", "image"], ["image"]], "Capture a display or window image."),
        .init("observe.capture.live.start", [["observe", "capture", "live", "start"], ["capture", "live", "start"]], "Start a local live capture session."),
        .init("observe.capture.live.frame", [["observe", "capture", "live", "frame"], ["capture", "live", "frame"]], "Capture a frame from a live session."),
        .init("observe.capture.live.status", [["observe", "capture", "live", "status"], ["capture", "live", "status"]], "Inspect live capture sessions."),
        .init("observe.capture.live.stop", [["observe", "capture", "live", "stop"], ["capture", "live", "stop"]], "Stop a live capture session."),
        .init("observe.capture.video.start", [["observe", "capture", "video", "start"], ["capture", "video", "start"]], "Start or run a ScreenCaptureKit video capture."),
        .init("observe.capture.video.status", [["observe", "capture", "video", "status"], ["capture", "video", "status"]], "Inspect video capture sessions."),
        .init("observe.capture.video.stop", [["observe", "capture", "video", "stop"], ["capture", "video", "stop"]], "Stop a video capture session."),

        .init("input.click", [["input", "click"], ["click"]], "Click a target or coordinate."),
        .init("input.type", [["input", "type"], ["type"]], "Type deterministic text."),
        .init("input.press", [["input", "press"], ["press"]], "Press a keyboard key."),
        .init("input.hotkey", [["input", "hotkey"], ["hotkey"]], "Press a keyboard shortcut."),
        .init("input.scroll", [["input", "scroll"], ["scroll"]], "Scroll at a coordinate or current pointer."),
        .init("input.drag", [["input", "drag"], ["drag"]], "Drag from one coordinate to another."),
        .init("input.move", [["input", "move"], ["move"]], "Move the pointer."),

        .init("semantic.set-value", [["semantic", "set-value"], ["set-value"]], "Set a value using Accessibility or synthetic input."),
        .init("semantic.perform-action", [["semantic", "perform-action"], ["perform-action"]], "Perform an AX action or deterministic fallback."),

        .init("window.list", [["window", "list"]], "List visible windows."),
        .init("window.focus", [["window", "focus"]], "Focus a window."),
        .init("window.move", [["window", "move"]], "Move a window."),
        .init("window.resize", [["window", "resize"]], "Resize a window."),
        .init("window.set-bounds", [["window", "set-bounds"]], "Set window bounds."),
        .init("window.minimize", [["window", "minimize"]], "Minimize a window."),
        .init("window.maximize", [["window", "maximize"]], "Maximize or zoom a window."),
        .init("window.restore", [["window", "restore"]], "Restore a minimized/fullscreen window."),
        .init("window.close", [["window", "close"]], "Close a window.", destructive: true),

        .init("app.list", [["app", "list"]], "List running applications."),
        .init("app.launch", [["app", "launch"]], "Launch an application."),
        .init("app.focus", [["app", "focus"]], "Focus an application."),
        .init("app.switch", [["app", "switch"]], "Switch to an application."),
        .init("app.quit", [["app", "quit"]], "Quit an application.", destructive: true),
        .init("app.hide", [["app", "hide"]], "Hide an application."),
        .init("app.unhide", [["app", "unhide"]], "Unhide an application."),
        .init("app.relaunch", [["app", "relaunch"]], "Quit and relaunch an application.", destructive: true),
        .init("app.open", [["app", "open"], ["open"]], "Open a file or URL."),

        .init("menu.list", [["menu", "list"]], "List focused app menus."),
        .init("menu.click", [["menu", "click"]], "Click a menu item."),

        .init("dialog.list", [["dialog", "list"]], "List dialogs and sheets."),
        .init("dialog.click", [["dialog", "click"]], "Click a dialog button."),
        .init("dialog.input", [["dialog", "input"]], "Input text into a dialog field."),
        .init("dialog.dismiss", [["dialog", "dismiss"]], "Dismiss a dialog.", destructive: true),
        .init("dialog.file.choose", [["dialog", "file", "choose"]], "Choose a file in an open/save dialog."),
        .init("dialog.file.save", [["dialog", "file", "save"]], "Save through a file dialog."),
        .init("dialog.file.open", [["dialog", "file", "open"]], "Open through a file dialog."),

        .init("clipboard.get", [["clipboard", "get"]], "Read the clipboard."),
        .init("clipboard.set", [["clipboard", "set"]], "Set the clipboard."),
        .init("clipboard.clear", [["clipboard", "clear"]], "Clear the clipboard.", destructive: true),
        .init("clipboard.paste", [["clipboard", "paste"], ["paste"]], "Paste clipboard contents using Cmd+V."),

        .init("dock.list", [["dock", "list"]], "List public Dock-adjacent state."),
        .init("dock.click", [["dock", "click"]], "Click a Dock item."),
        .init("dock.right-click", [["dock", "right-click"]], "Right-click a Dock item."),
        .init("dock.launch", [["dock", "launch"]], "Launch an app by Dock-style target."),
        .init("dock.hide", [["dock", "hide"]], "Hide the Dock.", destructive: true),
        .init("dock.show", [["dock", "show"]], "Show the Dock.", destructive: true),
        .init("dock.autohide", [["dock", "autohide"]], "Change Dock autohide.", destructive: true),
        .init("dock.status", [["dock", "status"]], "Report Dock capability status."),

        .init("menubar.list", [["menubar", "list"]], "List menu bar items."),
        .init("menubar.click", [["menubar", "click"]], "Click a menu bar item."),
        .init("menubar.open", [["menubar", "open"]], "Open a menu bar item."),
        .init("menubar.close", [["menubar", "close"]], "Close an open menu bar item."),

        .init("space.list", [["space", "list"]], "List Spaces where public APIs allow."),
        .init("space.current", [["space", "current"]], "Return current Space metadata where available."),
        .init("space.switch", [["space", "switch"]], "Switch Spaces using configured keyboard shortcuts."),
        .init("space.move-window", [["space", "move-window"]], "Move a window to another Space where available."),

        .init("snapshot.list", [["snapshot", "list"]], "List snapshots."),
        .init("snapshot.show", [["snapshot", "show"]], "Show a stored snapshot."),
        .init("snapshot.inspect", [["snapshot", "inspect"]], "Inspect a snapshot target."),
        .init("snapshot.clean", [["snapshot", "clean"]], "Delete old snapshots."),
        .init("snapshot.export", [["snapshot", "export"]], "Export a snapshot."),

        .init("overlay.show", [["overlay", "show"]], "Show a transparent ID overlay."),
        .init("overlay.hide", [["overlay", "hide"]], "Hide a transparent ID overlay."),
        .init("overlay.status", [["overlay", "status"]], "Report overlay status."),

        .init("daemon.start", [["daemon", "start"]], "Start the local-only Unix socket daemon."),
        .init("daemon.stop", [["daemon", "stop"]], "Stop the daemon."),
        .init("daemon.restart", [["daemon", "restart"]], "Restart the daemon."),
        .init("daemon.status", [["daemon", "status"]], "Report daemon status."),
        .init("daemon.logs", [["daemon", "logs"]], "Return daemon logs."),
        .init("daemon.install", [["daemon", "install"]], "Install a user LaunchAgent plist."),
        .init("daemon.uninstall", [["daemon", "uninstall"]], "Uninstall the user LaunchAgent plist.", destructive: true),

        .init("bridge.install", [["bridge", "install"]], "Install the permission-bearing Bridge app."),
        .init("bridge.open", [["bridge", "open"]], "Open Bridge or permission settings."),
        .init("bridge.status", [["bridge", "status"]], "Report Bridge status."),
        .init("bridge.reset-permissions", [["bridge", "reset-permissions"]], "Explain Bridge permission reset steps."),
        .init("bridge.uninstall", [["bridge", "uninstall"]], "Uninstall Bridge.", destructive: true),

        .init("config.init", [["config", "init"]], "Write a default config."),
        .init("config.show", [["config", "show"]], "Show effective config."),
        .init("config.validate", [["config", "validate"]], "Validate config."),
        .init("config.get", [["config", "get"]], "Get a config path."),
        .init("config.set", [["config", "set"]], "Set a config path."),

        .init("diagnostics.doctor", [["diagnostics", "doctor"], ["doctor"]], "Run local diagnostics."),
    ]

    public static func findCLI(arguments: [String]) -> (PBMCommandSpec, Int)? {
        var best: (PBMCommandSpec, Int)?
        for spec in commands {
            for path in spec.cliPaths {
                guard arguments.count >= path.count else { continue }
                let candidate = Array(arguments.prefix(path.count))
                if candidate == path, best == nil || path.count > best!.1 {
                    best = (spec, path.count)
                }
            }
        }
        return best
    }

    public static func byName(_ name: String) -> PBMCommandSpec? {
        commands.first { $0.name == name }
    }

    public static func helpData() -> [String: Any] {
        let grouped = Dictionary(grouping: commands.filter { $0.name != "help" && $0.name != "mcp" }, by: { $0.group })
        var groups: [[String: Any]] = []
        for group in grouped.keys.sorted() {
            groups.append([
                "name": group,
                "commands": (grouped[group] ?? []).map { spec in
                    [
                        "name": spec.name,
                        "cli": spec.cliPaths.first?.joined(separator: " ") ?? spec.name,
                        "summary": spec.summary,
                        "destructive": spec.destructive,
                    ]
                },
            ])
        }
        return [
            "command": "pbm",
            "schemaVersion": pbmStableSchemaVersion,
            "groups": groups,
            "mcpToolNames": commands.filter { $0.name != "help" && $0.name != "mcp" }.map(\.name).sorted(),
        ]
    }
}

public struct PBMArguments {
    public let options: [String: Any]
    public let positionals: [String]

    public init(options: [String: Any], positionals: [String]) {
        self.options = options
        self.positionals = positionals
    }

    public static func parse(_ args: [String]) -> PBMArguments {
        var options: [String: Any] = [:]
        var positionals: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let raw = String(arg.dropFirst(2))
                if let eq = raw.firstIndex(of: "=") {
                    let key = String(raw[..<eq])
                    let value = String(raw[raw.index(after: eq)...])
                    options[key] = coerce(value)
                } else if raw.hasPrefix("no-") {
                    options[String(raw.dropFirst(3))] = false
                } else if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                    options[raw] = coerce(args[index + 1])
                    index += 1
                } else {
                    options[raw] = true
                }
            } else if arg.hasPrefix("-"), arg.count > 1 {
                options[String(arg.dropFirst())] = true
            } else {
                positionals.append(arg)
            }
            index += 1
        }
        return PBMArguments(options: options, positionals: positionals)
    }

    public func merged(with object: [String: Any]) -> PBMArguments {
        var merged = options
        for (key, value) in object {
            merged[key] = value
        }
        return PBMArguments(options: merged, positionals: positionals)
    }

    public func string(_ key: String, fallback: String? = nil) -> String? {
        options.string(key) ?? fallback
    }

    public func bool(_ key: String, fallback: Bool = false) -> Bool {
        options.bool(key) ?? fallback
    }

    public func int(_ key: String) -> Int? {
        options.int(key)
    }

    public func double(_ key: String) -> Double? {
        options.double(key)
    }

    private static func coerce(_ value: String) -> Any {
        let lower = value.lowercased()
        if ["true", "yes", "on"].contains(lower) {
            return true
        }
        if ["false", "no", "off"].contains(lower) {
            return false
        }
        if let int = Int(value) {
            return int
        }
        if let double = Double(value), value.contains(".") {
            return double
        }
        return value
    }
}
