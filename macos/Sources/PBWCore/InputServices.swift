import AppKit
import CoreGraphics
import Foundation

enum PBWInput {
    static func click(args: PBWArguments) -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let point = targetPoint(args: args) else {
            return .failure(code: "invalid_argument.missing_target", message: "Provide --x and --y or a resolvable target.", exitCode: 2)
        }
        let button: CGMouseButton = args.string("button") == "right" ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        postMouse(type: downType, point: point, button: button)
        usleep(30000)
        postMouse(type: upType, point: point, button: button)
        return .success(["point": PBWNative.pointDict(point), "button": args.string("button") ?? "left", "strategy": "CGEvent"])
    }

    static func move(args: PBWArguments) -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let point = PBWNative.parsePoint(args) else {
            return .failure(code: "invalid_argument.missing_coordinates", message: "--x and --y are required.", exitCode: 2)
        }
        postMouse(type: .mouseMoved, point: point, button: .left)
        return .success(["point": PBWNative.pointDict(point), "strategy": "CGEvent"])
    }

    static func drag(args: PBWArguments) -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        guard let from = PBWNative.parsePoint(args, xKey: "from-x", yKey: "from-y"),
              let to = PBWNative.parsePoint(args, xKey: "to-x", yKey: "to-y")
        else {
            return .failure(code: "invalid_argument.missing_coordinates", message: "--from-x --from-y --to-x --to-y are required.", exitCode: 2)
        }
        postMouse(type: .leftMouseDown, point: from, button: .left)
        usleep(40000)
        postMouse(type: .leftMouseDragged, point: to, button: .left)
        usleep(40000)
        postMouse(type: .leftMouseUp, point: to, button: .left)
        return .success(["from": PBWNative.pointDict(from), "to": PBWNative.pointDict(to), "strategy": "CGEvent"])
    }

    static func scroll(args: PBWArguments) -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        let dx = Int32(args.int("dx") ?? 0)
        let dy = Int32(args.int("dy") ?? args.int("delta") ?? 0)
        guard dx != 0 || dy != 0 else {
            return .failure(code: "invalid_argument.missing_delta", message: "--dy or --dx is required.", exitCode: 2)
        }
        if let point = PBWNative.parsePoint(args) {
            postMouse(type: .mouseMoved, point: point, button: .left)
        }
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        event?.post(tap: .cghidEventTap)
        return .success(["dx": Int(dx), "dy": Int(dy), "strategy": "CGEvent"])
    }

    static func type(args: PBWArguments) -> PBWExecutionResult {
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

    static func press(args: PBWArguments) -> PBWExecutionResult {
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

    static func hotkey(args: PBWArguments) -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        let keys = (args.string("keys") ?? args.positionals.first ?? "")
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard let key = keys.last, let code = keyCode(key) else {
            return .failure(code: "invalid_argument.unknown_hotkey", message: "--keys like cmd+shift+p is required.", exitCode: 2)
        }
        var flags: CGEventFlags = []
        if keys.contains("cmd") || keys.contains("command") { flags.insert(.maskCommand) }
        if keys.contains("shift") { flags.insert(.maskShift) }
        if keys.contains("ctrl") || keys.contains("control") { flags.insert(.maskControl) }
        if keys.contains("alt") || keys.contains("option") { flags.insert(.maskAlternate) }
        postKey(code: code, modifiers: flags)
        return .success(["keys": keys.joined(separator: "+"), "keyCode": Int(code), "strategy": "CGEvent"])
    }

    static func paste() -> PBWExecutionResult {
        if let denied = permissionDeniedPostEvent() { return denied }
        postKey(code: 0x09, modifiers: .maskCommand)
        return .success(["keys": "cmd+v", "strategy": "CGEvent"])
    }

    private static func permissionDeniedPostEvent() -> PBWExecutionResult? {
        guard !PBWNative.postEventAllowed() else { return nil }
        return .failure(
            code: "permission_denied.input_monitoring",
            message: "Input event posting permission is required for synthetic input.",
            details: [
                "service": "Input Monitoring",
                "howToFix": "Grant input/event posting permission to the pbw executable or Bridge app in System Settings.",
            ],
            retryHint: "Run `pbw diagnostics doctor` after granting permission.",
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

    private static func targetPoint(args: PBWArguments) -> CGPoint? {
        if let point = PBWNative.parsePoint(args) {
            return point
        }
        if let id = args.string("id") ?? args.string("target"),
           let target = PBWTargetResolver.resolve(id: id, snapshotID: args.string("snapshot"))
        {
            return target.point
        }
        return nil
    }

    static func keyCode(_ key: String) -> CGKeyCode? {
        let k = key.lowercased()
        let map: [String: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "enter": 0x24, "l": 0x25, "j": 0x26,
            "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
            ".": 0x2F, "tab": 0x30, "space": 0x31, "`": 0x32, "delete": 0x33, "escape": 0x35, "esc": 0x35,
            "cmd": 0x37, "shift": 0x38, "capslock": 0x39, "option": 0x3A, "alt": 0x3A, "ctrl": 0x3B,
            "right": 0x7C, "left": 0x7B, "down": 0x7D, "up": 0x7E, "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79, "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        ]
        return map[k]
    }
}

struct PBWResolvedTarget {
    let id: String
    let point: CGPoint
    let item: [String: Any]
}

enum PBWTargetResolver {
    static func resolve(id: String, snapshotID: String?) -> PBWResolvedTarget? {
        let store = PBWSnapshotStore()
        guard let url = store.resolveSnapshotURL(id: snapshotID),
              let snapshot = try? PBWJSON.parseObject(Data(contentsOf: url))
        else {
            return nil
        }
        for key in ["elements", "windows", "menus", "dialogs", "dock", "menubar", "spaces"] {
            guard let list = snapshot[key] as? [[String: Any]] else { continue }
            for item in list where (item["id"] as? String) == id {
                if let bounds = item["bounds"] as? [String: Any],
                   let x = bounds.double("x"), let y = bounds.double("y"),
                   let width = bounds.double("width"), let height = bounds.double("height")
                {
                    return PBWResolvedTarget(id: id, point: CGPoint(x: x + width / 2, y: y + height / 2), item: item)
                }
            }
        }
        return nil
    }
}
