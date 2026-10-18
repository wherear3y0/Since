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

    @Test func waitingToBePickedUp() {
        let draft = ParcelParser.parse([
            "Wildberries", "Ожидает в пункте выдачи", "Пункт выдачи Wildberries, ул. Тверская, 7",
            "Хранится до 9 октября", "Код получения", "452 118", "Кроссовки беговые Asics Gel",
        ], now: now, calendar: calendar)
        #expect(draft.pickupCode == "452118")
        #expect(ymd(draft.storageUntil) == day(10, 9))
        #expect(draft.pickupPoint == "Wildberries, ул. Тверская, 7")
        // It's there already: the storage day isn't when it comes.
        #expect(ymd(draft.from) == day(10, 1))
        #expect(draft.to == nil)
        #expect(draft.title == "Кроссовки беговые Asics Gel")

        let english = ParcelParser.parse(["Ready for pickup", "Pickup code: 7731", "Pick up by Oct 6"],
                                         now: now, calendar: calendar)
        #expect(english.pickupCode == "7731")
        #expect(ymd(english.storageUntil) == day(10, 6))
        #expect(ymd(ParcelParser.parse(["Срок хранения до 12.10"], now: now, calendar: calendar).storageUntil)
                == day(10, 12))
        // An order number on the line after isn't a code.
        #expect(ParcelParser.parse(["Код получения придёт в СМС", "Заказ 12345678901"], now: now, calendar: calendar)
                .pickupCode == nil)
    }

    @MainActor @Test func aReminderBeforeTheLastDay() {
        let parcel = Countdown(title: "Sneakers", symbol: "shippingbox.fill", color: .orange, date: now)
        parcel.isParcel = true
        parcel.pickupCode = "452118"
        parcel.storageUntil = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))
        let reminders = Milestones.storageReminders(for: parcel, now: now, calendar: calendar)
        #expect(reminders.map { ymd($0.date) } == [day(10, 4), day(10, 5)])
        #expect(reminders[0].name == "Pick it up by tomorrow. Code 452118.")
        #expect(parcel.spacedPickupCode == "452 118")
        #expect(parcel.storageDaysLeft(now: now, calendar: calendar) == 4)
        parcel.markDone(now: now, calendar: calendar)
        #expect(Milestones.storageReminders(for: parcel, now: now, calendar: calendar).isEmpty)
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

    @Test func ozonDeliveryAndItsOrderNumber() {
        let draft = ParcelParser.parse(["Ozon", "Заказ № 12345678-0001-1", "Доставка завтра"],
                                       now: now, calendar: calendar)
        #expect(draft.carrier == .ozon)
        #expect(draft.trackingNumber == "12345678-0001-1")
        #expect(!Carrier.ozon.takesNumber)
        #expect(Carrier.ozon.trackURL(draft.trackingNumber!)?.absoluteString == "https://www.ozon.ru/my/orderlist/")
        #expect(ParcelParser.parse(["Ozon", "СДЭК", "Трек-номер 1234567890"], now: now, calendar: calendar)
            .carrier == .cdek)
    }

    @Test func everyCarrierHasAnHTTPSDestination() {
        for carrier in Carrier.allCases {
            let url = carrier.trackURL("A 12&34/56?#")
            #expect(url?.scheme == "https")
            #expect(url?.host != nil)
            if carrier.takesNumber {
                #expect(url?.absoluteString.contains("A%2012%2634%2F56%3F%23") == true)
            }
        }
    }

    @MainActor @Test func existingOzonParcelsResolveTheirCarrierWithoutAMigration() {
        let parcel = Countdown(title: "Headphones", symbol: "shippingbox.fill", color: .orange, date: now)
        parcel.isParcel = true
        parcel.shopName = "Ozon"
        #expect(parcel.carrier == .ozon)
        parcel.trackingNumber = "RA123456785RU"
        #expect(parcel.carrier == .russianPost)
        parcel.carrier = .cdek
        #expect(parcel.carrier == .cdek)
        parcel.style = .timeline
        #expect(parcel.style == .timeline)
    }
}
