import Foundation

public final class PBMMCPServer {
    private let runtime: PBMRuntime

    public init(runtime: PBMRuntime = PBMRuntime()) {
        self.runtime = runtime
    }

    public func run() -> Int32 {
        var buffer = Data()
        while true {
            let chunk = FileHandle.standardInput.readData(ofLength: 4096)
            if chunk.isEmpty {
                return 0
            }
            buffer.append(chunk)
            while let message = extractMessage(from: &buffer) {
                if let response = handle(message: message) {
                    writeMessage(response)
                }
            }
        }
    }

    public func handle(message: [String: Any]) -> [String: Any]? {
        let id = message["id"] ?? NSNull()
        guard let method = message["method"] as? String else {
            return jsonRPC(id: id, errorCode: -32600, message: "Missing method.")
        }
        if id is NSNull, method.hasPrefix("notifications/") {
            return nil
        }
        switch method {
        case "initialize":
            return jsonRPC(id: id, result: [
                "protocolVersion": "2025-06-18",
                "serverInfo": [
                    "name": "pbm",
                    "version": pbmVersion,
                ],
                "capabilities": [
                    "tools": [:],
                ],
            ])
        case "tools/list":
            return jsonRPC(id: id, result: [
                "tools": toolList(),
            ])
        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let name = params["name"] as? String
            else {
                return jsonRPC(id: id, errorCode: -32602, message: "tools/call requires params.name.")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = runtime.runTool(name: name, arguments: arguments)
            return jsonRPC(id: id, result: result.envelope)
        default:
            return jsonRPC(id: id, errorCode: -32601, message: "Method not found.")
        }
    }

    public func toolList() -> [[String: Any]] {
        PBMCommandRegistry.commands
            .filter { $0.name != "help" && $0.name != "mcp" }
            .map { spec in
                [
                    "name": spec.name,
                    "description": spec.summary,
                    "inputSchema": inputSchema(for: spec),
                ]
            }
    }

    private func inputSchema(for spec: PBMCommandSpec) -> [String: Any] {
        var properties: [String: Any] = [
            "confirm": ["type": "boolean"],
            "mode": ["type": "string", "enum": ["direct", "daemon", "bridge"]],
            "id": ["type": "string"],
            "snapshot": ["type": "string"],
            "path": ["type": "string"],
            "text": ["type": "string"],
            "title": ["type": "string"],
            "name": ["type": "string"],
            "bundle-id": ["type": "string"],
            "pid": ["type": "integer"],
            "x": ["type": "number"],
            "y": ["type": "number"],
            "width": ["type": "number"],
            "height": ["type": "number"],
            "duration": ["type": "number"],
        ]
        if spec.name.hasPrefix("input.") {
            properties["key"] = ["type": "string"]
            properties["keys"] = ["type": "string"]
            properties["dx"] = ["type": "integer"]
            properties["dy"] = ["type": "integer"]
            properties["from-x"] = ["type": "number"]
            properties["from-y"] = ["type": "number"]
            properties["to-x"] = ["type": "number"]
            properties["to-y"] = ["type": "number"]
            properties["button"] = ["type": "string", "enum": ["left", "right"]]
            addTargetSelectorProperties(to: &properties)
        }
        if spec.name.hasPrefix("semantic.") {
            properties["value"] = ["type": "string"]
            properties["action"] = ["type": "string"]
            properties["focused"] = ["type": "boolean"]
            addTargetSelectorProperties(to: &properties)
        }
        if spec.name.hasPrefix("window.") {
            properties["window-id"] = ["type": "integer"]
            properties["windowId"] = ["type": "integer"]
            properties["handle"] = ["type": "integer"]
            properties["fullscreen"] = ["type": "boolean"]
        }
        if spec.name.hasPrefix("snapshot.") {
            properties["target"] = ["type": "string"]
            properties["element"] = ["type": "string"]
            properties["window"] = ["type": "string"]
            properties["max-age"] = ["type": "number"]
            properties["maxAge"] = ["type": "number"]
        }
        if spec.name.hasPrefix("observe.") {
            properties["display-id"] = ["type": "integer"]
            properties["window-id"] = ["type": "integer"]
            properties["scope"] = ["type": "string", "enum": ["frontmost", "allApps"]]
            properties["app"] = ["type": "string"]
            properties["app-id"] = ["type": "string"]
            properties["appId"] = ["type": "string"]
            properties["bundleId"] = ["type": "string"]
            properties["max-depth"] = ["type": "integer"]
            properties["maxDepth"] = ["type": "integer"]
            properties["max-elements"] = ["type": "integer"]
            properties["maxElementCount"] = ["type": "integer"]
            properties["max-children"] = ["type": "integer"]
            properties["maxChildren"] = ["type": "integer"]
            properties["timeout"] = ["type": "number"]
            properties["timeout-seconds"] = ["type": "number"]
            properties["window-title"] = ["type": "string"]
            properties["windowTitle"] = ["type": "string"]
            properties["window-index"] = ["type": "integer"]
            properties["windowIndex"] = ["type": "integer"]
            properties["alternative-children"] = ["type": "boolean"]
            properties["application-windows"] = ["type": "boolean"]
            properties["focused-element"] = ["type": "boolean"]
            properties["web-focus-fallback"] = ["type": "boolean"]
            properties["fps"] = ["type": "integer"]
            properties["cursor"] = ["type": "boolean"]
        }
        if spec.name.hasPrefix("space.") {
            properties["index"] = ["type": "integer"]
            properties["space"] = ["type": "integer"]
        }
        if spec.name.hasPrefix("config.") {
            properties["value"] = ["type": ["string", "number", "boolean"]]
            properties["force"] = ["type": "boolean"]
        }
        if spec.name.hasPrefix("clipboard.") {
            properties["type"] = ["type": "string"]
            properties["uti"] = ["type": "string"]
            properties["prefer"] = ["type": "string"]
            properties["output"] = ["type": "string"]
            properties["output-path"] = ["type": "string"]
            properties["file"] = ["type": "string"]
            properties["file-path"] = ["type": "string"]
            properties["data-base64"] = ["type": "string"]
            properties["base64"] = ["type": "boolean"]
            properties["allow-large"] = ["type": "boolean"]
            properties["max-bytes"] = ["type": "integer"]
        }
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
        ]
    }

