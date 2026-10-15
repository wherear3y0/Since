import Foundation
import Testing
@testable import Since

@MainActor
struct UntilTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func ymd(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    @Test func daysUntilIsSigned() {
        #expect(DayMath.daysUntil(date(2026, 10, 20), from: date(2026, 10, 15), calendar: calendar) == 5)
        #expect(DayMath.daysUntil(date(2026, 10, 15, hour: 1), from: date(2026, 10, 15, hour: 23), calendar: calendar) == 0)
        #expect(DayMath.daysUntil(date(2026, 10, 13), from: date(2026, 10, 15), calendar: calendar) == -2)
    }

    func target(_ rule: RepeatRule, from start: Date, now: Date) -> DateComponents {
        ymd(rule.occurrence(rule.targetIndex(from: start, now: now, calendar: calendar), from: start, calendar: calendar))
    }

    @Test func yearlyTarget() {
        let birthday = date(1990, 3, 8)
        let yearly = RepeatRule(frequency: .yearly)
        // Later this year, today, and already gone this year.
        #expect(target(yearly, from: birthday, now: date(2026, 1, 10)) == DateComponents(year: 2026, month: 3, day: 8))
        #expect(target(yearly, from: birthday, now: date(2026, 3, 8, hour: 23)) == DateComponents(year: 2026, month: 3, day: 8))
        #expect(target(yearly, from: birthday, now: date(2026, 3, 9)) == DateComponents(year: 2027, month: 3, day: 8))
        // A first day still ahead is the first target.
        #expect(target(yearly, from: date(2028, 5, 1), now: date(2026, 10, 15)) == DateComponents(year: 2028, month: 5, day: 1))
    }

    @Test func leapDayFallsOnTheTwentyEighth() {
        let leap = date(2024, 2, 29)
        let yearly = RepeatRule(frequency: .yearly)
        #expect(target(yearly, from: leap, now: date(2026, 1, 1)) == DateComponents(year: 2026, month: 2, day: 28))
        #expect(target(yearly, from: leap, now: date(2027, 3, 1)) == DateComponents(year: 2028, month: 2, day: 29))
    }

    @Test func monthlyKeepsTheThirtyFirst() {
        let monthly = RepeatRule(frequency: .monthly)
        let start = date(2026, 1, 31)
        #expect(target(monthly, from: start, now: date(2026, 2, 10)) == DateComponents(year: 2026, month: 2, day: 28))
        // March goes back to the 31st instead of drifting to the 28th.
        #expect(target(monthly, from: start, now: date(2026, 3, 1)) == DateComponents(year: 2026, month: 3, day: 31))
        // Every 3 months.
        let quarterly = RepeatRule(frequency: .monthly, interval: 3)
        #expect(target(quarterly, from: date(2026, 1, 15), now: date(2026, 5, 1)) == DateComponents(year: 2026, month: 7, day: 15))
    }

    @Test func dailyAndWeekly() {
        let start = date(2026, 10, 1) // Thursday
        #expect(target(RepeatRule(frequency: .daily, interval: 3), from: start, now: date(2026, 10, 15))
                == DateComponents(year: 2026, month: 10, day: 16))
        // Every 2 weeks from a Thursday.
        #expect(target(RepeatRule(frequency: .weekly, interval: 2), from: start, now: date(2026, 10, 16))
                == DateComponents(year: 2026, month: 10, day: 29))
    }

    @Test func weeklyOnChosenWeekdays() {
        // Mondays and Wednesdays (2 and 4), every other week, from Thursday Oct 1, 2026; weeks start on Monday.
        let rule = RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 4])
        let start = date(2026, 10, 1)
        // Monday and Wednesday of the first week are before the first day, so the first is two weeks on.
        #expect(ymd(rule.occurrence(0, from: start, calendar: calendar)) == DateComponents(year: 2026, month: 10, day: 12))
        #expect(ymd(rule.occurrence(1, from: start, calendar: calendar)) == DateComponents(year: 2026, month: 10, day: 14))
        #expect(ymd(rule.occurrence(2, from: start, calendar: calendar)) == DateComponents(year: 2026, month: 10, day: 26))
        #expect(target(rule, from: start, now: date(2026, 10, 13)) == DateComponents(year: 2026, month: 10, day: 14))
        #expect(rule.summary(calendar: calendar) == "Every 2 weeks on Mon, Wed")
    }

    @Test func repeatEnds() {
        var rule = RepeatRule(frequency: .weekly)
        rule.end = date(2026, 10, 20)
        let start = date(2026, 10, 1)
        #expect(target(rule, from: start, now: date(2026, 10, 9)) == DateComponents(year: 2026, month: 10, day: 15))
        // After the last time round, the target stays on it, in the past.
        #expect(target(rule, from: start, now: date(2026, 10, 25)) == DateComponents(year: 2026, month: 10, day: 15))

        let countdown = Countdown(title: "Class", symbol: "book.fill", color: .blue, date: start, rule: rule)
        #expect(countdown.hasPassed(now: date(2026, 10, 25), calendar: calendar))
    }

    @Test func presetsAndSummaries() {
        #expect(RepeatRule(frequency: .weekly, interval: 2).summary() == "Every 2 Weeks")
        #expect(RepeatRule(frequency: .monthly, interval: 3).summary() == "Every 3 months")
        #expect(RepeatRule(frequency: .daily, end: date(2027, 1, 1)).isPreset)
        #expect(!RepeatRule(frequency: .daily, interval: 4).isPreset)
    }

    @Test func workdaysAndWeekends() {
        // Thursday Oct 15 to Monday Oct 26, 2026: Thu, Fri, two weekends and a full week between them.
        let left = DayMath.timeLeft(until: date(2026, 10, 26), from: date(2026, 10, 15), calendar: calendar)
        #expect(left == TimeLeft(workdays: 7, weekends: 2))
        // Starting on a Sunday still counts that weekend.
        #expect(DayMath.timeLeft(until: date(2026, 10, 19), from: date(2026, 10, 18), calendar: calendar)
                == TimeLeft(workdays: 0, weekends: 1))
        #expect(DayMath.timeLeft(until: date(2026, 10, 1), from: date(2026, 10, 18), calendar: calendar)
                == TimeLeft(workdays: 0, weekends: 0))
    }

    @Test func monthPage() {
        // October 2026 starts on a Thursday; weeks start on Monday here.
        let rows = DayMath.monthGrid(of: date(2026, 10, 1), today: date(2026, 10, 15), target: date(2026, 10, 28),
                                     calendar: calendar)
        #expect(rows.count == 6)
        #expect(rows[0].prefix(3).allSatisfy { $0 == nil })
        #expect(rows[0][3]?.number == 1)
        let days = rows.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(days.first { $0.isToday }?.number == 15)
        #expect(days.first { $0.state == .target }?.number == 28)
        #expect(days.filter { $0.state == .waiting }.count == 13) // Oct 15 … 27
        #expect(days.filter { $0.state == .gone }.count == 14)
        #expect(days.filter { $0.state == .later }.count == 3)
    }

    @Test func monthsShown() {
        let now = date(2026, 10, 15)
        let months = { (target: Date) in
            self.calendar.monthsShown(now: now, target: target).map { self.calendar.component(.month, from: $0) }
        }
        #expect(months(date(2026, 12, 3)) == [10, 12])
        #expect(months(date(2026, 10, 28)) == [10, 11])
        #expect(months(date(2026, 9, 2)) == [9, 10])
    }

    @Test func timelineTicks() {
        #expect(DayMath.timelineTicks(daysLeft: 5, from: date(2026, 10, 15), calendar: calendar) == [1, 2, 3, 4])
        #expect(DayMath.timelineTicks(daysLeft: 42, from: date(2026, 10, 15), calendar: calendar) == [7, 14, 21, 28, 35])
        // Months from Oct 15: Nov 15 is 31 days on, Dec 15 is 61.
        #expect(DayMath.timelineTicks(daysLeft: 150, from: date(2026, 10, 15), calendar: calendar) == [31, 61, 92, 123])
    }

    @Test func toGo() {
        let now = date(2026, 10, 15)
        #expect(DayMath.toGo(from: now, to: date(2026, 10, 20), calendar: calendar) == "5 days")
        #expect(DayMath.toGo(from: now, to: date(2026, 11, 26), calendar: calendar) == "6 weeks")
        #expect(DayMath.toGo(from: now, to: date(2026, 11, 25), calendar: calendar) == "5 weeks 6 days")
        #expect(DayMath.toGo(from: now, to: date(2027, 8, 29), calendar: calendar) == "10 months 14 days")
    }

    @Test func oneOffProgress() {
        let countdown = Countdown(title: "Vacation", symbol: "airplane", color: .cyan, date: date(2026, 11, 1))
        countdown.createdAt = date(2026, 10, 1)
        let now = date(2026, 10, 16)
        #expect(countdown.daysLeft(now: now, calendar: calendar) == 16)
        #expect(abs(countdown.progress(now: now, calendar: calendar) - 15.0 / 31.0) < 0.001)
        #expect(!countdown.hasPassed(now: now, calendar: calendar))
        #expect(countdown.hasPassed(now: date(2026, 11, 2), calendar: calendar))
        #expect(countdown.turns(now: now, calendar: calendar) == nil)
    }

    @Test func yearlyCountdown() {
        let countdown = Countdown(title: "Mom", symbol: "birthday.cake.fill", color: .pink,
                                  date: date(1968, 10, 27), rule: RepeatRule(frequency: .yearly))
        countdown.createdAt = date(2026, 9, 1)
        let now = date(2026, 10, 15)
        #expect(countdown.daysLeft(now: now, calendar: calendar) == 12)
        #expect(countdown.turns(now: now, calendar: calendar) == 58)
        // The wait runs from last year's birthday, not from when the countdown was added.
        #expect(ymd(countdown.waitStart(now: now, calendar: calendar)) == DateComponents(year: 2025, month: 10, day: 27))
        // The day after, it counts to next year's.
        #expect(countdown.daysLeft(now: date(2026, 10, 28), calendar: calendar) == 364)
        #expect(!countdown.hasPassed(now: date(2026, 10, 28), calendar: calendar))
    }

    @Test func repeatingDayWaitsFromTheTimeBefore() {
        // A holiday picked from Calendar at its next date: the wait runs from a year before, not from today.
        let countdown = Countdown(title: "Halloween", symbol: "star.fill", color: .orange, date: date(2026, 10, 31),
                                  rule: RepeatRule(frequency: .yearly))
        countdown.createdAt = date(2026, 10, 15)
        let now = date(2026, 10, 15)
        #expect(ymd(countdown.waitStart(now: now, calendar: calendar)) == DateComponents(year: 2025, month: 10, day: 31))
        #expect(countdown.progress(now: now, calendar: calendar) > 0.9)
        // One that starts later doesn't pretend it already came round.
        let later = Countdown(title: "Class", symbol: "book.fill", color: .blue, date: date(2027, 2, 1),
                              rule: RepeatRule(frequency: .monthly))
        later.createdAt = now
        #expect(later.previousTime(now: now, calendar: calendar) == nil)
    }

    @Test func countdownReminders() {
        let countdown = Countdown(title: "Concert", symbol: "music.note", color: .purple, date: date(2026, 10, 25))
        let reminders = Milestones.reminders(for: countdown, now: date(2026, 10, 15), calendar: calendar)
        #expect(reminders.map { ymd($0.date) } == [
            DateComponents(year: 2026, month: 10, day: 18),
            DateComponents(year: 2026, month: 10, day: 24),
            DateComponents(year: 2026, month: 10, day: 25),
        ])
        // A week before is already gone three days out.
        #expect(Milestones.reminders(for: countdown, now: date(2026, 10, 22), calendar: calendar).count == 2)
    }

    @Test func repeatingReminders() {
        // Every day: no "in a week" or "tomorrow" before days that come round daily, just the day itself, three times.
        let daily = Countdown(title: "Pills", symbol: "pills.fill", color: .mint, date: date(2026, 10, 1),
                              rule: RepeatRule(frequency: .daily))
        let reminders = Milestones.reminders(for: daily, now: date(2026, 10, 15, hour: 8), calendar: calendar)
        #expect(reminders.map(\.name) == ["It’s today!", "It’s today!", "It’s today!"])
        #expect(reminders.map { ymd($0.date) }.first == DateComponents(year: 2026, month: 10, day: 15))
    }
}
