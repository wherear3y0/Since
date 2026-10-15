import SwiftUI

/// A destructive list row that fills up while held and fires after 0.8 s,
/// so a stray tap can't reset a counter. Grayed out when disabled.
/// Haptics ramp up while it fills; the success tap comes from the screen once the reset is saved.
struct HoldToResetButton: View {
    var title = "Reset Counter"
    var color: Color = .red
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    /// Set when the hold completes. `progress` can't tell us: it jumps to 1 as soon as the fill animation starts.
    @State private var didFire = false
    /// 1, 2, 3 as the fill passes each quarter; drives the ramping haptic ticks.
    @State private var tick = 0
    @State private var tickTask: Task<Void, Never>?

    private let duration = 0.8

    var body: some View {
        Text(title)
            .foregroundStyle(isEnabled ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(color.opacity(0.18))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 30) {
                didFire = true
                action()
                withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            } onPressingChanged: { pressing in
                isPressing = pressing
                tickTask?.cancel()
                tick = 0
                if pressing {
                    didFire = false
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                    tickTask = Task {
                        for step in 1...3 {
                            try? await Task.sleep(for: .seconds(duration / 4))
                            guard !Task.isCancelled else { return }
                            tick = step
                        }
                    }
                } else if !didFire {
                    // Released early: drain the fill back out.
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .allowsHitTesting(isEnabled)
            .sensoryFeedback(.impact(weight: .light), trigger: isPressing) { _, pressing in pressing }
            .sensoryFeedback(trigger: tick) { _, step in
                step > 0 ? .impact(weight: .light, intensity: 0.4 + Double(step) * 0.2) : nil
            }
            .accessibilityLabel(title)
            .accessibilityHint("Starts the count again from today")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(title), action)
    }
}

#Preview {
    List {
        HoldToResetButton {}
            .listRowInsets(EdgeInsets())
        HoldToResetButton {}
            .listRowInsets(EdgeInsets())
            .disabled(true)
    }
}
