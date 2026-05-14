import Foundation

public struct PBMCLI {
    private let runtime: PBMRuntime

    public init(runtime: PBMRuntime = PBMRuntime()) {
        self.runtime = runtime
    }

    public func run(arguments: [String]) -> PBMExecutionResult {
        if arguments.first == "--version" || arguments.first == "-V" || arguments.first == "version" {
            return .success([
                "name": "pbm",
                "version": pbmVersion,
            ])
        }
        if arguments.first == "__daemon-run" {
            let exitCode = PBMDaemon.runForegroundServer()
            return PBMExecutionResult(envelope: [:], exitCode: exitCode, output: nil)
        }
        return runtime.runCLI(arguments: arguments)
    }
}

public struct PBMRuntime {
    public init() {}

    public func runCLI(arguments: [String]) -> PBMExecutionResult {
        if arguments.isEmpty {
            return .success(PBMCommandRegistry.helpData())
        }
        guard let (spec, consumed) = PBMCommandRegistry.findCLI(arguments: arguments) else {
            return .failure(
                code: "invalid_argument.unknown_command",
                message: "Unknown command.",
                details: ["arguments": arguments],
                exitCode: 2,
            )
        }
        let parsed = PBMArguments.parse(Array(arguments.dropFirst(consumed)))
        if spec.name == "mcp" {
            let exitCode = PBMMCPServer(runtime: self).run()
            return PBMExecutionResult(envelope: [:], exitCode: exitCode, output: nil)
        }
        return run(spec: spec, args: parsed)
    }

    public func runTool(name: String, arguments: [String: Any]) -> PBMExecutionResult {
        guard let spec = PBMCommandRegistry.byName(name) else {
            return .failure(code: "invalid_argument.unknown_tool", message: "Unknown MCP tool.", details: ["name": name], exitCode: 2)
        }
        return run(spec: spec, args: PBMArguments(options: arguments, positionals: []))
    }

    private func run(spec: PBMCommandSpec, args: PBMArguments) -> PBMExecutionResult {
        let config = PBMConfig.load()
        guard config.policyAllows(toolName: spec.name) else {
            return .failure(
                code: "tool_denied",
                message: "Tool is denied by policy.",
                details: ["tool": spec.name],
                exitCode: 1,
            )
        }
        if spec.destructive, config.destructiveConfirmationRequired(), !args.bool("confirm"), !args.bool("yes") {
            return .failure(
                code: "confirmation_required",
                message: "This destructive command requires --confirm because safety.confirmDestructiveActions is true.",
                details: ["tool": spec.name],
                exitCode: 2,
            )
        }
        switch spec.name {
        case "help":
            return .success(PBMCommandRegistry.helpData())
        case "observe.see":
            return PBMSnapshotStore().create(config: snapshotConfig(base: config, args: args), includeImage: args.bool("image"))
        case "observe.image":
            return PBMObserve.image(args: args)
        case "observe.capture.live.start":
            return PBMObserve.liveStart(args: args)
        case "observe.capture.live.frame":
            return PBMObserve.liveFrame(args: args)
        case "observe.capture.live.status":
            return PBMObserve.liveStatus(args: args)
        case "observe.capture.live.stop":
            return PBMObserve.liveStop(args: args)
        case "observe.capture.video.start":
            return PBMObserve.videoStart(args: args)
        case "observe.capture.video.status":
            return PBMObserve.videoStatus(args: args)
        case "observe.capture.video.stop":
            return PBMObserve.videoStop(args: args)
        case "input.click":
            return PBMInput.click(args: args)
        case "input.type":
            return PBMInput.type(args: args)
        case "input.press":
            return PBMInput.press(args: args)
        case "input.hotkey":
            return PBMInput.hotkey(args: args)
        case "input.scroll":
            return PBMInput.scroll(args: args)
        case "input.drag":
            return PBMInput.drag(args: args)
        case "input.move":
            return PBMInput.move(args: args)
        case "semantic.set-value":
            if args.bool("focused") {
                return PBMAX.setFocusedValue(args.string("value") ?? args.string("text") ?? "")
            }
            if let text = args.string("value") {
                let click = PBMInput.click(args: args)
                if click.envelope["ok"] as? Bool == true {
                    return PBMInput.type(args: PBMArguments(options: ["text": text], positionals: []))
                }
                return click
            }
            return .failure(code: "invalid_argument.missing_value", message: "--value is required for targeted set-value. Use --focused --text only for the focused element.", exitCode: 2)
        case "semantic.perform-action":
            if args.bool("focused") {
                return PBMAX.performFocusedAction(args.string("action") ?? "AXPress")
            }
            return PBMInput.click(args: args)
        case "window.list":
            return PBMWindow.list()
        case "window.focus":
            return PBMWindow.focus(args: args)
        case "window.move":
            return PBMWindow.setBounds(args: args, moveOnly: true)
        case "window.resize":
            return PBMWindow.setBounds(args: args, resizeOnly: true)
        case "window.set-bounds":
            return PBMWindow.setBounds(args: args)
        case "window.minimize":
            return PBMWindow.minimize(args: args, minimized: true)
        case "window.maximize":
            return PBMWindow.maximize(args: args, fullScreen: true)
        case "window.restore":
            if args.bool("fullscreen") {
                return PBMWindow.maximize(args: args, fullScreen: false)
            }
            return PBMWindow.minimize(args: args, minimized: false)
        case "window.close":
            return PBMWindow.close(args: args)
        case "app.list":
            return PBMApp.list()
        case "app.launch":
            return PBMApp.launch(args: args)
        case "app.focus", "app.switch":
            return PBMApp.focus(args: args)
        case "app.quit":
            return PBMApp.quit(args: args)
        case "app.hide":
            return PBMApp.hide(args: args, hidden: true)
        case "app.unhide":
            return PBMApp.hide(args: args, hidden: false)
        case "app.relaunch":
            return PBMApp.relaunch(args: args)
        case "app.open":
            return PBMApp.open(args: args)
        case "menu.list":
            return PBMAX.focusedAppMenuItems()
        case "menu.click":
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBMAX.clickMenuItem(title: title)
        case "dialog.list":
            return PBMAX.dialogs()
        case "dialog.click":
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBMAX.clickMenuItem(title: title)
        case "dialog.input":
            return PBMAX.setFocusedValue(args.string("text") ?? args.string("value") ?? "")
        case "dialog.dismiss":
            return PBMAX.performFocusedAction("AXCancel")
        case "dialog.file.choose", "dialog.file.save", "dialog.file.open":
            return .failure(
                code: "capability_unavailable.file_dialog_specialization",
                message: "File dialogs are represented through generic dialog/input/menu actions in v1 direct mode.",
                details: ["tool": spec.name, "publicAPI": "AXUIElement best-effort only"],
            )
        case "clipboard.get":
            return PBMClipboard.get(args: args)
        case "clipboard.set":
            return PBMClipboard.set(args: args)
        case "clipboard.clear":
            return PBMClipboard.clear()
        case "clipboard.paste":
            return PBMInput.paste()
        case let name where name.hasPrefix("dock."):
            return PBMDockCommands.handle(command: name, args: args)
        case let name where name.hasPrefix("menubar."):
            if name == "menubar.list" {
                return PBMAX.focusedAppMenuItems()
            }
            if name == "menubar.close" {
                return PBMInput.press(args: PBMArguments(options: ["key": "escape"], positionals: []))
            }
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBMAX.clickMenuItem(title: title)
        case let name where name.hasPrefix("space."):
            return PBMSpace.handle(command: name, args: args)
        case "snapshot.list":
            return PBMSnapshotStore().list()
        case "snapshot.show":
            return PBMSnapshotStore().show(id: args.string("id") ?? args.positionals.first)
        case "snapshot.inspect":
            return PBMSnapshotStore().inspect(args: args)
        case "snapshot.clean":
            return PBMSnapshotStore().clean(keep: args.int("keep") ?? 20)
        case "snapshot.export":
            return PBMSnapshotStore().export(id: args.string("id") ?? args.string("snapshot"), path: args.string("path"))
        case let name where name.hasPrefix("overlay."):
            return PBMOverlay.handle(command: name)
        case let name where name.hasPrefix("daemon."):
            return PBMDaemon.handle(command: name, args: args)
        case let name where name.hasPrefix("bridge."):
            return PBMBridge.handle(command: name, args: args)
        case let name where name.hasPrefix("config."):
            return PBMConfigCommands.handle(command: name, args: args)
        case "diagnostics.doctor":
            return PBMDiagnostics.doctor()
        default:
            return .failure(code: "invalid_argument.unimplemented_command", message: "Command is registered but not implemented.", details: ["name": spec.name], exitCode: 2)
        }
    }

