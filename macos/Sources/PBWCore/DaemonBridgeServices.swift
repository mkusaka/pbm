import AppKit
import Darwin
import Foundation

enum PBWDaemon {
    static func handle(command: String, args: PBWArguments) -> PBWExecutionResult {
        switch command {
        case "daemon.start":
            return start(args: args)
        case "daemon.stop":
            return stop()
        case "daemon.restart":
            _ = stop()
            return start(args: args)
        case "daemon.status":
            return status()
        case "daemon.logs":
            return logs(args: args)
        case "daemon.install":
            return install()
        case "daemon.uninstall":
            return uninstall()
        default:
            return .failure(code: "invalid_argument.daemon_command", message: "Unknown daemon command.", exitCode: 2)
        }
    }

    static func runForegroundServer() -> Int32 {
        do {
            try PBWPaths.ensureBaseDirectories()
            try? FileManager.default.removeItem(at: PBWPaths.daemonSocket)
            try "\(getpid())\n".write(to: PBWPaths.daemonPID, atomically: true, encoding: .utf8)
            let server = try UnixSocketServer(path: PBWPaths.daemonSocket.path)
            appendLog("daemon started pid=\(getpid()) socket=\(PBWPaths.daemonSocket.path)")
            while true {
                let request = try server.acceptLine()
                let response: [String: Any]
                switch request.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "status":
                    response = ["ok": true, "pid": Int(getpid()), "socket": PBWPaths.daemonSocket.path, "transport": "unix-domain-socket"]
                case "stop":
                    response = ["ok": true, "stopping": true]
                    try server.writeResponse(response)
                    appendLog("daemon stopping")
                    try? FileManager.default.removeItem(at: PBWPaths.daemonSocket)
                    try? FileManager.default.removeItem(at: PBWPaths.daemonPID)
                    return 0
                default:
                    response = ["ok": false, "error": "unknown request"]
                }
                try server.writeResponse(response)
            }
        } catch {
            appendLog("daemon failed \(error.localizedDescription)")
            return 1
        }
    }

    private static func start(args: PBWArguments) -> PBWExecutionResult {
        if args.bool("foreground") {
            return .success(["foreground": true, "note": "Use internal __daemon-run to run the foreground server."])
        }
        if let current = request("status") {
            return .success(["status": current, "alreadyRunning": true])
        }
        guard let executable = Bundle.main.executableURL else {
            return .failure(code: "internal.daemon_executable", message: "Could not locate pbw executable.")
        }
        do {
            try PBWPaths.ensureBaseDirectories()
            if !FileManager.default.fileExists(atPath: PBWPaths.daemonLog.path) {
                FileManager.default.createFile(atPath: PBWPaths.daemonLog.path, contents: nil)
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["__daemon-run"]
            process.standardOutput = try FileHandle(forWritingTo: PBWPaths.daemonLog)
            process.standardError = process.standardOutput
            try process.run()
            for _ in 0 ..< 30 {
                if let status = request("status") {
                    return .success(["started": true, "status": status])
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return .failure(code: "internal.daemon_start_timeout", message: "Daemon did not become ready.", details: ["socket": PBWPaths.daemonSocket.path])
        } catch {
            return .failure(code: "internal.daemon_start", message: error.localizedDescription)
        }
    }

    private static func stop() -> PBWExecutionResult {
        guard let response = request("stop") else {
            return .success(["running": false, "stopped": false])
        }
        return .success(["stopped": true, "response": response])
    }

    private static func status() -> PBWExecutionResult {
        if let response = request("status") {
            return .success(["running": true, "status": response])
        }
        return .success(["running": false, "socket": PBWPaths.daemonSocket.path, "pidFile": PBWPaths.daemonPID.path])
    }

    private static func logs(args: PBWArguments) -> PBWExecutionResult {
        let limit = args.int("lines") ?? 100
        let text = (try? String(contentsOf: PBWPaths.daemonLog, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").suffix(limit).map(String.init)
        let config = PBWConfig.load()
        let output = config.value(at: "redaction.logs") as? Bool ?? true ? lines.map { PBWRedactor.redact($0, config: config) } : lines
        return .success(["path": PBWPaths.daemonLog.path, "lines": output])
    }

    private static func install() -> PBWExecutionResult {
        guard let executable = Bundle.main.executableURL else {
            return .failure(code: "internal.daemon_executable", message: "Could not locate pbw executable.")
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>io.github.mkusaka.pbw.daemon</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executable.path)</string>
            <string>__daemon-run</string>
          </array>
          <key>RunAtLoad</key><false/>
          <key>StandardOutPath</key><string>\(PBWPaths.daemonLog.path)</string>
          <key>StandardErrorPath</key><string>\(PBWPaths.daemonLog.path)</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: PBWPaths.launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.write(to: PBWPaths.launchAgent, atomically: true, encoding: .utf8)
            return .success(["installed": true, "path": PBWPaths.launchAgent.path, "note": "Load with launchctl if desired; pbw daemon start works without installation."])
        } catch {
            return .failure(code: "internal.daemon_install", message: error.localizedDescription)
        }
    }

    private static func uninstall() -> PBWExecutionResult {
        do {
            if FileManager.default.fileExists(atPath: PBWPaths.launchAgent.path) {
                try FileManager.default.removeItem(at: PBWPaths.launchAgent)
            }
            return .success(["uninstalled": true, "path": PBWPaths.launchAgent.path])
        } catch {
            return .failure(code: "internal.daemon_uninstall", message: error.localizedDescription)
        }
    }

    private static func request(_ line: String) -> [String: Any]? {
        do {
            let client = try UnixSocketClient(path: PBWPaths.daemonSocket.path)
            let data = try client.sendLine(line)
            return try PBWJSON.parseObject(data)
        } catch {
            return nil
        }
    }

    private static func appendLog(_ line: String) {
        try? PBWPaths.ensureBaseDirectories()
        let text = "\(PBWTime.nowString()) \(line)\n"
        if FileManager.default.fileExists(atPath: PBWPaths.daemonLog.path),
           let handle = try? FileHandle(forWritingTo: PBWPaths.daemonLog)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: PBWPaths.daemonLog, atomically: true, encoding: .utf8)
        }
    }
}

final class UnixSocketServer {
    private let fd: Int32
    private var acceptedFD: Int32?

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PBWError.internalFailure("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else { throw PBWError.invalidArgument("Socket path is too long.") }
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { src in
                strncpy(ptr, src, maxLength - 1)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw PBWError.internalFailure("bind() failed") }
        chmod(path, S_IRUSR | S_IWUSR)
        guard listen(fd, 8) == 0 else { throw PBWError.internalFailure("listen() failed") }
    }

    deinit {
        if let acceptedFD { close(acceptedFD) }
        close(fd)
    }

    func acceptLine() throws -> String {
        if let acceptedFD {
            close(acceptedFD)
        }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { throw PBWError.internalFailure("accept() failed") }
        acceptedFD = client
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(n)), as: UTF8.self)
    }

    func writeResponse(_ object: [String: Any]) throws {
        guard let acceptedFD else { return }
        let data = PBWJSON.encode(object)
        _ = data.withUnsafeBytes { write(acceptedFD, $0.baseAddress, data.count) }
        close(acceptedFD)
        self.acceptedFD = nil
    }
}

