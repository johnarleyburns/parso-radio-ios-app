import Foundation

// Reroutes outbound HTTP(S) requests issued by the production services during
// integration tests.
//
//  - replay (default): forwards the request to the loopback IAHarnessServer,
//    carrying the original host in `X-Harness-Origin-Host`, and presents the
//    recorded response back to the caller AS IF it came from the original URL
//    (so production code and assertions see real archive.org URLs).
//  - record: performs the real request against the live origin, saves the
//    response to the fixture store, and returns the real bytes.
//
// Static config is set once by `IntegrationHarness` before the suite runs;
// integration tests execute sequentially, so static state is safe (matching the
// existing MockURLProtocol convention).
final class IAHarnessURLProtocol: URLProtocol {
    enum Mode { case record, replay }

    static var mode: Mode = .replay
    static var serverPort: UInt16 = 0
    static var store: IAFixtureStore?

    // A plain session WITHOUT this protocol installed — used to perform the
    // loopback (replay) or live (record) request so we never recurse.
    private static let forwarder: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    private var forwardingTask: URLSessionDataTask?

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        let host = request.url?.host?.lowercased() ?? ""
        if host == "127.0.0.1" || host == "localhost" { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let originalURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch Self.mode {
        case .replay: startReplay(originalURL: originalURL)
        case .record: startRecord(originalURL: originalURL)
        }
    }

    override func stopLoading() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    // MARK: - Replay

    private func startReplay(originalURL: URL) {
        guard let loopbackURL = Self.loopbackURL(for: originalURL) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var fwd = URLRequest(url: loopbackURL)
        fwd.httpMethod = request.httpMethod ?? "GET"
        fwd.setValue(originalURL.host, forHTTPHeaderField: IAHarnessServer.originHostHeader)

        forwardingTask = Self.forwarder.dataTask(with: fwd) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let contentType = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            self.deliver(originalURL: originalURL, status: status,
                         contentType: contentType, body: data ?? Data())
        }
        forwardingTask?.resume()
    }

    // MARK: - Record

    private func startRecord(originalURL: URL) {
        var fwd = URLRequest(url: originalURL)
        fwd.httpMethod = request.httpMethod ?? "GET"
        // Mirror the app's User-Agent expectations minimally; IA is lenient.
        forwardingTask = Self.forwarder.dataTask(with: fwd) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 200
            let contentType = http?.value(forHTTPHeaderField: "Content-Type")
            let body = data ?? Data()

            let signature = IAFixtureStore.signature(for: originalURL)
            Self.store?.record(signature: signature, url: originalURL,
                               status: status, contentType: contentType, body: body)

            self.deliver(originalURL: originalURL, status: status,
                         contentType: contentType ?? "application/octet-stream", body: body)
        }
        forwardingTask?.resume()
    }

    // MARK: - Helpers

    private func deliver(originalURL: URL, status: Int, contentType: String, body: Data) {
        guard let response = HTTPURLResponse(
            url: originalURL, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType,
                           "Content-Length": "\(body.count)"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func loopbackURL(for originalURL: URL) -> URL? {
        guard var comps = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = Int(serverPort)
        return comps.url
    }
}
