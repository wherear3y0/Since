import Testing
import UIKit
@testable import Since

struct PaletteTests {
    @Test func allSymbolsExist() {
        let missing = counterSymbols.filter { UIImage(systemName: $0) == nil }
        #expect(missing.isEmpty, "Unknown SF Symbols: \(missing)")
    }

    @Test func symbolsAreUnique() {
        #expect(Set(counterSymbols).count == counterSymbols.count)
    }
}
