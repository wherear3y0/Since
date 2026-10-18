import Foundation
import SwiftData
import Testing
@testable import Since

struct SharedMessageTests {
    func card() -> SharedMessageCard {
        SharedMessageCard(id: UUID(), kind: .countdown, title: "Meet for coffee", symbol: "cup.and.saucer.fill",
                          colorName: "cyan", date: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func nativeMessageRoundTripUsesASupportedSchemeWithinTheLimit() throws {
        var value = card()
        value.placeName = "Кафе & друзья"
        value.latitude = 55.75
        value.longitude = 37.61
        value.trackingInput = "https://tracking.example.com/parcel?id=A%2FB&lang=ru#state"
        let url = try value.encodedURL()
        #expect(url.scheme == "data")
        #expect(url.absoluteString.count <= 5000)
        #expect(try SharedMessageCard.decode(url) == value)
        #expect(value.mapsURL?.host == "maps.apple.com")
        #expect(value.trackURL?.absoluteString == value.trackingInput)
    }

    @Test func unselectedLocationNotesAndPickupCodeDoNotLeaveTheDeviceInThePayload() throws {
        var value = card()
        value.placeName = "Home"
        value.placeAddress = "Private address"
        value.latitude = 55.75
        value.longitude = 37.61
        value.note = "A private note"
        value.pickupCode = "123456"
        let sent = try SharedMessageCard.decode(value.sharing(location: false, note: false, pickupCode: false).encodedURL())
        #expect(sent.placeName == nil && sent.placeAddress == nil)
        #expect(sent.latitude == nil && sent.longitude == nil)
        #expect(sent.mapsURL == nil && sent.locationLine == nil)
        #expect(sent.note == nil && sent.pickupCode == nil)
        #expect(value.pickupCode == "123456")
    }

    @Test func invalidAndOversizedPayloadsAreRejected() throws {
        var value = card()
        value.latitude = 99
        value.longitude = 30
        #expect(throws: SharedMessageCard.PayloadError.invalid) { try value.encodedURL() }
        value.latitude = nil; value.longitude = nil
        value.version = 2
        #expect(throws: SharedMessageCard.PayloadError.invalid) { try value.encodedURL() }
        value.version = 1
        value.trackingInput = "javascript:alert(1)"
        #expect(throws: SharedMessageCard.PayloadError.invalid) { try value.encodedURL() }
        value.trackingInput = nil
        value.note = String(repeating: "Ж", count: 1500)
        value.placeAddress = String(repeating: "Д", count: 500)
        #expect(throws: SharedMessageCard.PayloadError.tooLarge) { try value.encodedURL() }
        #expect(throws: SharedMessageCard.PayloadError.invalid) {
            try SharedMessageCard.decode(URL(string: "data:application/vnd.since.card+json;base64,broken")!)
        }
    }

    @MainActor @Test func savingAReceivedParcelIsExplicitAndIdempotent() throws {
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        var value = card()
        value.isParcel = true
        value.styleRaw = "arc"
        value.placeName = "Pickup point"
        value.latitude = 55.75; value.longitude = 37.61
        value.trackingInput = "https://tracking.example.com/parcel/42"
        #expect(try !SharedMessageImport.contains(value, in: context))
        #expect(try context.fetchCount(FetchDescriptor<Countdown>()) == 0)
        #expect(try SharedMessageImport.save(value, in: context))
        let originalTitle = value.title
        value.title = "Changed by sender"
        #expect(try !SharedMessageImport.save(value, in: context))
        let rows = try context.fetch(FetchDescriptor<Countdown>())
        #expect(rows.count == 1)
        #expect(rows[0].id == value.id)
        #expect(rows[0].title == originalTitle)
        #expect(rows[0].isParcel)
        #expect(rows[0].style == .arc)
        #expect(rows[0].placeLatitude == 55.75)
        #expect(rows[0].parcelTrackingDestination?.absoluteString == value.trackingInput)
    }
}
