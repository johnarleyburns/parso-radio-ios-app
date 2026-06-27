import SwiftUI

struct EpisodeListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    /// When true, tapping an episode closes this list and re-opens the full
    /// player for the new episode (now-playing surface flow).
    var presentedFromSurface: Bool = false

    @State private var episodes: [Track] = []
    @State private var isLoading = true

    private var channelName: String {
        playerVM.currentChannel?.name ?? "Podcast"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                ContentUnavailableView(
                    "No Episodes",
                    systemImage: "newspaper",
                    description: Text("No episodes found for \(channelName).")
                )
            } else {
                List {
                    Section {
                        ForEach(episodes) { episode in
                            Button {
                                Task { await playerVM.playRecentTrack(episode) }
                                if presentedFromSurface {
                                    playerVM.didSelectFromSurfaceList()
                                }
                            } label: {
                                episodeRow(episode)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(summaryText)
                            .textCase(nil)
                            .accessibilityLabel(summaryAccessibilityText)
                    }
                }
            }
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            episodes = await fetchEpisodes()
            isLoading = false
        }
    }

    @ViewBuilder
    private func episodeRow(_ episode: Track) -> some View {
        let isCurrent = playerVM.currentTrack?.id == episode.id
        let artworkURL: URL? = episode.artworkURLString.flatMap(URL.init)
            ?? playerVM.currentChannel?.imageURL.flatMap(URL.init)
        HStack(spacing: 10) {
            Group {
                if let url = artworkURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Color(.systemGray5).overlay(
                                Image(systemName: "newspaper").foregroundStyle(.secondary)
                            )
                        }
                    }
                } else {
                    Color(.systemGray5).overlay(
                        Image(systemName: "newspaper").foregroundStyle(.secondary)
                    )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if episode.recordingDate != nil {
                        Text(episode.recordingDate!.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if episode.duration > 0 {
                        Text(episode.duration.formattedTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "play.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isCurrent ? "Currently playing" : "Plays this episode")
    }

    private var summaryText: String {
        let count = episodes.count
        let noun = count == 1 ? "episode" : "episodes"
        let total = episodes.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) \(noun) · \(total.formattedTime)"
            : "\(count) \(noun)"
    }

    private var summaryAccessibilityText: String {
        let count = episodes.count
        let total = episodes.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) episodes, total time \(total.formattedTime)"
            : "\(count) episodes"
    }

    private func fetchEpisodes() async -> [Track] {
        guard let channel = playerVM.currentChannel else { return [] }
        return await playerVM.db.fetchTracks(forChannel: channel)
            .filter { $0.source == "podcast" }
            .sorted { ($0.qualityScore) > ($1.qualityScore) }
    }
}
