import SwiftUI

struct BooksForYouSection: View {
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var shelfStore: MadeForYouShelfStore = {
        MadeForYouShelfStore(
            db: DatabaseService.shared,
            tasteProfileStore: TasteProfileStore(db: DatabaseService.shared),
            shelf: .books
        )
    }()

    var body: some View {
        Section {
            switch shelfStore.state {
            case .idle, .loading:
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Finding books for you\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .listRowBackground(Color.clear)

            case .loaded(_, let tracks) where !tracks.isEmpty:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(tracks, id: \.id) { track in
                            Button {
                                Task { await playBook(track) }
                            } label: {
                                JumpBackInCard(track: track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

            case .loaded(_, let tracks):
                Text("No book picks right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
                    .listRowBackground(Color.clear)

            case .empty(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await shelfStore.loadIfNeeded(historyVersion: playerVM.playHistoryVersion) }
                    }
                    .font(.caption)
                }
                .frame(height: 80)
                .listRowBackground(Color.clear)

            case .failed(let message, let retryable):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if retryable {
                        Button("Retry") {
                            Task { await shelfStore.loadIfNeeded(historyVersion: playerVM.playHistoryVersion) }
                        }
                        .font(.caption)
                    }
                }
                .frame(height: 80)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Books for You")
        } footer: {
            if case .loaded(let kind, let tracks) = shelfStore.state, !tracks.isEmpty {
                switch kind {
                case .personalized:
                    Text("Audiobooks from your taste \u{00B7} refreshes as you listen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .coldStart:
                    Text("Starter audiobooks while Lorewave learns \u{00B7} refreshes as you listen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: playerVM.playHistoryVersion) {
            shelfStore.setArchiveService(deps.archiveService)
            await shelfStore.loadIfNeeded(historyVersion: playerVM.playHistoryVersion)
        }
    }

    private func playBook(_ track: Track) async {
        let identifier = track.parentIdentifier ?? track.id
        playerVM.beginDirectPlaybackContext(
            pre: track,
            context: PlaybackContext(
                origin: .bookForYou, mediaKind: .audiobook,
                title: track.title),
            description: track.title)
        do {
            let tracks = try await deps.archiveService.fetchTracksForIdentifier(identifier)
            guard !tracks.isEmpty else {
                playerVM.errorMessage = "This book doesn't have any playable audio files."
                return
            }
            await playerVM.playAlbumTracks(tracks, title: track.title,
                                           mediaKind: .audiobook, origin: .bookForYou)
        } catch {
            playerVM.errorMessage = "Couldn't load this book. Try again later."
        }
    }
}
