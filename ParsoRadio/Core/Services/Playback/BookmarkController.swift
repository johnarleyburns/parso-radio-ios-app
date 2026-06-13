import Foundation

@MainActor
final class BookmarkController {
    private let db: DatabaseService
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, playerVM: PlayerViewModel) {
        self.db = db
        self.playerVM = playerVM
    }

    func addBookmarkAtCurrentPosition(label: String? = nil) async {
        guard let vm = playerVM, let track = vm.currentTrack else { return }
        let bm = Bookmark.new(trackId: track.id,
                              positionSeconds: vm.currentPosition,
                              label: label)
        await db.saveBookmark(bm)
        vm.bookmarksForCurrentTrack = await db.fetchBookmarks(forTrack: track.id)
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        await db.deleteBookmark(id: bookmark.id)
        if let vm = playerVM, let id = vm.currentTrack?.id, id == bookmark.trackId {
            vm.bookmarksForCurrentTrack = await db.fetchBookmarks(forTrack: id)
        }
    }

    func seekToBookmark(_ bookmark: Bookmark) {
        guard let vm = playerVM, vm.currentTrack?.id == bookmark.trackId else { return }
        vm.seek(to: bookmark.positionSeconds)
    }

    func fetchCurrentItemChapters() async -> [Track]? {
        guard let vm = playerVM, let track = vm.currentTrack else { return nil }
        let identifier = track.parentIdentifier ?? track.id
        return await vm.resolveItemParts(identifier: identifier)
    }
}
