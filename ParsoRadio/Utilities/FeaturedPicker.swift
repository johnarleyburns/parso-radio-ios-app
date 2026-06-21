import Foundation

/// Deterministic, offline-safe selection for the Home hero + Featured shelf.
/// Picks are seeded by calendar day and drawn from bundled `Channel.defaults`,
/// so they are stable for a whole day, rotate daily, and never require network.
enum FeaturedPicker {
    static func dayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// One channel per media kind (order follows LibrarySection.ordered), rotated daily.
    static func featured(on date: Date,
                         from channels: [Channel] = Channel.defaults,
                         calendar: Calendar = .current) -> [Channel] {
        let idx = dayIndex(for: date, calendar: calendar)
        return LibrarySection.ordered.compactMap { section in
            let pool = channels
                .filter { $0.mediaKind == section.id && $0.category != "For You" }
                .sorted { $0.id < $1.id }
            guard !pool.isEmpty else { return nil }
            return pool[idx % pool.count]
        }
    }

    /// Single channel for the hero "Play something now" button, rotated daily.
    /// Picks from all non-"For You" channels across every media kind to guarantee
    /// a result even when the user hasn't added any IA collections yet.
    static func hero(on date: Date,
                     from channels: [Channel] = Channel.defaults,
                     calendar: Calendar = .current) -> Channel? {
        let idx = dayIndex(for: date, calendar: calendar)
        let pool = channels
            .filter { $0.category != "For You" }
            .sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return nil }
        return pool[idx % pool.count]
    }
}
