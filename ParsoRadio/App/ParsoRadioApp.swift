import SwiftUI

@main
struct ParsoRadioApp: App {
    @StateObject private var playerVM: PlayerViewModel = {
        let db: DatabaseService
        do {
            db = try DatabaseService()
        } catch {
            db = try! DatabaseService(path: ":memory:")
        }
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
            .fullScreenCover(isPresented: $showTerms) {
                TermsView(isPresented: $showTerms)
            }
        }
    }
}
