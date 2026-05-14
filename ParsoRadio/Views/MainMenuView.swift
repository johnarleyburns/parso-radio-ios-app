import SwiftUI

struct MainMenuView: View {
    let displayChannel: Channel
    let onSelectChannel: () -> Void
    let onOpenPlaylists: () -> Void
    let onOpenSearch: () -> Void
    let onDownloadChannel: () -> Void
    let onOpenAbout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    menuRow(icon: "antenna.radiowaves.left.and.right", label: "Select Channel") {
                        onSelectChannel()
                    }
                    menuRow(icon: "music.note.list", label: "Playlists") {
                        onOpenPlaylists()
                    }
                    menuRow(icon: "magnifyingglass", label: "Search") {
                        onOpenSearch()
                    }
                    menuRow(icon: "arrow.down.circle", label: "Download \(displayChannel.name)") {
                        onDownloadChannel()
                    }
                }
                Section {
                    menuRow(icon: "info.circle", label: "About") {
                        onOpenAbout()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parso Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func menuRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.body)
                .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }
}
