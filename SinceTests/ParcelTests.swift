import Foundation
import Testing
@testable import Since

/// Reading an order's screenshot, and where its tracking number is looked up.
struct ParcelTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!
    }

    func day(_ month: Int, _ day: Int, year: Int = 2026) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    func ymd(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    @Test func anOzonOrder() {
        let draft = ParcelParser.parse([
            "OZON", "Заказ от 28 сентября", "Наушники беспроводные Sony WH-1000XM5",
            "Доставка 4–15 октября", "Пункт выдачи Ozon", "Трек-номер: RA123456785RU",
        ], now: now, calendar: calendar)
        #expect(draft.shop == "Ozon")
        #expect(draft.trackingNumber == "RA123456785RU")
        #expect(draft.carrier == .russianPost)
        #expect(ymd(draft.from) == day(10, 4))
        #expect(ymd(draft.to) == day(10, 15))
        #expect(draft.title == "Наушники беспроводные Sony WH-1000XM5")
    }

    @Test func aNameBrokenOverTwoLines() {
        let draft = ParcelParser.parse(["Наушники беспроводные Sony WH-", "1000XM5", "Доставка 21–28 октября"],
                                       now: now, calendar: calendar)
        #expect(draft.title == "Наушники беспроводные Sony WH-1000XM5")
    }

    @Test func anEnglishOrderAcrossMonths() {
        let draft = ParcelParser.parse([
            "AliExpress", "Ordered Sep 30", "Mechanical keyboard with brown switches",
            "Estimated delivery Oct 28 - Nov 2", "Tracking number LP00123456789012",
        ], now: now, calendar: calendar)
        #expect(draft.shop == "AliExpress")
        #expect(draft.carrier == .cainiao)
        #expect(ymd(draft.from) == day(10, 28))
        #expect(ymd(draft.to) == day(11, 2))
    }

    @Test func aSingleDayAndTomorrow() {
        let single = ParcelParser.parse(["Wildberries", "Ожидаемая дата доставки 12 октября"], now: now,
                                        calendar: calendar)
        #expect(ymd(single.from) == day(10, 12))
        #expect(single.to == nil)

        let tomorrow = ParcelParser.parse(["Яндекс Маркет", "Привезём завтра"], now: now, calendar: calendar)
        #expect(tomorrow.shop == "Яндекс Маркет")
        #expect(ymd(tomorrow.from) == day(10, 2))
    }

    @Test func aWindowIntoTheNextYear() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 10))!
        let draft = ParcelParser.parse(["Доставка 28 дек - 3 янв"], now: late, calendar: calendar)
        #expect(ymd(draft.from) == day(12, 28))
        #expect(ymd(draft.to) == day(1, 3, year: 2027))
    }

    @Test func cdekOnlyWhenNamed() {
        #expect(ParcelParser.parse(["СДЭК", "Заказ 1234567890"], now: now, calendar: calendar).carrier == .cdek)
        #expect(ParcelParser.parse(["СДЭК", "Номер 1234567890"], now: now, calendar: calendar).trackingNumber == "1234567890")
        #expect(ParcelParser.parse(["Телефон 8 800 1234567"], now: now, calendar: calendar).trackingNumber == nil)
    }

    @Test func avitoDelivery() {
        let named = ParcelParser.parse(["Авито Доставка", "Номер отправления 1234567890123"], now: now, calendar: calendar)
        #expect(named.carrier == .avito)
        // Bought on Avito, sent by a carrier the number tells: that carrier.
        #expect(ParcelParser.parse(["Avito", "Трек-номер RA123456785RU"], now: now, calendar: calendar).carrier
                == .russianPost)
        #expect(ParcelParser.parse(["Avito", "Заказ оформлен"], now: now, calendar: calendar).carrier == .avito)
        #expect(!Carrier.avito.takesNumber)
    }

    @Test func carriersFromNumbers() {
        #expect(Carrier.guess("RA123456785RU") == .russianPost)
        #expect(Carrier.guess("80085123456789") == .russianPost)
        #expect(Carrier.guess("1Z999AA10123456784") == .ups)
        #expect(Carrier.guess("LP00123456789012") == .cainiao)
        #expect(Carrier.guess("XY12345") == nil)
        #expect(Carrier.russianPost.trackURL("RA123456785RU")?.absoluteString
                == "https://www.pochta.ru/tracking?barcode=RA123456785RU")
    }
}
