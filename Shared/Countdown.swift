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
    /// A Live Activity on the Lock Screen and in the Dynamic Island on the day itself. Off by default:
    /// meant only for the days that really matter.
    var showsLiveActivity: Bool = false
    /// The Calendar event a countdown was picked from, to show it and notice when it's moved or deleted there.
    /// Nil for countdowns made by hand, and for ones imported before this was kept.
    var calendarItemID: String? = nil
    /// The same event's identifier on the calendar server, which survives a full resync that `calendarItemID`
    /// doesn't.
    var calendarExternalID: String? = nil
    /// The contact a birthday was picked from, to find the person's day in Calendar's Birthdays calendar.
    var contactID: String? = nil
    /// The day it was marked done. On that day a repeating countdown already counts to its next time.
    var doneDay: Date? = nil
    /// How the days are written: 42 days, 6w or 1m 12d (a `DurationStyle`).
    var durationStyleRaw: Int = DurationStyle.days.rawValue
    /// The day has a time too: the hour and minute of `date`, on each time round.
    var hasTime: Bool = false
    /// The last day of a window it should come in, like a delivery "Oct 4–15". Only for a day that doesn't repeat.
    var windowEnd: Date? = nil
    /// The days it was set for before it was postponed, earliest first.
    var postponedFrom: [Date] = []
    /// A quick timer: `date` is the moment it ends, and it goes away once it has.
    var isTimer: Bool = false
    /// How many days before the day its Live Activity starts showing: 0 on the day itself.
    var liveActivityLead: Int = 0
    /// Its Live Activity shows now, whatever the day, until it's turned off or the day has passed.
    var liveActivityForced: Bool = false

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

    var numberStyle: DurationStyle {
        get { DurationStyle(rawValue: durationStyleRaw) ?? .days }
        set { durationStyleRaw = newValue.rawValue }
    }

    /// The time to go (or, once passed, since) in the countdown's number style; nil when it's written in days.
    func durationParts(now: Date = .now, calendar: Calendar = .app) -> [DurationPart]? {
        guard numberStyle != .days else { return nil }
        let target = target(now: now, calendar: calendar)
        return target >= calendar.startOfDay(for: now)
            ? DayMath.parts(from: now, to: target, style: numberStyle, calendar: calendar)
            : DayMath.parts(from: target, to: now, style: numberStyle, calendar: calendar)
    }

    var color: CounterColor {
        get { CounterColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    /// The day being counted down to: the date itself, or a repeating day's next time round
    /// (its last one once the repeat has ended). Ahead of a window it's the window's middle, inside it the last day.
    func target(now: Date = .now, calendar: Calendar = .app) -> Date {
        if let window = window(calendar: calendar), let middle = windowMiddle(calendar: calendar) {
            return calendar.startOfDay(for: now) < window.lowerBound ? middle : window.upperBound
        }
        return rule.occurrence(currentIndex(now: now, calendar: calendar), from: date, calendar: calendar)
    }

    /// The moment it comes: its day at its time, or when a timer ends. Nil without a time.
    func moment(now: Date = .now, calendar: Calendar = .app) -> Date? {
        if isTimer {
            return date
        }
        guard hasTime, window(calendar: calendar) == nil else { return nil }
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0,
                             of: target(now: now, calendar: calendar))
    }

    // MARK: - Window

    /// The first and last day of the window it should come in, when it has one.
    func window(calendar: Calendar = .app) -> ClosedRange<Date>? {
        guard let windowEnd, !rule.repeats else { return nil }
        let start = calendar.startOfDay(for: date)
        return start...max(start, calendar.startOfDay(for: windowEnd))
    }

    /// Halfway through the window: the day it's most likely to come.
    func windowMiddle(calendar: Calendar = .app) -> Date? {
        guard let window = window(calendar: calendar) else { return nil }
        let days = DayMath.days(from: window.lowerBound, to: window.upperBound, calendar: calendar)
        return calendar.date(byAdding: .day, value: days / 2, to: window.lowerBound)
    }

    func isInWindow(now: Date = .now, calendar: Calendar = .app) -> Bool {
        window(calendar: calendar)?.contains(calendar.startOfDay(for: now)) ?? false
    }

    /// Ahead of its window the days are only roughly right: "~14 days", counted to the window's middle.
    func isApproximate(now: Date = .now, calendar: Calendar = .app) -> Bool {
        window(calendar: calendar).map { calendar.startOfDay(for: now) < $0.lowerBound } ?? false
    }

    /// The day itself, or any day of its window: when it can be marked done.
    func isTheDay(now: Date = .now, calendar: Calendar = .app) -> Bool {
        window(calendar: calendar) == nil ? daysLeft(now: now, calendar: calendar) == 0
                                          : isInWindow(now: now, calendar: calendar)
    }

    /// Moves it to a later day or window, keeping the day it was set for in its history.
    func postpone(to newDate: Date, windowEnd newWindowEnd: Date?, now: Date = .now, calendar: Calendar = .app) {
        postponedFrom.append(date)
        date = newDate
        windowEnd = newWindowEnd
        doneDay = nil
        if !hasPassed(now: now, calendar: calendar) {
            isArchived = false
        }
    }

    /// Which time round it counts toward: the rule's, or the one after when today's was marked done.
    func currentIndex(now: Date = .now, calendar: Calendar = .app) -> Int {
        let rule = rule
        let index = rule.targetIndex(from: date, now: now, calendar: calendar)
        guard rule.repeats, isDone(now: now, calendar: calendar),
              calendar.isDate(rule.occurrence(index, from: date, calendar: calendar), inSameDayAs: now) else { return index }
        let next = rule.occurrence(index + 1, from: date, calendar: calendar)
        if let end = rule.end, next > calendar.startOfDay(for: end) {
            return index
        }
        return index + 1
    }

    /// Marked done today.
    func isDone(now: Date = .now, calendar: Calendar = .app) -> Bool {
        doneDay.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }

    /// On the day: a repeating countdown moves on to its next time, a one-off one goes to Past.
    func markDone(now: Date = .now, calendar: Calendar = .app) {
        doneDay = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        if !rule.repeats {
            isArchived = true
        }
    }

    func undoDone(now: Date = .now, calendar: Calendar = .app) {
        doneDay = nil
        if !rule.repeats && !hasPassed(now: now, calendar: calendar) {
            isArchived = false
        }
    }

    /// The time round before the one being counted down to. Before the first one of a repeating day
    /// (like a holiday picked from Calendar at its next date) that's where it would have come round before.
    func previousTime(now: Date = .now, calendar: Calendar = .app) -> Date? {
        let rule = rule
        let index = currentIndex(now: now, calendar: calendar)
        if index > 0 {
            return rule.occurrence(index - 1, from: date, calendar: calendar)
        }
        let first = rule.occurrence(0, from: date, calendar: calendar)
        return rule.timeBefore(first, calendar: calendar).flatMap { $0 <= calendar.startOfDay(for: now) ? $0 : nil }
    }

    /// Days to go: 0 on the day, negative once a one-off (or ended) date has passed.
    func daysLeft(now: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.daysUntil(target(now: now, calendar: calendar), from: now, calendar: calendar)
    }

    func hasPassed(now: Date = .now, calendar: Calendar = .app) -> Bool {
        daysLeft(now: now, calendar: calendar) < 0
    }

    /// A yearly countdown with the cake icon: how a birthday is recognized where it wasn't marked as one
    /// (made before the Birthdays section, restored from an older backup, or added by Siri).
    var looksLikeBirthday: Bool {
        symbol == "birthday.cake.fill" && rule.frequency == .yearly
    }

    /// Its Live Activity is turned on and due: on the day (or in the window), up to `liveActivityLead` days
    /// before it, or right away when it was asked for now. A timer's runs until it ends.
    func wantsLiveActivity(now: Date = .now, calendar: Calendar = .app) -> Bool {
        if isTimer {
            return showsLiveActivity && date > now
        }
        guard showsLiveActivity, !isArchived, !isDone(now: now, calendar: calendar),
              !hasPassed(now: now, calendar: calendar) else { return false }
        if liveActivityForced || isTheDay(now: now, calendar: calendar) {
            return true
        }
        let start = window(calendar: calendar)?.lowerBound ?? target(now: now, calendar: calendar)
        return DayMath.daysUntil(start, from: now, calendar: calendar) <= max(0, liveActivityLead)
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

    /// How much of the wait is behind, from 0 to 1. A window's wait is up to its middle.
    func progress(now: Date = .now, calendar: Calendar = .app) -> Double {
        let start = waitStart(now: now, calendar: calendar)
        let end = windowMiddle(calendar: calendar) ?? target(now: now, calendar: calendar)
        let total = DayMath.days(from: start, to: end, calendar: calendar)
        guard total > 0 else { return 1 }
        return min(1, Double(DayMath.days(from: start, to: now, calendar: calendar)) / Double(total))
    }

    /// Sort orders that put `count` new countdowns at the top of the Until tab, in the order given.
    static func topOrders(_ count: Int, above countdowns: [Countdown]) -> [Int] {
        let first = (countdowns.map(\.sortOrder).min() ?? 0) - count
        return (0..<max(0, count)).map { first + $0 }
    }

    /// For a yearly day, how many years the next one marks: a birthday's age, an anniversary's year.
    func turns(now: Date = .now, calendar: Calendar = .app) -> Int? {
        guard rule.frequency == .yearly, countsYears else { return nil }
        let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: date),
                                            to: target(now: now, calendar: calendar)).year ?? 0
        return years > 0 ? years : nil
    }
}
