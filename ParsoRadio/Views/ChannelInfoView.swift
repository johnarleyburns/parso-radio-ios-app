import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ChannelExport: Codable {
    struct Info: Codable {
        let id: String
        let name: String
        let icon: String
        let iaQuery: String?
    }
    struct ApprovedEntry: Codable {
        let id: String
        let title: String
        let creator: String
        let duration: Double
        let parentIdentifier: String?
    }
    let version: Int
    let channel: Info
    let updatedAt: String
    let approved: [ApprovedEntry]
    let rejected: [String]
}

extension ChannelExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        DataRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? encoder.encode(export)) ?? Data()
        }
        FileRepresentation(exportedContentType: .json) { export in
            let slug = export.channel.name.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            let dateStr = ISO8601DateFormatter().string(from: Date())
                .prefix(10).replacingOccurrences(of: "-", with: "")
            let filename = "lorewave-\(slug)-\(dateStr).json"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export)
            try data.write(to: tmpURL)
            return SentTransferredFile(tmpURL)
        }
    }
}

/// "About this channel" — shown when the user taps the channel name on the
/// player. Surfaces the user-facing summary plus the technical knobs that
/// determine what the channel plays (category, content type, source).
struct ChannelInfoView: View {
    let channel: Channel

    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showCurator = false
    @State private var showIconPicker = false
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var isPreparingExport = false
    @State private var channelExport: ChannelExport?
    @ObservedObject private var chStore = CustomChannelsStore.shared
    @State private var episodeCount: Int = 0
    @State private var currentIcon: String
    @State private var localImageURL: String?

    init(channel: Channel) {
        self.channel = channel
        _currentIcon = State(initialValue: channel.icon)
        _localImageURL = State(initialValue: channel.imageURL)
    }

    private var displayName: String {
        if channel.category == "Curated",
           let meta = chStore.customChannels.first(where: { $0.id == channel.id }) {
            return meta.name
        }
        return channel.name
    }

    private var hasApprovedTracks: Bool {
        channel.category == "Curated"
            && !LiveCurationStore.shared.pool(for: channel.id).isEmpty
    }

    private var exportSlug: String {
        displayName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if let urlStr = localImageURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                channelIconView
                            }
                        }
                    } else {
                        channelIconView
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.title3).fontWeight(.semibold)
                        Text(channel.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            // Channel image — shown full-width below the name box
            if let urlStr = localImageURL, let url = URL(string: urlStr) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                                .listRowInsets(EdgeInsets())
                                .contextMenu {
                                    Button {
                                        saveToPhotos(url: urlStr)
                                    } label: {
                                        Label("Save Image", systemImage: "square.and.arrow.down")
                                    }
                                    if let imgURL = URL(string: urlStr) {
                                        ShareLink(item: imgURL) {
                                            Label("Share Image…", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                }
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

            // Curate this Channel (for user-curated or shipped channels)
            if channel.category == "Curated",
               CustomChannelsStore.shared.customChannels.contains(where: { $0.id == channel.id }) {
                Section {
                    Button {
                        showCurator = true
                    } label: {
                        Label("Curate this Channel", systemImage: "checklist")
                            .foregroundStyle(Color.accentColor)
                    }
                    Button {
                        showIconPicker = true
                    } label: {
                        Label("Edit Channel Icon", systemImage: "paintbrush")
                            .foregroundStyle(Color.accentColor)
                    }
                    Button {
                        showImagePicker = true
                    } label: {
                        Label(localImageURL != nil ? "Change Channel Image" : "Set Channel Image",
                              systemImage: "photo")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            // Export this Channel (for curated channels with approved tracks)
            if hasApprovedTracks {
                Section {
                    if isPreparingExport || channelExport == nil {
                        HStack { ProgressView(); Text("Preparing export…")
                            .foregroundStyle(.secondary) }
                    } else if let export = channelExport {
                        ShareLink(
                            item: export,
                            preview: SharePreview(
                                "\(displayName) Curated Tracks",
                                image: Image(systemName: currentIcon))
                        ) {
                            Label("Export this Channel", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } footer: {
                    Text("Export all approved and rejected tracks as a JSON file you can share, import on another device, or merge back into the app's defaults using the merge-curation CLI tool.")
                }
            }

            Section("About") {
                Text(channel.infoSentence)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
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
        .navigationTitle("Channel Info")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCurator) {
            if let meta = CustomChannelsStore.shared.customChannels.first(where: { $0.id == channel.id }) {
                CuratorChannelEditView(channelMeta: meta, playerVM: playerVM, onDismiss: { showCurator = false })
            }
        }
        .task {
            if channel.feedURL != nil {
                let tracks = await DatabaseService.shared.fetchTracks(forChannel: channel)
                episodeCount = tracks.count
            }
            if hasApprovedTracks { await prepareExport() }
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $currentIcon,
                           channelId: channel.id,
                           chStore: chStore)
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImageItem,
                       matching: .images)
        .onChange(of: selectedImageItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    saveChannelImage(data)
                }
            }
        }
    }

    private var channelIconView: some View {
        Group {
            if let assetImage = channelAssetImage() {
                Image(uiImage: assetImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: currentIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
    }

    private func channelAssetImage() -> UIImage? {
        if let img = UIImage(named: channel.id) { return img }
        // User-added podcasts: resolve via built-in name match
        if channel.id.hasPrefix("podcast-"),
           let builtIn = Channel.defaults.first(where: {
               $0.name == channel.name && $0.category == "Podcasts" && !$0.id.hasPrefix("podcast-")
           }),
           let img = UIImage(named: builtIn.id) {
            return img
        }
        return nil
    }

    private func saveChannelImage(_ data: Data) {
        guard var def = CustomChannelsStore.shared.channelDefinition(for: channel.id)
        else { return }
        let url = CustomChannelsStore.channelsDir
            .appendingPathComponent("\(channel.id).png")
        try? data.write(to: url, options: .atomic)
        localImageURL = url.absoluteString
        def.channel = ChannelDefinition.Info(
            id: def.channel.id, name: def.channel.name,
            icon: def.channel.icon, iaQuery: def.channel.iaQuery,
            imageFilename: "\(channel.id).png"
        )
        CustomChannelsStore.shared.writeChannelDefinition(def)
    }

    private func saveToPhotos(url: String) {
        guard let imgURL = URL(string: url),
              let data = try? Data(contentsOf: imgURL),
              let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func prepareExport() async {
        isPreparingExport = true
        defer { isPreparingExport = false }

        let approvedTracks = await DatabaseService.shared.fetchApprovedTracks(forChannelId: channel.id)
        let rejectedTracks = await DatabaseService.shared.fetchRejectedTracks(forChannelId: channel.id)
        let approvedEntries = approvedTracks.map {
            ChannelExport.ApprovedEntry(
                id: $0.id, title: $0.title, creator: $0.artist,
                duration: $0.duration, parentIdentifier: $0.parentIdentifier)
        }
        let info = ChannelExport.Info(
            id: channel.id,
            name: displayName,
            icon: currentIcon,
            iaQuery: channel.iaQueryEntry?.iaQuery
        )
        channelExport = ChannelExport(
            version: 1,
            channel: info,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            approved: approvedEntries,
            rejected: rejectedTracks.map { $0.id }
        )
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
