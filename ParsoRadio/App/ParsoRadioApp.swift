import SwiftUI

private func makeSharedDB() -> DatabaseService {
    do {
        return try DatabaseService()
    } catch {
        return try! DatabaseService(path: ":memory:")
    }
}

@main
struct ParsoMusicApp: App {
    private static let sharedDB = makeSharedDB()
    private static let sharedDownloadManager = DownloadManager(db: sharedDB)
    @MainActor static let sharedContributionStore = ContributionStore()

    @StateObject private var playerVM: PlayerViewModel = {
        let db = ParsoMusicApp.sharedDB
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: AudioPlayerService(),
            downloadManager: ParsoMusicApp.sharedDownloadManager
        )
        AppIntentBridge.shared.playerVM = vm
        PodcastSubscriptionStore.shared.configure(db: db)
        return vm
    }()

    @StateObject private var playlistVM: PlaylistViewModel = {
        PlaylistViewModel(db: ParsoMusicApp.sharedDB)
    }()

    @StateObject private var offlineService: OfflineDownloadService = {
        OfflineDownloadService(db: ParsoMusicApp.sharedDB, downloadManager: ParsoMusicApp.sharedDownloadManager)
    }()

    @StateObject private var contributions =
        ContributionCoordinator(store: ParsoMusicApp.sharedContributionStore)

    @AppStorage("tosAccepted") private var tosAccepted: Bool = false
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showSplash: Bool = {
        if UserDefaults.standard.string(forKey: "siri.pendingChannelId") != nil {
            return false
        }
        if UserDefaults.appGroup.string(forKey: "siri.pendingChannelId") != nil {
            return false
        }
        return true
    }()
    @State private var showTerms: Bool = false
    @State private var showSupport: Bool = false
    @State private var showAgeGate: Bool = false
    @ObservedObject private var ageAssurance = AgeAssuranceService.shared
    @ObservedObject private var kids = KidsModeController.shared
    @Environment(\.scenePhase) private var scenePhase

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if tosAccepted {
                    if kids.isEnabled {
                        KidsHomeView()
                            .environmentObject(playerVM)
                            .environmentObject(playlistVM)
                            .environmentObject(offlineService)
                    } else {
                        HomeView()
                            .environmentObject(playerVM)
                            .environmentObject(playlistVM)
                            .environmentObject(offlineService)
                    }
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }

                if showSplash {
                    SplashView(isPresented: $showSplash)
                        .zIndex(10)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .siriIntentDidPerform)) { _ in
                showSplash = false
            }
            .onChange(of: showSplash) { _, isShowing in
                if !isShowing && !tosAccepted {
                    if ageAssurance.needsCheck {
                        showAgeGate = true
                    } else {
                        showTerms = true
                    }
                }
            }
            .onChange(of: tosAccepted) { _, accepted in
                if accepted {
                    if ageAssurance.requiresKidsMode {
                        KidsModeController.shared.forceEnable()
                    }
                    Task { await playlistVM.loadPlaylists() }
                }
            }
            .task {
                await CustomChannelsStore.shared.importBundledCurationsIfNeeded(
                    db: ParsoMusicApp.sharedDB)
            }
            .fullScreenCover(isPresented: $showTerms) {
                TermsView(isPresented: $showTerms)
            }
            .fullScreenCover(isPresented: $showAgeGate) {
                AgeGateView(isPresented: $showAgeGate) {
                    showTerms = true
                }
            }
            .preferredColorScheme(preferredScheme)
            .overlay(alignment: .bottom) {
                if tosAccepted, !showSplash, contributions.showToast,
                   !KidsModeController.shared.isEnabled {
                    ContributionToast(
                        onSupport: { contributions.dismissToast(); showSupport = true },
                        onLater:   { contributions.dismissToast() },
                        onNever:   { contributions.optOutForever() }
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: contributions.showToast)
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    ContributionSupportView(store: ParsoMusicApp.sharedContributionStore,
                                            showsDoneButton: true)
                }
            }
            .task { contributions.beginSession() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleSiriPendingCommand()
                    if tosAccepted, !showSplash,
                       !KidsModeController.shared.isEnabled { contributions.evaluate() }
                }
            }
        }
    }

    private func handleSiriPendingCommand() {
        if let channelId = pendingSiriChannelId(from: .standard) {
            executeSiriCommandIfNeeded(channelId: channelId)
            UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
            UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
            return
        }

        if let channelId = pendingSiriChannelId(from: .appGroup) {
            executeSiriCommandIfNeeded(channelId: channelId)
            UserDefaults.appGroup.removeObject(forKey: "siri.pendingChannelId")
            UserDefaults.appGroup.removeObject(forKey: "siri.pendingTimestamp")
            return
        }
    }

    private func pendingSiriChannelId(from defaults: UserDefaults) -> String? {
        guard let channelId = defaults.string(forKey: "siri.pendingChannelId"),
              let ts = defaults.object(forKey: "siri.pendingTimestamp") as? TimeInterval,
              Date().timeIntervalSince1970 - ts < 60 else {
            defaults.removeObject(forKey: "siri.pendingChannelId")
            defaults.removeObject(forKey: "siri.pendingTimestamp")
            return nil
        }
        return channelId
    }

    private func executeSiriCommandIfNeeded(channelId: String) {
        guard !KidsModeController.shared.isEnabled else { return }
        if playerVM.isLoading || playerVM.currentChannel != nil { return }
        guard let ch = Channel.defaults.first(where: { $0.id == channelId }) else { return }
        Task { @MainActor in
            await playerVM.load(channel: ch, autoPlay: true)
        }
    }
}

