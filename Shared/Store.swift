import Foundation
import SwiftData

enum Store {
    static let appGroup = "group.me.wherar3y0.since"

    /// The on-disk database, shared with the widgets through the App Group container.
    static let container: ModelContainer = {
        let schema = Schema([Counter.self, Reset.self, Countdown.self])
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
        // The app and its widgets open the same file. Right after an update one of them can be upgrading it
        // to the new models while the other tries to open it, so a failed open is tried again a moment later.
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.3 * Double(attempt))
            }
        }
        fatalError("Could not open the database: \(String(describing: lastError))")
    }()

    /// One-time fixes to data saved by earlier versions, run at launch.
    @MainActor
    static func upgradeData() {
        let defaults = Settings.defaults
        let birthdaysKey = "didMarkBirthdays"
        guard !defaults.bool(forKey: birthdaysKey) else { return }
        // Birthdays added before the Birthdays section existed: yearly countdowns with the cake icon.
        let context = container.mainContext
        let countdowns = (try? context.fetch(FetchDescriptor<Countdown>())) ?? []
        for countdown in countdowns where countdown.looksLikeBirthday {
            countdown.isBirthday = true
        }
        do {
            try context.save()
            defaults.set(true, forKey: birthdaysKey)
        } catch {
            // Tried again at the next launch.
        }
    }

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
