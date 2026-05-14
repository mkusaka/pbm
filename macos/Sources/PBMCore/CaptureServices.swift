import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit

enum PBMObserve {
    static func image(args: PBMArguments) -> PBMExecutionResult {
        guard PBMNative.screenRecordingAllowed() else {
            return permissionDeniedScreenRecording()
        }
        let mode = args.string("mode") ?? "screen"
        let url = PBMOutputPath.resolve(
            rawPath: args.string("path"),
            defaultDirectory: PBMPaths.captures,
            defaultFilename: "capture-\(Int(Date().timeIntervalSince1970))",
            requiredExtension: "png",
        )
        do {
            let image: CGImage?
            var metadata: [String: Any] = [
                "mode": mode,
                "coordinateSpace": "logicalPoints",
            ]
            var strategy = "ScreenCaptureKit.SCScreenshotManager"
            switch mode {
            case "display", "screen":
                let explicitDisplay = args.options.keys.contains("display-id") || args.options.keys.contains("display")
                let displayID = CGDirectDisplayID(args.int("display-id") ?? args.int("display") ?? Int(CGMainDisplayID()))
                var fallbackReason: String?
                if
                    let content = try? PBMVideoRecorder.waitForShareableContent(),
                    let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = display.width
                    config.height = display.height
                    config.showsCursor = args.bool("cursor", fallback: true)
                    let capture = try captureImage(filter: filter, config: config)
                    image = capture.image
                    strategy = capture.strategy
                    let bounds = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
                    metadata["display"] = [
                        "id": Int(display.displayID),
                        "bounds": PBMNative.rectDict(bounds),
                        "scale": filter.pointPixelScale,
                    ]
                } else {
                    fallbackReason = "ScreenCaptureKit did not enumerate the requested display."
                    guard let arguments = PBMSystemScreencapture.screenArguments(
                        path: url.path,
                        displayID: displayID,
                        explicitDisplay: explicitDisplay,
                        cursor: args.bool("cursor", fallback: true),
                    ) else {
                        return .failure(code: "target_not_found", message: "Display was not found.", details: ["displayID": Int(displayID)])
                    }
                    let capture = try PBMSystemScreencapture.capture(arguments: arguments, outputURL: url)
                    image = capture.image
                    strategy = capture.strategy
                    metadata["display"] = PBMSystemScreencapture.displayMetadata(displayID: displayID, image: capture.image)
                }
                if let fallbackReason {
                    metadata["fallbackReason"] = fallbackReason
                }
            case "window":
                guard let windowID = args.int("window-id") ?? args.int("windowId") ?? args.int("handle") else {
                    return .failure(code: "invalid_argument.missing_window", message: "--window-id is required for --mode window.", exitCode: 2)
                }
                guard let window = PBMNative.windowList(onScreenOnly: false).first(where: { ($0["windowId"] as? Int) == windowID }) else {
                    return .failure(code: "target_not_found", message: "Window was not found for capture.", details: ["windowId": windowID])
                }
                let capture = try PBMSystemScreencapture.capture(
                    arguments: PBMSystemScreencapture.windowArguments(path: url.path, windowID: windowID),
                    outputURL: url,
                )
                image = capture.image
                strategy = capture.strategy
                metadata["windowId"] = windowID
                metadata["window"] = [
                    "windowId": windowID,
                    "bounds": window["bounds"] as? [String: Any] ?? [:],
                    "scale": PBMSystemScreencapture.scaleFromWindow(window, image: capture.image),
                ]
            default:
                return .failure(code: "invalid_argument.capture_mode", message: "Unsupported image mode.", details: ["mode": mode], exitCode: 2)
            }
            guard let image else {
                return .failure(code: "internal.capture_image", message: "macOS did not return an image.", details: metadata)
            }
            try PBMNative.writePNG(image, to: url)
            var data = metadata
            data["path"] = url.path
            data["width"] = image.width
            data["height"] = image.height
            data["native"] = true
            data["strategy"] = strategy
            return .success(data)
        } catch {
            if PBMObserve.isScreenCapturePermissionError(error) {
                return permissionDeniedScreenRecording(error: error)
            }
            if let captureError = error as? PBMSystemCaptureError, captureError.windowNotFound {
                return .failure(code: "target_not_found", message: "Window was not found for capture.", details: ["nativeError": captureError.localizedDescription])
            }
            return .failure(code: "internal.capture_image", message: error.localizedDescription)
        }
    }

    private struct CapturedImage {
        let image: CGImage
        let strategy: String
    }

    private static func captureImage(filter: SCContentFilter, config: SCStreamConfiguration) throws -> CapturedImage {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var image: CGImage?
            var error: Error?
        }
        let box = Box()
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
            box.image = image
            box.error = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        if let image = box.image {
            return CapturedImage(image: image, strategy: "ScreenCaptureKit.SCScreenshotManager")
        }
        do {
            return try captureFirstStreamFrame(filter: filter, config: config)
        } catch {
            throw box.error ?? error
        }
    }

    private static func captureFirstStreamFrame(filter: SCContentFilter, config: SCStreamConfiguration) throws -> CapturedImage {
        let semaphore = DispatchSemaphore(value: 0)
        let box = PBMFrameCaptureBox(semaphore: semaphore)
        let output = PBMFrameCaptureOutput(box: box)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "pbm.image.frame"))
        let startSemaphore = DispatchSemaphore(value: 0)
        final class StartBox: @unchecked Sendable {
            var error: Error?
        }
        let startBox = StartBox()
        stream.startCapture { error in
            startBox.error = error
            startSemaphore.signal()
        }
        _ = startSemaphore.wait(timeout: .now() + 10)
        if let error = startBox.error {
            throw error
        }
        _ = semaphore.wait(timeout: .now() + 10)
        let image = box.image
        let frameError = box.error
        let stopSemaphore = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in
            stopSemaphore.signal()
        }
        _ = stopSemaphore.wait(timeout: .now() + 5)
        if let image {
            return CapturedImage(image: image, strategy: "ScreenCaptureKit.SCStream.firstFrame")
        }
        throw frameError ?? PBMError.internalFailure("Timed out waiting for ScreenCaptureKit image frame.")
    }

    static func liveStart(args: PBMArguments) -> PBMExecutionResult {
        do {
            try PBMPaths.ensureBaseDirectories()
            let id = args.string("id") ?? "live-\(Int(Date().timeIntervalSince1970))"
            let session: [String: Any] = [
                "id": id,
                "kind": "live",
                "status": "running",
                "createdAt": PBMTime.nowString(),
                "strategy": "timer-image-fallback",
                "mode": args.string("mode") ?? "screen",
                "metadata": [
                    "screenCaptureKit": "reserved_for_bridge_or_daemon_streaming",
                    "coordinateSpace": "logicalPoints",
                ],
            ]
            try PBMJSON.encode(session, pretty: true).write(to: PBMPaths.sessions.appendingPathComponent("\(id).json"), options: .atomic)
            return .success(session)
        } catch {
            return .failure(code: "internal.live_start", message: error.localizedDescription)
        }
    }

    static func liveFrame(args: PBMArguments) -> PBMExecutionResult {
        let id = args.string("id")
        guard let session = session(kind: "live", id: id) else {
            return .failure(code: "target_not_found", message: "Live capture session was not found.", details: ["id": id ?? "latest"])
        }
        let path = PBMOutputPath.resolve(
            rawPath: args.string("path"),
            defaultDirectory: PBMPaths.captures,
            defaultFilename: "\(session["id"] ?? "live")-\(Int(Date().timeIntervalSince1970))",
            requiredExtension: "png",
        ).path
        let imageArgs = args.merged(with: ["path": path, "mode": session["mode"] as? String ?? "screen"])
        let result = image(args: imageArgs)
        if result.envelope["ok"] as? Bool == true, var data = result.envelope["data"] as? [String: Any] {
            data["sessionId"] = session["id"] ?? ""
            data["strategy"] = "timer-image-fallback"
            return .success(data)
        }
        return result
    }

    static func liveStatus(args: PBMArguments) -> PBMExecutionResult {
        let sessions = sessions(kind: "live")
        if let id = args.string("id") {
            guard let session = sessions.first(where: { ($0["id"] as? String) == id }) else {
                return .failure(code: "target_not_found", message: "Live capture session was not found.", details: ["id": id])
            }
            return .success(session)
        }
        return .success(["sessions": sessions])
    }

    static func liveStop(args: PBMArguments) -> PBMExecutionResult {
        guard let session = session(kind: "live", id: args.string("id")) else {
            return .failure(code: "target_not_found", message: "Live capture session was not found.", details: ["id": args.string("id") ?? "latest"])
        }
        let id = session["id"] as? String ?? ""
        let url = PBMPaths.sessions.appendingPathComponent("\(id).json")
        do {
            try FileManager.default.removeItem(at: url)
            return .success(["id": id, "status": "stopped"])
        } catch {
            return .failure(code: "internal.live_stop", message: error.localizedDescription)
        }
    }

    static func videoStart(args: PBMArguments) -> PBMExecutionResult {
        guard PBMNative.screenRecordingAllowed() else {
            return permissionDeniedScreenRecording()
        }
        guard let duration = args.double("duration") else {
            return .failure(
                code: "capability_unavailable.video_background_session",
                message: "Background video sessions require the daemon/Bridge runtime. Direct mode supports --duration only.",
                details: ["supportedDirectMode": "pbm observe capture video start --duration <seconds> --path <file.mp4>"],
            )
        }
        if #available(macOS 15.0, *) {
            return PBMVideoRecorder.recordDuration(args: args, duration: duration)
        }
        return .failure(code: "capability_unavailable.video_capture", message: "ScreenCaptureKit recording output requires macOS 15 or later.")
    }

    static func videoStatus(args: PBMArguments) -> PBMExecutionResult {
        let sessions = sessions(kind: "video")
        if let id = args.string("id") {
            guard let session = sessions.first(where: { ($0["id"] as? String) == id }) else {
                return .failure(code: "target_not_found", message: "Video capture session was not found.", details: ["id": id])
            }
            return .success(session)
        }
        return .success(["sessions": sessions])
    }

    static func videoStop(args _: PBMArguments) -> PBMExecutionResult {
        .failure(
            code: "capability_unavailable.video_background_session",
            message: "Direct mode does not keep background ScreenCaptureKit video streams alive. Use --duration or Bridge/daemon when implemented.",
            details: ["mode": "direct"],
        )
    }

    static func permissionDeniedScreenRecording(error: Error? = nil) -> PBMExecutionResult {
        var details: [String: Any] = [
            "service": "Screen Recording",
            "bundle": Bundle.main.bundleIdentifier ?? "pbm",
            "howToFix": "Grant Screen Recording permission to the pbm executable or Bridge app in System Settings.",
        ]
        if let error {
            details["nativeError"] = error.localizedDescription
        }
        return .failure(
            code: "permission_denied.screen_recording",
            message: "Screen Recording permission is required for capture.",
            details: details,
            retryHint: "Run `pbm diagnostics doctor` after granting permission.",
        )
    }

    private static func isScreenCapturePermissionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("tcc") || message.contains("screen recording") || message.contains("declined")
    }

    private static func session(kind: String, id: String?) -> [String: Any]? {
        let all = sessions(kind: kind)
        if let id {
            return all.first { ($0["id"] as? String) == id }
        }
        return all.sorted { ($0["createdAt"] as? String ?? "") > ($1["createdAt"] as? String ?? "") }.first
    }

    private static func sessions(kind: String) -> [[String: Any]] {
        try? PBMPaths.ensureBaseDirectories()
        let urls = (try? FileManager.default.contentsOfDirectory(at: PBMPaths.sessions, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let object = try? PBMJSON.parseObject(Data(contentsOf: url)),
                  object["kind"] as? String == kind
            else {
                return nil
            }
            return object
        }
    }
}

