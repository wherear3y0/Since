import Foundation

/// What a reset means. For `quit` it's a slip, for `lastTime` it's the event itself
/// (e.g. "Called mom"), so the wording and the stats differ.
nonisolated enum CounterKind: String, CaseIterable, Identifiable {
    case quit, lastTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quit: "Quit"
        case .lastTime: "Last Time"
        }
    }

    var explanation: String {
        switch self {
        case .quit: "For habits you’re quitting. A reset is a slip, and the days without one count as clean."
        case .lastTime: "For things you do now and then, like calling mom. Logging it starts the count again."
        }
    }

    /// "streak" or "gap", lowercase.
    var period: String { self == .quit ? "streak" : "gap" }
    var periods: String { self == .quit ? "Streaks" : "Gaps" }
    var longest: String { self == .quit ? "Best streak" : "Longest gap" }

    var resetsTitle: String { self == .quit ? "Resets" : "Logged" }
    var totalResets: String { self == .quit ? "Total resets" : "Times logged" }
    var lastReset: String { self == .quit ? "Last reset" : "Last logged" }

    var resetAction: String { self == .quit ? "Reset Counter" : "Log Today" }
    var holdHint: String { self == .quit ? "Press and hold to reset." : "Press and hold to log today." }
    var doneToday: String { self == .quit ? "Already reset today." : "Already logged today." }
    var toast: String { self == .quit ? "Counter reset" : "Logged today" }

    var addTitle: String { self == .quit ? "Add Reset" : "Log a Past Day" }
    var editTitle: String { self == .quit ? "Edit Reset" : "Edit Entry" }
}

extension CounterKind {
    /// Average length in days. For "last time" counters only finished gaps count:
    /// the running one isn't a full gap yet and would pull the average down.
    func average(of streaks: [Streak]) -> Double {
        let counted = self == .lastTime ? streaks.filter { !$0.isCurrent } : streaks
        guard !counted.isEmpty else { return 0 }
        return Double(counted.map(\.days).reduce(0, +)) / Double(counted.count)
    }
}
