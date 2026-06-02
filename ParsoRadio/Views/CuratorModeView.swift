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
    @Environment(\.scenePhase) private var scenePhase
    @State private var queue: [Track] = []
    @State private var counts: (review: Int, approved: Int, rejected: Int) = (0, 0, 0)
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var showFetchError = false
    @State private var showSearchAdd = false

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
                // Inline, very visible entry to manual search (the toolbar
                // button was easy to miss).
                Button {
                    showSearchAdd = true
                } label: {
                    Label("Search Archive.org to Add",
                          systemImage: "magnifyingglass.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Text("Add Candidates")
            } footer: {
                Text("Load More runs this channel's IA query and adds new tracks to the review queue. Search lets you add specific tracks or albums by hand. Already-approved or already-rejected tracks are SKIPPED automatically.")
            }

            if queue.isEmpty {
                Section {
                    ContentUnavailableView("Review queue empty",
                        systemImage: "tray",
                        description: Text("Tap “Load More Candidates” to populate from the channel's IA query."))
                }
            } else {
                Section("To Review (\(queue.count))") {
                    ForEach(queue, id: \.id) { track in
                        reviewRow(track)
                    }
                }
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearchAdd = true
                } label: {
                    Label("Add from Search", systemImage: "magnifyingglass.circle")
                }
            }
        }
        .sheet(isPresented: $showSearchAdd) {
            CuratorSearchAddView(channel: channel, db: db,
                                 archiveService: archiveService)
                .environmentObject(playerVM)
        }
        .onChange(of: showSearchAdd) { _, shown in
            if !shown { Task { await reload() } }   // refresh queue on dismiss
        }
        // Exit the review screen or background the app → STOP audition so a
        // curator track never keeps playing once the curator has stepped away.
        .onDisappear { playerVM.stopAudition() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playerVM.stopAudition() }
        }
        .task { await reload() }
        .alert("Fetch failed", isPresented: $showFetchError) {
            Button("OK", role: .cancel) {}
        } message: { Text(fetchError ?? "") }
    }

    @ViewBuilder
    private func reviewRow(_ track: Track) -> some View {
        let isLive    = playerVM.currentTrack?.id == track.id
        let isLoading = isLive && playerVM.isLoading
        let isPlaying = isLive && playerVM.isPlaying && !isLoading

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if track.duration > 0 {
                    Text(formatTime(track.duration))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            // Animated waveform indicator while this row is the live, playing
            // track — visual proof "this one is playing." iOS 17 symbolEffect.
            if isPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            // Play/pause/loading: spinner while resolving, pause when the live
            // row is playing, play otherwise. Tap toggles pause when live.
            Button {
                if isLive {
                    playerVM.togglePlayPause()
                } else {
                    Task { await playerVM.auditionTrack(track) }
                }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .accessibilityLabel(isPlaying ? "Pause audition" :
                                (isLoading ? "Loading audition" : "Audition track"))
            Button {
                Task { await verdict(track, "approved") }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Approve")
            Button {
                Task { await verdict(track, "rejected") }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reject")
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        counts = await db.curationCounts(channelId: channel.id)
        queue = await db.reviewSetTracks(channelId: channel.id)
    }

    private func verdict(_ track: Track, _ status: String) async {
        // Capture whether we just verdicted the LIVE track before mutating the
        // queue — used to auto-advance to the next candidate so the curator can
        // sprint through reviews without an extra tap per track.
        let wasPlaying = playerVM.currentTrack?.id == track.id
        await db.setCuration(channelId: channel.id, trackId: track.id, status: status)
        // Live update: refresh the in-memory manifest snapshot AND rewrite
        // Documents/curation.json so the channel's pool reflects this verdict
        // immediately (no app rebuild required).
        await LiveCurationStore.shared.reload(from: db)
        await reload()
        guard wasPlaying else { return }
        if let next = queue.first {
            await playerVM.auditionTrack(next)
        } else {
            // No more candidates → stop audition so the spinner/pause icon
            // doesn't linger on a track that no longer exists in the queue.
            playerVM.stopAudition()
        }
    }

    private func loadMoreCandidates() async {
        guard let entry = channel.iaQueryEntry else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            // Measure delta so we can tell the user when the channel is
            // exhausted (IA returned nothing new — already-verdicted tracks are
            // SKIPPED by ensureReviewSet, so "0 added" means we've seen them all).
            let before = await db.curationCounts(channelId: channel.id)
            let beforeTotal = before.review + before.approved + before.rejected
            let candidates = try await archiveService.fetchTracks(
                iaQuery: entry.iaQuery, matchTags: entry.matchTags)
            await db.saveTracks(candidates)
            await db.ensureReviewSet(channelId: channel.id,
                                     trackIds: candidates.map(\.id))
            await reload()
            let after = await db.curationCounts(channelId: channel.id)
            let afterTotal = after.review + after.approved + after.rejected
            let added = afterTotal - beforeTotal
            if added == 0 {
                fetchError = "No new candidates — every track IA returned is already reviewed for this channel. The query may be exhausted; broaden it in ia_queries.json or use Add from Search."
                showFetchError = true
            }
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

// MARK: - Phase 5: Search → Add to Review

/// Free-text Internet Archive search inside Curator Mode. Tap a result to drop
/// it into the channel's REVIEW queue (never directly approved — every
/// candidate still earns approval by audition). Already-verdicted tracks for
/// this channel are skipped (the reject set is sticky).
struct CuratorSearchAddView: View {
    let channel: Channel
    let db: DatabaseService
    let archiveService: InternetArchiveService

    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var query = ""
    @State private var results: [SearchViewModel.ResultGroup] = []
    @State private var isSearching = false
    @State private var addedIds = Set<String>()
    @State private var existingVerdicts: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    Section { ProgressView() }
                }
                if results.isEmpty, !isSearching {
                    Section {
                        ContentUnavailableView(
                            "Search archive.org",
                            systemImage: "magnifyingglass",
                            description: Text("Type a query and tap Search. Tap “Add” to drop a result into the review queue for “\(channel.name)”."))
                    }
                } else {
                    Section("Results") {
                        ForEach(results) { group in
                            resultRow(group)
                        }
                    }
                }
            }
            .navigationTitle("Add from Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search music, audiobooks, lectures…")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Search failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onDisappear { playerVM.stopAudition() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { playerVM.stopAudition() }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ group: SearchViewModel.ResultGroup) -> some View {
        let live      = playerVM.currentTrack?.id == group.id
        let isLoading = live && playerVM.isLoading
        let isPlaying = live && playerVM.isPlaying && !isLoading
        let verdict   = existingVerdicts[group.id]
        let alreadyAdded = addedIds.contains(group.id) || verdict == "review"

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.body).lineLimit(2)
                Text(group.creator).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let v = verdict {
                    Text(verdictLabel(v))
                        .font(.caption2)
                        .foregroundStyle(verdictColor(v))
                }
            }
            Spacer(minLength: 8)
            if isPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            Button {
                if live {
                    playerVM.togglePlayPause()
                } else {
                    Task { await playerVM.auditionTrack(searchTrack(group)) }
                }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .accessibilityLabel(isPlaying ? "Pause audition" : "Audition")
            Button {
                Task { await add(group) }
            } label: {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(alreadyAdded ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded || verdict == "approved" || verdict == "rejected")
            .accessibilityLabel(alreadyAdded ? "Added to review queue" : "Add to review queue")
        }
        .padding(.vertical, 4)
    }

    private func verdictLabel(_ s: String) -> String {
        switch s {
        case "approved": return "Already approved for this channel"
        case "rejected": return "Already rejected for this channel"
        case "review":   return "Already in the review queue"
        default:         return ""
        }
    }

    private func verdictColor(_ s: String) -> Color {
        switch s {
        case "approved": return .green
        case "rejected": return .red
        case "review":   return .secondary
        default:         return .secondary
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await archiveService.search(query: q, page: 0)
            // Look up existing verdicts so the UI can mark already-added /
            // already-verdicted results without offering a redundant Add tap.
            var existing: [String: String] = [:]
            for g in results {
                if let s = await db.curationStatus(channelId: channel.id, trackId: g.id) {
                    existing[g.id] = s
                }
            }
            existingVerdicts = existing
        } catch {
            results = []
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func add(_ group: SearchViewModel.ResultGroup) async {
        let t = searchTrack(group)
        await db.saveTracks([t])
        await db.ensureReviewSet(channelId: channel.id, trackIds: [t.id])
        addedIds.insert(group.id)
        existingVerdicts[group.id] = "review"
    }

    private func searchTrack(_ group: SearchViewModel.ResultGroup) -> Track {
        Track(
            id: group.id,
            source: "internet_archive",
            title: group.title,
            artist: group.creator,
            duration: group.duration,
            streamURL: URL(string: "https://archive.org/download/\(group.id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: [],
            qualityScore: 1.0,
            rawCreator: group.creator,
            composer: nil,
            instruments: [],
            metadataConfidence: 1.0,
            addedDate: group.addedDate
        )
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
