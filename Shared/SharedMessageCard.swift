import Foundation

/// A bounded snapshot sent with a native iMessage card. No account tokens, database paths or photos.
nonisolated struct SharedMessageCard: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case counter, countdown }
    var version = 1
    var id: UUID
    var kind: Kind
    var title: String
    var symbol: String
    var colorName: String
    var date: Date
    var hasTime = false
    var windowEnd: Date?
    var startDate: Date?
    var counterKind: String?
    var counterEnd: Date?
    var isParcel = false
    var styleRaw: String?
    var placeName: String?
    var placeAddress: String?
    var latitude: Double?
    var longitude: Double?
    var trackingInput: String?
    var carrierRaw: String?
    var shop: String?
    var storageUntil: Date?
    var pickupCode: String?
    var note: String?
    var summary: String?
    var sharedAt: Date = .now

    var color: CounterColor { CounterColor(rawValue: colorName) ?? .cyan }

    func value(now: Date = .now, calendar: Calendar = .app) -> String {
        if kind == .counter {
            let days = DayMath.days(from: date, to: counterEnd.map { min(now, $0) } ?? now, calendar: calendar)
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        if hasTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: now)
        }
        var target = date
        var approximate = false
        if let windowEnd {
            let today = calendar.startOfDay(for: now)
            let first = calendar.startOfDay(for: date)
            let last = calendar.startOfDay(for: windowEnd)
            if (first...last).contains(today) { return "Any day" }
            approximate = today < first
            target = approximate ? calendar.date(byAdding: .day, value: DayMath.days(from: first, to: last, calendar: calendar) / 2,
                                                  to: first) ?? first : last
        }
        let days = DayMath.daysUntil(target, from: now, calendar: calendar)
        return days == 0 ? "Today" : "\(approximate ? "~" : "")\(abs(days)) \(abs(days) == 1 ? "day" : "days")\(days < 0 ? " ago" : " left")"
    }

    var dateLine: String {
        let first = date.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
        if let windowEnd { return "\(first) – \(windowEnd.formatted(date: .abbreviated, time: .omitted))" }
        return kind == .counter ? "Since \(first)" : first
    }

    var mapsURL: URL? {
        let place = [placeName, placeAddress].compactMap { $0 }.joined(separator: ", ")
        guard latitude != nil || !place.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        var query = [URLQueryItem(name: "q", value: place.isEmpty ? "Event" : place)]
        if let latitude, let longitude {
            query.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        }
        components.queryItems = query
        return components.url
    }

    var locationLine: String? {
        let text = [placeName, placeAddress == placeName ? nil : placeAddress].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        if !text.isEmpty { return text }
        if let latitude, let longitude { return String(format: "%.4f, %.4f", latitude, longitude) }
        return nil
    }

    var trackURL: URL? {
        let parsed = ParcelTracking(trackingInput ?? "")
        guard parsed.isValid else { return nil }
        if let url = parsed.url { return url }
        let carrier = carrierRaw.flatMap(Carrier.init(rawValue:)) ?? parsed.carrier
        if let carrier, parsed.number != nil || !carrier.takesNumber { return carrier.trackURL(parsed.number ?? "") }
        return parsed.number == nil ? nil : Carrier.lookUpURL
    }

    func sharing(location: Bool, note: Bool, pickupCode: Bool) -> Self {
        var copy = self
        if !location {
            copy.placeName = nil; copy.placeAddress = nil; copy.latitude = nil; copy.longitude = nil
        }
        if !note { copy.note = nil }
        if !pickupCode { copy.pickupCode = nil }
        return copy
    }

    enum PayloadError: Error, Equatable, LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: "This card contains invalid dates or tracking details. Check them before sharing."
            case .tooLarge: "This card has too much text for an interactive message. Use Picture, or leave out the note."
            }
        }
    }

    private static let dataPrefix = "data:application/vnd.since.card+json;base64,"

    func encodedURL() throws -> URL {
        guard isValid else { throw PayloadError.invalid }
        let data = try JSONEncoder().encode(self)
        // MSMessage only accepts http, https or data URLs, with a 5,000-character limit.
        guard data.count <= 3600 else { throw PayloadError.tooLarge }
        let string = Self.dataPrefix + data.base64EncodedString()
        guard string.count <= 5000 else { throw PayloadError.tooLarge }
        guard let result = URL(string: string) else { throw PayloadError.invalid }
        return result
    }

    static func decode(_ url: URL) throws -> Self {
        let string = url.absoluteString
        guard string.utf8.count <= 5000, string.hasPrefix(dataPrefix),
              let data = Data(base64Encoded: String(string.dropFirst(dataPrefix.count))),
              data.count <= 3600 else { throw PayloadError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.isValid else { throw PayloadError.invalid }
        return value
    }

    private var isValid: Bool {
        let dates: [Date?] = [date, sharedAt, windowEnd, startDate, counterEnd, storageUntil]
        guard version == 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, symbol.count <= 100, colorName.count <= 30,
              dates.compactMap({ $0 }).allSatisfy({
                  $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > -62_135_596_800
                      && $0.timeIntervalSince1970 < 253_402_300_800
              }),
              (windowEnd == nil || windowEnd! >= date),
              (counterEnd == nil || counterEnd! >= date),
              (note?.count ?? 0) <= 1500, (summary?.count ?? 0) <= 500,
              (placeName?.count ?? 0) <= 300, (placeAddress?.count ?? 0) <= 500,
              (trackingInput?.count ?? 0) <= 3000, (pickupCode?.count ?? 0) <= 100,
              (shop?.count ?? 0) <= 200, (carrierRaw?.count ?? 0) <= 50,
              (counterKind?.count ?? 0) <= 50, ParcelTracking(trackingInput ?? "").isValid else { return false }
        guard (styleRaw?.count ?? 0) <= 30 else { return false }
        if latitude != nil || longitude != nil {
            guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        }
        return true
    }
}

extension SharedMessageCard {
    @MainActor
    init(_ countdown: Countdown) {
        self.init(id: countdown.id, kind: .countdown, title: String(countdown.title.prefix(200)),
                  symbol: countdown.symbol, colorName: countdown.colorName,
                  date: countdown.window()?.lowerBound ?? countdown.moment() ?? countdown.target())
        hasTime = countdown.hasTime
        windowEnd = countdown.window()?.upperBound
        startDate = countdown.waitStart()
        isParcel = countdown.isParcel
        styleRaw = countdown.styleRaw
        placeName = countdown.placeName.map { String($0.prefix(300)) }
        placeAddress = countdown.placeAddress.map { String($0.prefix(500)) }
        latitude = countdown.placeLatitude
        longitude = countdown.placeLongitude
        trackingInput = countdown.trackingInput.isEmpty ? nil : countdown.trackingInput
        carrierRaw = countdown.carrier?.rawValue
        shop = countdown.shopName
        storageUntil = countdown.storageUntil
        pickupCode = countdown.pickupCode
        note = countdown.note.map { String($0.prefix(1500)) }
    }

    @MainActor
    init(_ counter: Counter) {
        self.init(id: counter.id, kind: .counter, title: String(counter.title.prefix(200)), symbol: counter.symbol,
                  colorName: counter.colorName, date: counter.currentStreakStart)
        counterKind = counter.kindRaw
        counterEnd = counter.goneDate
        summary = counter.goneLine ?? counter.kind.title
        note = counter.note.map { String($0.prefix(1500)) }
    }
}
