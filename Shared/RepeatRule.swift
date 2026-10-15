import Foundation

/// How often a countdown's day comes round.
nonisolated enum RepeatFrequency: String, CaseIterable, Identifiable, Codable {
    case never, daily, weekly, monthly, yearly

    var id: String { rawValue }

    /// "Daily", for the custom frequency picker.
    var title: String {
        switch self {
        case .never: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    /// "day" or "days", "week" or "weeks"…
    func unit(_ count: Int) -> String {
        let one = count == 1
        switch self {
        case .never: return ""
        case .daily: return one ? "day" : "days"
        case .weekly: return one ? "week" : "weeks"
        case .monthly: return one ? "month" : "months"
        case .yearly: return one ? "year" : "years"
        }
    }
}

/// A repeating day, set up like a repeating event in Calendar: every N days, weeks (on chosen weekdays),
/// months or years from the first day, optionally until an end date.
nonisolated struct RepeatRule: Hashable, Codable {
    var frequency: RepeatFrequency = .never
    /// Every how many days, weeks, months or years.
    var interval = 1
    /// For weekly rules, the weekdays it falls on (1 = Sunday … 7 = Saturday). Empty: the first day's weekday.
    var weekdays: Set<Int> = []
    /// The last day it can come round on; nil repeats forever.
    var end: Date?

    static let never = RepeatRule()

    var repeats: Bool { frequency != .never }

    /// The choices listed before Custom, as in Calendar.
    static let presets: [(title: String, rule: RepeatRule)] = [
        ("Never", .never),
        ("Every Day", RepeatRule(frequency: .daily)),
        ("Every Week", RepeatRule(frequency: .weekly)),
        ("Every 2 Weeks", RepeatRule(frequency: .weekly, interval: 2)),
        ("Every Month", RepeatRule(frequency: .monthly)),
        ("Every Year", RepeatRule(frequency: .yearly)),
    ]

    /// The rule without its end date, for comparing with the presets.
    var withoutEnd: RepeatRule {
        var rule = self
        rule.end = nil
        return rule
    }

    var isPreset: Bool {
        Self.presets.contains { $0.rule == withoutEnd }
    }

    /// "Every Week", "Every 3 months", "Every 2 weeks on Mon, Wed".
    func summary(calendar: Calendar = .app) -> String {
        if let preset = Self.presets.first(where: { $0.rule == withoutEnd }) {
            return preset.title
        }
        let every = interval == 1 ? "Every \(frequency.unit(1))" : "Every \(interval) \(frequency.unit(interval))"
        guard frequency == .weekly, !weekdays.isEmpty else { return every }
        let names = orderedWeekdays(calendar: calendar).map { calendar.shortWeekdaySymbols[$0 - 1] }
        return "\(every) on \(names.joined(separator: ", "))"
    }

    /// The chosen weekdays in the order of the user's week.
    func orderedWeekdays(calendar: Calendar) -> [Int] {
        weekdays.sorted { (($0 - calendar.firstWeekday) + 7) % 7 < (($1 - calendar.firstWeekday) + 7) % 7 }
    }

    /// The `n`th time the rule comes round from `start` (0 is the first), at the start of that day.
    /// Months and years are added to the first day each time, so the 31st falls on the last day
    /// of shorter months and February 29 on the 28th, without drifting afterward.
    func occurrence(_ n: Int, from start: Date, calendar: Calendar = .app) -> Date {
        let first = calendar.startOfDay(for: start)
        switch frequency {
        case .never:
            return first
        case .daily:
            return calendar.date(byAdding: .day, value: n * interval, to: first)!
        case .weekly where weekdays.isEmpty:
            return calendar.date(byAdding: .day, value: n * interval * 7, to: first)!
        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start ?? first
            let offsets = weekdays.map { (($0 - calendar.firstWeekday) + 7) % 7 }.sorted()
            let firstOffset = DayMath.days(from: weekStart, to: first, calendar: calendar)
            // The first week only counts its chosen days from the first day on.
            let firstWeek = offsets.filter { $0 >= firstOffset }
            if n < firstWeek.count {
                return calendar.date(byAdding: .day, value: firstWeek[n], to: weekStart)!
            }
            let rest = n - firstWeek.count
            let week = (rest / offsets.count + 1) * interval
            return calendar.date(byAdding: .day, value: week * 7 + offsets[rest % offsets.count], to: weekStart)!
        case .monthly:
            return calendar.date(byAdding: .month, value: n * interval, to: first)!
        case .yearly:
            return calendar.date(byAdding: .year, value: n * interval, to: first)!
        }
    }

    /// The time it would have come round just before `start`: one interval earlier.
    /// For a weekly rule on chosen weekdays it's the same weekday a week (or interval) before.
    func timeBefore(_ start: Date, calendar: Calendar = .app) -> Date? {
        let first = calendar.startOfDay(for: start)
        switch frequency {
        case .never: return nil
        case .daily: return calendar.date(byAdding: .day, value: -interval, to: first)
        case .weekly: return calendar.date(byAdding: .day, value: -7 * interval, to: first)
        case .monthly: return calendar.date(byAdding: .month, value: -interval, to: first)
        case .yearly: return calendar.date(byAdding: .year, value: -interval, to: first)
        }
    }

    /// Which time round a countdown counts toward at `now`: the next one, today included,
    /// or the last one once the rule has ended. A day that doesn't repeat is its own only time round.
    func targetIndex(from start: Date, now: Date, calendar: Calendar = .app) -> Int {
        guard repeats else { return 0 }
        let today = calendar.startOfDay(for: now)
        var index = Self.firstIndex { occurrence($0, from: start, calendar: calendar) >= today }
        if let end {
            let endDay = calendar.startOfDay(for: end)
            let pastEnd = Self.firstIndex { occurrence($0, from: start, calendar: calendar) > endDay }
            index = min(index, max(0, pastEnd - 1))
        }
        return index
    }

    /// The smallest `n` for which `condition` holds, when it's false up to some point and true from then on.
    /// Doubles up to it, then halves back, so even a daily rule from decades ago takes a few dozen steps.
    private static func firstIndex(where condition: (Int) -> Bool) -> Int {
        if condition(0) { return 0 }
        var high = 1
        while !condition(high) {
            high *= 2
        }
        var low = high / 2
        while high - low > 1 {
            let middle = (low + high) / 2
            if condition(middle) {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }
}
