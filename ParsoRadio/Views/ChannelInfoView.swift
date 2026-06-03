import SwiftUI

/// "About this channel" — shown when the user taps the channel name on the
/// player. Surfaces the user-facing summary plus the technical knobs that
/// determine what the channel plays (category, content type, source).
struct ChannelInfoView: View {
    let channel: Channel

    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showCurator = false
    @ObservedObject private var chStore = CustomChannelsStore.shared

    /// For curated channels, look up the live name from CustomChannelsStore
    /// so renames appear immediately. Falls back to the Channel model for
    /// non-curated channels.
    private var displayName: String {
        if channel.category == "Curated",
           let meta = chStore.customChannels.first(where: { $0.id == channel.id }) {
            return meta.name
        }
        return channel.name
    }

    // Pushed inside the Main Menu's navigation stack — the standard back
    // chevron returns to the menu list (no own NavigationStack / Done button).
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: channel.icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
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
                }
            }

            Section("About") {
                Text(channel.infoSentence)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Details") {
                infoRow("Category",     channel.category)
                infoRow("Content type", channel.contentType.displayName)
                infoRow("Source",       channel.sourceName)
                if channel.iaQueryEntry != nil {
                    infoRow("Discovery", "Pure Internet Archive search")
                } else if let feed = channel.feedURL {
                    infoRow("Feed", feed)
                }
                if let minDur = channel.minTrackDuration {
                    infoRow("Min duration",
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
                CuratorChannelEditView(channelMeta: meta, onDismiss: { showCurator = false })
                    .environmentObject(playerVM)
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
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

