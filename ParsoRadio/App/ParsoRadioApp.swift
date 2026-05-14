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

    @StateObject private var playerVM: PlayerViewModel = {
        let db = ParsoMusicApp.sharedDB
        let archiveService = InternetArchiveService()
        let fmaService = FMAService()
        let queueManager = QueueManager(db: db)
        let audioPlayer = AudioPlayerService()
        let downloadManager = DownloadManager(db: db)
        return PlayerViewModel(
            db: db,
            archiveService: archiveService,
            fmaService: fmaService,
            queueManager: queueManager,
            audioPlayer: audioPlayer,
            downloadManager: downloadManager
        )
    }()

    @StateObject private var playlistVM: PlaylistViewModel = {
        PlaylistViewModel(db: ParsoMusicApp.sharedDB)
    }()

    @StateObject private var offlineService: OfflineDownloadService = {
        OfflineDownloadService(db: ParsoMusicApp.sharedDB)
    }()

    @AppStorage("tosAccepted") private var tosAccepted: Bool = false
    @State private var showSplash: Bool = true
    @State private var showTerms: Bool = false

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
        }
    }
}
