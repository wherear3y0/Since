import Foundation
import Testing
@testable import Since

/// Countdowns kept in step with calendars and Reminders lists.
@MainActor
struct CalendarSyncTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func item(_ id: String, on day: Date, source: SyncSource = .calendar, in list: String = "work",
              repeats: Bool = false) -> SyncedItem {
        SyncedItem(id: id, source: source, calendarID: list, title: "Item \(id)", date: day, isAllDay: true,
                   rule: nil, repeats: repeats, color: .blue, symbol: "star.fill")
    }

    @Test func newItemsAppearOnceAndNotWhenSkipped() {
        let changes = CalendarSync.apply([item("a", on: date(10, 20)), item("b", on: date(10, 22))], synced: ["work"],
                                         to: [], skipped: ["b"], missing: { _ in .deleted }, now: date(10, 18),
                                         calendar: calendar)
        #expect(changes.inserts.map(\.calendarItemID) == ["a"])
        #expect(changes.inserts[0].syncSource == .calendar)

        // One made by hand from the same event is left alone.
        let byHand = Countdown(title: "A", symbol: "star.fill", color: .blue, date: date(10, 20))
        byHand.calendarItemID = "a"
        let again = CalendarSync.apply([item("a", on: date(10, 20))], synced: ["work"], to: [byHand], skipped: [],
                                       missing: { _ in .deleted }, now: date(10, 18), calendar: calendar)
        #expect(again.inserts.isEmpty && again.deletes.isEmpty)
    }

    @Test func aMovedEventKeepsItsOldDayAndADeletedOneGoes() {
        let first = CalendarSync.apply([item("a", on: date(10, 20)), item("b", on: date(10, 25))], synced: ["work"],
                                       to: [], skipped: [], missing: { _ in .deleted }, now: date(10, 18),
                                       calendar: calendar).inserts
        let changes = CalendarSync.apply([item("a", on: date(10, 23))], synced: ["work"], to: first, skipped: [],
                                         missing: { _ in .deleted }, now: date(10, 18), calendar: calendar)
        let moved = first.first { $0.calendarItemID == "a" }!
        #expect(moved.date == date(10, 23))
        #expect(moved.postponedFrom == [date(10, 20)])
        #expect(changes.deletes.map(\.calendarItemID) == ["b"])
    }

    @Test func gonePastStaysAndAnUnsyncedCalendarGoes() {
        let made = CalendarSync.apply([item("a", on: date(10, 20))], synced: ["work"], to: [], skipped: [],
                                      missing: { _ in .deleted }, now: date(10, 18), calendar: calendar).inserts
        // A day later than the event: not found any more, but still in the calendar.
        let later = CalendarSync.apply([], synced: ["work"], to: made, skipped: [], missing: { _ in .outOfRange },
                                       now: date(10, 22), calendar: calendar)
        #expect(later.deletes.isEmpty)
        let off = CalendarSync.apply([], synced: [], to: made, skipped: [], missing: { _ in .outOfRange },
                                     now: date(10, 22), calendar: calendar)
        #expect(off.deletes.count == 1)
    }

    @Test func remindersTickedOffThereAreDoneHere() {
        let made = CalendarSync.apply([item("r", on: date(10, 20), source: .reminders, in: "home")], synced: ["home"],
                                      to: [], skipped: [], missing: { _ in .deleted }, now: date(10, 18),
                                      calendar: calendar).inserts
        let reminder = made[0]
        #expect(reminder.isReminder)
        // Overdue, not gone by: it can still be done.
        #expect(!reminder.hasPassed(now: date(10, 22), calendar: calendar))
        #expect(reminder.isTheDay(now: date(10, 22), calendar: calendar))

        _ = CalendarSync.apply([], synced: ["home"], to: made, skipped: [], missing: { _ in .completed },
                               now: date(10, 19), calendar: calendar)
        #expect(reminder.isArchived)

        // A repeating one comes back for its next time, without a postponement.
        _ = CalendarSync.apply([item("r", on: date(10, 27), source: .reminders, in: "home", repeats: true)],
                               synced: ["home"], to: made, skipped: [], missing: { _ in .deleted }, now: date(10, 21),
                               calendar: calendar)
        #expect(!reminder.isArchived)
        #expect(reminder.postponedFrom.isEmpty)
    }
}
