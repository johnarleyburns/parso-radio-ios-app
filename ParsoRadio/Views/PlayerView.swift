import SwiftUI

struct PlayerView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Button(action: {}) {
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PlayerView()
}
