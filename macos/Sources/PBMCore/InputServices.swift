import AppKit
import CoreGraphics
import Foundation

enum PBMInput {
    static func click(args: PBMArguments) -> PBMExecutionResult {
        let resolved = PBMTargetResolver.resolve(args: args)
        if let error = resolved.error { return error }
        guard let point = resolved.target?.point else {
            return .failure(code: "invalid_argument.missing_target", message: "Provide --x and --y or a resolvable target.", exitCode: 2)
        }
        if let denied = permissionDeniedPostEvent() { return denied }
        let button: CGMouseButton = args.string("button") == "right" ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        postMouse(type: downType, point: point, button: button)
        usleep(30000)
        postMouse(type: upType, point: point, button: button)
        let targetData: Any = resolved.target?.item ?? NSNull()
        return .success([
            "point": PBMNative.pointDict(point),
            "button": args.string("button") ?? "left",
            "strategy": "CGEvent",
            "target": targetData,
        ])
    }

    static func move(args: PBMArguments) -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let point = PBMNative.parsePoint(args) else {
            return .failure(code: "invalid_argument.missing_coordinates", message: "--x and --y are required.", exitCode: 2)
        }
        let start = CGEvent(source: nil)?.location ?? point
        let path = PBMMousePath.linear(from: start, to: point, steps: movementSteps(args: args))
        let delay = movementDelay(args: args, pointCount: path.count)
        for item in path {
            postMouse(type: .mouseMoved, point: item, button: .left)
            if delay > 0 { usleep(delay) }
        }
        return .success([
            "point": PBMNative.pointDict(point),
            "steps": path.count,
            "duration": args.double("duration") as Any? ?? NSNull(),
            "strategy": "CGEvent.linear",
        ])
    }

    static func drag(args: PBMArguments) -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let from = PBMNative.parsePoint(args, xKey: "from-x", yKey: "from-y"),
              let to = PBMNative.parsePoint(args, xKey: "to-x", yKey: "to-y")
        else {
            return .failure(code: "invalid_argument.missing_coordinates", message: "--from-x --from-y --to-x --to-y are required.", exitCode: 2)
        }
        postMouse(type: .leftMouseDown, point: from, button: .left)
        let path = PBMMousePath.linear(from: from, to: to, steps: movementSteps(args: args))
        let delay = movementDelay(args: args, pointCount: path.count)
        for item in path {
            if delay > 0 { usleep(delay) }
            postMouse(type: .leftMouseDragged, point: item, button: .left)
        }
        if delay == 0 { usleep(40000) }
        postMouse(type: .leftMouseUp, point: to, button: .left)
        return .success([
            "from": PBMNative.pointDict(from),
            "to": PBMNative.pointDict(to),
            "steps": path.count,
            "duration": args.double("duration") as Any? ?? NSNull(),
            "strategy": "CGEvent.linear",
        ])
    }

    static func scroll(args: PBMArguments) -> PBMExecutionResult {
        let dx = Int32(args.int("dx") ?? 0)
        let dy = Int32(args.int("dy") ?? args.int("delta") ?? 0)
        guard dx != 0 || dy != 0 else {
            return .failure(code: "invalid_argument.missing_delta", message: "--dy or --dx is required.", exitCode: 2)
        }
        let resolved = PBMTargetResolver.resolve(args: args, allowMissing: true)
        if let error = resolved.error { return error }
        if let denied = permissionDeniedPostEvent() { return denied }
        if let point = resolved.target?.point {
            postMouse(type: .mouseMoved, point: point, button: .left)
        }
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        event?.post(tap: .cghidEventTap)
        let targetData: Any = resolved.target?.item ?? NSNull()
        return .success(["dx": Int(dx), "dy": Int(dy), "strategy": "CGEvent", "target": targetData])
    }

    static func type(args: PBMArguments) -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let text = args.string("text") ?? args.positionals.first else {
            return .failure(code: "invalid_argument.missing_text", message: "--text is required.", exitCode: 2)
        }
        for scalar in text.unicodeScalars {
            var value = UniChar(scalar.value)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up?.post(tap: .cghidEventTap)
        }
        return .success(["characters": text.count, "strategy": "CGEvent"])
    }

    static func press(args: PBMArguments) -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let key = args.string("key") ?? args.positionals.first else {
            return .failure(code: "invalid_argument.missing_key", message: "--key is required.", exitCode: 2)
        }
        guard let code = keyCode(key) else {
            return .failure(code: "invalid_argument.unknown_key", message: "Unknown key.", details: ["key": key], exitCode: 2)
        }
        postKey(code: code, modifiers: [])
        return .success(["key": key, "keyCode": Int(code), "strategy": "CGEvent"])
    }

    static func paste() -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        postKey(code: 0x09, modifiers: .maskCommand)
        return .success(["keys": "cmd+v", "strategy": "CGEvent"])
    }

    private static func permissionDeniedPostEvent() -> PBMExecutionResult? {
        guard !PBMNative.postEventAllowed() else { return nil }
        return .failure(
            code: "permission_denied.input_monitoring",
            message: "Input event posting permission is required for synthetic input.",
            details: [
                "service": "Input Monitoring",
                "howToFix": "Grant input/event posting permission to the pbm executable or Bridge app in System Settings.",
            ],
            retryHint: "Run `pbm diagnostics doctor` after granting permission.",
        )
    }

    private static func postMouse(type: CGEventType, point: CGPoint, button: CGMouseButton) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.post(tap: .cghidEventTap)
    }

    private static func postKey(code: CGKeyCode, modifiers: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }

    static func keyCode(_ key: String) -> CGKeyCode? {
        let k = PBMHotkeyKey.normalizedName(for: key)
        if PBMHotkeyKey.modifierFlag(for: k) != nil {
            return nil
        }
        return PBMHotkeyKey.keyCode(for: k)
    }

    private static func movementSteps(args: PBMArguments) -> Int {
        if let steps = args.int("steps") {
            return max(1, min(steps, 240))
        }
        if args.double("duration") != nil {
            return 24
        }
        return 1
    }

    private static func movementDelay(args: PBMArguments, pointCount: Int) -> useconds_t {
        guard let duration = args.double("duration"), duration > 0, pointCount > 0 else {
            return 0
        }
        let micros = duration * 1_000_000 / Double(pointCount)
        return useconds_t(max(0, min(micros, Double(UInt32.max))))
    }
}

