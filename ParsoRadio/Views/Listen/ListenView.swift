import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var nowPlayingChannel: Channel?
    @State private var selectedRecentTrack: Track?
    @State private var showSupporterSheet = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false

    var body: some View {
        NavigationStack {
            List {
                HomeTopSection(playerVM: playerVM,
                               onSelectTrack: { selectedRecentTrack = $0 },
                               onPlayHero: { playHero() })

                MadeForYouSection()

                BooksForYouSection()

                ExploreTypeRow()

                FeaturedTodaySection(nowPlayingChannel: $nowPlayingChannel)

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
            .fullScreenCover(item: $nowPlayingChannel) { channel in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .environmentObject(playlistVM)
                    .environmentObject(deps.offlineService)
                    .task { await playerVM.load(channel: channel, autoPlay: true) }
            }
            .fullScreenCover(item: $selectedRecentTrack) { track in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .environmentObject(playlistVM)
                    .environmentObject(deps.offlineService)
                    .task { await playerVM.playRecentTrack(track) }
            }
        }
    }

    private func playHero() {
        let pool = Channel.defaults + IACollectionStore.shared.channels
        if let c = FeaturedPicker.hero(on: Date(), from: pool) { nowPlayingChannel = c }
    }
}
