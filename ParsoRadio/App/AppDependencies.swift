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
    let favoritesStore: FavoritesStore

    @MainActor init(
        db: DatabaseService,
        downloadManager: DownloadManager,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        artworkService: ArtworkService,
        kidsModeController: KidsModeController,
        liveCurationStore: LiveCurationStore,
        customChannelsStore: CustomChannelsStore,
        podcastStore: PodcastSubscriptionStore,
        contributionStore: ContributionStore,
        iaQueryRegistry: IAQueryRegistry,
        curationManifestStore: CurationManifestStore,
        networkMonitor: NetworkMonitor,
        ageAssuranceService: AgeAssuranceService,
        favoritesStore: FavoritesStore
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
        self.favoritesStore = favoritesStore
        self.offlineService = OfflineDownloadService(db: db, downloadManager: downloadManager)
    }
}
