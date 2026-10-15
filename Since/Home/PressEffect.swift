import SwiftUI
import UIKit

extension View {
    /// Liquid Glass–style response for custom surfaces: while a finger is down, light pools under it
    /// and the surface swells slightly and leans toward it, then springs back on release.
    /// It only watches touches, so scrolling, taps, drags and context menus keep working.
    func pressEffect(in shape: some Shape, glow: Color = .white) -> some View {
        modifier(PressEffect(shape: shape, glow: glow))
    }
}

private struct PressEffect<S: Shape>: ViewModifier {
    let shape: S
    let glow: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var touch: CGPoint?
    /// Where the finger last was, so the light fades out in place instead of jumping.
    @State private var lastTouch: CGPoint = .zero
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let isPressed = touch != nil
        let point = touch ?? lastTouch
        // Lean a few points toward the finger, like glass being pulled.
        let lean = CGSize(width: (point.x - size.width / 2) * 0.02, height: (point.y - size.height / 2) * 0.02)

        content
            .overlay {
                RadialGradient(colors: [glow.opacity(colorScheme == .dark ? 0.22 : 0.35), glow.opacity(0.06), .clear],
                               center: UnitPoint(x: size.width > 0 ? point.x / size.width : 0.5,
                                                 y: size.height > 0 ? point.y / size.height : 0.5),
                               startRadius: 0, endRadius: 130)
                    .blendMode(colorScheme == .dark ? .plusLighter : .normal)
                    .opacity(isPressed ? 1 : 0)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .scaleEffect(isPressed ? 1.02 : 1)
            .offset(isPressed ? lean : .zero)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isPressed)
            .gesture(TouchTracking { location in
                if let location {
                    // The light follows the finger directly; only press and release animate.
                    var transaction = Transaction()
                    transaction.disablesAnimations = touch != nil
                    withTransaction(transaction) {
                        touch = location
                        lastTouch = location
                    }
                } else {
                    touch = nil
                }
            })
    }
}

/// Reports where a finger is on the view (nil once it lifts or the touch is taken over by scrolling).
/// Recognizes alongside every other gesture and never cancels their touches.
private struct TouchTracking: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> TouchTrackingRecognizer {
        let recognizer = TouchTrackingRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: TouchTrackingRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        default:
            onChange(nil)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

final class TouchTrackingRecognizer: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    // Never stand in the way of scrolling or any other recognizer.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

#Preview {
    RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(Color.mint.opacity(0.2))
        .frame(width: 200, height: 200)
        .pressEffect(in: RoundedRectangle(cornerRadius: 26, style: .continuous), glow: .mint)
}
