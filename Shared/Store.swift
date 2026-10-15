import Foundation
import SwiftData

enum Store {
    static let appGroup = "group.me.wherar3y0.since"

    /// The on-disk database, shared with the widgets through the App Group container.
    static let container: ModelContainer = {
        let schema = Schema([Counter.self, Reset.self, Countdown.self])
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the database: \(error)")
        }
    }()

    /// All counters in the app's order, read in a fresh context (for widgets and intents).
    @MainActor
    static func counters() -> [Counter] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Counter>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All countdowns in the app's order, read in a fresh context (for widgets and intents).
    @MainActor
    static func countdowns() -> [Countdown] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
