import Foundation
import SwiftData
import Testing
@testable import Since

@MainActor
struct MilestonesAndBackupTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func upcomingMilestones() {
        let counter = Counter(title: "Smoke-free", symbol: "lungs.fill", color: .mint, startDate: date(2026, 1, 31))
        let upcoming = Milestones.upcoming(for: counter, now: date(2026, 3, 1), calendar: calendar)
        #expect(upcoming.first?.name == "Half a year")
        #expect(calendar.dateComponents([.month, .day], from: upcoming[0].date) == DateComponents(month: 7, day: 31))
        #expect(upcoming[1].name == "One year")
        #expect(upcoming[2].name == "2 years")
    }

    @Test func milestonesFollowTheLastReset() {
        let counter = Counter(title: "Coffee", symbol: "mug.fill", color: .orange, startDate: date(2024, 1, 1))
        counter.resets.append(Reset(date: date(2026, 2, 10)))
        let upcoming = Milestones.upcoming(for: counter, now: date(2026, 3, 1), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: upcoming[0].date)
                == DateComponents(year: 2026, month: 8, day: 10))
    }

    @Test func slipsKeepTheProgressAndFullResetsStartItOver() {
        let counter = Counter(title: "Smoke-free", symbol: "lungs.fill", color: .mint, startDate: date(2026, 1, 1))
        counter.resets.append(Reset(date: date(2026, 1, 5), isSlip: true))
        let now = date(2026, 1, 11)
        #expect(counter.days(on: now, calendar: calendar) == 6)
        #expect(counter.trackedDays(now: now, calendar: calendar) == 10)
        // Jan 1–4 and Jan 6–10; the slip day and today don't count.
        #expect(counter.cleanDays(now: now, calendar: calendar) == 9)
        #expect(counter.slipsSinceProgressStart == 1)

        counter.resets.append(Reset(date: date(2026, 1, 8)))
        #expect(counter.trackedDays(now: now, calendar: calendar) == 3)
        #expect(counter.cleanDays(now: now, calendar: calendar) == 3)
        #expect(counter.slipsSinceProgressStart == 0)
    }

    @Test func lastTimeStartedTodayIsDoneToday() {
        let counter = Counter(title: "Called mom", symbol: "phone.fill", color: .blue, kind: .lastTime, startDate: .now)
        #expect(counter.isDoneToday())
        let older = Counter(title: "Haircut", symbol: "scissors", color: .green, kind: .lastTime,
                            startDate: Calendar.app.date(byAdding: .day, value: -3, to: .now)!)
        #expect(!older.isDoneToday())
        older.addReset()
        #expect(older.isDoneToday())
    }

    @Test func backupRoundTrip() throws {
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let counter = Counter(title: "Called mom", symbol: "phone.fill", color: .blue, kind: .lastTime,
                              startDate: date(2026, 8, 1), note: "Sundays")
        counter.tinted = false
        counter.size = .xl
        counter.unitName = "cigarettes"
        counter.unitsPerDay = 12
        counter.price = 9.5
        counter.unitsPerPrice = 20
        counter.minutesPerUnit = 5
        counter.showsHealth = true
        context.insert(counter)
        counter.resets.append(Reset(date: date(2026, 9, 1), note: "Long call"))
        counter.resets.append(Reset(date: date(2026, 9, 10), isSlip: true))

        let countdown = Countdown(title: "Mom", symbol: "birthday.cake.fill", color: .pink,
                                  date: date(1968, 10, 27), rule: RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 6]))
        countdown.isArchived = true
        countdown.size = .l
        countdown.isPinned = true
        countdown.isBirthday = true
        countdown.showsLiveActivity = true
        context.insert(countdown)

        let data = try Backup(counters: [counter], countdowns: [countdown]).encoded()
        try Backup.decode(data).restore(into: context)

        let restored = try context.fetch(FetchDescriptor<Counter>())
        #expect(restored.count == 1)
        #expect(restored[0].title == "Called mom")
        #expect(restored[0].kind == .lastTime)
        #expect(restored[0].tinted == false)
        #expect(restored[0].size == .xl)
        #expect(restored[0].resetDates.count == 2)
        #expect(restored[0].resets.first { !$0.isSlip }?.note == "Long call")
        #expect(restored[0].slipDates.count == 1)
        #expect(restored[0].savings == Savings(unitsPerDay: 12, price: 9.5, unitsPerPrice: 20, minutesPerUnit: 5))
        #expect(restored[0].unitName == "cigarettes")
        #expect(restored[0].showsHealth)

        let restoredCountdowns = try context.fetch(FetchDescriptor<Countdown>())
        #expect(restoredCountdowns.count == 1)
        #expect(restoredCountdowns[0].rule == RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 6]))
        #expect(restoredCountdowns[0].isArchived)
        #expect(restoredCountdowns[0].size == .l)
        #expect(restoredCountdowns[0].isPinned)
        #expect(restoredCountdowns[0].isBirthday)
        #expect(restoredCountdowns[0].showsLiveActivity)
    }

    @Test func backupsFromBeforeSlipsStillRestore() throws {
        // A reset written by an older version: no isSlip, no savings fields.
        let json = """
        {"version": 1, "exportedAt": "2026-01-01T10:00:00Z", "counters": [{
            "id": "5D2F0B4E-8C1B-4B5A-9B44-2E2B9B6A1C11", "title": "Coffee", "symbol": "mug.fill",
            "color": "orange", "kind": "quit", "tinted": true, "startDate": "2025-12-01T10:00:00Z",
            "sortOrder": 0, "createdAt": "2025-12-01T10:00:00Z", "notifyMilestones": false,
            "resets": [{"id": "0B7E2C4A-1D3F-4E5B-8A6C-7D8E9F0A1B2C", "date": "2025-12-10T10:00:00Z"}]
        }]}
        """
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try Backup.decode(Data(json.utf8)).restore(into: container.mainContext)
        let restored = try container.mainContext.fetch(FetchDescriptor<Counter>())
        #expect(restored.count == 1)
        #expect(restored[0].slipDates.isEmpty)
        #expect(restored[0].fullResetDates.count == 1)
        #expect(!restored[0].tracksSavings)
    }

    @Test func oldBackupKeepsCountdowns() throws {
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(Countdown(title: "Vacation", symbol: "airplane", color: .cyan, date: date(2026, 12, 1)))

        var backup = Backup(counters: [])
        backup.countdowns = nil
        try Backup.decode(backup.encoded()).restore(into: context)

        #expect(try context.fetch(FetchDescriptor<Countdown>()).count == 1)
    }
}
