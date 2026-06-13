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
        // The Internet Archive collection this item lives in (e.g. "librivoxaudio").
        var collection: String? = nil
        var artworkURLString: String? = nil
    }

    // Single track, multi-track album, or multi-chapter audiobook — drives
    // the leading icon/label and the "Add Book/Album" action.
    enum ItemKind: String { case track, album, book }

    // Search scope filter (the segmented control under the search box). `all`
    // (= "All") is the default; `music` excludes book/podcast/radio
    // collections; `audiobooks` restricts to the book collections.
    // `podcasts` searches via iTunes podcast API.
    enum SearchScope: String, CaseIterable, Identifiable {
        case all, music, audiobooks, podcasts
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .music:      return "Music"
            case .audiobooks: return "Audiobooks"
            case .podcasts:   return "Podcasts"
            }
        }
    }

    @Published var query: String = ""
    @Published var scope: SearchScope = .all
    @Published var results: [ResultGroup] = []
    @Published var podcastResults: [PodcastSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasMorePages: Bool = false
    // True only once a search has actually completed for the current query.
    // Gates the "No results" message so it never flashes while typing or
    // during the debounce window before the first request goes out.
    @Published var hasSearched: Bool = false

    // Per-item total duration + classification, fetched lazily from IA
    // metadata in ONE request (search docs carry neither runtime nor file count).
    @Published var durations: [String: Double] = [:]
    @Published var itemKinds: [String: ItemKind] = [:]
    private var infoTasks: Set<String> = []

    // Recent successful queries, most-recent first (persisted, de-duped, capped).
    @Published var recentSearches: [String] = []
    private let historyKey = "searchHistory"
    private let historyLimit = 12

    private let archiveService: InternetArchiveService
    private let podcastSearchService: PodcastSearchService
    private var searchTask: Task<Void, Never>? = nil
    private var currentPage = 0

    init(archiveService: InternetArchiveService = InternetArchiveService(),
         podcastSearchService: PodcastSearchService = PodcastSearchService.shared) {
        self.archiveService = archiveService
        self.podcastSearchService = podcastSearchService
        recentSearches = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    // MARK: - Search history

    func recordHistory(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        var list = recentSearches.filter {
            $0.localizedCaseInsensitiveCompare(q) != .orderedSame
        }
        list.insert(q, at: 0)
        if list.count > historyLimit { list = Array(list.prefix(historyLimit)) }
        recentSearches = list
        UserDefaults.standard.set(list, forKey: historyKey)
    }

    func removeHistory(_ q: String) {
        recentSearches.removeAll { $0 == q }
        UserDefaults.standard.set(recentSearches, forKey: historyKey)
    }

    func clearHistory() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // True only when a real query produced zero results (not while typing,
    // during the debounce, or while searching) — drives the "No results"
    // message. hasSearched gates it so it appears strictly AFTER a search
    // returns nothing, never before the response arrives.
    var showNoResults: Bool {
        hasSearched && !isSearching && errorMessage == nil
            && query.count >= 2 && results.isEmpty && podcastResults.isEmpty
    }

    // Lazily fetch duration + kind for one result (one IA metadata request).
    func loadItemInfo(_ group: ResultGroup) {
        let id = group.id
        guard itemKinds[id] == nil, !infoTasks.contains(id) else { return }
        infoTasks.insert(id)
        Task { [weak self] in
            guard let self else { return }
            if let info = await self.archiveService.itemInfo(forIdentifier: id) {
                if info.duration > 0 { self.durations[id] = info.duration }
                self.itemKinds[id] = Self.classify(
                    audioCount: info.audioCount, collection: group.collection
                )
            }
            self.infoTasks.remove(id)
        }
    }

    // Books and albums are surfaced ABOVE individual tracks (collections are
    // generally higher-quality / more relevant). Stable: original relative
    // order is preserved within each kind, and not-yet-classified items keep
    // their place (rank as track) so the list doesn't churn while probing.
    var displayedResults: [ResultGroup] {
        func rank(_ g: ResultGroup) -> Int {
            switch itemKinds[g.id] {
            case .book:  return 0
            case .album: return 1
            default:     return 2
            }
        }
        return results.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }

    // Resolve kinds for the whole page up front so the ranking settles
    // quickly instead of reshuffling row-by-row as the user scrolls.
    private func prefetchKinds() {
        for group in results { loadItemInfo(group) }
    }

    static func classify(audioCount: Int, collection: String?) -> ItemKind {
        guard audioCount > 1 else { return .track }
        let c = (collection ?? "").lowercased()
        let bookish = ["librivox", "audio_bookspoetry", "audiobook",
                       "audio_books"].contains { c.contains($0) }
        return bookish ? .book : .album
    }

    func searchChanged() {
        searchTask?.cancel()
        hasSearched = false
        podcastResults = []
        guard query.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400 ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(page: 0)
        }
    }

    // The scope filter changed → re-run the current query from page 0.
    func scopeChanged() {
        searchTask?.cancel()
        hasSearched = false
        guard query.count >= 2 else { results = []; return }
        searchTask = Task {
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
        results = []
        podcastResults = []
        do {
            if scope == .podcasts {
                let podcastHits = try await podcastSearchService.search(term: query)
                podcastResults = podcastHits
            } else {
                let groups = try await archiveService.search(query: query, page: page, scope: scope)
                if page == 0 { results = groups } else { results.append(contentsOf: groups) }
                currentPage = page
                hasMorePages = groups.count == 20
                prefetchKinds()
            }
        } catch {
            errorMessage = "Search failed \u{2014} check your connection"
        }
        isSearching = false
        hasSearched = true
        if page == 0, errorMessage == nil { recordHistory(query) }
    }
}
