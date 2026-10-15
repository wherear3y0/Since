import Foundation

/// Workdays and weekends between today and a date.
nonisolated struct TimeLeft: Equatable {
    var workdays: Int
    /// Saturday and Sunday (or the local weekend) together count as one.
    var weekends: Int
}

/// One day on a countdown's calendar page.
nonisolated struct MonthDay: Hashable {
    enum State {
        /// Before today.
        case gone
        /// Today up to the day before the countdown's day.
        case waiting
        /// The countdown's day.
        case target
        /// After it.
        case later
    }

    var date: Date
    var number: Int
    var state: State
    var isToday: Bool
}

/// Day math for countdowns.
nonisolated extension DayMath {
    /// Calendar days from `now` to `date`: 0 on the same day, negative when `date` is in the past.
    static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .app) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Workdays and weekends from today up to the day before `date`; today counts.
    static func timeLeft(until date: Date, from now: Date, calendar: Calendar = .app) -> TimeLeft {
        let count = daysUntil(date, from: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var result = TimeLeft(workdays: 0, weekends: 0)
        var previousWasWeekend = false
        for offset in 0..<max(0, count) {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let isWeekend = calendar.isDateInWeekend(day)
            if isWeekend {
                if !previousWasWeekend {
                    result.weekends += 1
                }
            } else {
                result.workdays += 1
            }
            previousWasWeekend = isWeekend
        }
        return result
    }

    /// A month as a calendar page: six rows of seven days from the week's first day, nil outside the month.
    /// Always six rows, so two months side by side line up.
    static func monthGrid(of month: Date, today now: Date, target: Date, calendar: Calendar = .app) -> [[MonthDay?]] {
        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: target)
        let first = calendar.dateInterval(of: .month, for: month)!.start
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

        return (0..<6).map { row in
            (0..<7).map { column in
                let number = row * 7 + column - lead + 1
                guard (1...count).contains(number) else { return nil }
                let date = calendar.date(byAdding: .day, value: number - 1, to: first)!
                let state: MonthDay.State = date == targetDay ? .target
                    : (date < today ? .gone : (date < targetDay ? .waiting : .later))
                return MonthDay(date: date, number: number, state: state, isToday: date == today)
            }
        }
    }

    /// Where the marks on a timeline go, in days from today: every day for the last two weeks,
    /// every week up to about four months, every month beyond that.
    static func timelineTicks(daysLeft: Int, from now: Date = .now, calendar: Calendar = .app) -> [Int] {
        if daysLeft <= 14 {
            return Array(1..<max(1, daysLeft))
        }
        if daysLeft <= 120 {
            return Array(stride(from: 7, to: daysLeft, by: 7))
        }
        let today = calendar.startOfDay(for: now)
        return (1...24).map { daysUntil(calendar.date(byAdding: .month, value: $0, to: today)!, from: today, calendar: calendar) }
            .filter { $0 < daysLeft }
    }

    /// "5 days", "6 weeks 1 day", "10 months 14 days": the time left in the unit that reads best.
    static func toGo(from now: Date, to target: Date, calendar: Calendar = .app) -> String {
        let days = daysUntil(target, from: now, calendar: calendar)
        let style: DurationStyle = days < 14 ? .days : (days < 70 ? .weeks : .months)
        return parts(from: now, to: target, style: style, calendar: calendar)
            .map { "\($0.value) \($0.longUnit)" }
            .joined(separator: " ")
    }
}

extension Date {
    /// "Nov 26 · Thu". The year only when it's needed: a day more than a year ahead,
    /// or one gone by in an earlier year.
    var untilFormat: String {
        let days = DayMath.daysUntil(self, from: .now)
        let date = (0..<365).contains(days) ? formatted(.dateTime.month(.abbreviated).day()) : sinceFormat
        return "\(date) · \(formatted(.dateTime.weekday(.abbreviated)))"
    }
}
