import SwiftUI

/// AsyncImage that falls back to a named asset if the remote image
/// is too small (< 2KB), indicating an IA "notfound.png" placeholder.
struct VerifiedThumb: View {
    let url: URL
    let fallbackName: () -> String

    @State private var useFallback = false

    var body: some View {
        Group {
            if useFallback {
                Image(fallbackName())
                    .resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .task {
                                checkSize()
                            }
                    case .failure, .empty:
                        Image(fallbackName())
                            .resizable().scaledToFill()
                            .onAppear { useFallback = true }
                    @unknown default:
                        Image(fallbackName())
                            .resizable().scaledToFill()
                    }
                }
            }
        }
    }

    private func checkSize() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  data.count < 2048
            else { return }
            useFallback = true
        }
    }
}
