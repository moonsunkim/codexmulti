import Foundation
import XCTest
@testable import CodexMulti

final class KeychainProbeLaunchTests: XCTestCase {
    func testLaunchOptionsParseKeychainProbe() {
        XCTAssertTrue(LaunchOptions(arguments: ["CodexMulti", "--keychain-probe"]).keychainProbe)
        XCTAssertFalse(LaunchOptions(arguments: ["CodexMulti"]).keychainProbe)
    }

    func testProbeCreatesProbesPrintsVerbatimAndDestroysExactlyOnce() {
        let fake = FakeABI(bytes: Data())
        let json = Data(#"{"schema":1,"signer_valid":true,"accounts":[]}"#.utf8)
        fake.probeBytes = json
        var stdout = Data()
        var stderr = Data()

        let code = KeychainProbeLaunch.run(
            abi: fake.abi,
            writeStandardOutput: { stdout.append($0) },
            writeStandardError: { stderr.append($0) }
        )

        XCTAssertEqual(code, 0)
        XCTAssertEqual(fake.calls, ["create", "probe", "destroy"])
        XCTAssertEqual(fake.creates, 1)
        XCTAssertEqual(fake.probes, 1)
        XCTAssertEqual(fake.destroys, 1)
        XCTAssertEqual(stdout, json, "the shell must not wrap or append a newline to the core JSON")
        XCTAssertTrue(stderr.isEmpty)
    }

    func testCreateFailureMapsToExitOneWithoutProbeOrDestroy() {
        let fake = FakeABI(bytes: Data())
        fake.createSucceeds = false
        var stdout = Data()
        var stderr = Data()

        let code = KeychainProbeLaunch.run(
            abi: fake.abi,
            writeStandardOutput: { stdout.append($0) },
            writeStandardError: { stderr.append($0) }
        )

        XCTAssertEqual(code, 1)
        XCTAssertEqual(fake.calls, ["create"])
        XCTAssertEqual(fake.probes, 0)
        XCTAssertEqual(fake.destroys, 0)
        XCTAssertTrue(stdout.isEmpty)
        XCTAssertEqual(String(decoding: stderr, as: UTF8.self), "CodexMulti: keychain probe could not create core\n")
    }

    func testRuntimeAndProbeErrorsMapToExitOneAndStillDestroy() {
        for result: Int32 in [-1, -2, -3] {
            let fake = FakeABI(bytes: Data())
            fake.probeResult = result
            var stdout = Data()
            var stderr = Data()

            let code = KeychainProbeLaunch.run(
                abi: fake.abi,
                writeStandardOutput: { stdout.append($0) },
                writeStandardError: { stderr.append($0) }
            )

            XCTAssertEqual(code, 1)
            XCTAssertEqual(fake.calls, ["create", "probe", "destroy"])
            XCTAssertEqual(fake.creates, 1)
            XCTAssertEqual(fake.probes, 1)
            XCTAssertEqual(fake.destroys, 1)
            XCTAssertTrue(stdout.isEmpty)
            XCTAssertEqual(String(decoding: stderr, as: UTF8.self), "CodexMulti: keychain probe failed (\(result))\n")
        }
    }
}
