import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.82
    @State private var iconScale: CGFloat = 0.7

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                         Color(red: 0.10, green: 0.22, blue: 0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)

                VStack(spacing: 6) {
                    Text("Parso Music")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Free Music. Everywhere.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .scaleEffect(scale)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                opacity = 1
                scale = 1
                iconScale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    SplashView(isPresented: .constant(true))
}
