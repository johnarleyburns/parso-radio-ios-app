import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    // One flat result per Internet Archive item. Tapping it plays immediately
    // (no source picker, no expand/“N tracks”).
    struct ResultGroup: Identifiable {
        let id: String
        let title: String
        let creator: String
        let addedDate: Date?
        let duration: Double          // seconds; 0 if IA exposes no runtime
        var artworkURLString: String? = nil
    }

    @Published var query: String = ""
    @Published var results: [ResultGroup] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasMorePages: Bool = false

    // Per-item total duration, fetched lazily from IA metadata (search docs
    // carry no runtime). Distinguishes a song from a multi-hour audiobook.
    @Published var durations: [String: Double] = [:]
    private var durationTasks: Set<String> = []

    private let archiveService: InternetArchiveService
    private var searchTask: Task<Void, Never>? = nil
    private var currentPage = 0

    init(archiveService: InternetArchiveService = InternetArchiveService()) {
        self.archiveService = archiveService
    }

    // True only when a real query produced zero results (not while typing
    // or searching) — drives the "No results" message.
    var showNoResults: Bool {
        !isSearching && errorMessage == nil && query.count >= 2 && results.isEmpty
    }

    func loadDuration(_ id: String) {
        guard durations[id] == nil, !durationTasks.contains(id) else { return }
        durationTasks.insert(id)
        Task { [weak self] in
            guard let self else { return }
            if let d = await self.archiveService.itemDuration(forIdentifier: id), d > 0 {
                self.durations[id] = d
            }
            self.durationTasks.remove(id)
        }
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

    private func performSearch(page: Int) async {
        isSearching = true
        errorMessage = nil
        do {
            let groups = try await archiveService.search(query: query, page: page)
            if page == 0 { results = groups } else { results.append(contentsOf: groups) }
            currentPage = page
            hasMorePages = groups.count == 20
        } catch {
            errorMessage = "Search failed — check your connection"
        }
        isSearching = false
    }
}
