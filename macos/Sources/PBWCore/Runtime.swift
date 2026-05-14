import Foundation

public struct PBWCLI {
    private let runtime: PBWRuntime

    public init(runtime: PBWRuntime = PBWRuntime()) {
        self.runtime = runtime
    }

    public func run(arguments: [String]) -> PBWExecutionResult {
        if arguments.first == "__daemon-run" {
            let exitCode = PBWDaemon.runForegroundServer()
            return PBWExecutionResult(envelope: [:], exitCode: exitCode, output: nil)
        }
        return runtime.runCLI(arguments: arguments)
    }
}

public struct PBWRuntime {
    public init() {}

    public func runCLI(arguments: [String]) -> PBWExecutionResult {
        if arguments.isEmpty {
            return .success(PBWCommandRegistry.helpData())
        }
        guard let (spec, consumed) = PBWCommandRegistry.findCLI(arguments: arguments) else {
            return .failure(
                code: "invalid_argument.unknown_command",
                message: "Unknown command.",
                details: ["arguments": arguments],
                exitCode: 2,
            )
        }
        let parsed = PBWArguments.parse(Array(arguments.dropFirst(consumed)))
        if spec.name == "mcp" {
            let exitCode = PBWMCPServer(runtime: self).run()
            return PBWExecutionResult(envelope: [:], exitCode: exitCode, output: nil)
        }
        return run(spec: spec, args: parsed)
    }

    public func runTool(name: String, arguments: [String: Any]) -> PBWExecutionResult {
        guard let spec = PBWCommandRegistry.byName(name) else {
            return .failure(code: "invalid_argument.unknown_tool", message: "Unknown MCP tool.", details: ["name": name], exitCode: 2)
        }
        return run(spec: spec, args: PBWArguments(options: arguments, positionals: []))
    }

