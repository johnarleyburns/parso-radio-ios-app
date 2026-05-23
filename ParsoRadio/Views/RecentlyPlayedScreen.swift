import SwiftUI

/// Recently Played, reached by drilling in from the Main Menu (a category like
/// the others, not expanded inline). Lists recent tracks; tap to play, swipe to
/// remove, Clear empties the list.
struct RecentlyPlayedScreen: View {
    let dismissAll: () -> Void
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var tracks: [Track] = []

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "Nothing Played Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Tracks you play will show up here.")
                )
            } else {
                ForEach(tracks) { track in row(track) }
                    .onDelete { indices in
                        let toRemove = indices.map { tracks[$0] }
                        Task {
                            for t in toRemove { await playerVM.removeFromRecentlyPlayed(t) }
                            tracks = await playerVM.recentlyPlayedTracks(limit: 50)
                        }
                    }
            }
        }
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !tracks.isEmpty {
                    Button(role: .destructive) {
                        Task {
                            await playerVM.clearRecentlyPlayed()
                            tracks = []
                        }
                    } label: { Text("Clear") }
                    .accessibilityLabel("Clear all Recently Played")
                }
            }
        }
        .task { tracks = await playerVM.recentlyPlayedTracks(limit: 50) }
    }

    @ViewBuilder
    private func row(_ track: Track) -> some View {
        Button {
            Task {
                await playerVM.playRecentTrack(track)
                dismissAll()
            }
        } label: {
            HStack(spacing: 10) {
                ArtworkThumbnail(track: track, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.body).lineLimit(1)
                    Text(track.artist).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await playerVM.removeFromRecentlyPlayed(track)
                    tracks = await playerVM.recentlyPlayedTracks(limit: 50)
                }
            } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
    }
}
