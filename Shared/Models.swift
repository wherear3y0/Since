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
    /// Slips that aren't in the history (from before tracking, or never logged), added to the total.
    var extraSlips: Int = 0
    /// How the count is written: 127 days, 18w 1d or 4m 5d (a `DurationStyle`).
    var durationStyleRaw: Int = DurationStyle.days.rawValue
    /// What a "quit" counter is about (a `Habit`); "" is Other.
    var habitRaw: String = ""
    /// An owned thing's picture.
    @Attribute(.externalStorage) var photoData: Data? = nil
    /// The day an owned thing left: sold, broken, lost. Nil while it's still had.
    var goneDate: Date? = nil
    /// Why it left (a `GoneReason`); "" when not said.
    var goneReasonRaw: String = ""

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

    var habit: Habit {
        get { Habit(rawValue: habitRaw) ?? .other }
        set { habitRaw = newValue.rawValue }
    }

    /// "cigarette" or "cigarettes" for a smoking counter; the name typed in for Other, "" when none was.
    func unitWord(_ count: Double) -> String {
        if let unit = habit.unit {
            return count == 1 ? unit.one : unit.many
        }
        return unitName
    }

    /// "3 cigarettes", or just "3" when there's no unit.
    func amountText(_ count: Int) -> String {
        let word = unitWord(Double(count))
        return word.isEmpty ? "\(count)" : "\(count) \(word)"
    }

    var numberStyle: DurationStyle {
        get { DurationStyle(rawValue: durationStyleRaw) ?? .days }
        set { durationStyleRaw = newValue.rawValue }
    }

    /// The current streak written in the counter's number style, for cards and widgets.
    func durationParts(now: Date = .now, calendar: Calendar = .app) -> [DurationPart] {
        DayMath.parts(from: currentStreakStart, to: countEnd(now), style: numberStyle, calendar: calendar)
    }

    /// Where the count stops: the day an owned thing left, or now.
    func countEnd(_ now: Date) -> Date {
        goneDate.map { min($0, now) } ?? now
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

    /// Slips since the last full reset. The slips added by hand happened before tracking, so they count
    /// toward the run that was going on then: the current one until the first full reset.
    var slipsSinceProgressStart: Int {
        let start = progressStart
        let logged = resets.filter { $0.isSlip && $0.date >= start }.count
        return logged + (fullResetDates.isEmpty ? extraSlips : 0)
    }

    /// Every slip: the logged ones and the ones added by hand.
    var totalSlips: Int {
        slipDates.count + extraSlips
    }

    /// How many were had in all the logged slips (cigarettes, drinks), each slip at least one.
    var slippedAmount: Int {
        resets.filter(\.isSlip).map { max(1, $0.amount) }.reduce(0, +)
    }

    /// How many were had in the slips since the last full reset.
    var slippedAmountSinceProgressStart: Int {
        let start = progressStart
        return resets.filter { $0.isSlip && $0.date >= start }.map { max(1, $0.amount) }.reduce(0, +)
    }

    /// What wasn't had since the last full reset: every whole day's worth, less what the slips took.
    func savedUnits(now: Date = .now, calendar: Calendar = .app) -> Double {
        savings.units(days: trackedDays(now: now, calendar: calendar), less: Double(slippedAmountSinceProgressStart))
    }

    /// Days since the progress start, like the day count: the first day is day 0.
    func trackedDays(now: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.days(from: progressStart, to: now, calendar: calendar)
    }

    /// Days without a slip since the progress start: the first day counts, slip days don't. Whole days only
    /// (without slips the same as `trackedDays`), or with today too, like the summary's "Clean days".
    func cleanDays(now: Date = .now, includingToday: Bool = false, calendar: Calendar = .app) -> Int {
        let start = progressStart
        let slips = slipDates.filter { $0 >= start }
        let lastDay = includingToday ? now : calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        return DayMath.cleanRuns(start: start, resets: slips, now: lastDay, calendar: calendar)
            .map { DayMath.days(from: $0.lowerBound, to: $0.upperBound, calendar: calendar) + 1 }
            .reduce(0, +)
    }

    func days(on date: Date = .now, calendar: Calendar = .app) -> Int {
        DayMath.days(from: currentStreakStart, to: countEnd(date), calendar: calendar)
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

    /// Today's slip, which another slip today adds to instead of making a second entry.
    func slipToday(calendar: Calendar = .app) -> Reset? {
        resets.first { $0.isSlip && calendar.isDateInToday($0.date) }
    }

    /// A slip can be logged now: a new one, or one more on today's. Not after a full reset today.
    func canSlipToday(calendar: Calendar = .app) -> Bool {
        kind == .quit && !resets.contains { !$0.isSlip && calendar.isDateInToday($0.date) }
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
    /// For a slip: how many were had (cigarettes, drinks). Taken off what's been saved.
    var amount: Int = 1
    var counter: Counter?

    init(date: Date, note: String? = nil, isSlip: Bool = false, amount: Int = 1) {
        self.date = date
        self.note = note
        self.isSlip = isSlip
        self.amount = max(1, amount)
    }
}

extension Counter {
    func addReset(on date: Date = .now, note: String? = nil, isSlip: Bool = false) {
        resets.append(Reset(date: date, note: note, isSlip: isSlip))
    }

    /// Logs a slip now: one more on today's slip if there is one, otherwise a new slip of one.
    /// One more also moves today's slip to now, since the health steps count from the latest cigarette.
    /// Returns the slip, whether one was added to today's, and the time it had before, for Undo.
    @discardableResult
    func logSlip(calendar: Calendar = .app) -> (slip: Reset, addedToToday: Bool, previousDate: Date?) {
        if let today = slipToday(calendar: calendar) {
            let previous = today.date
            today.amount = max(1, today.amount) + 1
            today.date = max(today.date, .now)
            return (today, true, previous)
        }
        let slip = Reset(date: .now, isSlip: true)
        resets.append(slip)
        return (slip, false, nil)
    }
}
