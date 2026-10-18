import Foundation

/// Who brings a parcel: where "Track" opens with the number filled in.
nonisolated enum Carrier: String, CaseIterable, Identifiable {
    case russianPost, cdek, boxberry, avito, cainiao, dhl, ups, fedex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .russianPost: "Russian Post"
        case .cdek: "CDEK"
        case .boxberry: "Boxberry"
        case .avito: "Avito Delivery"
        case .cainiao: "Cainiao"
        case .dhl: "DHL"
        case .ups: "UPS"
        case .fedex: "FedEx"
        }
    }

    func trackURL(_ number: String) -> URL? {
        let number = number.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? number
        let link = switch self {
        case .russianPost: "https://www.pochta.ru/tracking?barcode=\(number)"
        case .cdek: "https://www.cdek.ru/ru/tracking/?order_id=\(number)"
        case .boxberry: "https://boxberry.ru/tracking-page?id=\(number)"
        // Avito has no page that takes a number: its orders, which open in the Avito app when it's there.
        case .avito: "https://www.avito.ru/orders"
        case .cainiao: "https://global.cainiao.com/newDetail.htm?mailNoList=\(number)"
        case .dhl: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=\(number)&submit=1"
        case .ups: "https://www.ups.com/track?tracknum=\(number)"
        case .fedex: "https://www.fedex.com/fedextrack/?trknbr=\(number)"
        }
        return URL(string: link)
    }

    /// Its tracking page has the number filled in. When it doesn't, the number is copied for pasting there.
    var takesNumber: Bool { self != .avito }

    /// The carrier a tracking number looks like it's from, when that can be told from the number alone.
    static func guess(_ number: String) -> Carrier? {
        let number = number.uppercased()
        if number.wholeMatch(of: /[A-Z]{2}\d{9}RU/) != nil || number.wholeMatch(of: /\d{14}/) != nil {
            return .russianPost
        }
        if number.wholeMatch(of: /1Z[0-9A-Z]{16}/) != nil {
            return .ups
        }
        if number.wholeMatch(of: /(LP|CN|YT|AEL)\d{12,16}/) != nil {
            return .cainiao
        }
        return nil
    }

    /// Where a tracking number with no known carrier can be looked up. It only takes the number typed
    /// into its form, so the number is copied for pasting there.
    static let lookUpURL = URL(string: "https://gdeposylka.ru/")!
}

/// What could be read off a screenshot of an order.
nonisolated struct ParcelDraft: Equatable {
    var title: String?
    var shop: String?
    var trackingNumber: String?
    var carrier: Carrier?
    /// The day it should come, or the first day of the window.
    var from: Date?
    /// The last day of the window; nil for a single day.
    var to: Date?
    /// The day it came or was bought, when that's already behind: for a thing that's had now.
    var got: Date?
    /// The code a pickup point asks for, and the last day it keeps the parcel.
    var pickupCode: String?
    var storageUntil: Date?
    /// Where it's picked up, as written: "Ozon, ул. Тверская, 7".
    var pickupPoint: String?
}

