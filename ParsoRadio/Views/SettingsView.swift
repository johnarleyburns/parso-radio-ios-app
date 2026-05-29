import SwiftUI

/// Settings: appearance + data management. Reached from the Main Menu (above
/// About). Two destructive actions, each behind a confirmation:
///  - Clear Listening History: the all-time history that powers the "for you"
///    recommendation channels (keeps playlists & downloads).
///  - Clear All Data: erase everything (history, playlists, downloads).
struct SettingsView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService

    // "system" | "light" | "dark" — applied at the app root via preferredColorScheme.
    @AppStorage("appearance") private var appearance: String = "system"

    // EXPERIMENTAL: route remote streams through CachingResourceLoaderDelegate so
    // streamed bytes warm an on-disk prefix cache (replays / seeks serve from
    // disk). Default OFF — flip on a real device to validate.

    @State private var confirmClearHistory = false
    @State private var confirmClearAll = false
    @State private var working = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                NavigationLink {
                    ContributionSupportView(store: contributionStore)
                } label: {
                    Label(contributionStore.isSupporter ? "Supporter — Thank You" : "Support Lorewave",
                          systemImage: contributionStore.isSupporter ? "heart.fill" : "heart")
                        .foregroundStyle(contributionStore.isSupporter ? Color.pink : Color.accentColor)
                }
            } footer: {
                Text("Keep Lorewave free and ad-free. We give 10% of proceeds to the Internet Archive.")
            }

            Section {
                Button(role: .destructive) {
                    confirmClearHistory = true
                } label: {
                    Label("Clear Listening History", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Erases your all-time listening history, which powers the “for you” recommendation channels and Recently Played. Your playlists and downloads are kept.")
            }

            Section {
                Button(role: .destructive) {
                    confirmClearAll = true
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                }
            } footer: {
                Text("Deletes everything: all listening history, every playlist, and all downloaded tracks. This cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .alert("Clear Listening History?", isPresented: $confirmClearHistory) {
            Button("Clear History", role: .destructive) {
                Task {
                    working = true
                    await playerVM.clearListeningHistory()
                    working = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recommended channels will reset and Recently Played will be emptied. Playlists and downloads are kept.")
        }
        .alert("Clear All Data?", isPresented: $confirmClearAll) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    working = true
                    await offlineService.deleteAllDownloads()
                    await playerVM.clearAllUserData()
                    await playlistVM.loadPlaylists()
                    working = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes ALL your data — listening history, every playlist, and all downloaded tracks. This cannot be undone.")
        }
    }
}
