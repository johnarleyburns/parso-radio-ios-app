import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var nowPlayingChannel: Channel?

    private func select(_ channel: Channel) { nowPlayingChannel = channel }

    var body: some View {
        NavigationStack {
            List {
                ForYouSection(onSelect: select)

                ForEach(LibrarySection.ordered) { section in
                    channelsSection(for: section)
                }

                LiveMusicSection(onSelect: select)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .fullScreenCover(item: $nowPlayingChannel) { channel in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .task { await playerVM.load(channel: channel) }
            }
        }
    }

    @ViewBuilder
    private func channelsSection(for section: LibrarySection) -> some View {
        let dedicated: Set<String> = ["For You", "Curated"]
        let channels = Channel.defaults.filter {
            $0.mediaKind == section.id && !dedicated.contains($0.category)
        }
        if !channels.isEmpty {
            Section(section.label) {
                ForEach(channels, id: \.id) { channel in
                    Button { select(channel) } label: {
                        Label(channel.name, systemImage: channel.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ForYouSection: View {
    let onSelect: (Channel) -> Void

    var body: some View {
        let forYouChannels = Channel.defaults.filter { $0.category == "For You" }
        if !forYouChannels.isEmpty {
            Section("For You") {
                ForEach(forYouChannels, id: \.id) { channel in
                    Button { onSelect(channel) } label: {
                        Label(channel.name, systemImage: channel.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LiveMusicSection: View {
    let onSelect: (Channel) -> Void

    var body: some View {
        Section("Live Music on This Day") {
            ForEach(Channel.defaults.filter { $0.category == "Curated" }.prefix(5), id: \.id) { channel in
                Button { onSelect(channel) } label: {
                    Label(channel.name, systemImage: "calendar")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
