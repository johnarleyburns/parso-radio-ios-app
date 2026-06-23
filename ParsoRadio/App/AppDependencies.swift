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
    let podcastStore: PodcastSubscriptionStore
    let contributionStore: ContributionStore
    let iaQueryRegistry: IAQueryRegistry
    let iaCollectionStore: IACollectionStore
    let networkMonitor: NetworkMonitor
    let ageAssuranceService: AgeAssuranceService
    let favoritesStore: FavoritesStore
    let tasteProfileStore: TasteProfileStore

    @MainActor init(
        db: DatabaseService,
        downloadManager: DownloadManager,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        artworkService: ArtworkService,
        kidsModeController: KidsModeController,
        podcastStore: PodcastSubscriptionStore,
        contributionStore: ContributionStore,
        iaQueryRegistry: IAQueryRegistry,
        iaCollectionStore: IACollectionStore,
        networkMonitor: NetworkMonitor,
        ageAssuranceService: AgeAssuranceService,
        favoritesStore: FavoritesStore,
        tasteProfileStore: TasteProfileStore
    ) {
        self.db = db
        self.downloadManager = downloadManager
        self.archiveService = archiveService
        self.fmaService = fmaService
        self.queueManager = queueManager
        self.audioPlayer = audioPlayer
        self.artworkService = artworkService
        self.kidsModeController = kidsModeController
        self.podcastStore = podcastStore
        self.contributionStore = contributionStore
        self.iaQueryRegistry = iaQueryRegistry
        self.iaCollectionStore = iaCollectionStore
        self.networkMonitor = networkMonitor
        self.ageAssuranceService = ageAssuranceService
        self.favoritesStore = favoritesStore
        self.tasteProfileStore = tasteProfileStore
        self.offlineService = OfflineDownloadService(db: db, downloadManager: downloadManager)
    }
}
