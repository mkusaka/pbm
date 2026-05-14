import Foundation

public enum PBMPaths {
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["PBM_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pbm", isDirectory: true)
    }

    public static var config: URL {
        home.appendingPathComponent("config.json")
    }

    public static var snapshots: URL {
        home.appendingPathComponent("snapshots", isDirectory: true)
    }

    public static var captures: URL {
        home.appendingPathComponent("captures", isDirectory: true)
    }

    public static var sessions: URL {
        home.appendingPathComponent("sessions", isDirectory: true)
    }

    public static var logs: URL {
        home.appendingPathComponent("logs", isDirectory: true)
    }

    public static var daemonSocket: URL {
        home.appendingPathComponent("daemon.sock")
    }

    public static var daemonPID: URL {
        home.appendingPathComponent("daemon.pid")
    }

    public static var daemonLog: URL {
        logs.appendingPathComponent("daemon.log")
    }

    public static var launchAgent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/io.github.mkusaka.pbm.daemon.plist")
    }

    public static func ensureBaseDirectories() throws {
        for directory in [home, snapshots, captures, sessions, logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

public struct PBMConfig {
    public var raw: [String: Any]

    public init(raw: [String: Any] = PBMConfig.defaultRaw) {
        self.raw = raw
    }

    public static var defaultRaw: [String: Any] {
        [
            "schemaVersion": "pbm.config.v1",
            "mode": "direct",
            "safety": [
                "confirmDestructiveActions": true,
            ],
            "policy": [
                "allow": [],
                "deny": [],
            ],
            "redaction": [
                "snapshotText": true,
                "logs": true,
                "screenshot": false,
                "patterns": [
                    "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
                    "AKIA[0-9A-Z]{16}",
                    "(?i)(password|token|secret)\\s*[:=]\\s*\\S+",
                ],
            ],
            "ocr": [
                "enabled": false,
                "engine": "none",
            ],
            "snapshot": [
                "maxAgeSeconds": 300,
                "maxElementCount": 500,
                "maxDepth": 8,
                "maxChildrenPerNode": 50,
                "timeoutSeconds": 8.0,
                "includeAlternativeChildren": true,
                "includeApplicationWindows": true,
                "includeFocusedElement": true,
                "webFocusFallback": false,
                "scope": "frontmost",
            ],
            "daemon": [
                "socket": PBMPaths.daemonSocket.path,
            ],
            "bridge": [
                "bundleIdentifier": "io.github.mkusaka.pbm.bridge",
                "installed": false,
            ],
            "capture": [
                "screenshotRedaction": false,
                "defaultCoordinateSpace": "logicalPoints",
            ],
        ]
    }

    public static func load() -> PBMConfig {
        guard let data = try? Data(contentsOf: PBMPaths.config),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PBMConfig()
        }
        return PBMConfig(raw: merge(defaults: defaultRaw, override: object))
    }

    public func save() throws {
        try PBMPaths.ensureBaseDirectories()
        try PBMJSON.encode(raw, pretty: true).write(to: PBMPaths.config, options: .atomic)
    }

    public func validate() -> [String: Any] {
        var issues: [[String: Any]] = []
        if raw.string("schemaVersion") != "pbm.config.v1" {
            issues.append(["path": "schemaVersion", "message": "Expected pbm.config.v1."])
        }
        if value(at: "safety.confirmDestructiveActions") as? Bool == nil {
            issues.append(["path": "safety.confirmDestructiveActions", "message": "Expected boolean."])
        }
        if value(at: "redaction.screenshot") as? Bool == nil {
            issues.append(["path": "redaction.screenshot", "message": "Expected boolean."])
        }
        return [
            "valid": issues.isEmpty,
            "issues": issues,
        ]
    }

    public func destructiveConfirmationRequired() -> Bool {
        (value(at: "safety.confirmDestructiveActions") as? Bool) ?? true
    }

    public func policyAllows(toolName: String) -> Bool {
        let deny = stringArray(at: "policy.deny")
        if deny.contains(toolName) || deny.contains("*") {
            return false
        }
        let allow = stringArray(at: "policy.allow")
        if allow.isEmpty {
            return true
        }
        return allow.contains(toolName)
    }

    public func stringArray(at path: String) -> [String] {
        value(at: path) as? [String] ?? []
    }

    public func value(at path: String) -> Any? {
        let pieces = path.split(separator: ".").map(String.init)
        var current: Any = raw
        for piece in pieces {
            guard let dict = current as? [String: Any],
                  let next = dict[piece]
            else {
                return nil
            }
            current = next
        }
        return current
    }

    public mutating func set(value: Any, at path: String) {
        var pieces = path.split(separator: ".").map(String.init)
        guard !pieces.isEmpty else { return }
        var object = raw
        Self.set(value: value, pieces: &pieces, object: &object)
        raw = object
    }

    private static func set(value: Any, pieces: inout [String], object: inout [String: Any]) {
        let key = pieces.removeFirst()
        if pieces.isEmpty {
            object[key] = value
            return
        }
        var child = object[key] as? [String: Any] ?? [:]
        Self.set(value: value, pieces: &pieces, object: &child)
        object[key] = child
    }

    private static func merge(defaults: [String: Any], override: [String: Any]) -> [String: Any] {
        var output = defaults
        for (key, value) in override {
            if let defaultChild = defaults[key] as? [String: Any],
               let overrideChild = value as? [String: Any]
            {
                output[key] = merge(defaults: defaultChild, override: overrideChild)
            } else {
                output[key] = value
            }
        }
        return output
    }
}

public enum PBMRedactor {
    public static func redact(_ value: String, config: PBMConfig) -> String {
        var output = value
        for pattern in config.stringArray(at: "redaction.patterns") {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex ..< output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "[REDACTED]")
            }
        }
        return output
    }

    public static func redactJSON(_ value: Any, config: PBMConfig) -> Any {
        switch value {
        case let string as String:
            return redact(string, config: config)
        case let array as [Any]:
            return array.map { redactJSON($0, config: config) }
        case let dict as [String: Any]:
            var output: [String: Any] = [:]
            for (key, item) in dict {
                output[key] = redactJSON(item, config: config)
            }
            return output
        default:
            return value
        }
    }
}