    private func snapshotConfig(base: PBMConfig, args: PBMArguments) -> PBMConfig {
        var config = base
        if let scope = args.string("scope") {
            config.set(value: scope, at: "snapshot.scope")
        }
        if let bundleID = args.string("bundle-id") ?? args.string("bundleId") ?? args.string("app-id") ?? args.string("appId") {
            config.set(value: bundleID, at: "snapshot.bundleIdentifier")
        }
        if let pid = args.int("pid") {
            config.set(value: pid, at: "snapshot.pid")
        }
        if let appName = args.string("app") ?? args.string("name") {
            config.set(value: appName, at: "snapshot.appName")
        }
        if let maxDepth = args.int("max-depth") ?? args.int("maxDepth") {
            config.set(value: maxDepth, at: "snapshot.maxDepth")
        }
        if let maxElementCount = args.int("max-elements") ?? args.int("maxElementCount") {
            config.set(value: maxElementCount, at: "snapshot.maxElementCount")
        }
        if let maxChildren = args.int("max-children") ?? args.int("maxChildren") ?? args.int("max-children-per-node") {
            config.set(value: maxChildren, at: "snapshot.maxChildrenPerNode")
        }
        if let timeout = args.double("timeout") ?? args.double("timeout-seconds") ?? args.double("timeoutSeconds") {
            config.set(value: timeout, at: "snapshot.timeoutSeconds")
        }
        if let windowID = args.int("window-id") ?? args.int("windowId") ?? args.int("handle") {
            config.set(value: windowID, at: "snapshot.windowId")
        }
        if let windowTitle = args.string("window-title") ?? args.string("windowTitle") ?? args.string("title") {
            config.set(value: windowTitle, at: "snapshot.windowTitle")
        }
        if let windowIndex = args.int("window-index") ?? args.int("windowIndex") {
            config.set(value: windowIndex, at: "snapshot.windowIndex")
        }
        if args.options.keys.contains("alternative-children") {
            config.set(value: args.bool("alternative-children"), at: "snapshot.includeAlternativeChildren")
        }
        if args.options.keys.contains("application-windows") {
            config.set(value: args.bool("application-windows"), at: "snapshot.includeApplicationWindows")
        }
        if args.options.keys.contains("focused-element") {
            config.set(value: args.bool("focused-element"), at: "snapshot.includeFocusedElement")
        }
        if args.bool("web-focus-fallback") {
            config.set(value: true, at: "snapshot.webFocusFallback")
        }
        return config
    }
}
