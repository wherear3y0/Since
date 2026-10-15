import Foundation
import Contacts
import EventKit
import UIKit
import Testing
@testable import Since

@MainActor
struct ImportTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func birthdayWithYearCountsYears() throws {
        let contact = CNMutableContact()
        contact.givenName = "Anna"
        contact.familyName = "Haro"
        contact.birthday = DateComponents(year: 1985, month: 8, day: 29)

        let countdown = try #require(Countdown.birthday(of: contact, color: .pink, sortOrder: 0, calendar: calendar))
        #expect(countdown.title == "Anna Haro")
        #expect(countdown.rule == RepeatRule(frequency: .yearly))
        // The next one is in August 2027.
        #expect(countdown.turns(now: date(2026, 10, 15), calendar: calendar) == 42)
    }

    @Test func birthdayWithoutYearDoesNot() throws {
        let contact = CNMutableContact()
        contact.givenName = "Kate"
        contact.birthday = DateComponents(month: 1, day: 19)

        let countdown = try #require(Countdown.birthday(of: contact, color: .pink, sortOrder: 0, calendar: calendar))
        #expect(countdown.turns(now: date(2026, 10, 15), calendar: calendar) == nil)
        #expect(calendar.dateComponents([.month, .day], from: countdown.target(now: date(2026, 10, 15), calendar: calendar))
                == DateComponents(month: 1, day: 19))
    }

    @Test func contactWithoutBirthdayIsSkipped() {
        let contact = CNMutableContact()
        contact.givenName = "Hank"
        #expect(Countdown.birthday(of: contact, color: .pink, sortOrder: 0) == nil)
    }

    @Test func calendarRepeats() {
        let start = date(2026, 10, 20)
        let weekly = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2,
                                      daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday), EKRecurrenceDayOfWeek(.thursday)],
                                      daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                      daysOfTheYear: nil, setPositions: nil, end: nil)
        #expect(RepeatRule(weekly, start: start, lastTime: nil)
                == RepeatRule(frequency: .weekly, interval: 2, weekdays: [3, 5]))

        let monthly = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: EKRecurrenceEnd(end: date(2027, 3, 1)))
        #expect(RepeatRule(monthly, start: start, lastTime: nil)?.end == date(2027, 3, 1))

        // Ten times: it ends with the last of them in the year ahead.
        let tenTimes = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 10))
        #expect(RepeatRule(tenTimes, start: start, lastTime: date(2026, 10, 29))?.end == date(2026, 10, 29))

        // "The second Tuesday of every month" is finer than Since can follow.
        let secondTuesday = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1,
                                             daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)],
                                             daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                             daysOfTheYear: nil, setPositions: nil, end: nil)
        #expect(RepeatRule(secondTuesday, start: start, lastTime: nil) == nil)
    }

    @Test func eventIcons() {
        #expect(CalendarEvent.symbol(for: "Flight to Tbilisi") == "airplane")
        #expect(CalendarEvent.symbol(for: "Отпуск в Грузии") == "airplane")
        #expect(CalendarEvent.symbol(for: "Team offsite") == "star.fill")
    }

    @Test func nearestPaletteColor() {
        #expect(CounterColor.nearest(to: .systemRed) == .red)
        #expect(CounterColor.nearest(to: UIColor(red: 0.1, green: 0.5, blue: 1, alpha: 1)) == .blue)
    }
}
