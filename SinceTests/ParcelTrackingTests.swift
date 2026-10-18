import Foundation
import Testing
@testable import Since

struct ParcelTrackingTests {
    @Test func acceptsNumbersAndKeepsOrderNumberHyphens() {
        let postal = ParcelTracking("  RA 123456785 RU\n")
        #expect(postal.isValid)
        #expect(postal.number == "RA123456785RU")
        #expect(postal.carrier == .russianPost)
        #expect(postal.url == nil)
        #expect(ParcelTracking("12345678-0001-1").number == "12345678-0001-1")
    }

    @Test func keepsTrackingURLsIntactAndFindsKnownCarriers() {
        let link = "https://www.cdek.ru/ru/tracking/?order_id=1234567890&source=mail#status"
        let parsed = ParcelTracking(link)
        #expect(parsed.isValid)
        #expect(parsed.url?.absoluteString == link)
        #expect(parsed.carrier == .cdek)
        #expect(parsed.number == "1234567890")
        #expect(ParcelTracking("gdeposylka.ru/tracking/ABC123").url?.scheme == "https")
        #expect(ParcelTracking("https://tracking.example.com/parcel?id=abc").carrier == nil)
        #expect(ParcelTracking("https://cdek.ru.example.com/track").carrier == nil)
    }

    @Test func invalidLinksAreNotConvertedIntoNumbers() {
        for input in ["javascript:alert(1)", "file:///tmp/parcel", "https://", "https://user:pass@example.com/track",
                      "https://example.com/a b", "Номер: 12345678"] {
            let parsed = ParcelTracking(input)
            #expect(!parsed.isValid)
            #expect(parsed.number == nil)
            #expect(parsed.url == nil)
        }
    }

    @MainActor @Test func directLinkWinsAndClearingItDoesNotLeaveAHiddenLink() {
        let parcel = Countdown(title: "Shoes", symbol: "shippingbox", color: .orange, date: .now)
        parcel.isParcel = true
        parcel.carrier = .cdek
        parcel.setTrackingInput("https://tracking.example.com/orders/42")
        #expect(parcel.parcelTrackingDestination?.host == "tracking.example.com")
        #expect(parcel.trackingNumber == nil)
        parcel.setTrackingInput("RA123456785RU")
        #expect(parcel.trackingURL == nil)
        #expect(parcel.trackingNumber == "RA123456785RU")
        parcel.carrier = nil
        #expect(parcel.carrier == .russianPost)
        parcel.setTrackingInput("")
        #expect(parcel.trackingURL == nil)
        #expect(parcel.trackingNumber == nil)
        #expect(parcel.parcelTrackingDestination == nil)
    }

    @Test func sharedTrackingPagesAreNotStoredAsProductOrderLinks() {
        let shared = ParcelShare(text: "Наушники Sony", url: URL(string: "https://www.fedex.com/fedextrack/?trknbr=123456789012"))
        #expect(shared.trackingURL?.host == "www.fedex.com")
        #expect(shared.orderURL == nil)
        #expect(shared.draft.carrier == .fedex)
        #expect(shared.draft.trackingNumber == "123456789012")
        #expect(ParcelShare(text: "", url: URL(string: "https://ozon.ru/product/123")).trackingURL == nil)
    }
}
