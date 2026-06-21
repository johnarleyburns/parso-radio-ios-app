import SwiftUI

// MARK: - Explore Type Row

struct ExploreTypeRow: View {
    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LibrarySection.ordered) { section in
                        NavigationLink {
                            ChannelBrowseList(kind: section.id)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: section.icon)
                                    .font(.title3)
                                    .frame(width: 30, height: 30)
                                Text(section.short).font(.caption)
                            }
                            .frame(width: 76, height: 72)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse \(section.short)")
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text("Explore")
        }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    let onPlay: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free & open audio").font(.headline)
            Text("Music, audiobooks, lectures, podcasts and ambient sound from the Internet Archive, LibriVox and Oxford — no ads, no login, no tracking, free forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onPlay) {
                Label("Play something now", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Jump Back In Card

struct JumpBackInCard: View {
    let track: Track
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: track.resolvedArtworkURL) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color(.systemGray5).overlay(Image(systemName: "music.note")) }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(track.title).font(.caption.weight(.medium)).lineLimit(1)
            Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 120)
        .contentShape(Rectangle())
    }
}

// MARK: - Home Top Section (Welcome or Jump Back In)

struct HomeTopSection: View {
    let playerVM: PlayerViewModel
    let onSelectTrack: (Track) -> Void
    let onPlayHero: () -> Void

    @State private var items: [Track] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if !loaded {
                Color.clear
                    .frame(height: 0)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if items.isEmpty {
                WelcomeCard(onPlay: onPlayHero)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items, id: \.id) { track in
                            Button { onSelectTrack(track) } label: { JumpBackInCard(track: track) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
        } header: {
            if loaded && !items.isEmpty { Text("Jump back in") }
        }
        .task(id: playerVM.playHistoryVersion) {
            items = await playerVM.recentlyPlayedTracks(limit: 10)
            loaded = true
        }
    }
}

// MARK: - Featured Card

struct FeaturedCard: View {
    let channel: Channel
    let titleOverride: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    if let s = channel.imageURL, let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() }
                            else { Image(systemName: channel.icon).font(.title).foregroundStyle(.secondary) }
                        }
                    } else {
                        Image(systemName: channel.icon).font(.title).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(titleOverride ?? channel.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(LibrarySection.section(for: channel.mediaKind).short)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(titleOverride ?? channel.name)")
    }
}

// MARK: - Featured Today Section

struct FeaturedTodaySection: View {
    let playerVM: PlayerViewModel
    @Binding var nowPlayingChannel: Channel?

    @State private var hasHistory = false
    private var forYouChannel: Channel? { Channel.defaults.first { $0.id == "for-you" } }

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if hasHistory, let fy = forYouChannel {
                        FeaturedCard(channel: fy, titleOverride: "Made for you") { nowPlayingChannel = fy }
                    }
                    ForEach(FeaturedPicker.featured(on: Date(), from: Channel.defaults + IACollectionStore.shared.channels), id: \.id) { channel in
                        FeaturedCard(channel: channel, titleOverride: nil) { nowPlayingChannel = channel }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text("Featured today")
        }
        .task(id: playerVM.playHistoryVersion) {
            hasHistory = !(await playerVM.recentlyPlayedTracks(limit: 1)).isEmpty
        }
    }
}
