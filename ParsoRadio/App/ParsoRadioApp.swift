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
                iPodView()
                    .environmentObject(playerVM)
                    .opacity(showSplash || showTerms ? 0 : 1)

                if showSplash {
                    SplashView(isPresented: $showSplash)
                        .zIndex(10)
                }
            }
            // onChange must live on the persistent ZStack, not inside `if showSplash`,
            // because SwiftUI may not fire it before SplashView is removed from the tree.
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