// MARK: - Kids Mode Home

struct KidsHomeView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @ObservedObject private var kids = KidsModeController.shared
    @State private var showExitPin = false
    @State private var pinEntry = ""
    @State private var showWrongPin = false
    @State private var showPlayer = false

    @State private var pendingChannel: Channel = {
        KidsModeController.allowedChannels().first ?? Channel.defaults[0]
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(KidsModeController.allowedChannels(), id: \.id) { ch in
                        Button {
                            Task { await playerVM.load(channel: ch) }
                            showPlayer = true
                        } label: {
                            Label(ch.name, systemImage: ch.icon)
                                .font(.title3)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Listen")
                } footer: {
                    Text("Songs and stories chosen for kids.")
                }

                if !playlistVM.kidSafePlaylists.isEmpty {
                    Section {
                        ForEach(playlistVM.kidSafePlaylists, id: \.id) { pl in
                            NavigationLink(value: pl) {
                                Label(pl.name, systemImage: "music.note.list")
                                    .font(.title3)
                                    .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("My Playlists")
                    } footer: {
                        Text("Playlists a grown-up has marked safe for kids.")
                    }
                }
            }
            .navigationDestination(for: Playlist.self) { pl in
                PlaylistDetailView(playlist: pl, dismissAll: { showPlayer = true })
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
                    .environmentObject(offlineService)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lorewave Kids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pinEntry = ""
                        showExitPin = true
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Exit Kids Mode")
                }
            }
            .alert("Enter PIN to exit Kids Mode", isPresented: $showExitPin) {
                TextField("4-digit PIN", text: $pinEntry)
                    .keyboardType(.numberPad)
                Button("Exit") {
                    if kids.disable(pin: pinEntry) {
                        pinEntry = ""
                    } else {
                        pinEntry = ""
                        showWrongPin = true
                    }
                }
                Button("Cancel", role: .cancel) { pinEntry = "" }
            }
            .alert("Wrong PIN", isPresented: $showWrongPin) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Kids Mode stays on.")
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingScreen(dismiss: { showPlayer = false })
                .environmentObject(playerVM)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
        }
        .task {
            let lastId = UserDefaults.standard.string(forKey: "lastChannelId")
            let allowed = KidsModeController.allowedChannels()
            let ch = allowed.first { $0.id == lastId } ?? allowed.first ?? pendingChannel
            await playerVM.load(channel: ch, autoPlay: false)
        }
    }
}
