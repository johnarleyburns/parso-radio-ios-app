import SwiftUI

struct NowPlayingView: View {
    let title: String
    let artist: String
    let license: LicenseType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if license == .ccBy {
                Text("CC BY")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
