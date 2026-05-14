import Foundation
@testable import PBMCore
import XCTest

final class IntegrationTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbm-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("PBM_HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("PBM_HOME")
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
    }

    func testConfigSnapshotAndCapabilityCommandsReturnStableEnvelopes() throws {
        let runtime = PBMRuntime()

        assertEnvelope(runtime.runCLI(arguments: ["config", "init", "--force"]), ok: true)
        assertEnvelope(runtime.runCLI(arguments: ["config", "validate"]), ok: true)
        assertEnvelope(runtime.runCLI(arguments: ["snapshot", "list"]), ok: true)

        let spaceMove = runtime.runCLI(arguments: ["space", "move-window"])
        assertEnvelope(spaceMove, ok: false)
        XCTAssertEqual(spaceMove.exitCode, 1)
        let error = try XCTUnwrap(spaceMove.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "capability_unavailable.space_move")
    }

    func testLiveSessionLifecycleDoesNotRequireCapturePermissionsUntilFrame() throws {
        let runtime = PBMRuntime()

        let start = runtime.runCLI(arguments: ["capture", "live", "start", "--id", "integration-live"])
        assertEnvelope(start, ok: true)

        let status = runtime.runCLI(arguments: ["capture", "live", "status", "--id", "integration-live"])
        assertEnvelope(status, ok: true)
        let statusData = try XCTUnwrap(status.envelope["data"] as? [String: Any])
        XCTAssertEqual(statusData["status"] as? String, "running")

        let stop = runtime.runCLI(arguments: ["capture", "live", "stop", "--id", "integration-live"])
        assertEnvelope(stop, ok: true)
        let stopData = try XCTUnwrap(stop.envelope["data"] as? [String: Any])
        XCTAssertEqual(stopData["status"] as? String, "stopped")
    }

    func testCLIDestructiveConfirmationPolicyAppliesBeforeNativeWork() throws {
        let result = PBMRuntime().runCLI(arguments: ["window", "close"])
        assertEnvelope(result, ok: false)
        XCTAssertEqual(result.exitCode, 2)
        let error = try XCTUnwrap(result.envelope["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "confirmation_required")
    }

    private func assertEnvelope(
        _ result: PBMExecutionResult,
        ok: Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(result.envelope["schemaVersion"] as? String, pbmStableSchemaVersion, file: file, line: line)
        XCTAssertEqual(result.envelope["ok"] as? Bool, ok, file: file, line: line)
        if ok {
            XCTAssertNotNil(result.envelope["data"], file: file, line: line)
        } else {
            XCTAssertNotNil(result.envelope["error"], file: file, line: line)
        }
    }
}
