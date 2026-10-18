import Foundation
import SwiftData
import WidgetKit

/// A small cross-process signal, written only after an extension's database save succeeded.
/// Reading the file avoids UserDefaults caching between the app and its extensions.
enum ExtensionChanges {
    private static var signalURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Store.appGroup)?
            .appendingPathComponent("extension-change")
    }

    static var revision: String {
        guard let url = signalURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func save(_ context: ModelContext) throws {
        try context.save()
        if let url = signalURL {
            try? Data(UUID().uuidString.utf8).write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
