import Foundation
import SwiftUI

@MainActor
final class AppDependencies: ObservableObject {
    let db: DatabaseService
    let downloadManager: DownloadManager
    let archiveService: InternetArchiveService
    let fmaService: FMAService
    let queueManager: QueueManager
    let audioPlayer: AudioPlayerService
    let offlineService: OfflineDownloadService
    let artworkService: ArtworkService
    let kidsModeController: KidsModeController
    let liveCurationStore: LiveCurationStore
    let customChannelsStore: CustomChannelsStore
    let podcastStore: PodcastSubscriptionStore
    let contributionStore: ContributionStore
    let iaQueryRegistry: IAQueryRegistry
    let curationManifestStore: CurationManifestStore
    let networkMonitor: NetworkMonitor
    let ageAssuranceService: AgeAssuranceService

    init(
        db: DatabaseService,
        downloadManager: DownloadManager,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        artworkService: ArtworkService = .shared,
        kidsModeController: KidsModeController = .shared,
        liveCurationStore: LiveCurationStore = .shared,
        customChannelsStore: CustomChannelsStore = .shared,
        podcastStore: PodcastSubscriptionStore = .shared,
        contributionStore: ContributionStore,
        iaQueryRegistry: IAQueryRegistry = .shared,
        curationManifestStore: CurationManifestStore = .shared,
        networkMonitor: NetworkMonitor = .shared,
        ageAssuranceService: AgeAssuranceService = .shared
    ) {
        self.db = db
        self.downloadManager = downloadManager
        self.archiveService = archiveService
        self.fmaService = fmaService
        self.queueManager = queueManager
        self.audioPlayer = audioPlayer
        self.artworkService = artworkService
        self.kidsModeController = kidsModeController
        self.liveCurationStore = liveCurationStore
        self.customChannelsStore = customChannelsStore
        self.podcastStore = podcastStore
        self.contributionStore = contributionStore
        self.iaQueryRegistry = iaQueryRegistry
        self.curationManifestStore = curationManifestStore
        self.networkMonitor = networkMonitor
        self.ageAssuranceService = ageAssuranceService
        self.offlineService = OfflineDownloadService(db: db, downloadManager: downloadManager)
    }
}
