import SwiftUI

struct MadeForYouSection: View {
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var showSection = false
    @State private var loaded = false

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Finding fresh picks...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .listRowBackground(Color.clear)
            } else if showSection, !tracks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(tracks, id: \.id) { track in
                            Button {
                                Task { await playerVM.playRecentTrack(track) }
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
            } else {
                Color.clear
                    .frame(height: 0)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            if showSection, loaded, !tracks.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                                             Color(red: 0.10, green: 0.22, blue: 0.65)]),
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Made for You")
                        .font(.headline.weight(.semibold))
                }
            }
        } footer: {
            if !isLoading, loaded, !tracks.isEmpty {
                Text("Fresh picks from your taste \u{00B7} refreshes daily")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: playerVM.playHistoryVersion) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        let hasProfile = await deps.tasteProfileStore.hasAnyProfile()
        showSection = true
        guard !loaded else { return }

        isLoading = true
        defer { isLoading = false }

        let controller = RecommendationsController(
            db: deps.db, archiveService: deps.archiveService,
            tasteStore: deps.tasteProfileStore)
        if let recs = try? await controller.fetchMixedRecommendations() {
            tracks = recs
        }

        // Cold-start fallback: if no profile yet (skipped onboarding, fresh install),
        // show popular picks from curated collections so the rail is never empty.
        if tracks.isEmpty, !hasProfile {
            tracks = await fetchColdStartPicks()
        }

        loaded = true
    }

    private func fetchColdStartPicks() async -> [Track] {
        let queries = [
            "mediatype:audio AND collection:(etree OR musopen OR 78rpm)",
            "mediatype:audio AND collection:librivoxaudio"
        ]
        var results: [Track] = []
        for query in queries {
            if let batch = try? await deps.archiveService.fetchTracks(
                iaQuery: query, matchTags: ["for-you"], limit: 15
            ), !batch.isEmpty {
                results.append(contentsOf: batch)
            }
        }
        return Array(results.shuffled().prefix(RecommendationConstants.kTarget))
    }
}
