import Foundation
import SwiftUI

@MainActor
final class LiveMusicOnThisDayStore: ObservableObject {
    static let shared = LiveMusicOnThisDayStore()
    @Published var entry: LiveMusicEntry?
    @Published var isLoading = false
    private var lastFetchDate: String?

    private init() {}

    func loadIfNeeded() async {
        let today = LiveMusicOnThisDayService.todayMMDD()
        guard today != lastFetchDate else { return }
        isLoading = true
        defer { isLoading = false }
        let service = LiveMusicOnThisDayService()
        entry = await service.fetchDailyEntry()
        lastFetchDate = today
    }

    func refresh() async {
        let service = LiveMusicOnThisDayService()
        service.clearCachedEntry()
        isLoading = true
        defer { isLoading = false }
        entry = await service.fetchDailyEntry()
        lastFetchDate = LiveMusicOnThisDayService.todayMMDD()
    }
}
