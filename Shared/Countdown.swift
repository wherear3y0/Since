import Foundation
import SwiftData

/// A day to count down to: a trip, a birthday, a deadline.
@Model
final class Countdown {
    var id: UUID = UUID()
    var title: String = ""
    var symbol: String = "star.fill"
    var colorName: String = CounterColor.blue.rawValue
    /// The day itself or, for a repeating day, the first time it comes round. A birthday can be the day of birth.
    var date: Date = Date.now
    // The repeat rule, stored field by field.
    var repeatRaw: String = RepeatFrequency.never.rawValue
    var repeatInterval: Int = 1
    var repeatWeekdays: [Int] = []
    var repeatEnd: Date?
    var note: String?
    var sortOrder: Int = 0
    /// When the wait began. Progress toward a one-off date is counted from here.
    var createdAt: Date = Date.now
    /// Notifications a week before, the day before and on the day.
    var notifyBefore: Bool = false
    var tinted: Bool = true
    var sizeRaw: String = CardSize.m.rawValue
    var styleRaw: String = CountdownStyle.calendar.rawValue
    /// A one-off date that has passed and was kept in Past instead of becoming a counter.
    var isArchived: Bool = false
    /// Off when the first day isn't the real first time, like a birthday without a year,
    /// so a yearly day doesn't count years from it.
    var countsYears: Bool = true
    /// Kept at the top of the Until tab.
    var isPinned: Bool = false
    /// Listed with the birthdays instead of the other events.
    var isBirthday: Bool = false
    /// A Live Activity on the Lock Screen from the evening before through the day.
    var showsLiveActivity: Bool = false

    init(title: String, symbol: String, color: CounterColor, date: Date, rule: RepeatRule = .never,
         note: String? = nil, sortOrder: Int = 0) {
        self.title = title
        self.symbol = symbol
        self.colorName = color.rawValue
        self.date = date
        self.note = note
        self.sortOrder = sortOrder
        self.rule = rule
    }

    var rule: RepeatRule {
        get {
            RepeatRule(frequency: RepeatFrequency(rawValue: repeatRaw) ?? .never, interval: max(1, repeatInterval),
                       weekdays: Set(repeatWeekdays), end: repeatEnd)
        }
        set {
            repeatRaw = newValue.frequency.rawValue
            repeatInterval = newValue.interval
            repeatWeekdays = newValue.weekdays.sorted()
            repeatEnd = newValue.end
        }
    }

    var size: CardSize {
        get { CardSize(rawValue: sizeRaw) ?? .m }
        set { sizeRaw = newValue.rawValue }
    }

    var style: CountdownStyle {
        get { CountdownStyle(rawValue: styleRaw) ?? .calendar }
        set { styleRaw = newValue.rawValue }
    }

    var color: CounterColor {
        get { CounterColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    /// The day being counted down to: the date itself, or a repeating day's next time round
    /// (its last one once the repeat has ended).
    func target(now: Date = .now, calendar: Calendar = .app) -> Date {
        let rule = rule
        return rule.occurrence(rule.targetIndex(from: date, now: now, calendar: calendar), from: date, calendar: calendar)
    }

    /// The time round before the one being counted down to. Before the first one of a repeating day
    /// (like a holiday picked from Calendar at its next date) that's where it would have come round before.
    func previousTime(now: Date = .now, calendar: Calendar = .app) -> Date? {
        let rule = rule
        let index = rule.targetIndex(from: date, now: now, calendar: calendar)
        if index > 0 {
            return rule.occurrence(index - 1, from: date, calendar: calendar)
        }
        return rule.timeBefore(date, calendar: calendar).flatMap { $0 <= calendar.startOfDay(for: now) ? $0 : nil }
    }

    /// Days to go: 0 on the day, negative once a one-off (or ended) date has passed.
    func daysLeft(now: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.daysUntil(target(now: now, calendar: calendar), from: now, calendar: calendar)
    }

    func hasPassed(now: Date = .now, calendar: Calendar = .app) -> Bool {
        daysLeft(now: now, calendar: calendar) < 0
    }

    /// Where the wait starts: the last time a repeating day came round, or when the countdown was added.
    func waitStart(now: Date = .now, calendar: Calendar = .app) -> Date {
        if let previous = previousTime(now: now, calendar: calendar) {
            return previous
        }
        return min(calendar.startOfDay(for: createdAt), target(now: now, calendar: calendar))
    }

    /// Days of the wait already behind.
    func waited(now: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.days(from: waitStart(now: now, calendar: calendar), to: now, calendar: calendar)
    }

    /// How much of the wait is behind, from 0 to 1.
    func progress(now: Date = .now, calendar: Calendar = .app) -> Double {
        let start = waitStart(now: now, calendar: calendar)
        let total = DayMath.days(from: start, to: target(now: now, calendar: calendar), calendar: calendar)
        guard total > 0 else { return 1 }
        return min(1, Double(DayMath.days(from: start, to: now, calendar: calendar)) / Double(total))
    }

    /// For a yearly day, how many years the next one marks: a birthday's age, an anniversary's year.
    func turns(now: Date = .now, calendar: Calendar = .app) -> Int? {
        guard rule.frequency == .yearly, countsYears else { return nil }
        let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: date),
                                            to: target(now: now, calendar: calendar)).year ?? 0
        return years > 0 ? years : nil
    }
}
