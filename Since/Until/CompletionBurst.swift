import SwiftUI

extension View {
    /// The moment a countdown comes: a soft flash of its color from the middle, its icon bursting out in a ring
    /// and fading into a blur, and the card taking one breath. Plays when `isActive` turns true (a timer ending,
    /// Done), and at `moment` if the view is still on screen then. With Reduce Motion, only the flash.
    func completionBurst(isActive: Bool, at moment: Date? = nil, symbol: String, tint: Color) -> some View {
        modifier(CompletionBurst(isActive: isActive, moment: moment, symbol: symbol, tint: tint))
    }
}

private struct CompletionBurst: ViewModifier {
    let isActive: Bool
    let moment: Date?
    let symbol: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 when it starts, 1 when it's spent.
    @State private var phase: CGFloat = 0
    @State private var isPlaying = false
    @State private var isBreathing = false
    @State private var plays = 0

    private static let count = 14

    func body(content: Content) -> some View {
        content
            .scaleEffect(isBreathing ? 1.03 : 1)
            .overlay {
                if isPlaying {
                    GeometryReader { proxy in
                        burst(in: proxy.size)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: isActive) { _, isOn in
                if isOn {
                    play()
                }
            }
            .task(id: moment) {
                guard let moment, moment > .now else { return }
                guard (try? await Task.sleep(for: .seconds(moment.timeIntervalSinceNow))) != nil else { return }
                play()
            }
            .sensoryFeedback(.success, trigger: plays)
    }

    private func burst(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Out to about the card's edges, where it's cut off.
        let reach = min(size.width, size.height) * 0.48
        let bright = tint.mix(with: .white, by: 0.35)

        return ZStack {
            // The flash: light pooling out from the middle and fading.
            Circle()
                .fill(RadialGradient(colors: [bright, tint.opacity(0.5), .clear], center: .center,
                                     startRadius: 0, endRadius: reach))
                .frame(width: reach * 2, height: reach * 2)
                .scaleEffect(0.3 + phase * 1.6)
                .opacity(1 - phase)
                .blendMode(.plusLighter)
                .position(center)

            if !reduceMotion {
                ForEach(0..<Self.count, id: \.self) { index in
                    let angle = Double(index) / Double(Self.count) * 2 * .pi + (index.isMultiple(of: 2) ? 0.12 : -0.08)
                    // Every third one flies a little farther and is a little bigger, so the ring isn't too even.
                    let distance = reach * (index % 3 == 0 ? 1.0 : 0.78)
                    Image(systemName: symbol)
                        .font(.system(size: index % 3 == 0 ? 30 : 22, weight: .bold))
                        .foregroundStyle(bright)
                        .shadow(color: tint, radius: 6)
                        .scaleEffect(0.4 + phase * 0.9)
                        .rotationEffect(.degrees((index.isMultiple(of: 2) ? 1 : -1) * 70 * phase))
                        .opacity(1 - phase)
                        .blur(radius: phase * 5)
                        .position(x: center.x + cos(angle) * distance * phase,
                                  y: center.y + sin(angle) * distance * phase)
                }
            }
        }
    }

    private func play() {
        guard !isPlaying else { return }
        phase = 0
        isPlaying = true
        plays += 1
        withAnimation(.timingCurve(0.15, 0.85, 0.3, 1, duration: 0.95)) {
            phase = 1
        }
        withAnimation(.spring(duration: 0.25, bounce: 0.5)) {
            isBreathing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
                isBreathing = false
            }
            try? await Task.sleep(for: .milliseconds(800))
            isPlaying = false
        }
    }
}
