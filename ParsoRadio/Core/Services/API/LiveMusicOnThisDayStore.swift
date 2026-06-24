import Foundation
import SwiftUI

@MainActor
final class LiveMusicOnThisDayStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(LiveMusicEntry)
        case empty(message: String)
        case failed(message: String, retryable: Bool)
    }

    static let shared = LiveMusicOnThisDayStore()
    @Published var state: State = .idle
    private var lastFetchDate: String?

    var entry: LiveMusicEntry? {
        if case .loaded(let entry) = state { return entry }
        return nil
    }

    private init() {}

    func loadIfNeeded() async {
        let today = LiveMusicOnThisDayService.todayMMDD()
        guard today != lastFetchDate else { return }
        state = .loading
        let service = LiveMusicOnThisDayService()
        lastFetchDate = today
        if let entry = await service.fetchDailyEntry() {
            state = .loaded(entry)
        } else {
            state = .empty(message: "No live recordings found for today.")
        }
    }

    func refreshFromPool() async {
        state = .loading
        let service = LiveMusicOnThisDayService()
        lastFetchDate = LiveMusicOnThisDayService.todayMMDD()
        if let entry = await service.fetchDailyEntry(forceFresh: true) {
            state = .loaded(entry)
        } else {
            state = .empty(message: "No live recordings found for today.")
        }
    }

    func refresh() async {
        let service = LiveMusicOnThisDayService()
        service.clearCachedEntry()
        state = .loading
        lastFetchDate = LiveMusicOnThisDayService.todayMMDD()
        if let entry = await service.fetchDailyEntry() {
            state = .loaded(entry)
        } else {
            state = .empty(message: "No live recordings found for today.")
        }
    }
}
