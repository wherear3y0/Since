import Foundation
import Testing
@testable import Since

struct ParcelShareTests {
    @Test func marketplaceLinksFillTheShopAndPreserveTheLink() {
        let url = URL(string: "https://www.ozon.ru/my/orderdetails/?order=12345678-0001")!
        let shared = ParcelShare(text: "Наушники", url: url)
        #expect(shared.trackingURL == url)
        #expect(shared.orderURL == nil)
        #expect(shared.draft.shop == "Ozon")
        #expect(shared.draft.carrier == .ozon)
        #expect(shared.draft.title == "Наушники")
        #expect(shared.draft.from == nil) // A link alone never invents a delivery date.

        #expect(ParcelShare(text: "", url: URL(string: "https://www.wildberries.ru/catalog/123/detail.aspx"))
            .draft.shop == "Wildberries")
        #expect(ParcelShare(text: "", url: URL(string: "https://market.yandex.ru/my/orders"))
            .draft.shop == "Яндекс Маркет")
    }

    @Test func linksEmbeddedInTextAreKeptOutOfTheProductName() {
        let shared = ParcelShare(text: "Наушники беспроводные Sony\nhttps://www.ozon.ru/product/123/\nДоставка завтра")
        #expect(shared.draft.title == "Наушники беспроводные Sony")
        #expect(shared.draft.from != nil)
        #expect(shared.orderURL?.host == "www.ozon.ru")
    }

    @Test func urlHostsAreMatchedAtDomainBoundaries() {
        for link in ["https://ozon.ru.example.com/order", "https://fakeozon.ru/order",
                     "https://example.com/?shop=ozon.ru", "https://example.com/?next=avito.ru"] {
            #expect(ParcelShare(text: "", url: URL(string: link)).draft.shop == nil)
        }
        for link in ["file:///etc/passwd", "javascript:alert(1)", "https://user:password@ozon.ru/order"] {
            #expect(ParcelShare.webURL(URL(string: link)) == nil)
        }
    }

    @Test func partnerCarrierOnAMarketplaceIsNotReplaced() {
        let shared = ParcelShare(text: "СДЭК\nТрек-номер 1234567890", url: URL(string: "https://ozon.ru/my/orderlist/"))
        #expect(shared.draft.shop == "Ozon")
        #expect(shared.draft.carrier == .cdek)
        #expect(shared.draft.trackingNumber == "1234567890")
    }
}
