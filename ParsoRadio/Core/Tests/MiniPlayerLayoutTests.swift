import XCTest

final class MiniPlayerLayoutTests: XCTestCase {

    private func rootTabViewSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceFile = projectRoot
            .appendingPathComponent("Views")
            .appendingPathComponent("RootTabView.swift")
        return try String(contentsOf: sourceFile)
    }

    func testMiniPlayerIsNotOverlay() throws {
        let source = try rootTabViewSource()
        XCTAssertFalse(source.contains(".overlay"),
            "MiniPlayer must NOT use .overlay on TabView — it covers the tab bar. "
            + "Apply .miniPlayerInset() to each tab's content instead.")
    }

    func testMiniPlayerAppliedPerTabNotOnTabView() throws {
        let source = try rootTabViewSource()
        let perTabCount = source.components(separatedBy: "miniPlayerInset()").count - 1
        XCTAssertGreaterThanOrEqual(perTabCount, 3,
            "Every tab must have .miniPlayerInset() so the mini player sits above — not over — the tab bar")
    }

    func testMiniPlayerNotDirectlyInBody() throws {
        let source = try rootTabViewSource()
        let lines = source.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            guard line.contains("MiniPlayer()") else { continue }
            let nearby = lines[max(0, i - 5)...i].joined(separator: "\n")
            XCTAssertFalse(nearby.contains("TabView") || nearby.contains("var body"),
                "MiniPlayer() at line \(i + 1) appears to be applied at the TabView level. "
                + "It must live inside miniPlayerInset() and be applied per-tab.")
        }
    }
}
