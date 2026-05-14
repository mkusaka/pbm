import Foundation

public let pbmStableSchemaVersion = "pbm.stable.v1"

public struct PBMExecutionResult {
    public let envelope: [String: Any]
    public let exitCode: Int32
    public let output: Data?

    public init(envelope: [String: Any], exitCode: Int32, output: Data? = nil) {
        self.envelope = envelope
        self.exitCode = exitCode
        self.output = output
    }

    public static func success(_ data: Any = [:], exitCode: Int32 = 0) -> PBMExecutionResult {
        let envelope: [String: Any] = [
            "schemaVersion": pbmStableSchemaVersion,
            "ok": true,
            "data": PBMJSON.normalized(data),
        ]
        return PBMExecutionResult(envelope: envelope, exitCode: exitCode, output: PBMJSON.encode(envelope))
    }

    public static func failure(
        code: String,
        message: String,
        details: Any = [:],
        retryHint: String? = nil,
        exitCode: Int32 = 1,
    ) -> PBMExecutionResult {
        var error: [String: Any] = [
            "code": code,
            "message": message,
            "details": PBMJSON.normalized(details),
        ]
        if let retryHint {
            error["retryHint"] = retryHint
        }
        let envelope: [String: Any] = [
            "schemaVersion": pbmStableSchemaVersion,
            "ok": false,
            "error": error,
        ]
        return PBMExecutionResult(envelope: envelope, exitCode: exitCode, output: PBMJSON.encode(envelope))
    }
}

public enum PBMJSON {
    public static func encode(_ object: Any, pretty: Bool = false) -> Data {
        let normalized = normalized(object)
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: options)
        else {
            let fallback: [String: Any] = [
                "schemaVersion": pbmStableSchemaVersion,
                "ok": false,
                "error": [
                    "code": "internal.serialization",
                    "message": "Failed to serialize JSON envelope.",
                    "details": [:],
                ],
            ]
            return try! JSONSerialization.data(withJSONObject: fallback, options: options)
        }
        return data
    }

    public static func parseObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PBMError.invalidArgument("Expected a JSON object.")
        }
        return object
    }

    public static func normalized(_ value: Any) -> Any {
        switch value {
        case Optional<Any>.none:
            return NSNull()
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int as Int32:
            return Int(int)
        case let int as Int64:
            return int
        case let uint as UInt32:
            return Int(uint)
        case let double as Double:
            return double.isFinite ? double : NSNull()
        case let float as Float:
            return float.isFinite ? Double(float) : NSNull()
        case let date as Date:
            return PBMTime.string(from: date)
        case let url as URL:
            return url.path
        case let dict as [String: Any]:
            var output: [String: Any] = [:]
            for key in dict.keys.sorted() {
                if let item = dict[key] {
                    output[key] = normalized(item)
                }
            }
            return output
        case let dict as [String: String]:
            return dict
        case let array as [Any]:
            return array.map { normalized($0) }
        case let array as [[String: Any]]:
            return array.map { normalized($0) }
        default:
            return String(describing: value)
        }
    }
}

public enum PBMTime {
    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func nowString() -> String {
        formatter().string(from: Date())
    }

    public static func string(from date: Date) -> String {
        formatter().string(from: date)
    }
}

public enum PBMError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case internalFailure(String)

    public var description: String {
        switch self {
        case let .invalidArgument(message), let .internalFailure(message):
            message
        }
    }
}

extension [String: Any] {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? String {
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        if let value = self[key] as? String {
            return Int(value)
        }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = self[key] as? String {
            return Double(value)
        }
        return nil
    }
}
