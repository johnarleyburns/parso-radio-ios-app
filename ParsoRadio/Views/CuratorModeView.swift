import SwiftUI
import UIKit

/// Curator Mode (Phase 3 + 4): channel list with verdict counts → per-channel
/// review (Audition / Accept / Reject / Skip / Approve Album) → Export the
/// approved set as JSON + CSV (share sheet — email included). See
/// CURATOR-MODE-PLAN.md.
struct CuratorModeView: View {
    let db: DatabaseService
    let archiveService: InternetArchiveService

    @ObservedObject private var curator = CuratorController.shared
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var counts: [String: (review: Int, approved: Int, rejected: Int)] = [:]
    @State private var exportURLs: [URL] = []
    @State private var showShare = false
    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CuratorController.curatedChannels(), id: \.id) { ch in
                        NavigationLink(value: ch) { channelRow(ch) }
                    }
                } header: {
                    Text("Curated Channels")
                } footer: {
                    Text("Review tracks per channel — Accept / Reject / Skip / Approve Album — then Export the approved set. The exported JSON is the bundled curation manifest the app ships.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Curator")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Channel.self) { ch in
                CuratorReviewView(channel: ch, db: db, archiveService: archiveService)
                    .environmentObject(playerVM)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock") {
                        curator.lock()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await prepareExport() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { await reloadCounts() }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: exportURLs)
            }
            .alert("Export failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "") }
        }
    }

    @ViewBuilder
    private func channelRow(_ ch: Channel) -> some View {
        let c = counts[ch.id] ?? (review: 0, approved: 0, rejected: 0)
        HStack(spacing: 8) {
            Label(ch.name, systemImage: ch.icon)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                badge("\(c.approved)", systemImage: "checkmark.circle.fill", tint: .green)
                badge("\(c.rejected)", systemImage: "xmark.circle.fill", tint: .red)
                badge("\(c.review)", systemImage: "circle", tint: .secondary)
            }
            .font(.caption2)
        }
    }

    @ViewBuilder
    private func badge(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).monospacedDigit()
        }
    }

    private func reloadCounts() async {
        var out: [String: (Int, Int, Int)] = [:]
        for ch in CuratorController.curatedChannels() {
            out[ch.id] = await db.curationCounts(channelId: ch.id)
        }
        counts = out
    }

    // MARK: - Export (Phase 4)

    private func prepareExport() async {
        let approved = await db.exportApprovedByChannel()
        let json = buildJSON(from: approved)
        let csv  = buildCSV(from: approved)
        let dir  = FileManager.default.temporaryDirectory
        let dateStamp = Self.dateStamp()
        let jsonURL = dir.appendingPathComponent("curation-\(dateStamp).json")
        let csvURL  = dir.appendingPathComponent("curation-\(dateStamp).csv")
        do {
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            exportURLs = [jsonURL, csvURL]
            showShare = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private static func dateStamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }

    /// JSON in the exact bundled-manifest shape; can be dropped into
    /// `ParsoRadio/Resources/curation.json` verbatim.
    private func buildJSON(from data: [String: [Track]]) -> String {
        var channels: [String: CurationManifest.ChannelCuration] = [:]
        let stamp = Self.dateStamp()
        for (ch, tracks) in data {
            let entries = tracks.map {
                CurationManifest.Entry(
                    id: $0.id,
                    title: $0.title,
                    creator: $0.artist,
                    duration: $0.duration,
                    parentIdentifier: $0.parentIdentifier
                )
            }
            channels[ch] = CurationManifest.ChannelCuration(
                updatedAt: stamp, approved: entries)
        }
        let manifest = CurationManifest(version: 1, channels: channels)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{\"version\":1,\"channels\":{}}"
    }

    /// CSV for human review — one row per approved track.
    private func buildCSV(from data: [String: [Track]]) -> String {
        var lines = ["channel_id,track_id,title,creator,duration_seconds,status"]
        for (ch, tracks) in data.sorted(by: { $0.key < $1.key }) {
            for t in tracks {
                lines.append([
                    csvField(ch),
                    csvField(t.id),
                    csvField(t.title),
                    csvField(t.artist),
                    String(Int(t.duration)),
                    "approved"
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

// MARK: - Per-channel review

struct CuratorReviewView: View {
    let channel: Channel
    let db: DatabaseService
    let archiveService: InternetArchiveService

    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var queue: [Track] = []
    @State private var counts: (review: Int, approved: Int, rejected: Int) = (0, 0, 0)
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var showFetchError = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Label("\(counts.approved)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("\(counts.rejected)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Label("\(counts.review)", systemImage: "circle")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .monospacedDigit()
            }

            Section {
                Button {
                    Task { await loadMoreCandidates() }
                } label: {
                    if isFetching {
                        HStack { ProgressView(); Text("Fetching candidates…") }
                    } else {
                        Label("Load More Candidates", systemImage: "plus.circle")
                    }
                }
                .disabled(isFetching)
            } footer: {
                Text("Runs this channel's IA query and adds new tracks to the review queue. Already-approved or already-rejected tracks are skipped automatically.")
            }

            if queue.isEmpty {
                Section {
                    ContentUnavailableView("Review queue empty",
                        systemImage: "tray",
                        description: Text("Tap “Load More Candidates” to populate from the channel's IA query."))
                }
            } else {
                Section("To Review (\(queue.count))") {
                    ForEach(queue) { track in
                        reviewRow(track)
                    }
                }
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Fetch failed", isPresented: $showFetchError) {
            Button("OK", role: .cancel) {}
        } message: { Text(fetchError ?? "") }
    }

    @ViewBuilder
    private func reviewRow(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.title).font(.body).lineLimit(2)
            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if track.duration > 0 {
                Text(formatTime(track.duration))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            HStack(spacing: 8) {
                Button {
                    Task { await playerVM.auditionTrack(track) }
                } label: { Label("Audition", systemImage: "play.fill") }
                    .buttonStyle(.bordered)
                Button {
                    Task { await verdict(track, "approved") }
                } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button {
                    Task { await verdict(track, "rejected") }
                } label: { Label("Reject", systemImage: "xmark") }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        counts = await db.curationCounts(channelId: channel.id)
        queue = await db.reviewSetTracks(channelId: channel.id)
    }

    private func verdict(_ track: Track, _ status: String) async {
        await db.setCuration(channelId: channel.id, trackId: track.id, status: status)
        await reload()
    }

    private func loadMoreCandidates() async {
        guard let entry = channel.iaQueryEntry else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let candidates = try await archiveService.fetchTracks(
                iaQuery: entry.iaQuery, matchTags: entry.matchTags)
            await db.saveTracks(candidates)
            await db.ensureReviewSet(channelId: channel.id,
                                     trackIds: candidates.map(\.id))
            await reload()
        } catch {
            fetchError = error.localizedDescription
            showFetchError = true
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); let m = t / 60; let sec = t % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
