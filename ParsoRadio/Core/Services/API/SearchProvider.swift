import Foundation

/// The narrow Internet Archive surface the search screen depends on. Abstracting
/// it behind a protocol lets unit tests drive `SearchViewModel.performSearch`
/// deterministically — including cancellation and stale-completion races — without
/// a live network or `MockURLProtocol` timing.
protocol SearchProvider {
    func search(query: String, page: Int,
                scope: SearchViewModel.SearchScope) async throws -> [SearchViewModel.ResultGroup]
    func itemInfo(forIdentifier identifier: String) async -> (duration: Double, audioCount: Int)?
}

extension InternetArchiveService: SearchProvider {}
