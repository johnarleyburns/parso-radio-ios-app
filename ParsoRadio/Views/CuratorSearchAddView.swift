import SwiftUI

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
    @State private var existingVerdicts: [String: String] = [:]
    @State private var sessionVerdicts = Set<String>()
    @State private var failedTrackIds: Set<String> = []
    @State private var flashTrackId: String?
    @State private var infoGroup: SearchViewModel.ResultGroup? = nil
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
                            description: Text("Type a query and tap Search. Tap \"Add\" to drop a result into the review queue for \"\(channel.name)\"."))
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
            .sheet(item: $infoGroup) { group in
                searchResultInfoSheet(group)
            }
            .onChange(of: playerVM.errorMessage) { _, msg in
                let failedId = playerVM.currentTrack?.id ?? playerVM.failedAuditionTrackId
                if let id = failedId, msg != nil {
                    failedTrackIds.insert(id)
                    flashTrackId = id
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        flashTrackId = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ group: SearchViewModel.ResultGroup) -> some View {
        let live      = playerVM.currentTrack?.id == group.id
        let isLoading = live && playerVM.isLoading
        let isPlaying = live && playerVM.isPlaying && !isLoading
        let verdict   = existingVerdicts[group.id]
        let isSession  = sessionVerdicts.contains(group.id)
        let hasFailed  = failedTrackIds.contains(group.id)
        let isFlashing = flashTrackId == group.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if hasFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .scaleEffect(isFlashing ? 1.4 : 1.0)
                            .animation(.none, value: isFlashing)
                    }
                    Text(group.title).font(.body).lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture { infoGroup = group }
                Text(group.creator).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let v = verdict, !isSession {
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
            Button {
                Task { await directVerdict(group, "approved") }
            } label: {
                Image(systemName: verdict == "approved" ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title)
                    .foregroundStyle(verdict == "approved" ? .green : .secondary)
            }
            .buttonStyle(.plain)
            Button {
                Task { await directVerdict(group, "rejected") }
            } label: {
                Image(systemName: verdict == "rejected" ? "xmark.circle.fill" : "xmark.circle")
                    .font(.title)
                    .foregroundStyle(verdict == "rejected" ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func directVerdict(_ group: SearchViewModel.ResultGroup, _ status: String) async {
        let t = searchTrack(group)
        await db.saveTracks([t])
        await db.setCuration(channelId: channel.id, trackId: t.id, status: status)
        await LiveCurationStore.shared.reload(channelId: channel.id, from: db)
        if var def = CustomChannelsStore.shared.channelDefinition(for: channel.id) {
            if status == "approved" {
                if !def.approved.contains(where: { $0.id == t.id }) {
                    def.approved.append(ChannelDefinition.ApprovedEntry(
                        id: t.id, title: t.title, creator: t.artist,
                        duration: t.duration, parentIdentifier: t.parentIdentifier))
                }
                def.rejected.removeAll(where: { $0 == t.id })
            } else {
                if !def.rejected.contains(t.id) {
                    def.rejected.append(t.id)
                }
                def.approved.removeAll(where: { $0.id == t.id })
            }
            CustomChannelsStore.shared.writeChannelDefinition(def)
        }
        existingVerdicts[group.id] = status
        sessionVerdicts.insert(group.id)
        if playerVM.currentTrack?.id == group.id {
            playerVM.stopAuditionWithoutRestore()
        }
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
            let statuses = await withTaskGroup(of: (String, String)?.self) { group in
                for g in results {
                    group.addTask { [channelId = channel.id] in
                        if let s = await db.curationStatus(channelId: channelId, trackId: g.id) {
                            return (g.id, s)
                        }
                        return nil
                    }
                }
                var dict: [String: String] = [:]
                for await pair in group {
                    if let (id, s) = pair { dict[id] = s }
                }
                return dict
            }
            existingVerdicts = statuses
        } catch {
            results = []
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); let m = t / 60; let sec = t % 60
        return String(format: "%d:%02d", m, sec)
    }

    @ViewBuilder
    private func searchResultInfoSheet(_ group: SearchViewModel.ResultGroup) -> some View {
        NavigationStack {
            List {
                Section("Track Info") {
                    Text(group.title).font(.headline)
                    Text(group.creator).foregroundStyle(.secondary)
                    if group.duration > 0 {
                        Text(formatTime(group.duration))
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                if let coll = group.collection,
                   !coll.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Collection") {
                        Text(coll)
                    }
                }
                Section {
                    Text("ID: \(group.id)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Track Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { infoGroup = nil }
                }
            }
        }
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
