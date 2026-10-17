import Foundation

/// What a "quit" counter is about, so its savings ask the right questions: a pack price and how many
/// are in the pack for smoking, a price per cup for coffee. Other is the free-form fallback.
nonisolated enum Habit: String, CaseIterable, Identifiable {
    case smoking, vaping, alcohol, coffee, sugar
    /// Stored as "", which is also what every counter made before habits existed has.
    case other = ""

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smoking: "Smoking"
        case .vaping: "Vaping"
        case .alcohol: "Alcohol"
        case .coffee: "Coffee"
        case .sugar: "Sugar"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .smoking: "lungs.fill"
        case .vaping: "smoke.fill"
        case .alcohol: "wineglass.fill"
        case .coffee: "cup.and.saucer.fill"
        case .sugar: "cube.fill"
        case .other: "star.fill"
        }
    }

    /// The thing counted, one and many; nil for Other, which uses the name typed in.
    var unit: (one: String, many: String)? {
        switch self {
        case .smoking: ("cigarette", "cigarettes")
        case .vaping: ("pod", "pods")
        case .alcohol: ("drink", "drinks")
        case .coffee: ("cup", "cups")
        case .sugar: ("sweet", "sweets")
        case .other: nil
        }
    }

    /// What the units are bought in, when it's more than one at a time.
    var pack: (name: String, size: Int)? {
        self == .smoking ? ("pack", 20) : nil
    }

    /// Minutes one unit takes, as a starting point.
    var defaultMinutes: Double {
        self == .smoking ? 5 : 0
    }

    /// The WHO's steps of recovery are about smoking.
    var hasHealthSteps: Bool {
        self == .smoking
    }

    /// A counter made before habits existed that's clearly about smoking: the health steps on,
    /// or "cigarette" in its unit, title or icon.
    static func guess(unitName: String, title: String, symbol: String, showsHealth: Bool) -> Habit {
        let text = "\(unitName) \(title)".lowercased()
        let smokingWords = ["cigarette", "smok", "сигарет", "курен", "курить", "кур"]
        if showsHealth || smokingWords.contains(where: text.contains) || symbol == "lungs.fill" || symbol == "smoke.fill" {
            return .smoking
        }
        return .other
    }
}
