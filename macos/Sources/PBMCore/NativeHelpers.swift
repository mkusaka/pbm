import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

enum PBMNative {
    static func rectDict(_ rect: CGRect) -> [String: Any] {
        [
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "width": Double(rect.size.width),
            "height": Double(rect.size.height),
        ]
    }

    static func pointDict(_ point: CGPoint) -> [String: Any] {
        [
            "x": Double(point.x),
            "y": Double(point.y),
        ]
    }

    static func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    static func screenRecordingAllowed() -> Bool {
        if #available(macOS 10.15, *) {
            if screenRecordingPreflightAllowed() {
                return true
            }
            guard !isRunningUnderTests else {
                return false
            }
            return screenRecordingContentProbeAllowed()
        }
        return true
    }

    static func screenRecordingPreflightAllowed() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func screenRecordingContentProbeAllowed() -> Bool {
        guard !isRunningUnderTests else {
            return false
        }
        return screenCaptureContentProbeAllowed()
    }

    static func accessibilityAllowed() -> Bool {
        AXIsProcessTrusted()
    }

    static func postEventAllowed() -> Bool {
        CGPreflightPostEventAccess()
    }

    static func requestAccessibilityIfNeeded(prompt: Bool) -> Bool {
        guard !isRunningUnderTests else {
            return accessibilityAllowed()
        }
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func appleEventsAllowed(targetBundleIdentifier: String = "com.apple.systemevents") -> Bool {
        guard !isRunningUnderTests else { return false }
        guard var address = makeAppleEventTarget(bundleIdentifier: targetBundleIdentifier) else {
            return false
        }
        defer { AEDisposeDesc(&address) }
        let eventClass = AEEventClass(0x636F_7265)
        let eventID = AEEventID(0x6765_7464)
        return AEDeterminePermissionToAutomateTarget(&address, eventClass, eventID, false) == noErr
    }

    static func displays() -> [[String: Any]] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { id in
            let bounds = CGDisplayBounds(id)
            let pixelWidth = CGDisplayPixelsWide(id)
            let pixelHeight = CGDisplayPixelsHigh(id)
            let scale = bounds.width > 0 ? Double(pixelWidth) / Double(bounds.width) : 1.0
            return [
                "id": Int(id),
                "isMain": id == CGMainDisplayID(),
                "bounds": rectDict(bounds),
                "pixelWidth": Int(pixelWidth),
                "pixelHeight": Int(pixelHeight),
                "scale": scale,
                "coordinateSpace": "logicalPoints",
            ]
        }
    }

    static func windowList(onScreenOnly: Bool = true) -> [[String: Any]] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var index = 0
        return raw.compactMap { item in
            guard let windowNumber = item[kCGWindowNumber as String] as? Int else { return nil }
            index += 1
            let boundsDict = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let rect = CGRect(
                x: boundsDict.double("X") ?? 0,
                y: boundsDict.double("Y") ?? 0,
                width: boundsDict.double("Width") ?? 0,
                height: boundsDict.double("Height") ?? 0,
            )
            let ownerPID = item[kCGWindowOwnerPID as String] as? Int ?? 0
            let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
            let title = item[kCGWindowName as String] as? String ?? ""
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            let alpha = item[kCGWindowAlpha as String] as? Double ?? 1.0
            let isOnScreen = item[kCGWindowIsOnscreen as String] as? Bool ?? onScreenOnly
            let renderabilityReason = PBMWindowRenderability.disqualificationReason(
                bounds: rect,
                layer: layer,
                alpha: alpha,
                isOnScreen: isOnScreen,
            )
            return [
                "id": "W\(index)",
                "windowId": windowNumber,
                "handle": windowNumber,
                "ownerPID": ownerPID,
                "app": ownerName,
                "title": title,
                "bounds": rectDict(rect),
                "layer": layer,
                "alpha": alpha,
                "onScreen": isOnScreen,
                "isRenderable": renderabilityReason == nil,
                "renderabilityReason": renderabilityReason as Any? ?? NSNull(),
            ]
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PBMError.internalFailure("Failed to create image destination.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw PBMError.internalFailure("Failed to write PNG.")
        }
    }

    static func parsePoint(_ args: PBMArguments, xKey: String = "x", yKey: String = "y") -> CGPoint? {
        guard let x = args.double(xKey), let y = args.double(yKey) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    static func boolResult(_ value: Bool, reason: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["performed": value]
        if let reason {
            result["reason"] = reason
        }
        return result
    }

    private static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("--test-mode") ||
            NSClassFromString("XCTest") != nil
    }

    private static func screenCaptureContentProbeAllowed() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var ok = false
        }
        let box = Box()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            box.ok = content != nil
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return box.ok
    }

    private static func makeAppleEventTarget(bundleIdentifier: String) -> AEDesc? {
        guard let data = bundleIdentifier.data(using: .utf8), !data.isEmpty else {
            return nil
        }
        var address = AEDesc()
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }
            return OSStatus(AECreateDesc(DescType(typeApplicationBundleID), baseAddress, buffer.count, &address))
        }
        return status == noErr ? address : nil
    }
}

