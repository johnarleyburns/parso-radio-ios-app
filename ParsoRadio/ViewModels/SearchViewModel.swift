import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    enum SearchSource: String, CaseIterable, Identifiable {
        case internetArchive = "Internet Archive"
        case librivox        = "Librivox"
        var id: String { rawValue }
    }

    struct ResultGroup: Identifiable {
        let id: String
        let title: String
        let creator: String
        let addedDate: Date?
        var trackCount: Int
        var tracks: [Track] = []
        var isExpanded: Bool = false
        let source: SearchSource
        var artworkURLString: String? = nil
    }

    @Published var query: String = ""
    @Published var source: SearchSource = .internetArchive
    @Published var results: [ResultGroup] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasMorePages: Bool = false

    private let archiveService: InternetArchiveService
    private var searchTask: Task<Void, Never>? = nil
    private var currentPage = 0

    init(archiveService: InternetArchiveService = InternetArchiveService()) {
        self.archiveService = archiveService
    }

    func searchChanged() {
        searchTask?.cancel()
        guard query.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400 ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(page: 0)
        }
    }

    func loadNextPage() async {
        guard !isSearching, hasMorePages else { return }
        await performSearch(page: currentPage + 1)
    }

    func expandGroup(at index: Int) async {
        guard index < results.count else { return }
        if !results[index].tracks.isEmpty {
            results[index].isExpanded.toggle()
            return
        }
        let group = results[index]
        let tracks = (try? await archiveService.fetchTracksForIdentifier(group.id)) ?? []
        results[index].tracks = tracks
        results[index].trackCount = tracks.count
        results[index].isExpanded = true
    }

    // MARK: - Private

    private func performSearch(page: Int) async {
        isSearching = true
        errorMessage = nil
        do {
            let groups: [ResultGroup]
            switch source {
            case .internetArchive:
                groups = try await archiveService.search(query: query, page: page)
            case .librivox:
                groups = try await archiveService.searchLibrivox(query: query, page: page)
            }
            if page == 0 { results = groups } else { results.append(contentsOf: groups) }
            currentPage = page
            hasMorePages = groups.count == 20
        } catch {
            errorMessage = "Search failed — check your connection"
        }
        isSearching = false
    }
}
