import Foundation

/// One input accepts either a number or a complete tracking page, including third-party sites.
/// It never downloads a page or claims to know a carrier from an ambiguous number.
nonisolated struct ParcelTracking: Equatable {
    var number: String?
    var url: URL?
    var carrier: Carrier?
    var isValid = true

    init(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let looksLikeLink = text.contains(":") || text.contains("/") || text.contains(".")
        if looksLikeLink {
            let candidate = text.contains(":") ? text : "https://" + text
            guard !text.contains(where: \.isWhitespace), let link = ParcelShare.webURL(URL(string: candidate)),
                  let host = link.host, host.contains(".") else {
                isValid = false
                return
            }
            url = link
            carrier = Carrier.fromURL(link)
            let keys = ["barcode", "order_id", "mailnolist", "tracking-id", "tracknum", "trknbr",
                        "trackingnumber", "tracking_number", "tracking_numbers", "nums"]
            if let query = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
               let value = query.first(where: { keys.contains($0.name.lowercased()) })?.value {
                let parsed = ParcelTracking(numberOnly: value)
                number = parsed.number
                carrier = carrier ?? parsed.carrier
            }
        } else {
            self = ParcelTracking(numberOnly: text)
        }
    }

    private init(numberOnly: String) {
        let compact = numberOnly.filter { !$0.isWhitespace }
        guard !compact.isEmpty, compact.count <= 100,
              compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            isValid = false
            return
        }
        number = compact
        carrier = Carrier.guess(compact)
    }

    static func isTrackingPage(_ url: URL) -> Bool {
        if let carrier = Carrier.fromURL(url) {
            return carrier.takesNumber || url.path.lowercased().contains("order") || url.path.lowercased().contains("track")
        }
        let host = url.host?.lowercased() ?? ""
        return ["gdeposylka.ru", "17track.net", "parcelsapp.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        } || url.path.lowercased().contains("track")
    }
}

extension Carrier {
    nonisolated static func fromURL(_ url: URL) -> Carrier? {
        guard let host = url.host?.lowercased() else { return nil }
        let domains: [(String, Carrier)] = [("pochta.ru", .russianPost), ("cdek.ru", .cdek),
            ("boxberry.ru", .boxberry), ("ozon.ru", .ozon), ("ozon.com", .ozon), ("avito.ru", .avito),
            ("cainiao.com", .cainiao), ("dhl.com", .dhl), ("ups.com", .ups), ("fedex.com", .fedex)]
        return domains.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1
    }
}

extension Countdown {
    var trackingInput: String { trackingURL ?? trackingNumber ?? "" }
    var parsedTracking: ParcelTracking { ParcelTracking(trackingInput) }

    func setTrackingInput(_ input: String) {
        let parsed = ParcelTracking(input)
        guard parsed.isValid else { return }
        trackingURL = parsed.url?.absoluteString
        trackingNumber = parsed.number
    }

    var parcelTrackingDestination: URL? {
        if let url = parsedTracking.url { return url }
        if let carrier, parsedTracking.number != nil || !carrier.takesNumber {
            return carrier.trackURL(parsedTracking.number ?? "")
        }
        return parsedTracking.number == nil ? nil : Carrier.lookUpURL
    }
}
