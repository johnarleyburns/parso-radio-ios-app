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
    // All ViewModels share one DatabaseService instance so they operate on the same connection.
    private static let sharedDB = makeSharedDB()
    private static let sharedDownloadManager = DownloadManager(db: sharedDB)
    // Shared so Settings, the toast's Support sheet, and the About badge all see
    // the same StoreKit state. @MainActor: ContributionStore is main-actor.
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
    // Appearance override from Settings: "system" | "light" | "dark".
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
    @Environment(\.scenePhase) private var scenePhase

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // follow the system
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // iPodView is only inserted into the tree after TOS is accepted.
                // Keeping it under opacity:0 still fires .task and starts audio; this does not.
                if tosAccepted {
                    iPodView()
                        .environmentObject(playerVM)
                        .environmentObject(playlistVM)
                        .environmentObject(offlineService)
                        .opacity(showSplash ? 0 : 1)
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
                // One-time import: seed the curation DB from bundled per-channel
                // JSON files for channels the user hasn't claimed yet. Once a
                // channel has any verdicts, the user owns it — JSON is never
                // consulted again for that channel. Also recovers lost verdicts
                // if the DB was wiped but the JSON file still has approved tracks.
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
            // Contribution ask: a dismissible bottom card, only once the app is
            // actually in use (TOS accepted, splash gone). The coordinator's
            // engine gates it to genuine engagement (≥12 tracks, ≥2 sessions…).
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
        // Check in-process pending first (set by intent running in the app).
        if let channelId = pendingSiriChannelId(from: .standard) {
            executeSiriCommandIfNeeded(channelId: channelId)
            UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
            UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
            return
        }

        // Check App Group pending (set by extension process via Tier 3).
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
        // If the intent already kicked off a load in-process, skip the duplicate.
        if playerVM.isLoading || playerVM.currentChannel != nil { return }
        guard let ch = Channel.defaults.first(where: { $0.id == channelId }) else { return }
        Task { @MainActor in
            await playerVM.load(channel: ch, autoPlay: true)
        }
    }
}
