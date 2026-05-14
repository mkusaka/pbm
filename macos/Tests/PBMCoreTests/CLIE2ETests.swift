import Foundation
@testable import PBMCore
import XCTest

final class CLIE2ETests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbm-cli-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
    }

    func testCLIStableEnvelopeExitCodesAndPolicy() throws {
        let initResult = try runPBM(["config", "init", "--force"])
        XCTAssertEqual(initResult.exitCode, 0)
        assertEnvelope(initResult.json, ok: true)

        let validateResult = try runPBM(["config", "validate"])
        XCTAssertEqual(validateResult.exitCode, 0)
        assertEnvelope(validateResult.json, ok: true)

        let capabilityResult = try runPBM(["space", "move-window"])
        XCTAssertEqual(capabilityResult.exitCode, 1)
        assertEnvelope(capabilityResult.json, ok: false, code: "capability_unavailable.space_move")

        let destructiveResult = try runPBM(["clipboard", "clear"])
        XCTAssertEqual(destructiveResult.exitCode, 2)
        assertEnvelope(destructiveResult.json, ok: false, code: "confirmation_required")
    }

    private func runPBM(_ arguments: [String]) throws -> (exitCode: Int32, json: [String: Any]) {
        guard let binary = ProcessInfo.processInfo.environment["PBM_BIN"], !binary.isEmpty else {
            throw XCTSkip("PBM_BIN is not set; skipping process-level CLI E2E.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PBM_HOME"] = tempHome.path
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        guard let json = try JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            let text = String(decoding: output + errorOutput, as: UTF8.self)
            XCTFail("pbm did not return a JSON object: \(text)")
            return (process.terminationStatus, [:])
        }
        return (process.terminationStatus, json)
    }

    private func assertEnvelope(
        _ envelope: [String: Any],
        ok: Bool,
        code: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(envelope["schemaVersion"] as? String, pbmStableSchemaVersion, file: file, line: line)
        XCTAssertEqual(envelope["ok"] as? Bool, ok, file: file, line: line)
        if ok {
            XCTAssertNotNil(envelope["data"], file: file, line: line)
        } else {
            let error = envelope["error"] as? [String: Any]
            XCTAssertNotNil(error, file: file, line: line)
            if let code {
                XCTAssertEqual(error?["code"] as? String, code, file: file, line: line)
            }
        }
    }
}
