import SwiftUI

/// The same half-circle in cards, editors, details and widgets. It needs no timer or network activity.
struct CountdownArc: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 112

    private var level: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }

    var body: some View {
        GeometryReader { proxy in
            let radius = max(0, min((proxy.size.width - 16) / 2, proxy.size.height - 12))
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 8)
            ZStack(alignment: .bottom) {
                ArcStroke(progress: 1).stroke(tint.opacity(0.18), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ArcStroke(progress: level)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .widgetAccentable()
                Circle().fill(tint)
                    .frame(width: 10, height: 10)
                    .shadow(color: tint.opacity(0.7), radius: 5)
                    .position(x: center.x - radius * CGFloat(cos(level * .pi)),
                              y: center.y - radius * CGFloat(sin(level * .pi)))
                VStack(spacing: 0) {
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: height < 60 ? 16 : height < 100 ? 24 : 36,
                                      weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if height >= 100 {
                        Text("of the wait").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wait complete")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}

nonisolated private struct ArcStroke: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let level = progress.isFinite ? min(1, max(0, progress)) : 0
        let radius = max(0, min((rect.width - 16) / 2, rect.height - 12))
        let center = CGPoint(x: rect.midX, y: rect.maxY - 8)
        let count = max(1, Int(ceil(level * 80)))
        let points = (0...count).map { step in
            let angle = Double(step) / Double(count) * level * .pi
            return CGPoint(x: center.x - radius * CGFloat(cos(angle)), y: center.y - radius * CGFloat(sin(angle)))
        }
        var path = Path()
        path.addLines(points)
        return path
    }
}
