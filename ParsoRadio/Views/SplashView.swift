import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.82
    @State private var iconScale: CGFloat = 0.7

    var body: some View {
        ZStack {
            BrandGradient.linear
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)

                VStack(spacing: 6) {
                    Text("Lorewave")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Free audio, forever.")
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