final class UnixSocketClient {
    private let fd: Int32

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PBWError.internalFailure("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else { throw PBWError.invalidArgument("Socket path is too long.") }
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { src in
                strncpy(ptr, src, maxLength - 1)
            }
        }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw PBWError.internalFailure("connect() failed") }
    }

    deinit { close(fd) }

    func sendLine(_ line: String) throws -> Data {
        let data = Data("\(line)\n".utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { throw PBWError.internalFailure("daemon returned no data") }
        return Data(buffer.prefix(Int(n)))
    }
}

enum PBWBridge {
    static func handle(command: String, args _: PBWArguments) -> PBWExecutionResult {
        switch command {
        case "bridge.status":
            return .success([
                "installed": false,
                "mode": "direct",
                "capability": "capability_unavailable.bridge_bundle",
                "permissions": [
                    "accessibility": PBWNative.accessibilityAllowed(),
                    "screenRecording": PBWNative.screenRecordingAllowed(),
                ],
            ])
        case "bridge.open":
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            let opened = NSWorkspace.shared.open(url)
            return .success(["opened": opened, "url": url.absoluteString, "note": "Open Screen Recording separately if capture is denied."])
        case "bridge.reset-permissions":
            return .failure(
                code: "capability_unavailable.bridge_reset_permissions",
                message: "Resetting TCC permissions is intentionally not automated by pbw.",
                details: ["manual": "Use System Settings or tccutil reset for the relevant service."],
            )
        case "bridge.install":
            return .failure(
                code: "capability_unavailable.bridge_bundle",
                message: "The v1 Swift package does not ship an app-bundled Bridge helper yet.",
                details: ["expectedUnlock": "Add a signed Bridge.app target that holds Screen Recording and Accessibility permissions."],
            )
        case "bridge.uninstall":
            return .success(["uninstalled": false, "reason": "Bridge app is not installed by this package."])
        default:
            return .failure(code: "invalid_argument.bridge_command", message: "Unknown bridge command.", exitCode: 2)
        }
    }
}
