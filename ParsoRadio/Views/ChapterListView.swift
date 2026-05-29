import SwiftUI

/// Lists every chapter of the currently-playing multi-part item (audiobook,
/// classical work, lecture series). The current chapter is highlighted; tap a
/// row to jump to that chapter immediately.
struct ChapterListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var chapters: [Track] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chapters…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chapters.isEmpty {
                ContentUnavailableView(
                    "No Chapters",
                    systemImage: "book.closed",
                    description: Text("This item is a single file — there are no separate chapters to navigate.")
                )
            } else {
                List {
                    Section {
                        ForEach(chapters) { chapter in
                            Button {
                                Task { await playerVM.playRecentTrack(chapter) }
                                onDismiss?()
                            } label: {
                                chapterRow(chapter)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        // Whole-work scope: how many chapters and the summed runtime.
                        Text(summaryText)
                            .textCase(nil)
                            .accessibilityLabel(summaryAccessibilityText)
                    }
                }
            }
        }
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chapters = await playerVM.fetchCurrentItemChapters() ?? []
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
                    Text(formatTime(chapter.duration))
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
        .accessibilityHint(isCurrent ? "Currently playing" : "Plays this chapter")
    }

    // "124 chapters · 38:42:10" — total parts + summed runtime (omitted if no
    // durations are known).
    private var summaryText: String {
        let count = chapters.count
        let noun = count == 1 ? "chapter" : "chapters"
        let total = chapters.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) \(noun) · \(formatTime(total))"
            : "\(count) \(noun)"
    }

    private var summaryAccessibilityText: String {
        let count = chapters.count
        let total = chapters.reduce(0.0) { $0 + max(0, $1.duration) }
        return total > 0
            ? "\(count) chapters, total time \(formatTime(total))"
            : "\(count) chapters"
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
