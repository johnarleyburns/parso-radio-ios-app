import SwiftUI

struct MainMenuView: View {
    @Binding var showChannels: Bool
    @Binding var showPlaylists: Bool
    @Binding var showSearch: Bool
    var onAbout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                menuRow(icon: "antenna.radiowaves.left.and.right", label: "Channels") {
                    showChannels = true
                    dismiss()
                }
                menuRow(icon: "music.note.list", label: "Playlists") {
                    showPlaylists = true
                    dismiss()
                }
                menuRow(icon: "magnifyingglass", label: "Search") {
                    showSearch = true
                    dismiss()
                }
                Divider()
                menuRow(icon: "info.circle", label: "About") {
                    onAbout()
                    dismiss()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parso Music")
            .navigationBarTitleDisplayMode(.inline)
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