enum PBMMousePath {
    static func linear(from: CGPoint, to: CGPoint, steps: Int) -> [CGPoint] {
        let clamped = max(1, steps)
        return (1 ... clamped).map { index in
            let progress = CGFloat(index) / CGFloat(clamped)
            return CGPoint(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress,
            )
        }
    }
}

struct PBMHotkeyPlan: Equatable {
    let primaryKey: String
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum PBMHotkeyKey {
    static func parse(_ keys: String) -> [String] {
        keys.components(separatedBy: CharacterSet(charactersIn: ",+").union(.whitespacesAndNewlines))
            .map(normalizedName)
            .filter { !$0.isEmpty }
    }

    static func plan(_ keys: String) -> PBMHotkeyPlan? {
        plan(parse(keys))
    }

    static func plan(_ keys: [String]) -> PBMHotkeyPlan? {
        var modifiers: CGEventFlags = []
        var primary: (name: String, code: CGKeyCode)?
        for raw in keys {
            let key = normalizedName(for: raw)
            if let modifier = modifierFlag(for: key) {
                modifiers.insert(modifier)
                continue
            }
            guard let code = keyCode(for: key), primary == nil else {
                return nil
            }
            primary = (key, code)
        }
        guard let primary else { return nil }
        return PBMHotkeyPlan(primaryKey: primary.name, keyCode: primary.code, modifiers: modifiers)
    }

    static func normalizedName(for rawKey: String) -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases[key] ?? key
    }

    static func modifierFlag(for key: String) -> CGEventFlags? {
        switch normalizedName(for: key) {
        case "cmd":
            .maskCommand
        case "shift":
            .maskShift
        case "alt":
            .maskAlternate
        case "ctrl":
            .maskControl
        case "fn":
            .maskSecondaryFn
        default:
            nil
        }
    }

    static func keyCode(for key: String) -> CGKeyCode? {
        let k = normalizedName(for: key)
        let map: [String: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18,
            "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C, "0": 0x1D, "rightbracket": 0x1E, "o": 0x1F, "u": 0x20,
            "leftbracket": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "l": 0x25, "j": 0x26,
            "quote": 0x27, "k": 0x28, "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E,
            "period": 0x2F, "tab": 0x30, "space": 0x31, "grave": 0x32, "delete": 0x33, "escape": 0x35,
            "capslock": 0x39, "clear": 0x47, "help": 0x72,
            "right": 0x7C, "left": 0x7B, "down": 0x7D, "up": 0x7E, "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79, "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
            "forwarddelete": 0x75,
        ]
        return map[k]
    }

