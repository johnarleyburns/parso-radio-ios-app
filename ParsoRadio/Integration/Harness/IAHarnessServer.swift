import Foundation
import Network

// A minimal in-process loopback HTTP/1.1 server used during integration-test
// replay. It accepts rerouted requests from `IAHarnessURLProtocol`, reconstructs
// the original request signature (origin host carried in `X-Harness-Origin-Host`)
// and serves the recorded fixture bytes. One request per connection
// (`Connection: close`) keeps the implementation small.
final class IAHarnessServer {
    static let originHostHeader = "X-Harness-Origin-Host"

    private let store: IAFixtureStore
    private let queue = DispatchQueue(label: "guru.parso.harness.server")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    // Strong references to in-flight connections (NWConnection is not retained by
    // the framework — dropping the reference resets the connection).
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(store: IAFixtureStore) { self.store = store }

    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind explicitly to IPv4 loopback so the URLSession forwarder (which
        // connects to 127.0.0.1) reaches this listener. Without this the OS may
        // bind a family/interface the loopback connection never hits, and the
        // connection is reset before `newConnectionHandler` ever fires.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let e): startError = e; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        ready.wait()
        if let startError { throw startError }
        guard let p = listener.port?.rawValue else {
            throw NSError(domain: "IAHarnessServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "listener has no port"])
        }
        self.port = p
        return p
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock(); let conns = connections; connections.removeAll(); lock.unlock()
        conns.forEach { $0.cancel() }
    }

    // MARK: - Connection lifecycle

    private func accept(_ conn: NWConnection) {
        lock.lock(); connections.append(conn); lock.unlock()
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive(conn, buffer: Data())
            case .failed, .cancelled:
                self?.drop(conn)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func drop(_ conn: NWConnection) {
        lock.lock(); connections.removeAll { $0 === conn }; lock.unlock()
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let terminator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = buffer.subdata(in: buffer.startIndex..<terminator.lowerBound)
                self.respond(conn, headerBytes: header)
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    private func respond(_ conn: NWConnection, headerBytes: Data) {
        let headerText = String(decoding: headerBytes, as: UTF8.self)
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { send(conn, status: 400, body: Data()); return }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { send(conn, status: 400, body: Data()); return }
        let target = String(parts[1])

        var originHost = ""
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            if name.caseInsensitiveCompare(Self.originHostHeader) == .orderedSame {
                originHost = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let loopbackURL = URL(string: "http://127.0.0.1" + target) else {
            send(conn, status: 400, body: Data()); return
        }
        let path = URLComponents(url: loopbackURL, resolvingAgainstBaseURL: false)?.path ?? loopbackURL.path
        let signature = IAFixtureStore.signature(originHost: originHost, loopbackURL: loopbackURL)

        if let resp = store.response(forSignature: signature, path: path, originURL: loopbackURL) {
            send(conn, status: resp.status, contentType: resp.contentType, body: resp.body)
        } else {
            let msg = "harness: no fixture for \(signature)"
            send(conn, status: 404, contentType: "text/plain", body: Data(msg.utf8))
        }
    }

    private func send(_ conn: NWConnection, status: Int, contentType: String? = nil, body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType ?? "application/octet-stream")\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        // Send the full response, then a graceful FIN (`.finalMessage`) so the
        // client reads the entire body before teardown. Cancelling abortively
        // straight after `.contentProcessed` RSTs the socket and surfaces as
        // NSURLErrorNetworkConnectionLost (-1005) on the client.
        conn.send(content: out, completion: .contentProcessed { [weak self] _ in
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                      completion: .contentProcessed { _ in
                conn.cancel()
                self?.drop(conn)
            })
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "Status"
        }
    }
}