enum PBMWindowRenderability {
    static func disqualificationReason(
        bounds: CGRect,
        layer: Int,
        alpha: Double,
        isOnScreen: Bool,
        minWidth: CGFloat = 60,
        minHeight: CGFloat = 60,
    ) -> String? {
        if layer != 0 {
            return "layer != 0"
        }
        if alpha <= 0 {
            return "alpha too low"
        }
        if !isOnScreen {
            return "window off-screen"
        }
        if bounds.width < minWidth || bounds.height < minHeight {
            return "window too small"
        }
        return nil
    }

    static func bestWindow(from windows: [[String: Any]]) -> [String: Any]? {
        windows.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private static func score(_ window: [String: Any]) -> Double {
        var score = 0.0
        if window["isRenderable"] as? Bool == true {
            score += 2000
        }
        if (window["layer"] as? Int ?? 0) == 0 {
            score += 500
        }
        let title = window["title"] as? String ?? ""
        score += title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? -500 : 1500
        if let bounds = window["bounds"] as? [String: Any] {
            let area = (bounds.double("width") ?? 0) * (bounds.double("height") ?? 0)
            score += min(area / 150.0, 4000)
        }
        return score
    }
}

enum PBMOutputPath {
    static func resolve(
        rawPath: String?,
        defaultDirectory: URL,
        defaultFilename: String,
        requiredExtension: String,
    ) -> URL {
        var url: URL
        if let rawPath, !rawPath.isEmpty {
            let expanded = expandTilde(rawPath)
            url = URL(fileURLWithPath: expanded)
            if isDirectoryLike(path: rawPath, url: url) {
                url.appendPathComponent(defaultFilename)
            }
        } else {
            url = defaultDirectory.appendingPathComponent(defaultFilename)
        }

        let wanted = requiredExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        if url.pathExtension.lowercased() != wanted {
            url = url.deletingPathExtension().appendingPathExtension(wanted)
        }
        return url
    }

    private static func expandTilde(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }

    private static func isDirectoryLike(path: String, url: URL) -> Bool {
        if path.hasSuffix("/") {
            return true
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return false
    }
}

public struct PBMSnapshotStore {
    public init() {}

    public func create(config: PBMConfig, includeImage: Bool = false) -> PBMExecutionResult {
        do {
            try PBMPaths.ensureBaseDirectories()
            let built = buildSnapshot(config: config, includeImage: includeImage)
            if let error = built.error {
                return error
            }
            let snapshot = built.snapshot
            let id = snapshot["id"] as? String ?? "snapshot-\(Int(Date().timeIntervalSince1970))"
            let url = PBMPaths.snapshots.appendingPathComponent("\(id).json")
            try PBMJSON.encode(snapshot, pretty: true).write(to: url, options: .atomic)
            var data = snapshot
            data["path"] = url.path
            return .success(data)
        } catch {
            return .failure(code: "internal.snapshot_store", message: error.localizedDescription)
        }
    }

    public func list() -> PBMExecutionResult {
        do {
            try PBMPaths.ensureBaseDirectories()
            let urls = try FileManager.default.contentsOfDirectory(at: PBMPaths.snapshots, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            let items: [[String: Any]] = urls.map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return [
                    "id": url.deletingPathExtension().lastPathComponent,
                    "path": url.path,
                    "modifiedAt": values?.contentModificationDate.map { PBMTime.string(from: $0) } ?? NSNull(),
                    "bytes": values?.fileSize ?? 0,
                ]
            }
            return .success(["snapshots": items])
        } catch {
            return .failure(code: "internal.snapshot_list", message: error.localizedDescription)
        }
    }

    public func show(id: String?) -> PBMExecutionResult {
        guard let url = resolveSnapshotURL(id: id) else {
            return .failure(code: "target_not_found", message: "Snapshot was not found.", details: ["id": id ?? "latest"])
        }
        do {
            let object = try PBMJSON.parseObject(Data(contentsOf: url))
            return .success(object)
        } catch {
            return .failure(code: "internal.snapshot_read", message: error.localizedDescription, details: ["path": url.path])
        }
    }