    private static let aliases: [String: String] = [
        "command": "cmd",
        "meta": "cmd",
        "win": "cmd",
        "windows": "cmd",
        "cmdorctrl": "cmd",
        "control": "ctrl",
        "option": "alt",
        "opt": "alt",
        "function": "fn",
        "enter": "return",
        "esc": "escape",
        "backspace": "delete",
        "del": "delete",
        "spacebar": "space",
        "page_up": "pageup",
        "page_down": "pagedown",
        "forward_delete": "forwarddelete",
        "arrow_left": "left",
        "arrow_right": "right",
        "arrow_down": "down",
        "arrow_up": "up",
        "left_bracket": "leftbracket",
        "[": "leftbracket",
        "right_bracket": "rightbracket",
        "]": "rightbracket",
        "=": "equal",
        "-": "minus",
        "'": "quote",
        ";": "semicolon",
        "\\": "backslash",
        ",": "comma",
        "/": "slash",
        ".": "period",
        "`": "grave",
        "caps_lock": "capslock",
    ]
}

extension PBMInput {
    static func hotkey(args: PBMArguments) -> PBMExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let plan = PBMHotkeyKey.plan(args.string("keys") ?? args.positionals.first ?? "") else {
            return .failure(code: "invalid_argument.unknown_hotkey", message: "--keys like cmd+shift+p is required.", exitCode: 2)
        }
        postKey(code: plan.keyCode, modifiers: plan.modifiers)
        var names = modifierNames(plan.modifiers)
        names.append(plan.primaryKey)
        return .success([
            "keys": names.joined(separator: "+"),
            "keyCode": Int(plan.keyCode),
            "strategy": "CGEvent",
        ])
    }

    private static func modifierNames(_ flags: CGEventFlags) -> [String] {
        var output: [String] = []
        if flags.contains(.maskCommand) { output.append("cmd") }
        if flags.contains(.maskControl) { output.append("ctrl") }
        if flags.contains(.maskAlternate) { output.append("alt") }
        if flags.contains(.maskShift) { output.append("shift") }
        if flags.contains(.maskSecondaryFn) { output.append("fn") }
        return output
    }
}

struct PBMResolvedTarget {
    let id: String
    let point: CGPoint
    let item: [String: Any]
}

