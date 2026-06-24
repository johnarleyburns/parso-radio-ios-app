import SwiftUI

struct FavoritesScreen: View {
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var selectedKind: FavoriteKind? = nil
    @State private var showPlayer = false

    private var totalCount: Int { favorites.favorites.count }

    var body: some View {
        Group {
            if !favorites.hasAnyFavorites() {
                emptyState
            } else if totalCount <= 8 {
                flatList
            } else {
                sectionedList
            }
        }
        .navigationTitle("Favorites")
        .task { await favorites.loadAll() }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingSheet()
                .environmentObject(playerVM)
                .environmentObject(favorites)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Favorites Yet")
                .font(.title2.weight(.semibold))
            Text("Tap the heart on any track, book, podcast, or lecture to save it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Flat List (≤8 items)

    private var flatList: some View {
        List {
            let songs = favorites.songs()
            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(songs) { fav in
                        favoriteSongRow(fav)
                    }
                }
            }
            let books = favorites.books()
            if !books.isEmpty {
                Section("Books") {
                    ForEach(books) { fav in
                        favoriteBookRow(fav)
                    }
                }
            }
            let episodes = favorites.episodes()
            if !episodes.isEmpty {
                Section("Podcasts") {
                    ForEach(episodes) { fav in
                        favoriteEpisodeRow(fav)
                    }
                }
            }
            let lectures = favorites.lectures()
            if !lectures.isEmpty {
                Section("Lectures") {
                    ForEach(lectures) { fav in
                        favoriteLectureRow(fav)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Sectioned List (>8 items)

    private var sectionedList: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $selectedKind) {
                Text("All").tag(nil as FavoriteKind?)
                ForEach(visibleKinds(), id: \.self) { kind in
                    Text(kind.displayName).tag(kind as FavoriteKind?)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if let kind = selectedKind {
                    sectionContent(for: kind)
                } else {
                    allSectionsContent
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func visibleKinds() -> [FavoriteKind] {
        FavoriteKind.allCases.filter { favorites.count(for: $0) > 0 }
    }

    private var allSectionsContent: some View {
        ForEach(FavoriteKind.allCases, id: \.self) { kind in
            if favorites.count(for: kind) > 0 {
                sectionContent(for: kind)
            }
        }
    }

    @ViewBuilder
    private func sectionContent(for kind: FavoriteKind) -> some View {
        switch kind {
        case .track:
            let items = favorites.songs()
            if !items.isEmpty {
                Section {
                    ForEach(items) { fav in favoriteSongRow(fav) }
                } header: {
                    songsHeader(count: items.count)
                }
            }
        case .book:
            let items = favorites.books()
            if !items.isEmpty {
                Section {
                    ForEach(items) { fav in favoriteBookRow(fav) }
                } header: {
                    Text("Books")
                }
            }
        case .episode:
            let items = favorites.episodes()
            if !items.isEmpty {
                Section {
                    ForEach(items) { fav in favoriteEpisodeRow(fav) }
                } header: {
                    Text("Podcasts")
                }
            }
        case .lecture:
            let items = favorites.lectures()
            if !items.isEmpty {
                Section {
                    ForEach(items) { fav in favoriteLectureRow(fav) }
                } header: {
                    Text("Lectures")
                }
            }
        }
    }

    private func songsHeader(count: Int) -> some View {
        HStack {
            Text("Songs")
            Spacer()
            Button {
                Task { await playAllSongs(shuffle: false) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            Button {
                Task { await playAllSongs(shuffle: true) }
            } label: {
                Image(systemName: "shuffle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Song Row

    private func favoriteSongRow(_ fav: Favorite) -> some View {
        Button {
            Task {
                await playFavoriteSong(fav)
                showPlayer = true
            }
        } label: {
            HStack(spacing: 12) {
                artworkThumb(url: fav.artworkURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fav.title)
                        .font(.body)
                        .lineLimit(1)
                    if let creator = fav.creator {
                        Text(creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await removeFavorite(fav) }
            } label: {
                Label("Remove", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Book Row

    private func favoriteBookRow(_ fav: Favorite) -> some View {
        HStack(spacing: 12) {
            artworkThumb(url: fav.artworkURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.title)
                    .font(.body)
                    .lineLimit(1)
                if let creator = fav.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let rp = fav.resumePoint {
                    Text(resumeLabel(rp))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await resumeBook(fav)
                showPlayer = true
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await removeFavorite(fav) }
            } label: {
                Label("Remove", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Episode Row

    private func favoriteEpisodeRow(_ fav: Favorite) -> some View {
        HStack(spacing: 12) {
            artworkThumb(url: fav.artworkURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.title)
                    .font(.body)
                    .lineLimit(1)
                if let creator = fav.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let rp = fav.resumePoint {
                    Text("Resume — \(rp.positionSeconds.formattedTime)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await resumeEpisode(fav)
                showPlayer = true
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await removeFavorite(fav) }
            } label: {
                Label("Remove", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Lecture Row

    private func favoriteLectureRow(_ fav: Favorite) -> some View {
        HStack(spacing: 12) {
            artworkThumb(url: fav.artworkURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.title)
                    .font(.body)
                    .lineLimit(1)
                if let creator = fav.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let rp = fav.resumePoint {
                    Text("Resume — \(rp.positionSeconds.formattedTime)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await resumeLecture(fav)
                showPlayer = true
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await removeFavorite(fav) }
            } label: {
                Label("Remove", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Helpers

    private func artworkThumb(url: URL?) -> some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func resumeLabel(_ rp: ResumePoint) -> String {
        if let ch = rp.chapterIndex {
            return "Resume — Ch. \(ch + 1)"
        }
        return "Resume — \(rp.positionSeconds.formattedTime)"
    }

    private func removeFavorite(_ fav: Favorite) async {
        await favorites.db.deleteFavorite(id: fav.id)
        await favorites.loadAll()
    }

    private func playAllSongs(shuffle: Bool) async {
        let songFavs = favorites.songs()
        guard !songFavs.isEmpty else { return }
        let trackIds = songFavs.map(\.id)
        let tracks = await resolveTracks(ids: trackIds)
        guard !tracks.isEmpty else { return }
        if shuffle {
            await playerVM.playShuffledTracks(tracks)
        } else {
            await playerVM.playSequentialTracks(tracks)
        }
        showPlayer = true
    }

    private func playFavoriteSong(_ fav: Favorite) async {
        guard let track = await playerVM.db.fetchTrack(id: fav.id) else { return }
        await playerVM.playSingleTrack(track)
    }

    private func resumeBook(_ fav: Favorite) async {
        let sourceId = fav.sourceIdentifier
        var tracks = await playerVM.db.fetchTracks(forParentIdentifier: sourceId)
        if tracks.isEmpty {
            tracks = await playerVM.db.fetchTracks(forChannel: Channel(
                id: "fav-book", name: fav.title, category: "Audiobooks",
                icon: "book", contentType: .spokenWord,
                preferredSource: "internet_archive"
            )).filter { $0.parentIdentifier == sourceId || $0.id == sourceId }
        }
        if tracks.isEmpty {
            if let track = await playerVM.db.fetchTrack(id: fav.id) {
                tracks = [track]
            }
        }
        guard !tracks.isEmpty else { return }
        let sorted = tracks.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        let seekTime = fav.resumePoint?.positionSeconds ?? 0
        let startTrack = sorted.first { t in
            if let rp = fav.resumePoint, let ci = rp.chapterIndex {
                return (t.partNumber ?? 0) == ci
            }
            return true
        } ?? sorted.first!
        let rest = sorted.filter { ($0.partNumber ?? 0) >= (startTrack.partNumber ?? 0) }
        await playerVM.playSequentialItem(parts: rest, startingAt: startTrack, seekTo: seekTime)
    }

    private func resumeEpisode(_ fav: Favorite) async {
        guard let track = await playerVM.db.fetchTrack(id: fav.sourceIdentifier) else { return }
        let seekTime = fav.resumePoint?.positionSeconds ?? 0
        await playerVM.playSingleTrack(track, seekTo: seekTime)
    }

    private func resumeLecture(_ fav: Favorite) async {
        guard let track = await playerVM.db.fetchTrack(id: fav.sourceIdentifier) else { return }
        let seekTime = fav.resumePoint?.positionSeconds ?? 0
        await playerVM.playSingleTrack(track, seekTo: seekTime)
    }

    private func resolveTracks(ids: [String]) async -> [Track] {
        var result: [Track] = []
        for id in ids {
            if let t = await playerVM.db.fetchTrack(id: id) {
                result.append(t)
            }
        }
        return result
    }
}

private extension FavoriteKind {
    var displayName: String {
        switch self {
        case .track: return "Songs"
        case .book: return "Books"
        case .episode: return "Podcasts"
        case .lecture: return "Lectures"
        }
    }
}
