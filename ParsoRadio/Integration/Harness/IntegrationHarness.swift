import Foundation

// Process-wide orchestrator for the integration harness. Lazily boots the
// loopback fixture server (replay) or arms the recorder (record), and vends a
// `URLSession` configured to reroute through `IAHarnessURLProtocol`.
//
// Mode is selected by the `IA_HARNESS_MODE` environment variable:
//   - "record": hit the live APIs and capture fixtures into `Integration/Fixtures`.
//   - anything else (default): replay committed fixtures, fully offline.
final class IntegrationHarness {
    static let shared = IntegrationHarness()

    let mode: IAHarnessURLProtocol.Mode
    let fixturesDirectory: URL
    private let store: IAFixtureStore
    private var server: IAHarnessServer?
    private var didStart = false
    private let lock = NSLock()

    private init() {
        let env = ProcessInfo.processInfo.environment["IA_HARNESS_MODE"]?.lowercased()
        self.mode = (env == "record") ? .record : .replay
        self.fixturesDirectory = Self.locateFixturesDirectory()
        self.store = IAFixtureStore(directory: fixturesDirectory)
    }

    private func startIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !didStart else { return }
        IAHarnessURLProtocol.mode = mode
        IAHarnessURLProtocol.store = store
        if mode == .replay {
            let server = IAHarnessServer(store: store)
            IAHarnessURLProtocol.serverPort = (try? server.start()) ?? 0
            self.server = server
        }
        didStart = true
    }

    /// A session whose traffic is rerouted to the harness. Inject this into the
    /// services under test, and use it in place of `URLSession.shared`.
    var session: URLSession {
        startIfNeeded()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IAHarnessURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }

    var isReplay: Bool { mode == .replay }
    var fixtureCount: Int { store.count }

    private static func locateFixturesDirectory(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)        // .../Integration/Harness/IntegrationHarness.swift
            .deletingLastPathComponent()  // .../Integration/Harness
            .deletingLastPathComponent()  // .../Integration
            .appendingPathComponent("Fixtures")
    }
}