enum PBMTargetResolver {
    static func resolve(args: PBMArguments, allowMissing: Bool = false) -> (target: PBMResolvedTarget?, error: PBMExecutionResult?) {
        if let point = PBMNative.parsePoint(args) {
            return (PBMResolvedTarget(id: "coordinates", point: point, item: ["source": "coordinates", "point": PBMNative.pointDict(point)]), nil)
        }

        var selectors: [String] = []
        if args.string("id") != nil || args.string("target") != nil { selectors.append("id") }
        if targetText(args) != nil { selectors.append("text") }
        if targetTitle(args) != nil { selectors.append("title") }
        if (args.string("automation-id") ?? args.string("automationId")) != nil { selectors.append("automationId") }
        if args.string("role") != nil { selectors.append("role") }
        if args.string("app") != nil || args.string("bundle-id") != nil || args.string("bundleId") != nil { selectors.append("scope") }
        if (args.int("window-id") ?? args.int("windowId") ?? args.int("handle")) != nil { selectors.append("window") }
        if args.int("index") != nil { selectors.append("index") }
        if selectors.isEmpty {
            return allowMissing ? (nil, nil) : (nil, nil)
        }
        if selectors.contains("id"), selectors.count > 1 {
            return (nil, .failure(
                code: "invalid_argument.conflicting_target",
                message: "Pass either an explicit target id or query selectors, not both.",
                details: ["selectors": selectors],
                exitCode: 2,
            ))
        }

        guard let snapshot = loadSnapshot(id: args.string("snapshot")) else {
            return (nil, .failure(code: "stale_snapshot", message: "Snapshot was not found for target resolution.", details: ["snapshot": args.string("snapshot") ?? "latest"]))
        }
        if let id = args.string("id") ?? args.string("target") {
            guard let target = resolve(id: id, in: snapshot) else {
                return (nil, .failure(code: "target_not_found", message: "Target id was not found in snapshot.", details: ["id": id, "snapshot": snapshot["id"] ?? "latest"]))
            }
            return (target, nil)
        }

        let candidates = flattenedTargets(in: snapshot)
        let role = args.string("role")?.lowercased()
        let text = targetText(args)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = targetTitle(args)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let automationID = (args.string("automation-id") ?? args.string("automationId"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = args.string("app")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = (args.string("bundle-id") ?? args.string("bundleId"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowID = args.int("window-id") ?? args.int("windowId") ?? args.int("handle")
        var filtered = candidates
        if let bundleID, !bundleID.isEmpty {
            filtered = filtered.filter { ($0.item["bundleIdentifier"] as? String ?? "").localizedCaseInsensitiveCompare(bundleID) == .orderedSame }
        }
        if let appName, !appName.isEmpty {
            filtered = preferExact(candidates: filtered, needle: appName, fields: ["app", "appName", "application", "ownerName"])
        }
        if let windowID {
            filtered = filtered.filter { ($0.item["windowId"] as? Int) == windowID || ($0.item["handle"] as? Int) == windowID }
        }
        if let automationID, !automationID.isEmpty {
            filtered = preferExact(candidates: filtered, needle: automationID, fields: ["automationId", "identifier", "id"])
        }
        if let role, !role.isEmpty {
            filtered = filtered.filter { ($0.item["role"] as? String ?? "").lowercased().contains(role) }
        }
        if let text, !text.isEmpty {
            filtered = preferExact(candidates: filtered, needle: text, fields: ["text", "title", "automationId", "label", "value"])
        }
        if let title, !title.isEmpty {
            filtered = preferExact(candidates: filtered, needle: title, fields: ["title", "text"])
        }
        if let index = args.int("index") {
            guard index >= 0, index < filtered.count else {
                return (nil, .failure(code: "target_not_found", message: "Target index was not found in snapshot.", details: ["index": index, "count": filtered.count]))
            }
            return (filtered[index], nil)
        }
        if filtered.isEmpty {
            return (nil, .failure(code: "target_not_found", message: "No snapshot target matched the query.", details: ["selectors": selectors]))
        }
        if filtered.count > 1 {
            return (nil, .failure(
                code: "target_ambiguous",
                message: "Snapshot target query matched multiple targets.",
                details: [
                    "selectors": selectors,
                    "matches": filtered.prefix(20).map { target in
                        [
                            "id": target.id,
                            "title": target.item["title"] ?? "",
                            "text": target.item["text"] ?? "",
                            "role": target.item["role"] ?? "",
                        ]
                    },
                ],
            ))
        }
        return (filtered[0], nil)
    }

    static func resolve(id: String, snapshotID: String?) -> PBMResolvedTarget? {
        guard let snapshot = loadSnapshot(id: snapshotID) else {
            return nil
        }
        return resolve(id: id, in: snapshot)
    }

    private static func loadSnapshot(id: String?) -> [String: Any]? {
        let store = PBMSnapshotStore()
        guard let url = store.resolveSnapshotURL(id: id),
              let snapshot = try? PBMJSON.parseObject(Data(contentsOf: url))
        else {
            return nil
        }
        return snapshot
    }

    private static func resolve(id: String, in snapshot: [String: Any]) -> PBMResolvedTarget? {
        for key in ["elements", "windows", "menus", "dialogs", "dock", "menubar", "spaces"] {
            guard let list = snapshot[key] as? [[String: Any]] else { continue }
            for item in list where (item["id"] as? String) == id {
                if let target = makeTarget(id: id, item: item) {
                    return target
                }
            }
        }
        return nil
    }

    private static func flattenedTargets(in snapshot: [String: Any]) -> [PBMResolvedTarget] {
        ["elements", "windows", "menus", "dialogs", "dock", "menubar", "spaces"].flatMap { key -> [PBMResolvedTarget] in
            guard let list = snapshot[key] as? [[String: Any]] else { return [] }
            return list.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return makeTarget(id: id, item: item)
            }
        }
    }

    private static func makeTarget(id: String, item: [String: Any]) -> PBMResolvedTarget? {
        guard let bounds = item["bounds"] as? [String: Any],
              let x = bounds.double("x"), let y = bounds.double("y"),
              let width = bounds.double("width"), let height = bounds.double("height")
        else {
            return nil
        }
        return PBMResolvedTarget(id: id, point: CGPoint(x: x + width / 2, y: y + height / 2), item: item)
    }

    private static func targetText(_ args: PBMArguments) -> String? {
        args.string("target-text") ?? args.string("targetText") ?? args.string("text")
    }

    private static func targetTitle(_ args: PBMArguments) -> String? {
        args.string("target-title") ?? args.string("targetTitle") ?? args.string("title")
    }

    private static func preferExact(candidates: [PBMResolvedTarget], needle: String, fields: [String]) -> [PBMResolvedTarget] {
        let exact = candidates.filter { target in
            fields.contains { field in
                (target.item[field] as? String ?? "").localizedCaseInsensitiveCompare(needle) == .orderedSame
            }
        }
        if !exact.isEmpty {
            return exact
        }
        return candidates.filter { target in
            fields.contains { field in
                (target.item[field] as? String ?? "").localizedCaseInsensitiveContains(needle)
            }
        }
    }
}
