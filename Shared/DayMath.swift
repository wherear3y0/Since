import Foundation

/// One stretch of days between two resets (or between the start and the first reset).
nonisolated struct Streak: Identifiable, Hashable {
    var start: Date
    var end: Date
    var days: Int
    var isCurrent: Bool

    var id: Date { start }
}

/// How a day on the heatmap looks. A full reset clears the heatmap: everything up to and including it
/// is drawn faint. A slip starts the count again but keeps the days before it, dimmed.
/// "Last time" counters draw the days something was done instead (see `logged`).
nonisolated enum DayState {
    /// Before the counter started, or up to and including the last full reset: drawn faint.
    case before
    /// A day of the current streak: drawn bright.
    case clean
    /// A clean day before a slip (after the last full reset): kept, but drawn dim and gray.
    case slipped
    /// The day of a slip.
    case slip
    /// For "last time" counters: a day it was done (the start or a logged day), drawn bright.
    case logged
    case future
}

nonisolated struct HeatmapDay: Identifiable, Hashable {
    var date: Date
    var state: DayState
    var isToday: Bool

    var id: Date { date }
}

nonisolated enum DurationStyle: Int, CaseIterable {
    case days, weeks, months

    var next: DurationStyle {
        DurationStyle(rawValue: (rawValue + 1) % DurationStyle.allCases.count)!
    }
}

/// A number with its unit, e.g. (18, "w"). Views draw the number big and the unit small.
nonisolated struct DurationPart: Hashable {
    var value: Int
    var unit: String

    /// "w" → "weeks", "d" → "day" and so on, for when there's room to spell it out.
    var longUnit: String {
        let one = value == 1
        switch unit {
        case "y": return one ? "year" : "years"
        case "m": return one ? "month" : "months"
        case "w": return one ? "week" : "weeks"
        case "d": return one ? "day" : "days"
        default: return unit
        }
    }
}

