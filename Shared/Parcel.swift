import Foundation

/// Who brings a parcel: where "Track" opens with the number filled in.
nonisolated enum Carrier: String, CaseIterable, Identifiable {
    case russianPost, cdek, boxberry, cainiao, dhl, ups, fedex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .russianPost: "Russian Post"
        case .cdek: "CDEK"
        case .boxberry: "Boxberry"
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
        case .cainiao: "https://global.cainiao.com/newDetail.htm?mailNoList=\(number)"
        case .dhl: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=\(number)&submit=1"
        case .ups: "https://www.ups.com/track?tracknum=\(number)"
        case .fedex: "https://www.fedex.com/fedextrack/?trknbr=\(number)"
        }
        return URL(string: link)
    }

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
}

/// Reads an order's details out of the lines of text recognized on a screenshot: the delivery dates
/// ("4–15 октября", "Oct 28 – Nov 2", "завтра"), the tracking number, the shop and the product's name.
nonisolated enum ParcelParser {
    static func parse(_ lines: [String], now: Date = .now, calendar: Calendar = .app) -> ParcelDraft {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var draft = ParcelDraft()
        draft.shop = shop(in: lines)
        (draft.trackingNumber, draft.carrier) = tracking(in: lines)
        (draft.from, draft.to) = dates(in: lines, now: now, calendar: calendar)
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

    // MARK: - Title

    /// Words of the shop's own screens, not of a product.
    private static let screenWords = ["заказ", "доставк", "курьер", "пункт", "оплач", "получ", "трек", "статус",
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