    private func addTargetSelectorProperties(to properties: inout [String: Any]) {
        properties["target"] = ["type": "string"]
        properties["target-text"] = ["type": "string"]
        properties["target-title"] = ["type": "string"]
        properties["automation-id"] = ["type": "string"]
        properties["automationId"] = ["type": "string"]
        properties["role"] = ["type": "string"]
        properties["index"] = ["type": "integer"]
        properties["window-id"] = ["type": "integer"]
        properties["windowId"] = ["type": "integer"]
        properties["handle"] = ["type": "integer"]
    }

    private func jsonRPC(id: Any, result: Any) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
    }

    private func jsonRPC(id: Any, errorCode: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": errorCode,
                "message": message,
            ],
        ]
    }

    private func writeMessage(_ object: [String: Any]) {
        let body = PBMJSON.encode(object)
        let header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(body)
    }

    private func extractMessage(from buffer: inout Data) -> [String: Any]? {
        let headerSeparator = Data("\r\n\r\n".utf8)
        if let range = buffer.range(of: headerSeparator) {
            let headerData = buffer.subdata(in: buffer.startIndex ..< range.lowerBound)
            let header = String(decoding: headerData, as: UTF8.self)
            let length = header
                .split(separator: "\r\n")
                .compactMap { line -> Int? in
                    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                    return Int(parts[1])
                }
                .first
            guard let length else {
                buffer.removeSubrange(buffer.startIndex ..< range.upperBound)
                return nil
            }
            let bodyStart = range.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else { return nil }
            let body = buffer.subdata(in: bodyStart ..< bodyEnd)
            buffer.removeSubrange(buffer.startIndex ..< bodyEnd)
            return try? PBMJSON.parseObject(body)
        }
        if let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex ..< newline)
            buffer.removeSubrange(buffer.startIndex ... newline)
            return try? PBMJSON.parseObject(line)
        }
        return nil
    }
}