nonisolated enum DayMath {
    /// Calendar days between two moments in the local time zone. Same day → 0.
    static func days(from start: Date, to end: Date, calendar: Calendar = .app) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Splits the history into streaks. The last one is the current streak and runs until `now`.
    static func streaks(start: Date, resets: [Date], now: Date, calendar: Calendar = .app) -> [Streak] {
        let boundaries = [start] + resets.filter { $0 >= start }.sorted()
        var result: [Streak] = []
        for (index, from) in boundaries.enumerated() {
            let isCurrent = index == boundaries.count - 1
            let to = isCurrent ? now : boundaries[index + 1]
            result.append(Streak(start: from, end: to, days: days(from: from, to: to, calendar: calendar), isCurrent: isCurrent))
        }
        return result
    }

    /// Runs of days without a reset (first and last day inclusive, both at start of day).
    /// The start day counts as clean, a reset day doesn't.
    static func cleanRuns(start: Date, resets: [Date], now: Date, calendar: Calendar = .app) -> [ClosedRange<Date>] {
        let today = calendar.startOfDay(for: now)
        var runStart = calendar.startOfDay(for: start)
        let resetDays = Set(resets.filter { $0 >= start }.map { calendar.startOfDay(for: $0) }).sorted()

        var runs: [ClosedRange<Date>] = []
        for reset in resetDays {
            let lastClean = calendar.date(byAdding: .day, value: -1, to: reset)!
            if lastClean >= runStart {
                runs.append(runStart...lastClean)
            }
            runStart = calendar.date(byAdding: .day, value: 1, to: reset)!
        }
        if runStart <= today {
            runs.append(runStart...today)
        }
        return runs
    }

    /// The last `weeks` weeks, oldest first, split into columns of 7 days (one column per week).
    /// `resets` are all resets, slips included; `slips` are the ones among them that were slips.
    /// With `logsEvents` ("last time" counters) the start and every reset are drawn as days it was done.
    static func heatmap(start: Date, resets: [Date], slips: [Date] = [], logsEvents: Bool = false, now: Date,
                        weeks: Int = 7, calendar: Calendar = .app) -> [[HeatmapDay]] {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let day = dayMaker(start: start, resets: resets, slips: slips, logsEvents: logsEvents, today: today,
                           calendar: calendar)

        return (0..<weeks).map { week in
            (0..<7).map { weekday in
                day(calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstWeek)!)
            }
        }
    }

    /// The last `count` days ending today, oldest first.
    static func recentDays(_ count: Int, start: Date, resets: [Date], slips: [Date] = [], logsEvents: Bool = false,
                           now: Date, calendar: Calendar = .app) -> [HeatmapDay] {
        let today = calendar.startOfDay(for: now)
        let day = dayMaker(start: start, resets: resets, slips: slips, logsEvents: logsEvents, today: today,
                           calendar: calendar)
        return (0..<count).reversed().map { offset in
            day(calendar.date(byAdding: .day, value: -offset, to: today)!)
        }
    }

    private static func dayMaker(start: Date, resets: [Date], slips: [Date], logsEvents: Bool, today: Date,
                                 calendar: Calendar) -> (Date) -> HeatmapDay {
        let startDay = calendar.startOfDay(for: start)
        let counted = resets.filter { calendar.startOfDay(for: $0) >= startDay && calendar.startOfDay(for: $0) <= today }

        if logsEvents {
            let logged = Set(counted.map { calendar.startOfDay(for: $0) } + [startDay])
            return { date in
                let state: DayState = date > today ? .future : (logged.contains(date) ? .logged : .before)
                return HeatmapDay(date: date, state: state, isToday: date == today)
            }
        }

        // Slips are matched by their exact moment, so a slip and a full reset on the same day stay apart.
        let slipMoments = Set(slips)
        let lastFullReset = counted.filter { !slipMoments.contains($0) }.map { calendar.startOfDay(for: $0) }.max()
        let slipDays = Set(counted.filter { slipMoments.contains($0) }.map { calendar.startOfDay(for: $0) })
        let lastReset = counted.map { calendar.startOfDay(for: $0) }.max()
        return { date in
            let state: DayState
            if date > today {
                state = .future
            } else if date < startDay {
                state = .before
            } else if let lastFullReset, date <= lastFullReset {
                // The reset day itself is day 0 of the new streak, not a clean day.
                state = .before
            } else if slipDays.contains(date) {
                state = .slip
            } else if let lastReset, date < lastReset {
                // Only slips can be left after the last full reset: the days before them stay, dimmed.
                state = .slipped
            } else {
                state = .clean
            }
            return HeatmapDay(date: date, state: state, isToday: date == today)
        }
    }

    /// 127 → [127 days] / [18w, 1d] / [4m, 5d]. Zero parts are dropped, but at least one part is kept.
    static func parts(from start: Date, to end: Date, style: DurationStyle, calendar: Calendar = .app) -> [DurationPart] {
        let total = days(from: start, to: end, calendar: calendar)
        switch style {
        case .days:
            return [DurationPart(value: total, unit: total == 1 ? "day" : "days")]
        case .weeks:
            return nonEmpty([DurationPart(value: total / 7, unit: "w"), DurationPart(value: total % 7, unit: "d")])
        case .months:
            let c = calendar.dateComponents([.year, .month, .day],
                                            from: calendar.startOfDay(for: start),
                                            to: calendar.startOfDay(for: end))
            return nonEmpty([DurationPart(value: max(0, c.year ?? 0), unit: "y"),
                             DurationPart(value: max(0, c.month ?? 0), unit: "m"),
                             DurationPart(value: max(0, c.day ?? 0), unit: "d")])
        }
    }

    private static func nonEmpty(_ parts: [DurationPart]) -> [DurationPart] {
        let kept = parts.filter { $0.value > 0 }
        return kept.isEmpty ? [parts.last!] : kept
    }
}

nonisolated extension Date {
    /// "Jun 8", or "Jun 8, 2025" when it's not this year.
    var sinceFormat: String {
        if Calendar.app.isDate(self, equalTo: .now, toGranularity: .year) {
            formatted(.dateTime.month(.abbreviated).day())
        } else {
            formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
