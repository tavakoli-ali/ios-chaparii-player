import SwiftUI

/// Animated launch splash: the app-icon turtle springs in, the "Chaparii"
/// wordmark rises beneath it, and a soft glow pulses. RootView fades this out
/// once its hold elapses.
struct SplashView: View {
    @State private var logoScale: CGFloat = 0.55
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -8
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 16
    @State private var glow = false

    var body: some View {
        ZStack {
            // Cinematic dark backdrop; the logo's own black field blends in.
            RadialGradient(
                colors: [Color(white: 0.14), .black],
                center: .center, startRadius: 10, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("ChapariiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                    .shadow(color: .white.opacity(glow ? 0.28 : 0.06),
                            radius: glow ? 30 : 10)
                    .scaleEffect(logoScale)
                    .rotationEffect(.degrees(logoRotation))
                    .opacity(logoOpacity)

                Text("Chaparii")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(1)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.58)) {
                logoScale = 1
                logoOpacity = 1
                logoRotation = 0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
                textOpacity = 1
                textOffset = 0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.5)) {
                glow = true
            }
        }
    }
}
