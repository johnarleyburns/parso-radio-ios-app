import SwiftUI

struct ArtworkThumbnail: View {
    let track: Track
    var channel: Channel?
    var size: CGFloat = 48
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .task(id: track.id) {
            image = await ArtworkService.shared.bestArtwork(for: track, channel: channel)
        }
    }
}
