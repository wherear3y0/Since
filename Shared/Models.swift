import Foundation
import SwiftData

// Every stored property of a model has a default value. That lets SwiftData upgrade a database made by
// an older version of the app on its own (a lightweight migration) when properties are added.
// Don't rename, retype or remove stored properties: that's what breaks opening an existing database.

@Model
final class Counter {
    var id: UUID = UUID()
    var title: String = ""
    var symbol: String = "star.fill"
    var colorName: String = CounterColor.blue.rawValue
    var startDate: Date = Date.now
    var note: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var notifyMilestones: Bool = false
    var kindRaw: String = CounterKind.quit.rawValue
    /// Card filled with the counter's color and a soft glow, or a plain gray card when off.
    var tinted: Bool = true
    var sizeRaw: String = CardSize.m.rawValue

    // Savings, for "quit" counters: what the habit cost, so the app can say what's been saved.
    /// "cigarettes", "cups"; empty when not set.
    var unitName: String = ""
    var unitsPerDay: Double = 0
    /// What `unitsPerPrice` units cost, like a pack of 20.
    var price: Double = 0
    var unitsPerPrice: Int = 1
    var minutesPerUnit: Double = 0
    /// Shows how the body recovers after quitting smoking.
    var showsHealth: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Reset.counter)
    var resets: [Reset] = []

    init(title: String, symbol: String, color: CounterColor, kind: CounterKind = .quit,
         startDate: Date, note: String? = nil, sortOrder: Int = 0) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.symbol = symbol
        self.colorName = color.rawValue
        self.startDate = startDate
        self.note = note
        self.sortOrder = sortOrder
    }

    var size: CardSize {
        get { CardSize(rawValue: sizeRaw) ?? .m }
        set { sizeRaw = newValue.rawValue }
    }

    var kind: CounterKind {
        get { CounterKind(rawValue: kindRaw) ?? .quit }
        set { kindRaw = newValue.rawValue }
    }

    var color: CounterColor {
        get { CounterColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    /// Reset dates, oldest first, slips included.
    var resetDates: [Date] {
        resets.map(\.date).sorted()
    }

    /// Dates of slips: resets that start the count again but keep the earlier days on the heatmap.
    var slipDates: [Date] {
        resets.filter(\.isSlip).map(\.date).sorted()
    }

    /// The last weeks of days, drawn the way this counter's kind draws them.
    func heatmap(weeks: Int, now: Date = .now) -> [[HeatmapDay]] {
        DayMath.heatmap(start: startDate, resets: resetDates, slips: slipDates, logsEvents: kind == .lastTime,
                        now: now, weeks: weeks)
    }

    /// The last `count` days, oldest first.
    func recentDays(_ count: Int, now: Date = .now) -> [HeatmapDay] {
        DayMath.recentDays(count, start: startDate, resets: resetDates, slips: slipDates,
                           logsEvents: kind == .lastTime, now: now)
    }

    /// Whether savings are set up: something a day and what it costs or takes.
    var tracksSavings: Bool {
        kind == .quit && unitsPerDay > 0 && (price > 0 || minutesPerUnit > 0)
    }

    var savings: Savings {
        Savings(unitsPerDay: unitsPerDay, price: price, unitsPerPrice: unitsPerPrice, minutesPerUnit: minutesPerUnit)
    }

    /// Start of the current streak: the last reset or slip, or the start date if there are none.
    var currentStreakStart: Date {
        max(startDate, resetDates.last ?? startDate)
    }

    /// Dates of full resets, the ones that clear the heatmap, oldest first.
    var fullResetDates: [Date] {
        resets.filter { !$0.isSlip }.map(\.date).sorted()
    }

    /// Where the overall progress counts from: the last full reset, or the start. Slips don't move it.
    var progressStart: Date {
        max(startDate, fullResetDates.last ?? startDate)
    }

    /// Slips since the last full reset.
    var slipsSinceProgressStart: Int {
        let start = progressStart
        return resets.filter { $0.isSlip && $0.date > start }.count
    }

    /// Days since the progress start, like the day count: the first day is day 0.
    func trackedDays(now: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.days(from: progressStart, to: now, calendar: calendar)
    }

    /// Whole days without a slip since the progress start, today not included: the first day counts,
    /// slip days don't. Without slips it's the same as `trackedDays`. Savings are counted over these days.
    func cleanDays(now: Date = .now, calendar: Calendar = .app) -> Int {
        let start = progressStart
        let slips = slipDates.filter { $0 > start }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        return DayMath.cleanRuns(start: start, resets: slips, now: yesterday, calendar: calendar)
            .map { DayMath.days(from: $0.lowerBound, to: $0.upperBound, calendar: calendar) + 1 }
            .reduce(0, +)
    }

    func days(on date: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.days(from: currentStreakStart, to: date, calendar: calendar)
    }

    func streaks(now: Date = .now, calendar: Calendar = .app) -> [Streak] {
        DayMath.streaks(start: startDate, resets: resetDates, now: now, calendar: calendar)
    }

    func wasResetToday(calendar: Calendar = .app) -> Bool {
        resetDates.contains { calendar.isDateInToday($0) }
    }

    /// Nothing left to do today: reset or slipped already, or, for a "last time" counter,
    /// already logged (a counter started today counts as done today).
    func isDoneToday(calendar: Calendar = .app) -> Bool {
        wasResetToday(calendar: calendar) || (kind == .lastTime && calendar.isDateInToday(startDate))
    }

    /// Today's reset or slip, if there is one.
    func resetToday(calendar: Calendar = .app) -> Reset? {
        resets.first { calendar.isDateInToday($0.date) }
    }
}

@Model
final class Reset {
    var id: UUID = UUID()
    var date: Date = Date.now
    var note: String?
    /// A slip: the count starts again, but the days before stay on the heatmap, dimmed.
    /// A full reset (`false`) starts over with a clean heatmap.
    var isSlip: Bool = false
    var counter: Counter?

    init(date: Date, note: String? = nil, isSlip: Bool = false) {
        self.date = date
        self.note = note
        self.isSlip = isSlip
    }
}

extension Counter {
    func addReset(on date: Date = .now, note: String? = nil, isSlip: Bool = false) {
        resets.append(Reset(date: date, note: note, isSlip: isSlip))
    }
}
