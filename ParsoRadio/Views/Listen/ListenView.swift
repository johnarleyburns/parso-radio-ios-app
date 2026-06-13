import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                ForYouSection()

                ForEach(LibrarySection.ordered) { section in
                    channelsSection(for: section)
                }

                LiveMusicSection()
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listen")
            .navigationDestination(for: Channel.self) { channel in
                PlayerView(channel: channel)
                    .environmentObject(playerVM)
            }
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
        }
    }

    @ViewBuilder
    private func channelsSection(for section: LibrarySection) -> some View {
        let channels = Channel.defaults.filter { $0.mediaKind == section.id }
        if !channels.isEmpty {
            Section(section.label) {
                ForEach(channels, id: \.id) { channel in
                    NavigationLink(value: channel) {
                        Label(channel.name, systemImage: channel.icon)
                    }
                }
            }
        }
    }
}

private struct ForYouSection: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        let forYouChannels = Channel.defaults.filter { $0.category == "For You" }
        if !forYouChannels.isEmpty {
            Section("For You") {
                ForEach(forYouChannels, id: \.id) { channel in
                    NavigationLink(value: channel) {
                        Label(channel.name, systemImage: channel.icon)
                    }
                }
            }
        }
    }
}

private struct LiveMusicSection: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        Section("Live Music on This Day") {
            ForEach(Channel.defaults.filter { $0.category == "Curated" }.prefix(5), id: \.id) { channel in
                NavigationLink(value: channel) {
                    Label(channel.name, systemImage: "calendar")
                }
            }
        }
    }
}
