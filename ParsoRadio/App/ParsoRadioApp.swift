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

    // Shared so the CarPlay scene (CarPlaySceneDelegate) drives the SAME player
    // as the on-phone UI — one audio session, one now-playing state. @MainActor
    // because PlayerViewModel is main-actor isolated.
    @MainActor static let sharedPlayerVM: PlayerViewModel = {
        let db = ParsoMusicApp.sharedDB
        return PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: AudioPlayerService(),
            downloadManager: ParsoMusicApp.sharedDownloadManager
        )
    }()

    @StateObject private var playerVM = ParsoMusicApp.sharedPlayerVM

    @StateObject private var playlistVM: PlaylistViewModel = {
        PlaylistViewModel(db: ParsoMusicApp.sharedDB)
    }()

    @StateObject private var offlineService: OfflineDownloadService = {
        OfflineDownloadService(db: ParsoMusicApp.sharedDB, downloadManager: ParsoMusicApp.sharedDownloadManager)
    }()

    @AppStorage("tosAccepted") private var tosAccepted: Bool = false
    // Appearance override from Settings: "system" | "light" | "dark".
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showSplash: Bool = true
    @State private var showTerms: Bool = false

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
            .onChange(of: showSplash) { _, isShowing in
                if !isShowing && !tosAccepted {
                    showTerms = true
                }
            }
            .onChange(of: tosAccepted) { _, accepted in
                if accepted {
                    Task { await playlistVM.loadPlaylists() }
                }
            }
            .fullScreenCover(isPresented: $showTerms) {
                TermsView(isPresented: $showTerms)
            }
            .preferredColorScheme(preferredScheme)
        }
    }
}
