import Foundation
import Testing
@testable import Since

/// Times, windows, postponing and Live Activities ahead of the day.
@MainActor
struct UntilTimeTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func countdown(on day: Date, rule: RepeatRule = .never) -> Countdown {
        Countdown(title: "Parcel", symbol: "shippingbox.fill", color: .orange, date: day, rule: rule)
    }

    @Test func aWindowCountsToItsMiddleThenToItsEnd() {
        // Oct 4–15: the middle is Oct 9.
        let parcel = countdown(on: date(2026, 10, 4))
        parcel.windowEnd = date(2026, 10, 15)
        let before = date(2026, 9, 25)
        #expect(parcel.daysLeft(now: before, calendar: calendar) == 14)
        #expect(parcel.isApproximate(now: before, calendar: calendar))
        #expect(!parcel.isTheDay(now: before, calendar: calendar))

        let inside = date(2026, 10, 12)
        #expect(parcel.isInWindow(now: inside, calendar: calendar))
        #expect(parcel.isTheDay(now: inside, calendar: calendar))
        #expect(!parcel.isApproximate(now: inside, calendar: calendar))
        #expect(parcel.daysLeft(now: inside, calendar: calendar) == 3)

        // Gone only once the last day has passed.
        #expect(!parcel.hasPassed(now: date(2026, 10, 15, hour: 23), calendar: calendar))
        #expect(parcel.hasPassed(now: date(2026, 10, 16), calendar: calendar))
    }

    @Test func aRepeatingDayHasNoWindow() {
        let yearly = countdown(on: date(2026, 10, 4), rule: RepeatRule(frequency: .yearly))
        yearly.windowEnd = date(2026, 10, 15)
        #expect(yearly.window(calendar: calendar) == nil)
        #expect(yearly.daysLeft(now: date(2026, 9, 25), calendar: calendar) == 9)
    }

    @Test func theMomentIsEachTimeRoundAtItsTime() {
        let weekly = countdown(on: date(2026, 10, 5, hour: 18, minute: 30), rule: RepeatRule(frequency: .weekly))
        #expect(weekly.moment(now: date(2026, 10, 1), calendar: calendar) == nil)
        weekly.hasTime = true
        #expect(weekly.moment(now: date(2026, 10, 1), calendar: calendar) == date(2026, 10, 5, hour: 18, minute: 30))
        #expect(weekly.moment(now: date(2026, 10, 7), calendar: calendar) == date(2026, 10, 12, hour: 18, minute: 30))

        let timer = countdown(on: date(2026, 10, 5, hour: 23, minute: 59))
        timer.isTimer = true
        #expect(timer.moment(calendar: calendar) == date(2026, 10, 5, hour: 23, minute: 59))
    }

    @Test func postponingKeepsTheHistoryAndBringsItBack() {
        let trip = countdown(on: date(2026, 10, 10))
        trip.isArchived = true
        trip.postpone(to: date(2026, 10, 14), windowEnd: nil, now: date(2026, 10, 11), calendar: calendar)
        trip.postpone(to: date(2026, 10, 18), windowEnd: date(2026, 10, 20), now: date(2026, 10, 11), calendar: calendar)
        #expect(trip.postponedFrom == [date(2026, 10, 10), date(2026, 10, 14)])
        #expect(trip.date == date(2026, 10, 18))
        #expect(trip.windowEnd == date(2026, 10, 20))
        #expect(!trip.isArchived)
    }

    @Test func liveActivityShowsFromItsLeadOrWhenForced() {
        let trip = countdown(on: date(2026, 10, 20))
        let now = date(2026, 10, 17)
        #expect(!trip.wantsLiveActivity(now: now, calendar: calendar))
        trip.showsLiveActivity = true
        #expect(!trip.wantsLiveActivity(now: now, calendar: calendar))
        #expect(trip.wantsLiveActivity(now: date(2026, 10, 20), calendar: calendar))
        trip.liveActivityLead = 3
        #expect(trip.wantsLiveActivity(now: now, calendar: calendar))
        #expect(!trip.wantsLiveActivity(now: date(2026, 10, 16), calendar: calendar))
        trip.liveActivityForced = true
        #expect(trip.wantsLiveActivity(now: date(2026, 10, 1), calendar: calendar))
        // Not once it has passed or is done.
        #expect(!trip.wantsLiveActivity(now: date(2026, 10, 21), calendar: calendar))
        trip.markDone(now: date(2026, 10, 20), calendar: calendar)
        #expect(!trip.wantsLiveActivity(now: date(2026, 10, 20), calendar: calendar))

        // A window shows all through it.
        let parcel = countdown(on: date(2026, 10, 4))
        parcel.windowEnd = date(2026, 10, 15)
        parcel.showsLiveActivity = true
        #expect(parcel.wantsLiveActivity(now: date(2026, 10, 10), calendar: calendar))
        #expect(!parcel.wantsLiveActivity(now: date(2026, 10, 2), calendar: calendar))
    }

    @Test func aTimerRunsUntilItEnds() {
        let timer = countdown(on: date(2026, 10, 5, hour: 15))
        timer.isTimer = true
        timer.showsLiveActivity = true
        #expect(timer.wantsLiveActivity(now: date(2026, 10, 5, hour: 14), calendar: calendar))
        #expect(!timer.wantsLiveActivity(now: date(2026, 10, 5, hour: 16), calendar: calendar))
    }
}
