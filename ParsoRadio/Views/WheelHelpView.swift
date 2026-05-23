import SwiftUI

/// Explains the click-wheel's non-obvious gestures. Shown once on first launch
/// (HIG: make non-standard gestures discoverable) and re-openable from About.
struct WheelHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let rows: [Row] = [
        Row(icon: "line.3.horizontal", title: "Menu (top)",
            detail: "Tap to open the current playlist or channel info. Double-tap to jump straight to the Main Menu."),
        Row(icon: "forward.fill", title: "Forward (right)",
            detail: "Tap to skip ahead 10 seconds. Double-tap for the next track. Press and hold to fast-forward, accelerating as you hold."),
        Row(icon: "backward.fill", title: "Back (left)",
            detail: "Tap to jump back 10 seconds. Double-tap for the previous track. Press and hold to rewind."),
        Row(icon: "playpause.fill", title: "Play / Pause (bottom)",
            detail: "Tap to play or pause."),
        Row(icon: "info.circle", title: "Center",
            detail: "Tap the middle of the wheel to open Track Info — speed, sleep timer, bookmarks, favorites and more.")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The wheel is your remote. Here's what each part does:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 14) {
                        Image(systemName: row.icon)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).font(.headline)
                            Text(row.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("How the Wheel Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                }
            }
        }
    }
}
