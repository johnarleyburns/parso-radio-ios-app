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

    @State private var confirmClearHistory = false
    @State private var confirmClearAll = false
    @State private var working = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @ObservedObject private var kids = KidsModeController.shared
    @State private var showSetKidsPin = false
    @State private var kidsPinEntry = ""
    @AppStorage("maxCacheMB") private var maxCacheMB = 250
    @AppStorage("wifiOnlyDownloads") private var wifiOnlyDownloads = true
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @State private var confirmClearDownloads = false
    @State private var confirmClearStreamingCache = false
    @State private var cacheSizeTrigger = 0

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance theme")
                .accessibilityHint("Switches between system, light, and dark mode")
            }

            Section {
                NavigationLink {
                    ContributionSupportView(store: contributionStore)
                } label: {
                    Label(contributionStore.isSupporter ? "Supporter — Thank You" : "Support Lorewave",
                          systemImage: contributionStore.isSupporter ? "heart.fill" : "heart")
                        .foregroundStyle(contributionStore.isSupporter ? Color.pink : Color.accentColor)
                }
                if contributionStore.hasActiveSubscription {
                    Toggle(isOn: Binding(
                        get: { !supporterBadgeHidden },
                        set: { supporterBadgeHidden = !$0 }
                    )) {
                        Label("Show Supporter Badge", systemImage: "seal.fill")
                    }
                    .accessibilityHint("Hides or shows the supporter badge on the Now Playing screen")
                }
            } footer: {
                Text("Keep Lorewave free and ad-free. We give 10% of proceeds to the Internet Archive.")
            }

            Section {
                if kids.isEnabled {
                    Label("Kids Mode is on", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Exit from the lock button in the Kids menu (your PIN).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button {
                        kidsPinEntry = ""
                        showSetKidsPin = true
                    } label: {
                        Label("Turn On Kids Mode", systemImage: "figure.and.child.holdinghands")
                    }
                }
            } header: {
                Text("Kids Mode")
            } footer: {
                Text("Limits the app to the children's songs and stories — no search, no news, no purchases. A 4-digit PIN is needed to turn it off, so it's safe to hand the phone to a child.")
            }

            // Storage & cache management
            Section {
                HStack {
                    Label("Downloaded", systemImage: "arrow.down.circle")
                    Spacer()
                    Text(formattedBytes(CacheManager.shared.downloadedBytes()))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Label("Streaming Cache", systemImage: "waveform.circle")
                    Spacer()
                    Text(formattedBytes(CacheManager.shared.streamingCacheBytes()))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Label("Total Used", systemImage: "internaldrive")
                    Spacer()
                    Text(formattedBytes(CacheManager.shared.totalCacheBytes()))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Streaming cache speeds up replay and scrubbing. Downloaded tracks play offline.")
            }

            Section {
                Picker("Cache Limit", selection: $maxCacheMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("5 GB").tag(5120)
                }
                .onChange(of: maxCacheMB) { _, newLimit in
                    let budget = Int64(newLimit) * 1_048_576
                    CacheManager.shared.evictIfNeeded(maxBytes: budget)
                    cacheSizeTrigger &+= 1
                }
            } header: {
                Text("Cache Limit")
            } footer: {
                Text("When the limit is exceeded, least-recently-played tracks are removed first.")
            }

            Section {
                Toggle(isOn: $wifiOnlyDownloads) {
                    Label("Wi-Fi Only Downloads", systemImage: "wifi")
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("When on, downloads and prefetch only happen on Wi-Fi. Streaming still works on cellular.")
            }

            Section {
                Button(role: .destructive) {
                    confirmClearStreamingCache = true
                } label: {
                    Label("Clear Streaming Cache", systemImage: "waveform.circle.badge.xmark")
                }
                Button(role: .destructive) {
                    confirmClearDownloads = true
                } label: {
                    Label("Delete All Downloaded Tracks", systemImage: "arrow.down.circle.badge.xmark")
                }
            } footer: {
                Text("Deleting downloads keeps your playlists and history intact. Streaming cache is temporary and rebuilt as you listen.")
            }

            Section {
                ForEach(playlistVM.playlists.filter { pl in
                    !pl.isFavorites
                }) { pl in
                    HStack {
                        Label(pl.name, systemImage: "music.note.list")
                        Spacer()
                        Button("Remove Downloads") {
                            Task {
                                working = true
                                await offlineService.removeOffline(playlist: pl)
                                await playlistVM.loadPlaylists()
                                cacheSizeTrigger &+= 1
                                working = false
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                }
            } header: {
                Text("Downloads by Playlist")
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
        .alert("Set a 4-digit PIN", isPresented: $showSetKidsPin) {
            TextField("PIN", text: $kidsPinEntry)
                .keyboardType(.numberPad)
                .accessibilityLabel("Kids Mode PIN")
                .accessibilityHint("Enter a 4-digit number to lock Kids Mode")
            Button("Turn On") {
                kids.enable(pin: kidsPinEntry)
                kidsPinEntry = ""
            }
            .accessibilityHint("Enables Kids Mode with the entered PIN")
            Button("Cancel", role: .cancel) { kidsPinEntry = "" }
        } message: {
            Text("You'll need this PIN to turn Kids Mode off. Pick something a child won't guess.")
        }
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
        .alert("Clear Streaming Cache?", isPresented: $confirmClearStreamingCache) {
            Button("Clear Cache", role: .destructive) {
                Task {
                    working = true
                    await CacheManager.shared.clearStreamingCache()
                    cacheSizeTrigger &+= 1
                    working = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes temporary streaming cache files. Downloaded tracks are kept.")
        }
        .alert("Delete All Downloads?", isPresented: $confirmClearDownloads) {
            Button("Delete Downloads", role: .destructive) {
                Task {
                    working = true
                    await offlineService.deleteAllDownloads()
                    cacheSizeTrigger &+= 1
                    working = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes all downloaded tracks. Playlists, history, and streaming cache are kept.")
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}
