import Foundation

/// Text and a link supplied by a share sheet. A link identifies the shop only by its actual host,
/// never by a shop name in a query string or in a lookalike domain.
nonisolated struct ParcelShare {
    var draft: ParcelDraft
    var orderURL: URL?
    var trackingURL: URL?

    init(text: String, url: URL? = nil, now: Date = .now, calendar: Calendar = .app) {
        let embedded = text.range(of: #"https?://[^\s<>]+"#, options: .regularExpression).flatMap {
            URL(string: String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}")))
        }
        orderURL = Self.webURL(url) ?? Self.webURL(embedded)
        if let link = orderURL, ParcelTracking.isTrackingPage(link) {
            trackingURL = link
            orderURL = nil
        }
        let lines = text.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft = ParcelParser.parse(lines, now: now, calendar: calendar)
        if let trackingURL {
            let parsed = ParcelTracking(trackingURL.absoluteString)
            draft.trackingNumber = draft.trackingNumber ?? parsed.number
            draft.carrier = draft.carrier ?? parsed.carrier
        }
        if draft.shop == nil, let host = (orderURL ?? trackingURL)?.host?.lowercased() {
            let shops = [("ozon.ru", "Ozon"), ("ozon.com", "Ozon"), ("wildberries.ru", "Wildberries"),
                         ("wb.ru", "Wildberries"), ("avito.ru", "Avito"), ("market.yandex.ru", "Яндекс Маркет"),
                         ("aliexpress.com", "AliExpress"), ("aliexpress.ru", "AliExpress")]
            draft.shop = shops.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1
        }
        if draft.carrier == nil {
            if draft.shop == "Ozon" { draft.carrier = .ozon }
            if draft.shop == "Avito" { draft.carrier = .avito }
        }
        if draft.title == nil {
            let metadata = ["заказ", "достав", "трек", "номер", "код", "хранит", "order", "tracking", "delivery"]
            draft.title = lines.first { line in
                line != draft.shop && line.count >= 2 && line.contains(where: \.isLetter)
                    && !metadata.contains(where: { line.lowercased().contains($0) })
            }.map { String($0.prefix(100)) }
        }
    }

    static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
