import SwiftUI

struct SearchView: View {
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @StateObject private var searchVM: SearchViewModel
    @State private var detailGroup: SearchViewModel.ResultGroup? = nil
    @State private var failedTrackIds: Set<String> = []
    @State private var flashTrackId: String?
    @State private var showDuplicateAlert = false
    @FocusState private var searchFocused: Bool

    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    init(dismissAll: (() -> Void)? = nil,
         archiveService: InternetArchiveService = InternetArchiveService()) {
        self.dismissAll = dismissAll
        _searchVM = StateObject(wrappedValue: SearchViewModel(
            archiveService: archiveService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search music, audiobooks, podcasts...", text: $searchVM.query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onChange(of: searchVM.query) { searchVM.searchChanged() }
                        .onSubmit { searchVM.submitSearch() }
                    if !searchVM.query.isEmpty {
                        Button { searchVM.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                Picker("Search scope", selection: $searchVM.scope) {
                    ForEach(SearchViewModel.SearchScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: searchVM.scope) { searchVM.scopeChanged() }
                .accessibilityLabel("Filter results by type")

                if searchVM.query.count < 2 {
                    historyList
                } else {
                    if searchVM.isSearching { ProgressView().padding() }
                    if let error = searchVM.errorMessage {
                        ContentUnavailableView("Search failed", systemImage: "wifi.slash",
                                                description: Text(error))
                    } else if searchVM.showNoResults {
                        ContentUnavailableView.search(text: searchVM.query)
                    }
                    if searchVM.scope == .podcasts {
                        podcastResultsList
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                }
            }
            .sheet(item: $detailGroup) { group in
                ItemDetailView(
                    identifier: group.id,
                    title: group.title,
                    creator: group.creator,
                    kind: searchVM.itemKinds[group.id] ?? .album
                )
                .environmentObject(playerVM)
                .environmentObject(favorites)
            }
            .alert("Already Subscribed", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You're already subscribed to this podcast.")
            }
            .onAppear { searchFocused = true }
            .onChange(of: playerVM.errorMessage) { _, msg in
                let failedId = playerVM.currentTrack?.id
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

    // MARK: - Podcast Results

    private var podcastResultsList: some View {
        List {
            ForEach(searchVM.podcastResults) { podcast in
                Button {
                    Task {
                        let added = await podcastStore.add(
                            name: podcast.title,
                            feedURL: podcast.feedURL,
                            artworkURL: podcast.artworkURL
                        )
                        if !added { showDuplicateAlert = true }
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let artURL = podcast.artworkURL, let url = URL(string: artURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Color(.systemGray5)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 48, height: 48)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(podcast.title)
                                .font(.body).lineLimit(2)
                            Text(podcast.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(podcast.trackCount) episodes")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Recent searches

    @ViewBuilder
    private var historyList: some View {
        if searchVM.recentSearches.isEmpty {
            ContentUnavailableView(
                "Search the Internet Archive",
                systemImage: "magnifyingglass",
                description: Text("Find music, audiobooks, and podcasts.")
            )
        } else {
            List {
                Section {
                    ForEach(searchVM.recentSearches, id: \.self) { q in
                        Button {
                            searchVM.query = q
                        } label: {
                            Label(q, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                searchVM.removeHistory(q)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") { searchVM.clearHistory() }
                            .font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - IA Results

    private var resultsList: some View {
        List {
            ForEach(searchVM.displayedResults) { group in
                let dur = searchVM.durations[group.id] ?? group.duration
                let hasFailed = failedTrackIds.contains(group.id)
                let isFlashing = flashTrackId == group.id
                let itemKind = searchVM.itemKinds[group.id]
                Button {
                    handleTap(group, kind: itemKind)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kindIcon(group))
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if hasFailed {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                        .scaleEffect(isFlashing ? 1.4 : 1.0)
                                        .animation(isFlashing ? .easeInOut(duration: 0.3).repeatCount(2, autoreverses: true) : .default, value: isFlashing)
                                }
                                Text(group.title)
                                    .font(.body).fontWeight(.medium).lineLimit(2)
                            }
                            Text(group.creator)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 6) {
                                if let kind = itemKind {
                                    Text(kindLabel(kind))
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                if let coll = group.collection,
                                   !coll.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(coll)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let date = group.addedDate {
                                Text(date.formatted(.dateTime.year().month().day()))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if dur > 0 {
                            Text(Duration.seconds(dur)
                                .formatted(.time(pattern: .hourMinuteSecond)))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(accessibilityHint(for: itemKind))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Task { await toggleSearchFavorite(group, kind: itemKind) }
                    } label: {
                        Label("Favorite", systemImage: "heart")
                    }
                    .tint(.pink)
                    .accessibilityIdentifier("search.result.favorite.\(group.id)")
                }
                .task { searchVM.loadItemInfo(group) }
            }

            if searchVM.hasMorePages {
                Button {
                    Task { await searchVM.loadNextPage() }
                } label: {
                    HStack(spacing: 8) {
                        if searchVM.isSearching {
                            ProgressView()
                        } else if searchVM.loadMoreFailed {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(searchVM.loadMoreFailed
                             ? "Load more failed \u{2014} Retry"
                             : "Load More Results")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(searchVM.loadMoreFailed ? Color.orange : Color.accentColor)
                }
                .disabled(searchVM.isSearching)
                .accessibilityIdentifier("search.loadmore")
                .accessibilityLabel(searchVM.loadMoreFailed
                    ? "Load more failed, tap to retry"
                    : "Load more results")
            }
        }
        .listStyle(.plain)
    }

    private func handleTap(_ group: SearchViewModel.ResultGroup,
                           kind: SearchViewModel.ItemKind?) {
        switch kind {
        case .track:
            let mediaKind = SearchViewModel.mediaKind(forCollection: group.collection)
            Task { await playerVM.playSearchResult(group, mediaKind: mediaKind); dismissAll?() }
        case .album, .book:
            detailGroup = group
        case nil:
            break
        }
    }

    private func searchFavoriteMediaKind(_ group: SearchViewModel.ResultGroup,
                                         kind: SearchViewModel.ItemKind?) -> MediaKind {
        switch kind {
        case .book: return .audiobook
        case .album: return .music
        case .track, nil:
            return SearchViewModel.mediaKind(forCollection: group.collection)
        }
    }

    private func toggleSearchFavorite(_ group: SearchViewModel.ResultGroup,
                                      kind: SearchViewModel.ItemKind?) async {
        let mediaKind = searchFavoriteMediaKind(group, kind: kind)
        let isBook = mediaKind == .audiobook
        let track = Track(
            id: group.id, source: "internet_archive",
            title: group.title, artist: group.creator,
            duration: group.duration,
            streamURL: URL(string: "https://archive.org/details/\(group.id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0, rawCreator: group.creator, composer: nil,
            instruments: [], metadataConfidence: 0.0,
            addedDate: group.addedDate,
            parentIdentifier: isBook ? group.id : nil
        )
        await favorites.toggle(track: track, channel: nil, mediaKind: mediaKind)
    }

    private func accessibilityHint(for kind: SearchViewModel.ItemKind?) -> String {
        switch kind {
        case .track: return "Plays this track"
        case .album: return "Opens album details"
        case .book:  return "Opens book details"
        case nil:    return "Loading item details"
        }
    }

    private func kindIcon(_ group: SearchViewModel.ResultGroup) -> String {
        switch searchVM.itemKinds[group.id] {
        case .book:  return "book.closed.fill"
        case .album: return "opticaldisc.fill"
        case .track: return "music.note"
        case nil:    return "waveform"
        }
    }

    private func kindLabel(_ kind: SearchViewModel.ItemKind) -> String {
        switch kind {
        case .book:  return "Book"
        case .album: return "Album"
        case .track: return "Track"
        }
    }
}
