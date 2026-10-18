import Foundation
import SwiftData

enum SharedMessageImport {
    static func contains(_ card: SharedMessageCard, in context: ModelContext) throws -> Bool {
        let id = card.id
        if card.kind == .counter {
            return try context.fetchCount(FetchDescriptor<Counter>(predicate: #Predicate { $0.id == id })) > 0
        }
        return try context.fetchCount(FetchDescriptor<Countdown>(predicate: #Predicate { $0.id == id })) > 0
    }

    /// Explicitly save a received snapshot as a local item. Never changes an existing sender/local item.
    @discardableResult
    static func save(_ card: SharedMessageCard, in context: ModelContext) throws -> Bool {
        _ = try card.encodedURL() // The same bounds apply even when called without decoding a message first.
        guard try !contains(card, in: context) else { return false }
        if card.kind == .counter {
            let rows = try context.fetch(FetchDescriptor<Counter>())
            let counter = Counter(title: card.title, symbol: card.symbol, color: card.color,
                                  kind: card.counterKind.flatMap(CounterKind.init(rawValue:)) ?? .lastTime,
                                  startDate: card.date, note: card.note,
                                  sortOrder: (rows.map(\.sortOrder).min() ?? 0) - 1)
            counter.id = card.id
            if counter.isOwned { counter.goneDate = card.counterEnd }
            context.insert(counter)
        } else {
            let rows = try context.fetch(FetchDescriptor<Countdown>())
            let countdown = Countdown(title: card.title, symbol: card.symbol, color: card.color, date: card.date,
                                      note: card.note, sortOrder: (rows.map(\.sortOrder).min() ?? 0) - 1)
            countdown.id = card.id
            countdown.hasTime = card.hasTime
            countdown.windowEnd = card.windowEnd
            countdown.createdAt = min(card.startDate ?? .now, .now)
            countdown.isParcel = card.isParcel
            countdown.styleRaw = card.styleRaw ?? CountdownStyle.calendar.rawValue
            countdown.setTrackingInput(card.trackingInput ?? "")
            countdown.carrierRaw = card.carrierRaw ?? ""
            countdown.shopName = card.shop
            countdown.storageUntil = card.storageUntil
            countdown.pickupCode = card.pickupCode
            countdown.placeName = card.placeName
            countdown.placeAddress = card.placeAddress
            countdown.placeLatitude = card.latitude
            countdown.placeLongitude = card.longitude
            context.insert(countdown)
        }
        try ExtensionChanges.save(context)
        return true
    }
}
