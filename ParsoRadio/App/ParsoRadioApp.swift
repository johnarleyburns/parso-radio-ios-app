import SwiftUI

@main
struct ParsoRadioApp: App {
    @StateObject private var playerVM: PlayerViewModel = {
        let db = try! DatabaseService()
        let archiveService = InternetArchiveService()
        let queueManager = QueueManager(db: db)
        let audioPlayer = AudioPlayerService()
        let downloadManager = DownloadManager(db: db)
        return PlayerViewModel(
            db: db,
            archiveService: archiveService,
            queueManager: queueManager,
            audioPlayer: audioPlayer,
            downloadManager: downloadManager
        )
    }()

    var body: some Scene {
        WindowGroup {
            ChannelListView()
                .environmentObject(playerVM)
        }
    }
}
