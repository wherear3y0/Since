import SwiftUI
import SwiftData

/// A counter frozen at one moment of the timeline, so a widget can show tomorrow's numbers ahead of time.
struct CounterSnapshot: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let color: CounterColor
    let tinted: Bool
    let kind: CounterKind
    let start: Date
    /// Oldest first, slips included.
    let resetDates: [Date]
    let date: Date
    /// The resets that were slips.
    var slipDates: [Date] = []
    var numberStyle: DurationStyle = .days

    /// The count in weeks or months ("18w 1d"), when the counter is written that way.
    var displayParts: [DurationPart]? {
        numberStyle == .days ? nil : DayMath.parts(from: since, to: date, style: numberStyle)
    }

    var streaks: [Streak] { DayMath.streaks(start: start, resets: resetDates, now: date) }
    var days: Int { streaks.last?.days ?? 0 }
    var since: Date { streaks.last?.start ?? start }
    var best: Int { streaks.map(\.days).max() ?? 0 }
    var average: Int { Int(kind.average(of: streaks).rounded()) }

    /// For "last time" counters: the gap is already longer than usual.
    var isOverdue: Bool { kind == .lastTime && average > 0 && days > average }

    /// For an owned thing: the next whole year it will have been had, and how many days that is from the start.
    var nextYear: (years: Int, days: Int) {
        let calendar = Calendar.app
        let had = calendar.dateComponents([.year], from: calendar.startOfDay(for: start),
                                          to: calendar.startOfDay(for: date)).year ?? 0
        let next = calendar.date(byAdding: .year, value: had + 1, to: start) ?? date
        return (had + 1, DayMath.days(from: start, to: next))
    }

    var tint: Color { color.color.onCard(tinted: tinted) }
    var url: URL { URL(string: "since://counter/\(id.uuidString)")! }

    func heatmap(weeks: Int) -> [[HeatmapDay]] {
        DayMath.heatmap(start: start, resets: resetDates, slips: slipDates, logsEvents: kind == .lastTime,
                        now: date, weeks: weeks)
    }

    var lastWeek: [HeatmapDay] {
        DayMath.recentDays(7, start: start, resets: resetDates, slips: slipDates, logsEvents: kind == .lastTime,
                           now: date)
    }
}

extension CounterSnapshot {
    init(_ counter: Counter, at date: Date) {
        self.init(id: counter.id, title: counter.title, symbol: counter.symbol, color: counter.color,
                  tinted: counter.tinted, kind: counter.kind, start: counter.startDate,
                  resetDates: counter.resetDates, date: date, slipDates: counter.slipDates,
                  numberStyle: counter.numberStyle)
    }

    /// Stand-ins for the widget gallery and placeholders.
    static func samples(at date: Date = .now) -> [CounterSnapshot] {
        let daysAgo = { (n: Int) in Calendar.app.date(byAdding: .day, value: -n, to: date)! }
        let rows: [(String, String, CounterColor, CounterKind, Int, [Int])] = [
            ("Smoke-free", "lungs.fill", .mint, .quit, 210, [160, 95, 41]),
            ("Coffee", "cup.and.saucer.fill", .orange, .quit, 70, [52, 30, 12]),
            ("Alcohol-free", "wineglass.fill", .purple, .quit, 400, []),
            ("Doomscrolling", "iphone", .red, .quit, 35, [24, 17, 9, 4]),
            ("Haircut", "scissors", .green, .lastTime, 120, [92, 61, 28]),
            ("Called mom", "phone.fill", .blue, .lastTime, 45, [37, 30, 22, 16]),
        ]
        return rows.map { title, symbol, color, kind, start, resets in
            CounterSnapshot(id: UUID(), title: title, symbol: symbol, color: color, tinted: true, kind: kind,
                            start: daysAgo(start), resetDates: resets.map(daysAgo), date: date)
        }
    }
}

enum WidgetData {
    static func counters() -> [Counter] {
        Store.counters()
    }

    /// Now and the coming local midnight, when every count goes up by one, and any of `moments`
    /// (countdowns' times) in between.
    static func timelineDates(adding moments: [Date] = []) -> [Date] {
        let now = Date.now
        let midnight = Calendar.app.date(byAdding: .day, value: 1, to: Calendar.app.startOfDay(for: now))!
        return ([now, midnight] + moments.filter { $0 > now && $0 < midnight }).sorted()
    }
}
