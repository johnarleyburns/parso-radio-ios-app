import SwiftUI

/// Lists every chapter/lecture of the currently-playing multi-part item
/// (audiobook, classical work, lecture series). The current item is
/// highlighted; tap a row to jump to that chapter/lecture immediately.
struct ChapterListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var onDismiss: (() -> Void)? = nil
    /// When true, tapping a chapter closes this list and re-opens the full
    /// player for the new chapter (now-playing surface flow).
    var presentedFromSurface: Bool = false

    @State private var chapters: [Track] = []
    @State private var isLoading = true

    private var isLecture: Bool {
        playerVM.currentChannel?.mediaKind == .lecture
    }

    private var itemNoun: String { isLecture ? "lecture" : "chapter" }
    private var itemsNoun: String { isLecture ? "Lectures" : "Chapters" }

    private var navigationTitle: String {
        chapters.first?.collectionTitle ?? itemsNoun
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(itemsNoun.lowercased())…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chapters.isEmpty {
                ContentUnavailableView(
                    "No \(itemsNoun)",
                    systemImage: isLecture ? "building.columns" : "book.closed",
                    description: Text(isLecture
                        ? "This lecture is a standalone talk — there are no other lectures in the series."
                        : "This item is a single file — there are no separate chapters to navigate.")
                )
            } else {
                List {
                    Section {
                        ForEach(chapters) { chapter in
                            Button {
                                Task { await playerVM.playRecentTrack(chapter) }
                                if presentedFromSurface {
                                    playerVM.didSelectFromSurfaceList()
                                } else {
                                    onDismiss?()
                                }
                            } label: {
                                chapterRow(chapter)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chapterlist.row.\(chapter.id)")
                        }
                    } header: {
                        Text(summaryText)
                            .textCase(nil)
                            .accessibilityLabel(summaryAccessibilityText)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chapters = await playerVM.bookmarks.fetchCurrentItemChapters() ?? []
            isLoading = false
        }
    }

    @ViewBuilder
    private func chapterRow(_ chapter: Track) -> some View {
        let isCurrent = playerVM.currentTrack?.id == chapter.id
        HStack(spacing: 10) {
            if let part = chapter.partNumber {
                Text("\(part)")
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    .frame(width: 32, alignment: .trailing)
            } else {
                Spacer().frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(2)
                if chapter.duration > 0 {
                    Text(chapter.duration.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "play.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isCurrent ? "Currently playing" : "Plays this \(itemNoun)")
    }

    private var summaryText: String {
        let count = chapters.count
        let noun = count == 1 ? itemNoun : itemsNoun.lowercased()
        let total = chapters.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) \(noun) · \(total.formattedTime)"
            : "\(count) \(noun)"
    }

    private var summaryAccessibilityText: String {
        let count = chapters.count
        let total = chapters.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) \(itemsNoun.lowercased()), total time \(total.formattedTime)"
            : "\(count) \(itemsNoun.lowercased())"
    }
}
