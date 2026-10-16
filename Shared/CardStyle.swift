import SwiftUI

extension Color {
    /// Page background: pure black in dark mode (sheets would otherwise be gray), grouped gray in light mode.
    static let pageBackground = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .systemGroupedBackground })

    /// Fill for plain cards and form rows on top of `pageBackground`.
    static let cardBackground = Color(UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : .secondarySystemGroupedBackground
    })
}

extension Color {
    /// The counter's color as drawn inside its card: a little muted on a plain (untinted) card.
    func onCard(tinted: Bool) -> Color {
        tinted ? self : mix(with: Color(white: 0.5), by: 0.35)
    }

    /// A clean day before a slip on a heatmap: the counter's color faded toward gray.
    var slippedDay: Color {
        mix(with: Color(white: 0.5), by: 0.7).opacity(0.5)
    }
}

/// Plain card fill with a soft, blurred patch of the counter's color glowing from the center.
struct SoftColorFill: View {
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.cardBackground
            Ellipse()
                .fill(tint.opacity(colorScheme == .dark ? 0.12 : 0.08))
                .scaleEffect(x: 0.7, y: 0.55)
                .blur(radius: 30)
        }
    }
}

/// Background shared by counter cards: a fill in the counter's color with a thin light edge and a soft glow,
/// or a plain card with a soft color patch in the middle when the counter's tinted background is off.
struct CounterCardBackground: ViewModifier {
    let tint: Color
    let tinted: Bool
    var glowOpacity: Double = 0.15
    var glowRadius: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .background {
                if tinted {
                    // The glow is cast by an opaque base layer, so it only shows outside the card,
                    // not through the translucent tint.
                    shape
                        .fill(Color.pageBackground)
                        .shadow(color: tint.opacity(colorScheme == .dark ? glowOpacity : glowOpacity / 2), radius: glowRadius)
                    shape.fill(tint.opacity(0.16))
                } else {
                    SoftColorFill(tint: tint)
                        .clipShape(shape)
                }
            }
            .cardEdge(tint: tint)
    }
}

extension View {
    /// The thin, slightly whitened edge every card has, brighter at the top.
    func cardEdge(tint: Color) -> some View {
        overlay {
            let edge = tint.mix(with: .white, by: 0.45)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [edge.opacity(0.25), edge.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 0.75)
        }
    }
}

extension View {
    func counterCardBackground(tint: Color, tinted: Bool, glowOpacity: Double = 0.15, glowRadius: CGFloat = 10) -> some View {
        modifier(CounterCardBackground(tint: tint, tinted: tinted, glowOpacity: glowOpacity, glowRadius: glowRadius))
    }
}

/// "18w 1d" or "4m 5d": the numbers big, the units small, on one line that shrinks to fit.
/// Cards and widgets use it for counters and countdowns written in weeks or months.
struct DurationPartsText: View {
    let parts: [DurationPart]
    var size: CGFloat = 40
    /// Shown after the parts, like "ago".
    var suffix: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(parts, id: \.unit) { part in
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(part.value, format: .number)
                        .font(.system(size: size, weight: .bold))
                        .widgetAccentable()
                    Text(part.unit)
                        .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let suffix {
                Text(suffix)
                    .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
