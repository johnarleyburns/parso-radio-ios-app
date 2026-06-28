import SwiftUI
import UniformTypeIdentifiers

struct ChannelInfoView: View {
    let channel: Channel
    let playerVM: PlayerViewModel

    @State private var episodeCount: Int = 0

    var body: some View {
        List {
            if let urlStr = channel.imageURL, let url = URL(string: urlStr) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                                .listRowInsets(EdgeInsets())
                        case .failure:
                            EmptyView()
                        case .empty:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                } header: {
                    Text("Channel Image").textCase(nil).font(.footnote)
                }
            } else if let asset = channelAssetImage() {
                Section {
                    Image(uiImage: asset)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Channel Image").textCase(nil).font(.footnote)
                }
            }

            Section("About") {
                Text(channel.infoSentence)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if channel.category == "Curated Music",
               let col = IACollectionStore.shared.collection(forChannelId: channel.id) {
                Section("Collection") {
                    SharedViews.infoRow("Curator", col.curator)
                    if let url = col.archiveURL {
                        Link(destination: url) {
                            Label("View on Internet Archive", systemImage: "safari")
                        }
                    }
                }
            }

            Section("Details") {
                SharedViews.infoRow("Category",     channel.category)
                SharedViews.infoRow("Content type", channel.contentType.displayName)
                SharedViews.infoRow("Source",       channel.sourceName)
                if channel.iaQueryEntry != nil {
                    SharedViews.infoRow("Discovery", "Pure Internet Archive search")
                } else if let feed = channel.feedURL {
                    SharedViews.infoRow("Feed", feed)
                }
                if channel.feedURL != nil, episodeCount > 0 {
                    SharedViews.infoRow("Episodes", "\(episodeCount)")
                }
                if let minDur = channel.minTrackDuration {
                    SharedViews.infoRow("Min duration",
                            "\(Int(minDur)) seconds (shorter tracks are skipped)")
                }
            }

            Section("Licensing") {
                Text(
                    "Lorewave plays only public-domain and Creative Commons "
                    + "content. Per-track license is shown in the Track Info popup."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if channel.mediaKind == .podcast {
                let tracks = await DatabaseService.shared.fetchTracks(forChannel: channel)
                episodeCount = tracks.count
            }
        }
    }

    private func channelAssetImage() -> UIImage? {
        if let img = UIImage(named: channel.id) { return img }
        if channel.id.hasPrefix("podcast-"),
           let builtIn = Channel.defaults.first(where: {
               $0.name == channel.name && $0.category == "Podcasts" && !$0.id.hasPrefix("podcast-")
           }),
           let img = UIImage(named: builtIn.id) {
            return img
        }
        return nil
    }
}

private extension ContentType {
    var displayName: String {
        switch self {
        case .music:       return "Music"
        case .spokenWord:  return "Spoken word"
        case .ambientLoop: return "Ambient loop"
        }
    }
}

private extension Channel {
    var sourceName: String {
        switch preferredSource {
        case "internet_archive": return "Internet Archive"
        case "fma":              return "Free Music Archive"
        case "oxford_lectures":  return "Oxford University"
        case "podcast":          return "Podcast RSS"
        case "freesound":        return "Freesound"
        case "ambient":          return "Bundled ambient asset"
        case .some(let s):       return s
        case .none:              return "Mixed"
        }
    }
}
