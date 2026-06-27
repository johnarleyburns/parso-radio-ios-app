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
    let title: String
    let subtitle: String
    let artworkURL: URL?

    init(track: Track) {
        self.title = track.title
        self.subtitle = track.artist
        self.artworkURL = track.resolvedArtworkURL
    }

    init(work: RecentWork) {
        self.title = work.displayTitle
        self.subtitle = work.displaySubtitle
        self.artworkURL = work.track.resolvedArtworkURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: artworkURL) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color(.systemGray5).overlay(Image(systemName: "music.note")) }
            }
            .frame(width: 120, height: 120)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            Text(title).font(.caption.weight(.medium)).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 120)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

extension RecentWork {
    /// Stable XCUITest identifier distinguishing a whole-work card (book vs
    /// music album) from a standalone track.
    var jumpBackInAccessibilityID: String {
        guard playsWholeWork, let parent = track.parentIdentifier else {
            return "jumpbackin.card.track.\(track.id)"
        }
        return mediaKind == .music
            ? "jumpbackin.card.album.\(parent)"
            : "jumpbackin.card.book.\(parent)"
    }
}

// MARK: - Home Top Section (Welcome or Jump Back In)

struct HomeTopSection: View {
    let playerVM: PlayerViewModel
    let onSelectWork: (RecentWork) -> Void
    let onPlayHero: () -> Void

    @State private var items: [RecentWork] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if !loaded {
                Color.clear
                    .frame(height: 120)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if items.isEmpty {
                WelcomeCard(onPlay: onPlayHero)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { work in
                            Button { onSelectWork(work) } label: { JumpBackInCard(work: work) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(work.jumpBackInAccessibilityID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Jump back in")
        }
        .task(id: playerVM.playHistoryVersion) {
            items = await playerVM.recentlyPlayedWorks(limit: 10)
            loaded = true
        }
    }
}