struct PBMSystemCaptureError: LocalizedError {
    let message: String
    let terminationStatus: Int32?

    var errorDescription: String? {
        message
    }

    var windowNotFound: Bool {
        message.localizedCaseInsensitiveContains("could not create image from window")
    }
}

enum PBMSystemScreencapture {
    struct CapturedImage {
        let image: CGImage
        let strategy: String
    }

    static func screenArguments(
        path: String,
        displayID: CGDirectDisplayID,
        explicitDisplay: Bool,
        cursor: Bool,
        mainDisplayID: CGDirectDisplayID = CGMainDisplayID(),
        activeDisplayIDs: [CGDirectDisplayID]? = nil,
    ) -> [String]? {
        var arguments = ["-x", "-t", "png"]
        let displayIDs = activeDisplayIDs ?? activeDisplays()
        if !explicitDisplay {
            arguments.append("-m")
        } else if let index = displayIDs.firstIndex(of: displayID) {
            arguments.append(contentsOf: ["-D", String(index + 1)])
        } else if displayID == mainDisplayID {
            arguments.append("-m")
        } else {
            return nil
        }
        if cursor {
            arguments.append("-C")
        }
        arguments.append(path)
        return arguments
    }

    static func windowArguments(path: String, windowID: Int) -> [String] {
        ["-l", String(windowID), "-o", "-x", "-t", "png", path]
    }

