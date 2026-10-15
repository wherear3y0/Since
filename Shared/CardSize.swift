import Foundation

/// How much room a counter's card takes on the home screen, like home screen widgets:
/// M is half the width, L the full width at the same height, XL the full width and twice as tall.
nonisolated enum CardSize: String, CaseIterable, Identifiable {
    case m, l, xl

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}
