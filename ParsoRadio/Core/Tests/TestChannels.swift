import Foundation
@testable import ParsoMusic

// Stand-ins for the FMA tag channels removed from Channel.defaults in the
// public-library/public-radio wedge pivot. Many playback/DB unit tests just
// needed "a simple tag-matching music channel" and used fma-jazz/fma-classical
// for that. These replicate the old entries exactly (same id, tags,
// preferredSource — no registry stamp, tag-based matching), so the tests keep
// exercising the same code paths without depending on shipped channels.
extension Channel {
    static var fmaJazzTestChannel: Channel {
        Channel(id: "fma-jazz", name: "Jazz", category: "Curated",
                icon: "music.mic", tags: ["jazz"], preferredSource: "fma")
    }
    static var fmaClassicalTestChannel: Channel {
        Channel(id: "fma-classical", name: "Classical", category: "Curated",
                icon: "music.quarternote.3", tags: ["classical"], preferredSource: "fma")
    }
}
