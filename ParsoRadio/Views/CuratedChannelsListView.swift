import SwiftUI

/// The new Curated Channels list (replaces the generic ChannelListScreen for
/// the Curated category). Toolbar: Edit + `+`. Swipe-to-delete, drag-to-reorder,
/// context menu per row, `(i)` chevron → ChannelInfoView.
///
/// Phase B of CUSTOMIZABLE-CURATED-CHANNELS-PLAN.md.
struct CuratedChannelsListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var store = CustomChannelsStore.shared

    // Direct access to shared singleton for method calls (avoids StateObject
    // dynamic-member-lookup shadowing of method calls in Swift 6/Xcode 16).

    @State private var showNewChannel = false
    @State private var editingChannel: ChannelMeta?
    @State private var showCurateChannel: ChannelMeta?

    let onSelectChannel: (Channel) -> Void

    var body: some View {
        List {
            // DEBUG: Show bootstrap state at the top of the list
            #if DEBUG
            Section {
                let ordered: [ChannelMeta] = store.orderedChannels()
                let allMeta = store.customChannels
                Text("Channels: \(ordered.count) visible / \(allMeta.count) registered")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Deleted defaults: \(store.deletedDefaults.count)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Docs dir files: \((try? FileManager.default.contentsOfDirectory(at: CustomChannelsStore.channelsDir, includingPropertiesForKeys: nil))?.count ?? 0)")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(ordered.prefix(3), id: \.id) { m in
                    let count = store.approvedTracks(for: m.id).count
                    Text("  \(m.id): \(count) approved")
                        .font(.caption2).foregroundStyle(count > 0 ? .green : .orange)
                }
            } header: {
                Text("Debug").font(.caption).foregroundStyle(.tertiary)
            }
            #endif

            ForEach(store.orderedChannels(), id: \.id) { meta in
                curatedRow(meta)
                    .contextMenu { rowContextMenu(meta) }
            }

            if store.orderedChannels().isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Curated Channels",
                        systemImage: "star.slash",
                        description: Text("Tap + to create a curated channel, or import one from a friend."))
                }
            }
        }
        .navigationTitle("Curated")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewChannel = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New curated channel")
            }
        }
        .sheet(isPresented: $showNewChannel) {
            NewChannelSheet(onCreated: { meta in
                showNewChannel = false
                showCurateChannel = meta
            })
            .environmentObject(playerVM)
        }
        .sheet(item: $showCurateChannel) { meta in
            CuratorChannelEditView(
                channelMeta: meta,
                onDismiss: { showCurateChannel = nil })
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func curatedRow(_ meta: ChannelMeta) -> some View {
        let approvedCount = store.approvedTracks(for: meta.id).count
        HStack(spacing: 8) {
            Button {
                let ch = store.runtimeChannel(from: meta)
                onSelectChannel(ch)
            } label: {
                HStack {
                    Label(meta.name, systemImage: meta.icon)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays this channel")

            if approvedCount > 0 {
                Text("\(approvedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            NavigationLink(value: MenuRoute.channelInfo(
                store.runtimeChannel(from: meta))) {
                EmptyView()
            }
            .frame(width: 0).opacity(0) // hidden, but drives (i) via Info link
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func rowContextMenu(_ meta: ChannelMeta) -> some View {
        Button {
            showCurateChannel = meta
        } label: {
            Label("Curate", systemImage: "checklist")
        }

        Button {
            editingChannel = meta
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            _ = store.duplicateChannel(chId: meta.id)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        ShareLink(item: store.exportURL(for: meta.id)) {
            Label("Export…", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            store.deleteChannel(chId: meta.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - NewChannelSheet (Phase B)

struct NewChannelSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var channelName = ""
    @State private var selectedIcon = "star"
    @State private var iaQuery = ""
    @State private var importURL: URL?
    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var showImportError = false

    // Search to bulk-add initial tracks
    @State private var searchQuery = ""
    @State private var searchResults: [SearchViewModel.ResultGroup] = []
    @State private var isSearching = false
    @State private var selectedIds = Set<String>()
    @State private var searchError: String?

    let onCreated: (ChannelMeta) -> Void

    private let iconOptions = [
        "star", "heart", "music.note", "guitars", "pianokeys",
        "theatermasks", "book", "leaf", "tree", "mountain.2",
        "globe", "antenna.radiowaves.left.and.right", "wave.3.right",
        "headphones", "speaker.wave.3", "film", "camera.macro",
        "flame", "bolt", "moon.stars", "sparkles", "crown", "hands.clap"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Step 1: Name + icon
                Section("Channel Name & Icon") {
                    TextField("Channel name", text: $channelName)
                    iconPicker
                }

                // Step 2: iaQuery (optional)
                Section {
                    TextField("IA search query (optional)", text: $iaQuery)
                } header: {
                    Text("Candidate Generator")
                } footer: {
                    Text("Leave empty to curate purely by search. The query is used by \"Load More Candidates\" to auto-populate the review queue.")
                }

                // Step 2b: Import from file
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import from file…", systemImage: "doc.badge.plus")
                    }
                } footer: {
                    Text("Import a curated channel JSON shared by a friend.")
                }

                // Step 3: Initial search → bulk-add
                Section("Pre-populate with Search") {
                    HStack {
                        TextField("Search archive.org", text: $searchQuery)
                        Button {
                            Task { await performSearch() }
                        } label: {
                            if isSearching {
                                ProgressView()
                            } else {
                                Text("Search")
                            }
                        }
                        .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !searchResults.isEmpty {
                        ForEach(searchResults) { group in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.title).font(.body).lineLimit(2)
                                    Text(group.creator).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    if selectedIds.contains(group.id) {
                                        selectedIds.remove(group.id)
                                    } else {
                                        selectedIds.insert(group.id)
                                    }
                                } label: {
                                    Image(systemName: selectedIds.contains(group.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                }
                            }
                        }
                        if !selectedIds.isEmpty {
                            Text("\(selectedIds.count) items selected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Curated Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createChannel()
                    }
                    .disabled(channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importURL = url
                    // Parse the imported file's metadata into the sheet
                    if let data = try? Data(contentsOf: url),
                       let def = try? JSONDecoder().decode(ChannelDefinition.self, from: data) {
                        channelName = def.channel.name
                        selectedIcon = def.channel.icon
                        iaQuery = def.channel.iaQuery ?? ""
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                    showImportError = true
                }
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
        }
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5)) {
            ForEach(iconOptions, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(selectedIcon == icon
                                ? Color.accentColor.opacity(0.25)
                                : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { selectedIcon = icon }
                    .accessibilityLabel(icon)
                    .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
            }
        }
    }

    private func performSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let service = InternetArchiveService()
            searchResults = try await service.search(query: q, page: 0)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func createChannel() {
        let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let finalQuery = iaQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = finalQuery.isEmpty ? nil : finalQuery

        let initialTracks: [Track] = searchResults
            .filter { selectedIds.contains($0.id) }
            .map { group in
                Track(
                    id: group.id, source: "internet_archive",
                    title: group.title, artist: group.creator,
                    duration: group.duration,
                    streamURL: URL(string: "https://archive.org/download/\(group.id)")
                        ?? URL(string: "https://archive.org")!,
                    downloadURL: nil, localFilePath: nil,
                    license: .publicDomain, tags: [],
                    qualityScore: 1.0, rawCreator: group.creator,
                    composer: nil, instruments: [], metadataConfidence: 1.0)
            }

        let chId = CustomChannelsStore.shared.addChannel(
            name: name, icon: selectedIcon, iaQuery: query,
            initialTracks: initialTracks)

        if let importedURL = importURL {
            // Import was used — copy the full approved list from the file
            _ = try? CustomChannelsStore.shared.importChannel(from: importedURL)
        }

        dismiss()

        // Notify caller so they can open the curator for this new channel
        if let meta = CustomChannelsStore.shared.customChannels.first(where: { $0.id == chId }) {
            onCreated(meta)
        }
    }
}

// MARK: - CuratorChannelEditView (Phase C)

/// Per-channel curator, reachable from ChannelInfoView or long-press.
/// Same as CuratorReviewView but refit for in-place use, with filter picker.
struct CuratorChannelEditView: View {
    let channelMeta: ChannelMeta
    let onDismiss: () -> Void

    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var db = DatabaseService.shared
    @State private var archiveService = InternetArchiveService()
    @State private var queue: [Track] = []
    @State private var counts: (review: Int, approved: Int, rejected: Int) = (0, 0, 0)
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var showFetchError = false
    @State private var showSearchAdd = false
    @State private var filterMode: FilterMode = .review

    enum FilterMode: String, CaseIterable {
        case review = "Review"
        case approved = "Approved"
        case rejected = "Rejected"
    }

    // Channel settings
    @State private var editedName: String = ""
    @State private var showRename = false
    @State private var editedQuery: String = ""
    @State private var showQueryEditor = false   // full-page sheet

    // Verdict state for undo support
    @State private var verdictStates: [String: (status: String, undone: Bool)] = [:]
    // Resolve timeout for curator auditions
    @State private var auditionTimeout: Task<Void, Never>?
    // Tracks that failed to play — show a yellow warning icon
    @State private var failedTrackIds: Set<String> = []
    @State private var flashTrackId: String?
    // Track info popup when tapping name/author area
    @State private var infoTrack: Track?    // triggers brief yellow flash

    var body: some View {
        NavigationStack {
            List {
                // Counts + filter picker
                Section {
                    HStack(spacing: 12) {
                        ForEach(FilterMode.allCases, id: \.self) { mode in
                            Button {
                                filterMode = mode
                                Task { await reload() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: modeIcon(mode))
                                    Text("\(countFor(mode))")
                                }
                                .font(.subheadline)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filterMode == mode
                                            ? modeTint(mode).opacity(0.2)
                                            : Color.clear)
                                .foregroundStyle(filterMode == mode
                                                 ? modeTint(mode) : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Playback error: show non-intrusive banner so curator
                // sees when a track is unplayable instead of just a spinner.
                if let err = playerVM.errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Add Candidates
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
                    Button {
                        showSearchAdd = true
                    } label: {
                        Label("Search Archive.org to Add",
                              systemImage: "magnifyingglass.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("Add Candidates")
                }

                // Review queue / approved / rejected
                if queue.isEmpty {
                    Section {
                        ContentUnavailableView("\(filterMode.rawValue) queue empty",
                            systemImage: "tray",
                            description: Text("Tap \"Load More Candidates\" or \"Search Archive.org to Add\"."))
                    }
                } else {
                    Section("\(filterMode.rawValue) (\(queue.count))") {
                        ForEach(queue, id: \.id) { track in
                            reviewRow(track)
                        }
                    }
                }
            }
            .navigationTitle(channelMeta.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        playerVM.stopAudition()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editedName = channelMeta.name
                            showRename = true
                        } label: {
                            Label("Edit Channel Name", systemImage: "pencil")
                        }
                        Button {
                            editedQuery = channelMeta.iaQuery ?? ""
                            showQueryEditor = true
                        } label: {
                            Label("Edit Search Query", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showQueryEditor) {
                QueryEditorView(query: $editedQuery, channelName: channelMeta.name) {
                    let q = editedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    CustomChannelsStore.shared.updateQuery(
                        chId: channelMeta.id,
                        newQuery: q.isEmpty ? nil : q)
                    showQueryEditor = false
                }
            }
            .sheet(item: $infoTrack) { track in
                NavigationStack {
                    List {
                        Section("Track Info") {
                            Text(track.title).font(.headline)
                            Text(track.artist).foregroundStyle(.secondary)
                            if track.duration > 0 {
                                Text(formatTime(track.duration))
                                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                            }
                        }
                        Section("Source") {
                            Text(track.streamURL.absoluteString)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        Section {
                            Text("ID: \(track.id)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .navigationTitle("Track Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { infoTrack = nil }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSearchAdd) {
                CuratorSearchAddView(channel: runtimeChannel, db: db,
                                     archiveService: archiveService)
                    .environmentObject(playerVM)
            }
            .onChange(of: showSearchAdd) { _, shown in
                if !shown { Task { await reload() } }
            }
            .onDisappear { playerVM.stopAudition() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { playerVM.stopAudition() }
            }
            .task { await reload() }
            .onChange(of: playerVM.errorMessage) { _, msg in
                // When an audition track fails, currentTrack is cleared BEFORE
                // errorMessage is set. Use failedAuditionTrackId so the correct
                // row gets the yellow warning icon and flash.
                let failedId = playerVM.currentTrack?.id ?? playerVM.failedAuditionTrackId
                if let id = failedId, msg != nil {
                    failedTrackIds.insert(id)
                    flashTrackId = id
                    // Brief yellow flash, then settle to persistent icon
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        flashTrackId = nil
                    }
                }
            }
            .alert("Rename Channel", isPresented: $showRename) {
                TextField("Channel name", text: $editedName)
                Button("Save") {
                    let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    CustomChannelsStore.shared.renameChannel(chId: channelMeta.id, newName: name)
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Fetch failed", isPresented: $showFetchError) {
                Button("OK", role: .cancel) {}
            } message: { Text(fetchError ?? "") }
        }
    }

    private var runtimeChannel: Channel {
        CustomChannelsStore.shared.runtimeChannel(from: channelMeta)
    }

    // MARK: - Review row (with undo support)

    @ViewBuilder
    private func reviewRow(_ track: Track) -> some View {
        let vs = verdictStates[track.id]
        let isVerdicted = vs != nil && !vs!.undone
        let isLive = playerVM.currentTrack?.id == track.id
        let isLoading = isLive && playerVM.isLoading
        let isPlaying = isLive && playerVM.isPlaying && !isLoading
        let hasFailed = failedTrackIds.contains(track.id)
        let isFlashing = flashTrackId == track.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if hasFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .scaleEffect(isFlashing ? 1.4 : 1.0)
                            .animation(isFlashing ? .easeInOut(duration: 0.3).repeatCount(2, autoreverses: true) : .default, value: isFlashing)
                    }
                    Text(track.title).font(.body).lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture { infoTrack = track }
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if track.duration > 0 {
                    Text(formatTime(track.duration))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                if let vs = vs {
                    Text(vs.status == "approved" ? "Approved" : "Rejected")
                        .font(.caption2)
                        .foregroundStyle(vs.status == "approved" ? .green : .red)
                }
            }
            Spacer(minLength: 8)
            if isPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
            if isVerdicted {
                Button {
                    undoVerdict(track)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo verdict")
            } else {
                Button {
                    if isLive { playerVM.togglePlayPause() }
                    else { Task { await playerVM.auditionTrack(track) } }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.regular)
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title).foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .accessibilityLabel(isPlaying ? "Pause" : "Audition")
                Button {
                    Task { await verdict(track, "approved") }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title).foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Approve")
                Button {
                    Task { await verdict(track, "rejected") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reject")
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        counts = await db.curationCounts(channelId: channelMeta.id)
        let raw: [Track]
        switch filterMode {
        case .review:   raw = await db.reviewSetTracks(channelId: channelMeta.id)
        case .approved: raw = await db.fetchApprovedTracks(forChannelId: channelMeta.id)
        case .rejected: raw = await db.fetchRejectedTracks(forChannelId: channelMeta.id)
        }
        queue = raw.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let ids = Set(queue.map(\.id))
        verdictStates = verdictStates.filter { ids.contains($0.key) }
    }

    private func verdict(_ track: Track, _ status: String) async {
        let wasPlaying = playerVM.currentTrack?.id == track.id
        await db.setCuration(channelId: channelMeta.id, trackId: track.id, status: status)
        await LiveCurationStore.shared.reload(from: db)

        // Write the track to the per-channel JSON file WITH cross-removal:
        // approving removes from rejected, rejecting removes from approved.
        if var def = CustomChannelsStore.shared.channelDefinition(for: channelMeta.id) {
            if status == "approved" {
                def.rejected.removeAll(where: { $0 == track.id })
                if !def.approved.contains(where: { $0.id == track.id }) {
                    def.approved.append(ChannelDefinition.ApprovedEntry(
                        id: track.id, title: track.title, creator: track.artist,
                        duration: track.duration, parentIdentifier: track.parentIdentifier))
                }
            } else if status == "rejected" {
                def.approved.removeAll(where: { $0.id == track.id })
                if !def.rejected.contains(track.id) {
                    def.rejected.append(track.id)
                }
            }
            CustomChannelsStore.shared.writeChannelDefinition(def)
        }

        // Mark verdict for undo
        verdictStates[track.id] = (status: status, undone: false)

        await reload()

        guard wasPlaying else { return }
        // Auto-advance to NEXT candidate
        if let next = queue.first(where: { verdictStates[$0.id] == nil }) {
            await playerVM.auditionTrack(next)
        } else {
            playerVM.stopAudition()
        }
    }

    private func undoVerdict(_ track: Track) {
        verdictStates.removeValue(forKey: track.id)
        Task {
            await db.setCuration(channelId: channelMeta.id, trackId: track.id, status: "review")
            await LiveCurationStore.shared.reload(from: db)
            // Remove from per-channel JSON file
            if var def = CustomChannelsStore.shared.channelDefinition(for: channelMeta.id) {
                def.approved.removeAll(where: { $0.id == track.id })
                def.rejected.removeAll(where: { $0 == track.id })
                CustomChannelsStore.shared.writeChannelDefinition(def)
            }
            await reload()
        }
    }

    private func loadMoreCandidates() async {
        guard let query = channelMeta.iaQuery, !query.isEmpty else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let before = await db.curationCounts(channelId: channelMeta.id)
            let candidates = try await archiveService.fetchTracks(
                iaQuery: query, matchTags: [])
            await db.saveTracks(candidates)
            await db.ensureReviewSet(channelId: channelMeta.id,
                                      trackIds: candidates.map(\.id))
            await reload()
            let after = await db.curationCounts(channelId: channelMeta.id)
            let added = (after.review + after.approved + after.rejected)
                - (before.review + before.approved + before.rejected)
            if added == 0 {
                fetchError = "No new candidates — every track is already reviewed."
                showFetchError = true
            }
        } catch {
            fetchError = error.localizedDescription
            showFetchError = true
        }
    }

    private func countFor(_ mode: FilterMode) -> Int {
        switch mode {
        case .review:   return counts.review
        case .approved: return counts.approved
        case .rejected: return counts.rejected
        }
    }

    private func modeIcon(_ mode: FilterMode) -> String {
        switch mode {
        case .review:   return "circle"
        case .approved: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    private func modeTint(_ mode: FilterMode) -> Color {
        switch mode {
        case .review:   return .secondary
        case .approved: return .green
        case .rejected: return .red
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); let m = t / 60; let sec = t % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Full-page IA Query Editor

struct QueryEditorView: View {
    @Binding var query: String
    let channelName: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $query)
                    .font(.body.monospaced())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if query.isEmpty {
                            Text("Paste or type the Internet Archive search query…")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .navigationTitle("Search Query — \(channelName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
    }
}
