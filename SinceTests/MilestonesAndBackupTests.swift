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

    @Test func backupRoundTrip() throws {
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let counter = Counter(title: "Called mom", symbol: "phone.fill", color: .blue, kind: .lastTime,
                              startDate: date(2026, 8, 1), note: "Sundays")
        counter.tinted = false
        counter.size = .xl
        context.insert(counter)
        counter.resets.append(Reset(date: date(2026, 9, 1), note: "Long call"))

        let countdown = Countdown(title: "Mom", symbol: "birthday.cake.fill", color: .pink,
                                  date: date(1968, 10, 27), rule: RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 6]))
        countdown.isArchived = true
        countdown.size = .l
        context.insert(countdown)

        let data = try Backup(counters: [counter], countdowns: [countdown]).encoded()
        try Backup.decode(data).restore(into: context)

        let restored = try context.fetch(FetchDescriptor<Counter>())
        #expect(restored.count == 1)
        #expect(restored[0].title == "Called mom")
        #expect(restored[0].kind == .lastTime)
        #expect(restored[0].tinted == false)
        #expect(restored[0].size == .xl)
        #expect(restored[0].resets.first?.note == "Long call")

        let restoredCountdowns = try context.fetch(FetchDescriptor<Countdown>())
        #expect(restoredCountdowns.count == 1)
        #expect(restoredCountdowns[0].rule == RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 6]))
        #expect(restoredCountdowns[0].isArchived)
        #expect(restoredCountdowns[0].size == .l)
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
