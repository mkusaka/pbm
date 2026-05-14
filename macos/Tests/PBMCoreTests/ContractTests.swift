import Darwin
import Foundation
@testable import PBMCore
import XCTest

final class ContractTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbm-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("PBM_HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("PBM_HOME")
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
    }

    func testSuccessAndFailureEnvelopeShapes() throws {
        let success = PBMExecutionResult.success(["value": 1])
        assertStableEnvelope(success.envelope, ok: true)
        XCTAssertEqual(success.exitCode, 0)

        let failure = PBMExecutionResult.failure(code: "target_not_found", message: "missing", exitCode: 1)
        assertStableEnvelope(failure.envelope, ok: false)
        let error = try XCTUnwrap(failure.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "target_not_found")
    }

    func testCommandRegistryCoversRequiredSurface() {
        let names = Set(PBMCommandRegistry.commands.map(\.name))
        let required = [
            "observe.see", "observe.image", "observe.capture.live.start", "observe.capture.live.frame",
            "observe.capture.live.status", "observe.capture.live.stop", "observe.capture.video.start",
            "observe.capture.video.status", "observe.capture.video.stop",
            "input.click", "input.type", "input.press", "input.hotkey", "input.scroll", "input.drag", "input.move",
            "semantic.set-value", "semantic.perform-action",
            "window.list", "window.focus", "window.move", "window.resize", "window.set-bounds", "window.minimize",
            "window.maximize", "window.restore", "window.close",
            "app.list", "app.launch", "app.focus", "app.switch", "app.quit", "app.hide", "app.unhide", "app.relaunch", "app.open",
            "menu.list", "menu.click",
            "dialog.list", "dialog.click", "dialog.input", "dialog.dismiss", "dialog.file.choose", "dialog.file.save", "dialog.file.open",
            "clipboard.get", "clipboard.set", "clipboard.clear", "clipboard.paste",
            "dock.list", "dock.click", "dock.right-click", "dock.launch", "dock.hide", "dock.show", "dock.autohide", "dock.status",
            "menubar.list", "menubar.click", "menubar.open", "menubar.close",
            "space.list", "space.current", "space.switch", "space.move-window",
            "snapshot.list", "snapshot.show", "snapshot.inspect", "snapshot.clean", "snapshot.export",
            "overlay.show", "overlay.hide", "overlay.status",
            "daemon.start", "daemon.stop", "daemon.restart", "daemon.status", "daemon.logs", "daemon.install", "daemon.uninstall",
            "bridge.install", "bridge.open", "bridge.status", "bridge.reset-permissions", "bridge.uninstall",
            "config.init", "config.show", "config.validate", "config.get", "config.set",
            "diagnostics.doctor",
        ]
        for name in required {
            XCTAssertTrue(names.contains(name), "Missing command \(name)")
        }
    }

    func testDestructiveCommandsRequireConfirmationByDefault() throws {
        let result = PBMRuntime().runCLI(arguments: ["clipboard", "clear"])
        assertStableEnvelope(result.envelope, ok: false)
        XCTAssertEqual(result.exitCode, 2)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "confirmation_required")
    }

    func testToolPolicyDeniesCLICommands() throws {
        var config = PBMConfig()
        config.set(value: ["app.list"], at: "policy.deny")
        try config.save()

        let result = PBMRuntime().runCLI(arguments: ["app", "list"])
        assertStableEnvelope(result.envelope, ok: false)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "tool_denied")
    }

    func testSnapshotStaleErrorIsStructured() throws {
        try PBMPaths.ensureBaseDirectories()
        let id = "old"
        let url = PBMPaths.snapshots.appendingPathComponent("\(id).json")
        try PBMJSON.encode([
            "id": id,
            "createdAt": "2026-01-01T00:00:00.000Z",
            "platform": "macos",
        ]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: url.path)

        let result = PBMRuntime().runCLI(arguments: ["snapshot", "inspect", "--id", id, "--max-age", "0"])
        assertStableEnvelope(result.envelope, ok: false)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "stale_snapshot")
    }

    func testSnapshotInvalidScopeIsStructuredBeforeTCC() throws {
        var config = PBMConfig()
        config.set(value: "spaces", at: "snapshot.scope")

        let result = PBMSnapshotStore().create(config: config)

        assertStableEnvelope(result.envelope, ok: false)
        XCTAssertEqual(result.exitCode, 2)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "invalid_argument.snapshot_scope")
    }

    func testSnapshotConflictingTargetsAreStructuredBeforeTCC() throws {
        var config = PBMConfig()
        config.set(value: "allApps", at: "snapshot.scope")
        config.set(value: "com.example.Missing", at: "snapshot.bundleIdentifier")

        let result = PBMSnapshotStore().create(config: config)

        assertStableEnvelope(result.envelope, ok: false)
        XCTAssertEqual(result.exitCode, 2)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "invalid_argument.conflicting_snapshot_target")
    }

    func testSnapshotMissingTargetIsStructuredBeforeTCC() throws {
        var config = PBMConfig()
        config.set(value: "com.example.Missing", at: "snapshot.bundleIdentifier")

        let result = PBMSnapshotStore().create(config: config)

        assertStableEnvelope(result.envelope, ok: false)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "target_not_found")
    }

    func testMCPToolsListAndToolCallReturnStableEnvelope() throws {
        let server = PBMMCPServer(runtime: PBMRuntime())
        let list = server.toolList()
        XCTAssertFalse(list.isEmpty)
        for tool in list {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        }
        let observeSee = try XCTUnwrap(list.first { $0["name"] as? String == "observe.see" })
        let observeSchema = try XCTUnwrap(observeSee["inputSchema"] as? [String: Any])
        let observeProperties = try XCTUnwrap(observeSchema["properties"] as? [String: Any])
        XCTAssertNotNil(observeProperties["scope"])
        XCTAssertNotNil(observeProperties["bundle-id"])
        XCTAssertNotNil(observeProperties["bundleId"])
        XCTAssertNotNil(observeProperties["app-id"])
        XCTAssertNotNil(observeProperties["appId"])
        XCTAssertNotNil(observeProperties["pid"])
        XCTAssertNotNil(observeProperties["app"])
        XCTAssertNotNil(observeProperties["max-depth"])
        XCTAssertNotNil(observeProperties["max-elements"])

        let response = try XCTUnwrap(server.handle(message: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "space.move-window",
                "arguments": [:],
            ],
        ]))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        assertStableEnvelope(result, ok: false)
        let error = try XCTUnwrap(result["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "capability_unavailable.space_move")
    }

    func testGoldenFixturesAreStableEnvelopes() throws {
        let root = try repositoryRoot()
        let fixtureURL = root.appendingPathComponent("tests/golden", isDirectory: true)
        let fixtures = try FileManager.default.contentsOfDirectory(at: fixtureURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThan(fixtures.count, 0)
        var observedCodes: Set<String> = []
        for fixture in fixtures {
            let object = try PBMJSON.parseObject(Data(contentsOf: fixture))
            let ok = try XCTUnwrap(object["ok"] as? Bool, fixture.lastPathComponent)
            assertStableEnvelope(object, ok: ok)
            if !ok, let error = object["error"] as? [String: Any], let code = error["code"] as? String {
                observedCodes.insert(code)
            }
        }
        for code in [
            "permission_denied.screen_recording",
            "permission_denied.accessibility",
            "target_not_found",
            "target_ambiguous",
            "stale_snapshot",
            "capability_unavailable.space_move",
            "tool_denied",
        ] {
            XCTAssertTrue(observedCodes.contains(code), "Missing golden error \(code)")
        }
    }

    func testSystemScreencaptureScreenArgumentsAreDeterministic() throws {
        let arguments = try XCTUnwrap(PBMSystemScreencapture.screenArguments(
            path: "/tmp/pbm.png",
            displayID: 42,
            explicitDisplay: true,
            cursor: true,
            mainDisplayID: 1,
            activeDisplayIDs: [1, 42],
        ))
        XCTAssertEqual(arguments, ["-x", "-t", "png", "-D", "2", "-C", "/tmp/pbm.png"])

        let mainFallback = try XCTUnwrap(PBMSystemScreencapture.screenArguments(
            path: "/tmp/main.png",
            displayID: 1,
            explicitDisplay: false,
            cursor: false,
            mainDisplayID: 1,
            activeDisplayIDs: [],
        ))
        XCTAssertEqual(mainFallback, ["-x", "-t", "png", "-m", "/tmp/main.png"])

        XCTAssertNil(PBMSystemScreencapture.screenArguments(
            path: "/tmp/missing.png",
            displayID: 99,
            explicitDisplay: true,
            cursor: false,
            mainDisplayID: 1,
            activeDisplayIDs: [],
        ))
    }

    func testSystemScreencaptureWindowArgumentsUseFixedExecutableArguments() {
        XCTAssertEqual(
            PBMSystemScreencapture.windowArguments(path: "/tmp/window.png", windowID: 123),
            ["-l", "123", "-o", "-x", "-t", "png", "/tmp/window.png"],
        )
    }

    private func assertStableEnvelope(_ envelope: [String: Any], ok: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(envelope["schemaVersion"] as? String, pbmStableSchemaVersion, file: file, line: line)
        XCTAssertEqual(envelope["ok"] as? Bool, ok, file: file, line: line)
        if ok {
            XCTAssertNotNil(envelope["data"], file: file, line: line)
        } else {
            XCTAssertNotNil(envelope["error"], file: file, line: line)
        }
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw PBMError.internalFailure("Package.swift was not found.")
    }
}
