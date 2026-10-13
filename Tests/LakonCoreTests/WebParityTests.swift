import XCTest
@testable import LakonCore
@testable import LakonRender

/// The HTML export runs web/*.js, a port of LakonCore. These tests replay the same scripted input through both
/// and require identical per-frame snapshots (Simulation.swift ⇄ web/sim.js). Skipped when Node isn't installed.
final class WebParityTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func node() -> String? {
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    func runParity(project root: URL, script name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let node = Self.node() else { throw XCTSkip("node not found") }
        let scriptURL = Self.repo.appendingPathComponent("web/test/\(name)")
        let swift = Simulation.run(project: try Project.load(from: root), script: try JSONDecoder().decode(Simulation.Script.self, from: Data(contentsOf: scriptURL)))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-js-\(UUID().uuidString).txt")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [Self.repo.appendingPathComponent("web/sim.js").path, root.path, scriptURL.path, out.path]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, file: file, line: line)
        let js = try String(contentsOf: out, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try? FileManager.default.removeItem(at: out)
        XCTAssertEqual(js.count, swift.count, file: file, line: line)
        if let i = zip(swift, js).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            XCTFail("first divergence at frame \(i + 1)\nswift: \(swift[i])\njs:    \(js[i])", file: file, line: line)
        }
    }

    func testDemoPlaythroughMatches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-parity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SampleProject.create(at: dir, title: "Parity")
        try runParity(project: dir, script: "parity-demo.json")
        try runParity(project: dir, script: "parity-walk.json")
    }

    /// LAKON_MZ_FIXTURE=<imported MZ project> runs the same walk on real MZ data.
    func testMZFixtureMatches() throws {
        guard let path = ProcessInfo.processInfo.environment["LAKON_MZ_FIXTURE"] else { throw XCTSkip("set LAKON_MZ_FIXTURE") }
        let src = URL(fileURLWithPath: path)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-mzparity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = FileManager.default.fileExists(atPath: src.appendingPathComponent(Project.markerFile).path) ? src : try Project.importMZ(from: src, to: dir).root
        try runParity(project: root, script: "parity-walk.json")
    }
}
