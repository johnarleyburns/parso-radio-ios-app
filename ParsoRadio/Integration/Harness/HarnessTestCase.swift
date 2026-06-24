import XCTest

// Base class for integration tests that hit external APIs through the harness.
// Exposes the rerouted `session` to inject into services under test (and to use
// in place of `URLSession.shared`).
class HarnessTestCase: XCTestCase {
    var session: URLSession { IntegrationHarness.shared.session }
    var isReplay: Bool { IntegrationHarness.shared.isReplay }
}
