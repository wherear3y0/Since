import Foundation
import Testing
@testable import Since

/// Things you have: the days since you got one, until it's gone; and the day it was got, read off a screenshot.
struct OwnedTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func ymd(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    @Test func theCountStopsOnceItsGone() {
        let bike = Counter(title: "Bike", symbol: "bicycle", color: .green, kind: .owned, startDate: date(2026, 1, 1))
        #expect(bike.days(on: date(2026, 3, 1), calendar: calendar) == 59)
        bike.letGo(on: date(2026, 3, 1), reason: .sold)
        #expect(bike.isGone)
        #expect(bike.days(on: date(2026, 10, 1), calendar: calendar) == 59)
        #expect(bike.goneReason == .sold)

        // Never gone before it was got.
        bike.letGo(on: date(2025, 12, 1), reason: nil)
        #expect(bike.goneDate == date(2026, 1, 1))
        #expect(bike.goneReason == nil)

        bike.keep()
        #expect(!bike.isGone)
        #expect(bike.days(on: date(2026, 10, 1), calendar: calendar) == 273)
    }

    @Test func nextAnniversary() {
        let phone = Counter(title: "iPhone", symbol: "iphone", color: .cyan, kind: .owned, startDate: date(2025, 10, 18))
        let before = phone.nextAnniversary(now: date(2026, 10, 1), calendar: calendar)
        #expect(before?.years == 1)
        #expect(ymd(before?.date) == day(2026, 10, 18))
        // On the day it's that one.
        #expect(phone.nextAnniversary(now: date(2026, 10, 18), calendar: calendar)?.years == 1)
        #expect(phone.nextAnniversary(now: date(2026, 10, 19), calendar: calendar)?.years == 2)
        phone.letGo(on: date(2026, 10, 1), reason: .lost)
        #expect(phone.nextAnniversary(now: date(2026, 10, 2), calendar: calendar) == nil)
    }

    @Test func theDayItWasGot() {
        let now = date(2026, 10, 1)
        let got = { (lines: [String]) in ymd(ParcelParser.parse(lines, now: now, calendar: calendar).got) }
        #expect(got(["Заказ получен", "Получен 28 сентября", "Наушники Sony WH-1000XM5"]) == day(2026, 9, 28))
        #expect(got(["Delivered Sep 2", "Mechanical keyboard"]) == day(2026, 9, 2))
        #expect(got(["Кассовый чек", "18.09.2026 14:32", "Итого 24 990"]) == day(2026, 9, 18))
        #expect(got(["Заказ от 28 сентября", "Доставка 4–15 октября"]) == day(2026, 9, 28))
        // A delivery already gone by: its last day.
        #expect(got(["Доставка 20–25 сентября"]) == day(2026, 9, 25))
        // Still ahead: not got yet.
        #expect(got(["Получение 4 октября"]) == nil)

        let january = date(2027, 1, 5)
        #expect(ymd(ParcelParser.parse(["Получен 28 декабря"], now: january, calendar: calendar).got)
                == day(2026, 12, 28))
    }
}