    static func capture(arguments: [String], outputURL: URL) throws -> CapturedImage {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let outputText = [
            stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr.fileHandleForReading.readDataToEndOfFile(),
        ]
        .compactMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            let message = outputText.isEmpty ? "screencapture exited with \(process.terminationStatus)" : outputText
            throw PBMSystemCaptureError(message: message, terminationStatus: process.terminationStatus)
        }

        let data = try Data(contentsOf: outputURL)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw PBMSystemCaptureError(message: "Failed to decode screencapture output.", terminationStatus: nil)
        }
        return CapturedImage(image: image, strategy: "system.screencapture")
    }

    static func displayMetadata(displayID: CGDirectDisplayID, image: CGImage) -> [String: Any] {
        let bounds = CGDisplayBounds(displayID)
        let scale = bounds.width > 0 ? Double(image.width) / Double(bounds.width) : 1.0
        return [
            "id": Int(displayID),
            "bounds": PBMNative.rectDict(bounds),
            "scale": scale,
            "coordinateSpace": "logicalPoints",
        ]
    }

    static func scaleFromWindow(_ window: [String: Any], image: CGImage) -> Double {
        guard
            let bounds = window["bounds"] as? [String: Any],
            let width = bounds.double("width"),
            width > 0
        else {
            return 1.0
        }
        return Double(image.width) / width
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }
}

