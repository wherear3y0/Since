import Foundation
import Testing
@testable import Since

struct DayMathTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter.date(from: string)!
    }

    @Test func sameDayIsZero() {
        #expect(DayMath.days(from: date("2026-06-08T00:01:00"), to: date("2026-06-08T23:59:00"), calendar: calendar) == 0)
    }

    @Test func justAfterMidnightIsOneDay() {
        #expect(DayMath.days(from: date("2026-06-08T23:59:00"), to: date("2026-06-09T00:01:00"), calendar: calendar) == 1)
    }

    @Test func daylightSavingDaysCountAsOne() {
        // Germany switches to summer time on 2026-03-29 (a 23-hour day) and back on 2026-10-25 (25 hours).
        #expect(DayMath.days(from: date("2026-03-28T12:00:00"), to: date("2026-03-30T12:00:00"), calendar: calendar) == 2)
        #expect(DayMath.days(from: date("2026-10-24T23:30:00"), to: date("2026-10-26T00:30:00"), calendar: calendar) == 2)
    }

    @Test func leapDay() {
        let start = date("2024-02-29T10:00:00")
        #expect(DayMath.days(from: start, to: date("2025-03-01T10:00:00"), calendar: calendar) == 366)
        let parts = DayMath.parts(from: start, to: date("2025-03-01T10:00:00"), style: .months, calendar: calendar)
        #expect(parts.first?.unit == "y")
    }

    @Test func durationStyles() {
        let start = date("2026-06-08T09:00:00")
        let end = date("2026-10-13T09:00:00") // 127 days
        #expect(DayMath.parts(from: start, to: end, style: .days, calendar: calendar) == [DurationPart(value: 127, unit: "days")])
        #expect(DayMath.parts(from: start, to: end, style: .weeks, calendar: calendar) == [DurationPart(value: 18, unit: "w"), DurationPart(value: 1, unit: "d")])
        #expect(DayMath.parts(from: start, to: end, style: .months, calendar: calendar) == [DurationPart(value: 4, unit: "m"), DurationPart(value: 5, unit: "d")])
        #expect(DayMath.parts(from: start, to: start, style: .weeks, calendar: calendar) == [DurationPart(value: 0, unit: "d")])
    }

    @Test func streaks() {
        let start = date("2026-01-01T09:00:00")
        let resets = [date("2026-01-11T20:00:00"), date("2026-01-04T08:00:00")]
        let streaks = DayMath.streaks(start: start, resets: resets, now: date("2026-01-20T07:00:00"), calendar: calendar)
        #expect(streaks.map(\.days) == [3, 7, 9])
        #expect(streaks.map(\.isCurrent) == [false, false, true])
    }

    @Test func heatmap() {
        let start = date("2026-10-01T09:00:00")
        let grid = DayMath.heatmap(start: start, resets: [date("2026-10-07T09:00:00")],
                                   now: date("2026-10-13T12:00:00"), calendar: calendar)
        let days = grid.flatMap { $0 }
        #expect(grid.count == 7 && grid.allSatisfy { $0.count == 7 })
        #expect(days.filter(\.isToday).count == 1)
        #expect(days.first { $0.isToday }?.state == .clean)
        // Only the days after the Oct 7 reset are lit.
        #expect(days.filter { $0.state == .clean }.count == 6)
        #expect(days.last?.state == .future) // Sunday after Tuesday the 13th
    }

    @Test func cleanRuns() {
        let runs = DayMath.cleanRuns(start: date("2026-01-01T09:00:00"),
                                     resets: [date("2026-01-04T08:00:00"), date("2026-01-11T20:00:00")],
                                     now: date("2026-01-20T07:00:00"), calendar: calendar)
        let lengths = runs.map { DayMath.days(from: $0.lowerBound, to: $0.upperBound, calendar: calendar) + 1 }
        #expect(lengths == [3, 6, 9])
    }

    @Test func cleanRunsWithResetToday() {
        let runs = DayMath.cleanRuns(start: date("2026-01-01T09:00:00"),
                                     resets: [date("2026-01-05T08:00:00")],
                                     now: date("2026-01-05T20:00:00"), calendar: calendar)
        #expect(runs.count == 1)
    }

    @Test func averageSkipsRunningGapForLastTime() {
        let streaks = DayMath.streaks(start: date("2026-01-01T09:00:00"),
                                      resets: [date("2026-01-05T09:00:00"), date("2026-01-11T09:00:00")],
                                      now: date("2026-01-12T09:00:00"), calendar: calendar)
        #expect(streaks.map(\.days) == [4, 6, 1])
        #expect(CounterKind.quit.average(of: streaks) == 11.0 / 3)
        #expect(CounterKind.lastTime.average(of: streaks) == 5)
    }

    @Test func recentDays() {
        let days = DayMath.recentDays(7, start: date("2026-10-09T09:00:00"), resets: [date("2026-10-11T20:00:00")],
                                      now: date("2026-10-13T12:00:00"), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.last?.isToday == true)
        #expect(days.map(\.state) == [.before, .before, .before, .before, .before, .clean, .clean])
    }

    @Test func slipKeepsTheDaysBeforeItDimmed() {
        let grid = DayMath.heatmap(start: date("2026-10-01T09:00:00"), resets: [date("2026-10-07T09:00:00")],
                                   slips: [date("2026-10-07T09:00:00")], now: date("2026-10-13T12:00:00"),
                                   calendar: calendar)
        let days = grid.flatMap { $0 }
        #expect(days.filter { $0.state == .slipped }.count == 6) // Oct 1–6
        #expect(days.filter { $0.state == .slip }.count == 1)
        #expect(days.filter { $0.state == .clean }.count == 6) // Oct 8–13
    }

    @Test func fullResetStillClearsBeforeLaterSlips() {
        let reset = date("2026-10-03T09:00:00")
        let slip = date("2026-10-07T09:00:00")
        let grid = DayMath.heatmap(start: date("2026-10-01T09:00:00"), resets: [slip, reset], slips: [slip],
                                   now: date("2026-10-13T12:00:00"), calendar: calendar)
        let days = grid.flatMap { $0 }
        #expect(days.filter { $0.state == .slipped }.count == 3) // Oct 4–6
        #expect(days.filter { $0.state == .slip }.count == 1)
        #expect(days.filter { $0.state == .clean }.count == 6)
        #expect(days.first { calendar.isDate($0.date, inSameDayAs: reset) }?.state == .before)
    }

    @Test func lastTimeMarksTheDaysItWasDone() {
        let days = DayMath.recentDays(14, start: date("2026-10-01T09:00:00"),
                                      resets: [date("2026-10-07T09:00:00"), date("2026-10-13T08:00:00")],
                                      logsEvents: true, now: date("2026-10-13T12:00:00"), calendar: calendar)
        #expect(days.filter { $0.state == .logged }.count == 3) // Oct 1, 7 and today
        #expect(days.last?.state == .logged)
        #expect(!days.contains { $0.state == .clean })
    }

    @Test func savings() {
        let savings = Savings(unitsPerDay: 10, price: 8, unitsPerPrice: 20, minutesPerUnit: 5)
        #expect(savings.moneyPerDay == 4)
        #expect(savings.money(days: 9) == 36)
        #expect(savings.units(days: 9) == 90)
        #expect(savings.minutes(days: 9) == 450)
        #expect(savings.money(days: -3) == 0)
    }

    @Test func healthMilestones() {
        let start = date("2026-10-01T09:00:00")
        let progress = HealthMilestone.progress(since: start, now: date("2026-10-04T09:00:00"), calendar: calendar)
        #expect(progress.reached.map(\.when) == ["20 minutes", "12 hours"])
        #expect(progress.next?.when == "2 weeks")
        #expect(abs(progress.fraction - 2.5 / 13.5) < 0.01)
    }

    @Test func longUnits() {
        #expect(DurationPart(value: 1, unit: "d").longUnit == "day")
        #expect(DurationPart(value: 18, unit: "w").longUnit == "weeks")
        #expect(DurationPart(value: 1, unit: "y").longUnit == "year")
        #expect(DurationPart(value: 127, unit: "days").longUnit == "days")
    }
}
