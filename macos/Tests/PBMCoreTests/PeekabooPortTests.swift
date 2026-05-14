import CoreGraphics
import Foundation
@testable import PBMCore
import XCTest

final class PeekabooPortTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbm-peekaboo-port-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("PBM_HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("PBM_HOME")
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
    }

    func testVersionCommandReturnsStableEnvelope() throws {
        let result = PBMCLI().run(arguments: ["--version"])

        assertEnvelope(result, ok: true)
        let data = try XCTUnwrap(result.envelope["data"] as? [String: Any])
        XCTAssertEqual(data["name"] as? String, "pbm")
        XCTAssertEqual(data["version"] as? String, "0.0.1")
    }

    func testHotkeyParserAcceptsPeekabooStyleAliases() throws {
        let plan = try XCTUnwrap(PBMHotkeyKey.plan("command shift p"))

        XCTAssertEqual(plan.primaryKey, "p")
        XCTAssertEqual(plan.keyCode, 0x23)
        XCTAssertTrue(plan.modifiers.contains(.maskCommand))
        XCTAssertTrue(plan.modifiers.contains(.maskShift))
        XCTAssertNil(PBMHotkeyKey.plan("cmd+p+q"))
        XCTAssertNil(PBMHotkeyKey.plan("cmd+shift"))
    }

    func testMousePathIsDeterministicLinearPath() {
        let path = PBMMousePath.linear(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 80), steps: 3)

        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path[0].x, 20)
        XCTAssertEqual(path[0].y, 40)
        XCTAssertEqual(path[1].x, 30)
        XCTAssertEqual(path[1].y, 60)
        XCTAssertEqual(path[2].x, 40)
        XCTAssertEqual(path[2].y, 80)
    }

    func testOutputPathResolverTreatsDirectoriesAndExtensionsDeterministically() throws {
        let directory = tempHome.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let directoryPath = PBMOutputPath.resolve(
            rawPath: directory.path,
            defaultDirectory: tempHome,
            defaultFilename: "screen",
            requiredExtension: "png",
        )
        XCTAssertEqual(directoryPath.lastPathComponent, "screen.png")

        let missingExtension = PBMOutputPath.resolve(
            rawPath: tempHome.appendingPathComponent("named").path,
            defaultDirectory: tempHome,
            defaultFilename: "fallback",
            requiredExtension: "png",
        )
        XCTAssertEqual(missingExtension.lastPathComponent, "named.png")

        let wrongExtension = PBMOutputPath.resolve(
            rawPath: tempHome.appendingPathComponent("image.jpg").path,
            defaultDirectory: tempHome,
            defaultFilename: "fallback",
            requiredExtension: "png",
        )
        XCTAssertEqual(wrongExtension.lastPathComponent, "image.png")
    }

    func testWindowRenderabilityScoresUsableWindowsAboveUtilityEntries() {
        let visibleWindow: [String: Any] = [
            "title": "Main",
            "layer": 0,
            "isRenderable": true,
            "bounds": ["x": 0, "y": 0, "width": 800, "height": 600],
        ]
        let tinyOverlay: [String: Any] = [
            "title": "",
            "layer": 25,
            "isRenderable": false,
            "bounds": ["x": 0, "y": 0, "width": 10, "height": 10],
        ]

        XCTAssertNil(PBMWindowRenderability.disqualificationReason(bounds: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 1, isOnScreen: true))
        XCTAssertEqual(PBMWindowRenderability.disqualificationReason(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), layer: 0, alpha: 1, isOnScreen: true), "window too small")
        XCTAssertEqual(PBMWindowRenderability.bestWindow(from: [tinyOverlay, visibleWindow])?["title"] as? String, "Main")
    }

    func testTargetResolverPrefersExactTextThenSupportsScopedSelectors() throws {
        try writeTargetSnapshot()

        let byText = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "targets", "target-text": "Open"], positionals: []))
        XCTAssertNil(byText.error)
        XCTAssertEqual(byText.target?.id, "B1")
        XCTAssertEqual(byText.target?.point.x, 20)
        XCTAssertEqual(byText.target?.point.y, 30)

        let byAutomationID = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "targets", "automation-id": "name-field"], positionals: []))
        XCTAssertNil(byAutomationID.error)
        XCTAssertEqual(byAutomationID.target?.id, "T1")

        let scoped = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "targets", "app": "Chrome", "window-id": 123, "role": "button", "index": 1], positionals: []))
        XCTAssertNil(scoped.error)
        XCTAssertEqual(scoped.target?.id, "B2")
    }

    func testTargetResolverStructuredFailures() throws {
        try writeTargetSnapshot()

        let ambiguous = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "targets", "target-title": "Duplicate"], positionals: []))
        XCTAssertNil(ambiguous.target)
        assertError(ambiguous.error, code: "target_ambiguous")

        let conflicting = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "targets", "id": "B1", "target-text": "Open"], positionals: []))
        XCTAssertNil(conflicting.target)
        assertError(conflicting.error, code: "invalid_argument.conflicting_target")

        let stale = PBMTargetResolver.resolve(args: PBMArguments(options: ["snapshot": "missing", "id": "B1"], positionals: []))
        XCTAssertNil(stale.target)
        assertError(stale.error, code: "stale_snapshot")
    }

    func testMCPToolSchemasExposePortedOptions() throws {
        let server = PBMMCPServer()
        let tools = server.toolList()

        let observeSee = try XCTUnwrap(tools.first { $0["name"] as? String == "observe.see" })
        let observeProperties = try schemaProperties(observeSee)
        XCTAssertNotNil(observeProperties["max-children"])
        XCTAssertNotNil(observeProperties["window-title"])
        XCTAssertNotNil(observeProperties["timeout"])

        let inputClick = try XCTUnwrap(tools.first { $0["name"] as? String == "input.click" })
        let inputProperties = try schemaProperties(inputClick)
        XCTAssertNotNil(inputProperties["target-text"])
        XCTAssertNotNil(inputProperties["automation-id"])

        let semanticSetValue = try XCTUnwrap(tools.first { $0["name"] as? String == "semantic.set-value" })
        let semanticProperties = try schemaProperties(semanticSetValue)
        XCTAssertNotNil(semanticProperties["value"])
        XCTAssertNotNil(semanticProperties["focused"])
        XCTAssertNotNil(semanticProperties["target-text"])

        let windowFocus = try XCTUnwrap(tools.first { $0["name"] as? String == "window.focus" })
        let windowProperties = try schemaProperties(windowFocus)
        XCTAssertNotNil(windowProperties["window-id"])
        XCTAssertNotNil(windowProperties["handle"])

        let clipboardGet = try XCTUnwrap(tools.first { $0["name"] as? String == "clipboard.get" })
        let clipboardProperties = try schemaProperties(clipboardGet)
        XCTAssertNotNil(clipboardProperties["base64"])
        XCTAssertNotNil(clipboardProperties["output-path"])
        XCTAssertNotNil(clipboardProperties["max-bytes"])
    }

    private func writeTargetSnapshot() throws {
        try PBMPaths.ensureBaseDirectories()
        let snapshot: [String: Any] = [
            "id": "targets",
            "createdAt": "2026-05-15T00:00:00.000Z",
            "platform": "macos",
            "elements": [
                element(id: "B1", title: "Open", text: "Open", automationID: "open-button", role: "AXButton", x: 10, y: 20, width: 20, height: 20),
                element(id: "B2", title: "Open Settings", text: "Open Settings", automationID: "settings-button", role: "AXButton", x: 40, y: 20, width: 20, height: 20),
                element(id: "T1", title: "Name", text: "Name", automationID: "name-field", role: "AXTextField", x: 70, y: 20, width: 80, height: 20),
                element(id: "B3", title: "Duplicate", text: "Duplicate", automationID: "duplicate-one", role: "AXButton", x: 10, y: 60, width: 20, height: 20),
                element(id: "B4", title: "Duplicate", text: "Duplicate", automationID: "duplicate-two", role: "AXButton", x: 40, y: 60, width: 20, height: 20),
            ],
        ]
        let url = PBMPaths.snapshots.appendingPathComponent("targets.json")
        try PBMJSON.encode(snapshot, pretty: true).write(to: url, options: .atomic)
    }

    private func element(
        id: String,
        title: String,
        text: String,
        automationID: String,
        role: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "text": text,
            "automationId": automationID,
            "role": role,
            "app": "Google Chrome",
            "bundleIdentifier": "com.google.Chrome",
            "windowId": 123,
            "bounds": [
                "x": x,
                "y": y,
                "width": width,
                "height": height,
            ],
        ]
    }

    private func schemaProperties(_ tool: [String: Any]) throws -> [String: Any] {
        let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
        return try XCTUnwrap(schema["properties"] as? [String: Any])
    }

    private func assertEnvelope(
        _ result: PBMExecutionResult,
        ok: Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(result.envelope["schemaVersion"] as? String, pbmStableSchemaVersion, file: file, line: line)
        XCTAssertEqual(result.envelope["ok"] as? Bool, ok, file: file, line: line)
    }

    private func assertError(
        _ result: PBMExecutionResult?,
        code: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let result = try? XCTUnwrap(result, file: file, line: line)
        XCTAssertEqual(result?.envelope["ok"] as? Bool, false, file: file, line: line)
        let error = result?.envelope["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, code, file: file, line: line)
    }
}