private final class PBMFrameCaptureBox: @unchecked Sendable {
    private let semaphore: DispatchSemaphore
    private let lock = NSLock()
    private var completed = false
    var image: CGImage?
    var error: Error?

    init(semaphore: DispatchSemaphore) {
        self.semaphore = semaphore
    }

    func complete(image: CGImage? = nil, error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        self.image = image
        self.error = error
        completed = true
        semaphore.signal()
    }
}

private final class PBMFrameCaptureOutput: NSObject, SCStreamOutput {
    private let context = CIContext()
    private let box: PBMFrameCaptureBox

    init(box: PBMFrameCaptureBox) {
        self.box = box
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = context.createCGImage(image, from: rect) {
            box.complete(image: cgImage)
        }
    }
}

@available(macOS 15.0, *)
final class PBMRecordingDelegate: NSObject, SCRecordingOutputDelegate {
    var started = false
    var finished = false
    var error: Error?

    func recordingOutputDidStartRecording(_: SCRecordingOutput) {
        started = true
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: Error) {
        self.error = error
        finished = true
    }

    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        finished = true
    }
}

@available(macOS 15.0, *)
enum PBMVideoRecorder {
    static func recordDuration(args: PBMArguments, duration: Double) -> PBMExecutionResult {
        let outputURL = PBMOutputPath.resolve(
            rawPath: args.string("path"),
            defaultDirectory: PBMPaths.captures,
            defaultFilename: "capture-\(Int(Date().timeIntervalSince1970))",
            requiredExtension: "mp4",
        )
        let outputPath = outputURL.path
        do {
            try PBMPaths.ensureBaseDirectories()
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let content = try waitForShareableContent()
            guard let display = selectDisplay(content: content, args: args) else {
                return .failure(code: "target_not_found", message: "Display was not found for video capture.")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(args.int("fps") ?? 30))
            config.queueDepth = 3
            config.showsCursor = args.bool("cursor", fallback: true)
            config.captureMicrophone = false
            let delegate = PBMRecordingDelegate()
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = outputURL
            let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: delegate)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addRecordingOutput(recordingOutput)
            try waitForStreamStart(stream)
            Thread.sleep(forTimeInterval: max(0.1, duration))
            var warnings: [String] = []
            do {
                try waitForStreamStop(stream)
            } catch {
                warnings.append(error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(5)
            while !delegate.finished, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let bytes = attrs?[.size] as? Int ?? 0
            if let error = delegate.error, bytes == 0 {
                return .failure(code: "internal.video_record", message: error.localizedDescription)
            }
            var data: [String: Any] = [
                "path": outputURL.path,
                "duration": duration,
                "bytes": bytes,
                "strategy": "ScreenCaptureKit.SCRecordingOutput",
                "display": [
                    "displayID": display.displayID,
                    "width": display.width,
                    "height": display.height,
                ],
            ]
            if !warnings.isEmpty {
                data["warnings"] = warnings
            }
            return .success(data)
        } catch {
            return .failure(code: "internal.video_record", message: error.localizedDescription, details: ["path": outputPath])
        }
    }

    static func waitForShareableContent() throws -> SCShareableContent {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var output: SCShareableContent?
            var outputError: Error?
        }
        let box = Box()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            box.output = content
            box.outputError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        if let output = box.output { return output }
        throw box.outputError ?? PBMError.internalFailure("Timed out waiting for ScreenCaptureKit content.")
    }

    private static func selectDisplay(content: SCShareableContent, args: PBMArguments) -> SCDisplay? {
        if let id = args.int("display-id") ?? args.int("display") {
            return content.displays.first { Int($0.displayID) == id }
        }
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }

    private static func waitForStreamStart(_ stream: SCStream) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var outputError: Error?
        }
        let box = Box()
        stream.startCapture { error in
            box.outputError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        if let outputError = box.outputError {
            throw outputError
        }
    }

    private static func waitForStreamStop(_ stream: SCStream) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var outputError: Error?
        }
        let box = Box()
        stream.stopCapture { error in
            box.outputError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        if let outputError = box.outputError {
            throw outputError
        }
    }
}
