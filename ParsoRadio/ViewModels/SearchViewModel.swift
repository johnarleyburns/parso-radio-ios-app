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

    // Search scope filter (the segmented control under the search box).
    // `music` fetches all IA audio, displaying only single-track items.
    // `albums` excludes book/podcast/radio collections, displaying only
    //   multi-track items.
    // `audiobooks` restricts to book collections, displaying only book items.
    // `podcasts` searches via iTunes podcast API.
    enum SearchScope: String, CaseIterable, Identifiable {
        case music, albums, audiobooks, podcasts
        var id: String { rawValue }
        var label: String {
            switch self {
            case .music:      return "Music"
            case .albums:     return "Albums"
            case .audiobooks: return "Audiobooks"
            case .podcasts:   return "Podcasts"
            }
        }
        var filterKind: ItemKind? {
            switch self {
            case .music:      return .track
            case .albums:     return .album
            case .audiobooks: return .book
            case .podcasts:   return nil
            }
        }
    }

    @Published var query: String = ""
    @Published var scope: SearchScope = .music
    @Published var results: [ResultGroup] = []
    @Published var podcastResults: [PodcastSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String? = nil
    // Set when loading a NEXT page (page > 0) fails. Surfaced inline on the
    // "Load More" row so the already-showing results stay put — a failed
    // pagination never raises the full-screen "Search failed" banner.
    @Published var loadMoreFailed: Bool = false
    @Published var hasMorePages: Bool = false
    // True only once a search has actually completed for the current query.
    // Gates the "No results" message so it never flashes while typing or
    // during the debounce window before the first request goes out.
    @Published var hasSearched: Bool = false

    // Stable display list — set once per page load, never re-sorted
    // as incremental metadata loads. Uses insertion order from the API.
    @Published var displayedResults: [ResultGroup] = []

    // Per-item total duration + classification, fetched lazily from IA
    // metadata in ONE request (search docs carry neither runtime nor file count).
    @Published var durations: [String: Double] = [:]
    @Published var itemKinds: [String: ItemKind] = [:]
    private var infoTasks: Set<String> = []

    // Recent successful queries, most-recent first (persisted, de-duped, capped).
    @Published var recentSearches: [String] = []
    private let historyKey = "searchHistory"
    private let historyLimit = 12

    private let archiveService: SearchProvider
    private let podcastSearchService: PodcastSearchService
    private var searchTask: Task<Void, Never>? = nil
    private var currentPage = 0
    // Monotonic id stamped on each search. Any completion whose stamp is stale
    // (a newer search has since started) must not mutate published state, so a
    // slow request that lands after a newer one can never clobber fresh results
    // or flip on a "Search failed" banner over results that are already showing.
    private var searchGeneration = 0

    init(archiveService: SearchProvider = InternetArchiveService(),
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
            && query.count >= 2 && displayedResults.isEmpty && podcastResults.isEmpty
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

    static func classify(audioCount: Int, collection: String?) -> ItemKind {
        guard audioCount > 1 else { return .track }
        return isBookish(collection) ? .book : .album
    }

    /// True when an IA collection string belongs to a spoken-word / audiobook
    /// collection. Shared by `classify` and single-tap media-kind resolution so
    /// a single-file spoken item never renders the music surface.
    static func isBookish(_ collection: String?) -> Bool {
        let c = (collection ?? "").lowercased()
        return ["librivox", "audio_bookspoetry", "audiobook", "audio_books"]
            .contains { c.contains($0) }
    }

    /// Authoritative media kind for a one-tap search play, derived from the
    /// item's collection (single-file items lack a probed part count).
    static func mediaKind(forCollection collection: String?) -> MediaKind {
        isBookish(collection) ? .audiobook : .music
    }

    func searchChanged() {
        searchTask?.cancel()
        hasSearched = false
        errorMessage = nil
        loadMoreFailed = false
        podcastResults = []
        guard query.count >= 2 else { results = []; displayedResults = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400 ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(page: 0)
        }
    }

    func submitSearch() {
        searchTask?.cancel()
        hasSearched = false
        errorMessage = nil
        loadMoreFailed = false
        podcastResults = []
        guard query.count >= 2 else { results = []; displayedResults = []; return }
        searchTask = Task {
            await performSearch(page: 0)
        }
    }

    // The scope filter changed → re-run the current query from page 0.
    func scopeChanged() {
        searchTask?.cancel()
        hasSearched = false
        errorMessage = nil
        loadMoreFailed = false
        guard query.count >= 2 else { results = []; displayedResults = []; return }
        searchTask = Task {
            guard !Task.isCancelled else { return }
            await performSearch(page: 0)
        }
    }

    func loadNextPage() async {
        guard !isSearching, hasMorePages else { return }
        await performSearch(page: currentPage + 1)
    }

    // Internal (not private) so unit tests can drive the generation/cancellation
    // logic deterministically without the debounce/Task wrapper.
    func performSearch(page: Int) async {
        searchGeneration += 1
        let generation = searchGeneration

        isSearching = true
        if page == 0 {
            errorMessage = nil
            loadMoreFailed = false
            results = []
            displayedResults = []
            podcastResults = []
        } else {
            loadMoreFailed = false
        }

        do {
            if scope == .podcasts {
                let podcastHits = try await podcastSearchService.search(term: query)
                guard generation == searchGeneration else { return }
                podcastResults = podcastHits
            } else {
                let groups = try await archiveService.search(query: query, page: page, scope: scope)
                guard generation == searchGeneration else { return }
                if page == 0 { results = groups } else { results.append(contentsOf: groups) }
                displayedResults = results
                currentPage = page
                hasMorePages = groups.count == 20
            }
        } catch {
            // A newer search already superseded this one — let it own the state.
            guard generation == searchGeneration else { return }
            isSearching = false
            // Our own cancellation (a fresh keystroke or scope change cancelled the
            // in-flight request) is not a failure — never surface a connection error.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            if page == 0 {
                errorMessage = "Search failed \u{2014} check your connection"
            } else {
                loadMoreFailed = true
            }
            hasSearched = true
            return
        }

        guard generation == searchGeneration else { return }
        isSearching = false
        hasSearched = true
        if page == 0, errorMessage == nil { recordHistory(query) }
    }
}
