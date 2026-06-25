import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var presentation: ListenPresentation?
    @State private var showSupporterSheet = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false

    var body: some View {
        NavigationStack {
            List {
                HomeTopSection(playerVM: playerVM,
                               onSelectWork: { presentation = .work($0) },
                               onPlayHero: { playHero() })

                MadeForYouSection()

                BooksForYouSection()

                ExploreTypeRow()

                FeaturedTodaySection(onSelect: { presentation = .channel($0) })

                Section {
                    NavigationLink {
                        List { ForEach(LibrarySection.ordered) { s in
                            NavigationLink { ChannelBrowseList(kind: s.id) } label: { Label(s.label, systemImage: s.icon) }
                        } }
                        .listStyle(.insetGrouped)
                        .navigationTitle("Browse")
                    } label: {
                        Label("Browse all collections", systemImage: "square.grid.2x2")
                    }
                }

                Color.clear
                    .frame(height: 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if contributionStore.isSupporter && !supporterBadgeHidden {
                            Button {
                                showSupporterSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("SUPPORTER")
                                        .font(.caption2)
                                        .fontDesign(.rounded)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    Image(systemName: "heart.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .accessibilityLabel("Supporter")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showSupporterSheet) {
                NavigationStack {
                    ContributionSupportView(store: contributionStore, showsDoneButton: true)
                }
            }
        }
        .fullScreenCover(item: $presentation) { item in
            NowPlayingSheet()
                .environmentObject(playerVM)
                .environmentObject(favorites)
                .environmentObject(playlistVM)
                .environmentObject(deps.offlineService)
                .task {
                    switch item {
                    case .channel(let channel):
                        await playerVM.load(channel: channel, autoPlay: true)
                    case .work(let work):
                        await playerVM.playRecentWork(work)
                    }
                }
        }
    }

    private func playHero() {
        let pool = Channel.defaults + IACollectionStore.shared.channels
        if let c = FeaturedPicker.hero(on: Date(), from: pool) { presentation = .channel(c) }
    }
}

/// Drives the single now-playing `fullScreenCover` in ListenView. Using one
/// presentation item (instead of multiple stacked `.fullScreenCover` modifiers)
/// guarantees the sheet actually presents for every entry point.
enum ListenPresentation: Identifiable {
    case channel(Channel)
    case work(RecentWork)

    var id: String {
        switch self {
        case .channel(let c): return "channel:\(c.id)"
        case .work(let w): return "work:\(w.id)"
        }
    }
}