/// Reads an order's details out of the lines of text recognized on a screenshot: the delivery dates
/// ("4–15 октября", "Oct 28 – Nov 2", "завтра"), the tracking number, the shop and the product's name.
nonisolated enum ParcelParser {
    static func parse(_ lines: [String], now: Date = .now, calendar: Calendar = .app) -> ParcelDraft {
        // A name broken over two lines with a hyphen ("Sony WH-" / "1000XM5") is put back together.
        var joined: [String] = []
        for line in lines.map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if let last = joined.last, last.hasSuffix("-"), last.count > 1 {
                joined[joined.count - 1] = last + line
            } else {
                joined.append(line)
            }
        }
        let lines = joined
        var draft = ParcelDraft()
        draft.pickupCode = pickupCode(in: lines)
        draft.storageUntil = storageUntil(in: lines, now: now, calendar: calendar)
        draft.pickupPoint = pickupPoint(in: lines)
        draft.shop = shop(in: lines)
        (draft.trackingNumber, draft.carrier) = tracking(in: lines)
        // Bought on Avito with no other carrier named or told by the number: Avito's own delivery.
        if draft.carrier == nil && draft.shop == "Avito" {
            draft.carrier = .avito
        }
        // The last day it's kept isn't when it comes; one waiting to be picked up is here already.
        (draft.from, draft.to) = dates(in: lines.filter { !isAboutStorage($0) }, now: now, calendar: calendar)
        if draft.from == nil && draft.storageUntil != nil {
            draft.from = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)
        }
        draft.got = got(in: lines, delivery: draft.to ?? draft.from, now: now, calendar: calendar)
        draft.title = title(in: lines, shop: draft.shop)
        return draft
    }

    // MARK: - Shop and carrier

    private static let shops: [(name: String, words: [String])] = [
        ("Ozon", ["ozon", "озон"]),
        ("Wildberries", ["wildberries", "вайлдберриз", "вайлдбериз"]),
        ("Яндекс Маркет", ["яндекс маркет", "яндекс.маркет", "market.yandex"]),
        ("AliExpress", ["aliexpress", "алиэкспресс"]),
        ("Мегамаркет", ["мегамаркет", "megamarket"]),
        ("Lamoda", ["lamoda", "ламода"]),
        ("Золотое Яблоко", ["золотое яблоко", "goldapple"]),
        ("Avito", ["avito", "авито"]),
        ("М.Видео", ["м.видео", "mvideo"]),
        ("Ситилинк", ["ситилинк", "citilink"]),
        ("Amazon", ["amazon"]),
        ("Temu", ["temu"]),
        ("Shein", ["shein"]),
        ("eBay", ["ebay"]),
    ]

    private static let carriers: [(carrier: Carrier, words: [String])] = [
        (.russianPost, ["почта россии", "pochta"]),
        (.cdek, ["сдэк", "cdek"]),
        (.boxberry, ["boxberry", "боксберри"]),
        (.avito, ["авито доставка", "авито доставки", "авито доставкой", "авито доставку", "avito доставка",
                  "avito delivery"]),
        (.cainiao, ["cainiao"]),
        (.dhl, ["dhl"]),
        (.ups, ["ups"]),
        (.fedex, ["fedex"]),
    ]

    private static func shop(in lines: [String]) -> String? {
        let text = lines.joined(separator: "\n").lowercased()
        return shops.first { shop in shop.words.contains { text.contains($0) } }?.name
    }

    // MARK: - Tracking number

    private static let trackingWords = ["трек", "track", "отправлени", "почтовый идентификатор", "tracking"]

    /// A tracking number: one in a carrier's known form anywhere, or a long code on a line that says it's one.
    private static func tracking(in lines: [String]) -> (String?, Carrier?) {
        let text = lines.joined(separator: "\n").lowercased()
        let named = carriers.first { carrier in carrier.words.contains { word in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        } }?.carrier

        for line in lines {
            for token in tokens(in: line) {
                if let carrier = Carrier.guess(token) {
                    return (token, carrier)
                }
            }
        }
        for line in lines where trackingWords.contains(where: { line.lowercased().contains($0) }) {
            if let token = tokens(in: line).first(where: { $0.filter(\.isNumber).count >= 5 }) {
                return (token, Carrier.guess(token) ?? named)
            }
        }
        // A CDEK number is ten digits: only taken when CDEK is named.
        if named == .cdek, let token = lines.lazy.flatMap({ tokens(in: $0) }).first(where: {
            $0.wholeMatch(of: /\d{10}/) != nil
        }) {
            return (token, .cdek)
        }
        return (nil, named)
    }

    /// Codes of 8 to 30 letters and digits with at least one digit, spaces inside a number of digits closed up.
    private static func tokens(in line: String) -> [String] {
        let joinedDigits = line.replacing(/(\d) (?=\d)/) { String($0.output.1) }
        return joinedDigits.uppercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                (8...30).contains(token.count) && token.contains { $0.isNumber } && token.allSatisfy { $0.isASCII }
            }
    }

    // MARK: - Dates

    private static let months: [(prefix: String, month: Int)] = [
        ("янв", 1), ("фев", 2), ("мар", 3), ("апр", 4), ("мая", 5), ("май", 5), ("июн", 6), ("июл", 7),
        ("авг", 8), ("сен", 9), ("окт", 10), ("ноя", 11), ("дек", 12),
        ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("may", 5), ("jun", 6), ("jul", 7), ("aug", 8),
        ("sep", 9), ("oct", 10), ("nov", 11), ("dec", 12),
    ]

    private static func month(_ word: Substring) -> Int? {
        let word = word.lowercased()
        return months.first { word.hasPrefix($0.prefix) }?.month
    }

    private static let deliveryWords = ["достав", "привез", "получ", "ожида", "прибуд", "приед", "arriv", "deliver",
                                        "expected", "estimated", "get it"]
    private static let orderedWords = ["заказ от", "оформлен", "оплачен", "ordered", "placed", "paid"]

    /// The delivery window or day: a range anywhere, else a day on a line about delivery, else any day not
    /// on a line about when it was ordered, else "today" or "tomorrow".
    private static func dates(in lines: [String], now: Date, calendar: Calendar) -> (Date?, Date?) {
        let texts = lines.map { $0.lowercased().replacing(/[–—−]/, with: "-").replacing("ё", with: "е") }
        let day = { (d: Substring, m: Substring) -> Date? in
            guard let month = month(m), let d = Int(d) else { return nil }
            return date(day: d, month: month, now: now, calendar: calendar)
        }

        for text in texts where !orderedWords.contains(where: { text.contains($0) }) {
            // 28 окт - 2 ноя
            for m in text.matches(of: /(\d{1,2})\s+([a-zа-я]{3,})\s*(?:-|по|до|to)\s*(\d{1,2})\s+([a-zа-я]{3,})/) {
                if let a = day(m.output.1, m.output.2), let b = day(m.output.3, m.output.4) {
                    return ordered(a, b, calendar: calendar)
                }
            }
            // oct 28 - nov 2
            for m in text.matches(of: /([a-z]{3,})\s+(\d{1,2})\s*(?:-|to)\s*([a-z]{3,})\s+(\d{1,2})/) {
                if let a = day(m.output.2, m.output.1), let b = day(m.output.4, m.output.3) {
                    return ordered(a, b, calendar: calendar)
                }
            }
            // 4-15 октября, с 4 по 15 октября
            for m in text.matches(of: /(\d{1,2})\s*(?:-|по|до)\s*(\d{1,2})\s+([a-zа-я]{3,})/) {
                if let a = day(m.output.1, m.output.3), let b = day(m.output.2, m.output.3) {
                    return ordered(a, b, calendar: calendar)
                }
            }
            // oct 4-15
            for m in text.matches(of: /([a-z]{3,})\s+(\d{1,2})\s*(?:-|to)\s*(\d{1,2})/) {
                if let a = day(m.output.2, m.output.1), let b = day(m.output.3, m.output.1) {
                    return ordered(a, b, calendar: calendar)
                }
            }
        }

        let single = { (text: String) -> Date? in
            for m in text.matches(of: /(\d{1,2})\s+([a-zа-я]{3,})/) {
                if let date = day(m.output.1, m.output.2) {
                    return date
                }
            }
            for m in text.matches(of: /([a-z]{3,})\s+(\d{1,2})/) {
                if let date = day(m.output.2, m.output.1) {
                    return date
                }
            }
            return nil
        }
        let relative = { (text: String) -> Date? in
            let today = calendar.startOfDay(for: now)
            let offset = text.contains("послезавтра") ? 2
                : (text.contains("завтра") || text.contains("tomorrow")) ? 1
                : (text.contains("сегодня") || text.contains("today")) ? 0 : nil
            return offset.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }
        }
        for text in texts where deliveryWords.contains(where: { text.contains($0) }) {
            if let date = single(text) ?? relative(text) {
                return (date, nil)
            }
        }
        for text in texts where !orderedWords.contains(where: { text.contains($0) }) {
            if let date = single(text) {
                return (date, nil)
            }
        }
        for text in texts {
            if let date = relative(text) {
                return (date, nil)
            }
        }
        return (nil, nil)
    }

    private static func ordered(_ a: Date, _ b: Date, calendar: Calendar) -> (Date?, Date?) {
        // "28 Dec – 3 Jan": the end is in the next year.
        let b = b < a ? calendar.date(byAdding: .year, value: 1, to: b)! : b
        return (a, b == a ? nil : b)
    }

    /// A day this year, or next year when it would be long gone (a delivery is ahead, or only just behind).
    private static func date(day: Int, month: Int, now: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return nil
        }
        if date < calendar.date(byAdding: .day, value: -60, to: now)! {
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
        return date
    }

    // MARK: - Picking it up

    private static let codeWords = ["код получ", "код для получ", "код выдач", "код для выдач", "код подтвержд",
                                    "pickup code", "pick-up code", "pin code", "пин-код", "пин код"]
    private static let storageWords = ["хранит", "срок хранения", "заберите до", "забрать до", "забрать можно до",
                                       "ждет вас до", "ждет до", "pick up by", "pick it up by", "available until",
                                       "held until", "hold until"]
    private static let pointWords = ["пункт выдачи", "пвз", "постамат", "pickup point", "pick-up point",
                                     "адрес получения", "адрес пункта"]

    private static func isAboutStorage(_ line: String) -> Bool {
        let text = line.lowercased().replacing("ё", with: "е")
        return storageWords.contains { text.contains($0) }
    }

    /// The digits after "Код получения" on its line, or on the line under it when they're shown big there.
    private static func pickupCode(in lines: [String]) -> String? {
        let digits = { (text: Substring) -> String? in
            let code = text.filter(\.isNumber)
            return (3...8).contains(code.count) ? String(code) : nil
        }
        for (index, line) in lines.enumerated() {
            let text = line.lowercased()
            guard let word = codeWords.first(where: { text.contains($0) }),
                  let range = text.range(of: word) else { continue }
            // "123 456" and "123-456" count as one code; anything after it on the line doesn't.
            let rest = text[range.upperBound...]
            if let m = rest.firstMatch(of: /\d[\d \-]{1,10}\d/), let code = digits(m.output) {
                return code
            }
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if next.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }), let code = digits(Substring(next)) {
                    return code
                }
            }
        }
        return nil
    }

    /// "Хранится до 25 октября", "Срок хранения до 25.10", "Pick up by Oct 25": a day ahead, or only just gone.
    private static func storageUntil(in lines: [String], now: Date, calendar: Calendar) -> Date? {
        for line in lines where isAboutStorage(line) {
            let text = line.lowercased().replacing("ё", with: "е")
            if let m = text.firstMatch(of: /(\d{1,2})\s+([a-zа-я]{3,})/), let month = month(m.output.2),
               let d = Int(m.output.1), let date = date(day: d, month: month, now: now, calendar: calendar) {
                return date
            }
            if let m = text.firstMatch(of: /([a-z]{3,})\s+(\d{1,2})/), let month = month(m.output.1),
               let d = Int(m.output.2), let date = date(day: d, month: month, now: now, calendar: calendar) {
                return date
            }
            if let m = text.firstMatch(of: /(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?/), let d = Int(m.output.1),
               let month = Int(m.output.2), (1...12).contains(month),
               let date = date(day: d, month: month, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    /// The pickup point's line, without the words that say it's one: what Maps is asked to find.
    private static func pickupPoint(in lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            guard let word = pointWords.first(where: { lowered.contains($0) }), let range = lowered.range(of: word) else {
                continue
            }
            let rest = line[line.index(line.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.upperBound))...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " :—–-,").union(.whitespaces))
            // Something that looks like an address: a street, a building number.
            if rest.count >= 5 && rest.contains(where: \.isNumber) {
                return rest
            }
        }
        return nil
    }

    // MARK: - The day it was got

    private static let gotWords = ["получен", "доставлен", "вручен", "delivered", "received", "picked up"]
    private static let boughtWords = ["заказ от", "оформлен", "оплачен", "куплен", "покупк", "ordered", "placed",
                                      "paid", "purchased", "bought"]

    /// The day it came, else the day it was bought (a receipt's "18.09.2026" too), else a delivery day
    /// that's already gone by. Never a day still ahead.
    private static func got(in lines: [String], delivery: Date?, now: Date, calendar: Calendar) -> Date? {
        let texts = lines.map { $0.lowercased().replacing("ё", with: "е") }
        let past = { (d: Substring, m: Substring) -> Date? in
            guard let month = month(m), let d = Int(d) else { return nil }
            return pastDate(day: d, month: month, now: now, calendar: calendar)
        }
        let named = { (text: String) -> Date? in
            for m in text.matches(of: /(\d{1,2})\s+([a-zа-я]{3,})/) {
                if let date = past(m.output.1, m.output.2) {
                    return date
                }
            }
            for m in text.matches(of: /([a-z]{3,})\s+(\d{1,2})/) {
                if let date = past(m.output.2, m.output.1) {
                    return date
                }
            }
            return nil
        }
        for words in [gotWords, boughtWords] {
            for text in texts where words.contains(where: { text.contains($0) }) {
                if let date = named(text) ?? numericDate(in: text, now: now, calendar: calendar) {
                    return date
                }
            }
        }
        for text in texts {
            if let date = numericDate(in: text, now: now, calendar: calendar) {
                return date
            }
        }
        if let delivery, calendar.startOfDay(for: delivery) <= calendar.startOfDay(for: now) {
            return delivery
        }
        return nil
    }

    /// "18.09.2026" or "18.09.26", as on a receipt; only a day already come.
    private static func numericDate(in text: String, now: Date, calendar: Calendar) -> Date? {
        for m in text.matches(of: /(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})\b/) {
            guard let day = Int(m.output.1), let month = Int(m.output.2), var year = Int(m.output.3),
                  (1...31).contains(day), (1...12).contains(month) else { continue }
            if year < 100 {
                year += 2000
            }
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
               calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) {
                return date
            }
        }
        return nil
    }

    /// A day this year, or last year when this year's is far ahead. One only a little ahead isn't behind yet.
    private static func pastDate(day: Int, month: Int, now: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return nil
        }
        if calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) {
            return date
        }
        if date > calendar.date(byAdding: .day, value: 60, to: now)! {
            return calendar.date(byAdding: .year, value: -1, to: date)
        }
        return nil
    }

    // MARK: - Title

    /// Words of the shop's own screens, not of a product.
    private static let screenWords = ["заказ", "доставк", "курьер", "пункт", "оплач", "получ", "трек", "статус",
                                      "хранит", "код", "пвз", "постамат", "заберите", "pick up", "pickup",
                                      "отследить", "order", "delivery", "track", "status", "shipped", "подробнее",
                                      "итого", "total", "адрес", "address", "ожида", "отмен", "вернуть", "чек"]

    /// The product's name: the longest line of several words that's mostly letters and isn't about the order.
    private static func title(in lines: [String], shop: String?) -> String? {
        let candidates = lines.filter { line in
            let lowered = line.lowercased()
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            return line.count >= 10 && line.split(separator: " ").count >= 2 && digits * 4 < letters
                && !screenWords.contains { lowered.contains($0) }
                && month(lowered.split(separator: " ").last ?? "") == nil
                && lowered != shop?.lowercased()
        }
        guard let best = candidates.max(by: { $0.count < $1.count }) else { return nil }
        return best.count > 60 ? String(best.prefix(57)) + "…" : best
    }
}

extension Countdown {
    var carrier: Carrier? {
        get { Carrier(rawValue: carrierRaw) ?? trackingNumber.flatMap(Carrier.guess) }
        set { carrierRaw = newValue?.rawValue ?? "" }
    }

    /// "452 118": a code in two halves, easier to read out at the pickup point.
    var spacedPickupCode: String? {
        guard let code = pickupCode else { return nil }
        guard code.count >= 6, code.count % 2 == 0, code.allSatisfy(\.isNumber) else { return code }
        return "\(code.prefix(code.count / 2)) \(code.suffix(code.count / 2))"
    }

    /// Days left at the pickup point: 0 on the last day, below 0 once it's over. Nil without a deadline.
    func storageDaysLeft(now: Date = .now, calendar: Calendar = .app) -> Int? {
        storageUntil.map { DayMath.days(from: now, to: $0, calendar: calendar) }
    }

    /// "Ozon · RA123…85RU": where it's from and its number, shortened.
    var parcelLine: String? {
        let number = trackingNumber.map { $0.count > 12 ? "\($0.prefix(5))…\($0.suffix(4))" : $0 }
        let parts = [shopName, number].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
