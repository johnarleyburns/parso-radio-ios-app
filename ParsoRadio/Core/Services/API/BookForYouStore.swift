import Foundation
import SwiftUI

@MainActor
final class BookForYouStore: ObservableObject {
    static let shared = BookForYouStore()

    @Published var entry: BookForYouEntry?
    @Published var isLoading = false

    private var lastLoadedDay: String?
    private let db: DatabaseService
    private let tasteStore: TasteProfileStore?

    private init() {
        self.db = DatabaseService.shared
        self.tasteStore = TasteProfileStore(db: db)
    }

    func loadIfNeeded() async {
        let today = todayKey()
        guard today != lastLoadedDay else { return }
        isLoading = true
        defer { isLoading = false }

        // Check DB cache for today
        if let cached = await db.fetchBookCuratedForDay(today) {
            entry = cached
            lastLoadedDay = today
            return
        }

        let service = BookForYouService(db: db, tasteStore: tasteStore)
        entry = await service.generatePick(for: today)
        lastLoadedDay = today
    }

    func refresh() async {
        let today = todayKey()
        isLoading = true
        defer { isLoading = false }

        await db.deleteBookCuratedForDay(today)
        lastLoadedDay = nil

        let service = BookForYouService(db: db, tasteStore: tasteStore)
        entry = await service.generatePick(for: today)
        lastLoadedDay = today
    }

    private func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
