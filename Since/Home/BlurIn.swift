import SwiftUI

extension View {
    /// Materializes out of a blur: fades in, sharpens and settles up a few points when `isShown` turns true.
    /// Used for content arriving on screen, with small `delay` steps so blocks come in one after another.
    func blurIn(_ isShown: Bool, delay: Double = 0) -> some View {
        self
            .blur(radius: isShown ? 0 : 10)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 14)
            .animation(.smooth(duration: 0.6).delay(delay), value: isShown)
    }
}

extension View {
    /// For a Form section: its rows blur in, and their cell background fades in with them.
    func sectionReveal(_ isShown: Bool, delay: Double, background: Color = .cardBackground) -> some View {
        self
            .blurIn(isShown, delay: delay)
            .listRowBackground(
                background
                    .opacity(isShown ? 1 : 0)
                    .animation(.smooth(duration: 0.6).delay(delay), value: isShown)
            )
    }
}

extension AnyTransition {
    /// Floating elements (the undo toast) rise out of a blur and sink back into one.
    static var blurRise: AnyTransition {
        AnyTransition(BlurReplaceTransition(configuration: .downUp)).combined(with: .move(edge: .bottom))
    }
}