    private func run(spec: PBWCommandSpec, args: PBWArguments) -> PBWExecutionResult {
        let config = PBWConfig.load()
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
            return .success(PBWCommandRegistry.helpData())
        case "observe.see":
            return PBWSnapshotStore().create(config: config, includeImage: args.bool("image"))
        case "observe.image":
            return PBWObserve.image(args: args)
        case "observe.capture.live.start":
            return PBWObserve.liveStart(args: args)
        case "observe.capture.live.frame":
            return PBWObserve.liveFrame(args: args)
        case "observe.capture.live.status":
            return PBWObserve.liveStatus(args: args)
        case "observe.capture.live.stop":
            return PBWObserve.liveStop(args: args)
        case "observe.capture.video.start":
            return PBWObserve.videoStart(args: args)
        case "observe.capture.video.status":
            return PBWObserve.videoStatus(args: args)
        case "observe.capture.video.stop":
            return PBWObserve.videoStop(args: args)
        case "input.click":
            return PBWInput.click(args: args)
        case "input.type":
            return PBWInput.type(args: args)
        case "input.press":
            return PBWInput.press(args: args)
        case "input.hotkey":
            return PBWInput.hotkey(args: args)
        case "input.scroll":
            return PBWInput.scroll(args: args)
        case "input.drag":
            return PBWInput.drag(args: args)
        case "input.move":
            return PBWInput.move(args: args)
        case "semantic.set-value":
            if args.bool("focused") {
                return PBWAX.setFocusedValue(args.string("value") ?? args.string("text") ?? "")
            }
            if let text = args.string("value") ?? args.string("text") {
                let click = PBWInput.click(args: args)
                if click.envelope["ok"] as? Bool == true {
                    return PBWInput.type(args: PBWArguments(options: ["text": text], positionals: []))
                }
                return click
            }
            return .failure(code: "invalid_argument.missing_value", message: "--value or --text is required.", exitCode: 2)
        case "semantic.perform-action":
            if args.bool("focused") {
                return PBWAX.performFocusedAction(args.string("action") ?? "AXPress")
            }
            return PBWInput.click(args: args)
        case "window.list":
            return PBWWindow.list()
        case "window.focus":
            return PBWWindow.focus(args: args)
        case "window.move":
            return PBWWindow.setBounds(args: args, moveOnly: true)
        case "window.resize":
            return PBWWindow.setBounds(args: args, resizeOnly: true)
        case "window.set-bounds":
            return PBWWindow.setBounds(args: args)
        case "window.minimize":
            return PBWWindow.minimize(args: args, minimized: true)
        case "window.maximize":
            return PBWWindow.maximize(args: args, fullScreen: true)
        case "window.restore":
            if args.bool("fullscreen") {
                return PBWWindow.maximize(args: args, fullScreen: false)
            }
            return PBWWindow.minimize(args: args, minimized: false)
        case "window.close":
            return PBWWindow.close(args: args)
        case "app.list":
            return PBWApp.list()
        case "app.launch":
            return PBWApp.launch(args: args)
        case "app.focus", "app.switch":
            return PBWApp.focus(args: args)
        case "app.quit":
            return PBWApp.quit(args: args)
        case "app.hide":
            return PBWApp.hide(args: args, hidden: true)
        case "app.unhide":
            return PBWApp.hide(args: args, hidden: false)
        case "app.relaunch":
            return PBWApp.relaunch(args: args)
        case "app.open":
            return PBWApp.open(args: args)
        case "menu.list":
            return PBWAX.focusedAppMenuItems()
        case "menu.click":
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBWAX.clickMenuItem(title: title)
        case "dialog.list":
            return PBWAX.dialogs()
        case "dialog.click":
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBWAX.clickMenuItem(title: title)
        case "dialog.input":
            return PBWAX.setFocusedValue(args.string("text") ?? args.string("value") ?? "")
        case "dialog.dismiss":
            return PBWAX.performFocusedAction("AXCancel")
        case "dialog.file.choose", "dialog.file.save", "dialog.file.open":
            return .failure(
                code: "capability_unavailable.file_dialog_specialization",
                message: "File dialogs are represented through generic dialog/input/menu actions in v1 direct mode.",
                details: ["tool": spec.name, "publicAPI": "AXUIElement best-effort only"],
            )
        case "clipboard.get":
            return PBWClipboard.get()
        case "clipboard.set":
            return PBWClipboard.set(args: args)
        case "clipboard.clear":
            return PBWClipboard.clear()
        case "clipboard.paste":
            return PBWInput.paste()
        case let name where name.hasPrefix("dock."):
            return PBWDockCommands.handle(command: name, args: args)
        case let name where name.hasPrefix("menubar."):
            if name == "menubar.list" {
                return PBWAX.focusedAppMenuItems()
            }
            if name == "menubar.close" {
                return PBWInput.press(args: PBWArguments(options: ["key": "escape"], positionals: []))
            }
            guard let title = args.string("title") ?? args.positionals.first else {
                return .failure(code: "invalid_argument.missing_title", message: "--title is required.", exitCode: 2)
            }
            return PBWAX.clickMenuItem(title: title)
        case let name where name.hasPrefix("space."):
            return PBWSpace.handle(command: name, args: args)
        case "snapshot.list":
            return PBWSnapshotStore().list()
        case "snapshot.show":
            return PBWSnapshotStore().show(id: args.string("id") ?? args.positionals.first)
        case "snapshot.inspect":
            return PBWSnapshotStore().inspect(args: args)
        case "snapshot.clean":
            return PBWSnapshotStore().clean(keep: args.int("keep") ?? 20)
        case "snapshot.export":
            return PBWSnapshotStore().export(id: args.string("id") ?? args.string("snapshot"), path: args.string("path"))
        case let name where name.hasPrefix("overlay."):
            return PBWOverlay.handle(command: name)
        case let name where name.hasPrefix("daemon."):
            return PBWDaemon.handle(command: name, args: args)
        case let name where name.hasPrefix("bridge."):
            return PBWBridge.handle(command: name, args: args)
        case let name where name.hasPrefix("config."):
            return PBWConfigCommands.handle(command: name, args: args)
        case "diagnostics.doctor":
            return PBWDiagnostics.doctor()
        default:
            return .failure(code: "invalid_argument.unimplemented_command", message: "Command is registered but not implemented.", details: ["name": spec.name], exitCode: 2)
        }
    }
}
