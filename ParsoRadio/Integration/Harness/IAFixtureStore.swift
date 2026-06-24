import Foundation
import CryptoKit

// On-disk record/replay fixture store for the integration harness.
//
// A fixture is keyed by a canonical request *signature*:
//     "<host><path>?<sorted-decoded-query>"   (GET only; host lowercased)
//
// Replay lookup is exact-match first, then a small ordered fallback for
// requests whose identifier is nondeterministic across runs (BookForYou's
// daily pick): any recorded `/services/img/` cover, then any recorded
// `/metadata/` document. Exact matches (e.g. `metadata/Laws_Plato`) always win.
struct RecordedResponse {
    let status: Int
    let contentType: String?
    let body: Data
    let originURL: URL
}

final class IAFixtureStore {
    private let directory: URL
    private let manifestURL: URL
    private let ioQueue = DispatchQueue(label: "guru.parso.harness.fixtures")

    struct Entry: Codable {
        var signature: String
        var url: String
        var status: Int
        var contentType: String?
        var bodyFile: String
    }

    private var entries: [Entry]
    private var index: [String: Entry]

    init(directory: URL) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let loaded = try? JSONDecoder().decode([Entry].self, from: data) {
            self.entries = loaded
        } else {
            self.entries = []
        }
        self.index = Dictionary(entries.map { ($0.signature, $0) },
                                uniquingKeysWith: { _, new in new })
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    // MARK: - Signature

    static func signature(host: String, path: String, query: [URLQueryItem]?) -> String {
        let h = host.lowercased()
        guard let query, !query.isEmpty else { return h + path }
        let sorted = query
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return h + path + "?" + sorted
    }

    static func signature(for url: URL) -> String {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url.host ?? "") + url.path
        }
        return signature(host: comps.host ?? "", path: comps.path, query: comps.queryItems)
    }

    // Signature for a rerouted loopback request: the origin host comes from the
    // header the protocol attached; path/query come from the loopback URL.
    static func signature(originHost: String, loopbackURL: URL) -> String {
        guard let comps = URLComponents(url: loopbackURL, resolvingAgainstBaseURL: false) else {
            return originHost.lowercased() + loopbackURL.path
        }
        return signature(host: originHost, path: comps.path, query: comps.queryItems)
    }

    // MARK: - Replay lookup

    func response(forSignature signature: String, path: String, originURL: URL) -> RecordedResponse? {
        if let exact = index[signature] {
            return makeResponse(exact, originURL: originURL)
        }
        // Fallback for nondeterministic daily picks.
        if path.contains("/services/img/"),
           let cover = entries.first(where: { $0.url.contains("/services/img/") }) {
            return makeResponse(cover, originURL: originURL)
        }
        if path.contains("/metadata/"),
           let meta = entries.first(where: { $0.url.contains("/metadata/") }) {
            return makeResponse(meta, originURL: originURL)
        }
        return nil
    }

    private func makeResponse(_ entry: Entry, originURL: URL) -> RecordedResponse? {
        let bodyURL = directory.appendingPathComponent(entry.bodyFile)
        guard let body = try? Data(contentsOf: bodyURL) else { return nil }
        return RecordedResponse(status: entry.status,
                                contentType: entry.contentType,
                                body: body,
                                originURL: originURL)
    }

    // MARK: - Record

    func record(signature: String, url: URL, status: Int, contentType: String?, body: Data) {
        ioQueue.sync {
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true)
            let ext = Self.fileExtension(for: contentType)
            let bodyFile = Self.sha(signature) + "." + ext
            try? body.write(to: directory.appendingPathComponent(bodyFile))
            let entry = Entry(signature: signature, url: url.absoluteString,
                              status: status, contentType: contentType, bodyFile: bodyFile)
            if let i = entries.firstIndex(where: { $0.signature == signature }) {
                entries[i] = entry
            } else {
                entries.append(entry)
            }
            index[signature] = entry
            entries.sort { $0.signature < $1.signature }
            if let data = try? JSONEncoder.sortedPretty.encode(entries) {
                try? data.write(to: manifestURL)
            }
        }
    }

    // MARK: - Helpers

    private static func sha(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private static func fileExtension(for contentType: String?) -> String {
        guard let ct = contentType?.lowercased() else { return "bin" }
        if ct.contains("json") { return "json" }
        if ct.contains("xml") { return "xml" }
        if ct.contains("html") { return "html" }
        if ct.contains("image") { return "bin" }
        if ct.contains("text") { return "txt" }
        return "bin"
    }
}

private extension JSONEncoder {
    static let sortedPretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