    public func inspect(args: PBMArguments) -> PBMExecutionResult {
        guard let url = resolveSnapshotURL(id: args.string("snapshot") ?? args.string("id")) else {
            return .failure(code: "target_not_found", message: "Snapshot was not found.")
        }
        do {
            if let maxAge = args.double("max-age") ?? args.double("maxAge") {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values.contentModificationDate {
                    let age = Date().timeIntervalSince(modified)
                    if age > maxAge {
                        return .failure(
                            code: "stale_snapshot",
                            message: "Snapshot is older than the requested max age.",
                            details: [
                                "id": url.deletingPathExtension().lastPathComponent,
                                "ageSeconds": age,
                                "maxAgeSeconds": maxAge,
                            ],
                        )
                    }
                }
            }
            let snapshot = try PBMJSON.parseObject(Data(contentsOf: url))
            let target = args.string("target") ?? args.string("element") ?? args.string("window")
            if let target {
                for key in ["elements", "windows", "menus", "dialogs", "dock", "menubar", "spaces"] {
                    if let list = snapshot[key] as? [[String: Any]],
                       let item = list.first(where: { ($0["id"] as? String) == target })
                    {
                        return .success(["snapshot": snapshot["id"] ?? url.deletingPathExtension().lastPathComponent, "target": item])
                    }
                }
                return .failure(code: "target_not_found", message: "Target was not found in snapshot.", details: ["target": target])
            }
            return .success(["snapshot": snapshot])
        } catch {
            return .failure(code: "internal.snapshot_inspect", message: error.localizedDescription)
        }
    }

    public func clean(keep: Int) -> PBMExecutionResult {
        do {
            try PBMPaths.ensureBaseDirectories()
            let urls = try FileManager.default.contentsOfDirectory(at: PBMPaths.snapshots, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            let removed = Array(urls.dropFirst(max(0, keep)))
            for url in removed {
                try FileManager.default.removeItem(at: url)
            }
            return .success(["removed": removed.map(\.path), "kept": min(keep, urls.count)])
        } catch {
            return .failure(code: "internal.snapshot_clean", message: error.localizedDescription)
        }
    }

    public func export(id: String?, path: String?) -> PBMExecutionResult {
        guard let source = resolveSnapshotURL(id: id) else {
            return .failure(code: "target_not_found", message: "Snapshot was not found.", details: ["id": id ?? "latest"])
        }
        guard let path else {
            return .failure(code: "invalid_argument.missing_path", message: "--path is required.", exitCode: 2)
        }
        let destination = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return .success(["path": destination.path, "source": source.path])
        } catch {
            return .failure(code: "internal.snapshot_export", message: error.localizedDescription)
        }
    }

    public func resolveSnapshotURL(id: String?) -> URL? {
        try? PBMPaths.ensureBaseDirectories()
        if let id, !id.isEmpty {
            let url = PBMPaths.snapshots.appendingPathComponent("\(id).json")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let urls = (try? FileManager.default.contentsOfDirectory(at: PBMPaths.snapshots, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    private func buildSnapshot(config: PBMConfig, includeImage _: Bool) -> (snapshot: [String: Any], error: PBMExecutionResult?) {
        let createdAt = PBMTime.nowString()
        let safeID = createdAt
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "Z", with: "Z")
        let windows = PBMNative.windowList()
        let ax = PBMAX.snapshotElements(config: config)
        if let error = ax.error {
            return ([:], error)
        }
        var snapshot: [String: Any] = [
            "id": "macos-\(safeID)",
            "createdAt": createdAt,
            "platform": "macos",
            "mode": "direct",
            "display": PBMNative.displays(),
            "windows": windows,
            "elements": ax.elements,
            "menus": ax.menus,
            "dialogs": ax.dialogs,
            "dock": PBMDock.publicDockItems(),
            "menubar": ax.menubar,
            "spaces": [],
            "ocrText": NSNull(),
            "imagePath": NSNull(),
            "metadata": [
                "schemaVersion": pbmStableSchemaVersion,
                "permissions": [
                    "accessibility": PBMNative.accessibilityAllowed(),
                    "screenRecording": PBMNative.screenRecordingAllowed(),
                ],
                "coordinateSpace": "logicalPoints",
                "scale": "perDisplay",
                "ocr": [
                    "enabled": config.value(at: "ocr.enabled") as? Bool ?? false,
                    "engine": config.value(at: "ocr.engine") as? String ?? "none",
                ],
                "limits": ax.limits,
            ],
        ]
        if config.value(at: "redaction.snapshotText") as? Bool ?? true {
            snapshot = PBMRedactor.redactJSON(snapshot, config: config) as? [String: Any] ?? snapshot
        }
        return (snapshot, nil)
    }
}
