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
        copyNumberStyle()
        guessHabits()
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

    /// Counters made before habits existed: the ones clearly about smoking become Smoking. Their price was
    /// meant for a pack, so one counted as the price of a single cigarette becomes a pack of 20.
    @MainActor
    private static func guessHabits() {
        let key = "didGuessHabits"
        guard !Settings.defaults.bool(forKey: key) else { return }
        let context = container.mainContext
        for counter in (try? context.fetch(FetchDescriptor<Counter>())) ?? [] where counter.kind == .quit && counter.habitRaw.isEmpty {
            let habit = Habit.guess(unitName: counter.unitName, title: counter.title, symbol: counter.symbol,
                                    showsHealth: counter.showsHealth)
            guard habit != .other else { continue }
            counter.habit = habit
            if let pack = habit.pack, counter.unitsPerPrice <= 1 {
                counter.unitsPerPrice = pack.size
            }
        }
        if (try? context.save()) != nil {
            Settings.defaults.set(true, forKey: key)
        }
    }

    /// The number format used to be one setting for the whole app; each counter and countdown now has its own,
    /// starting from that setting.
    @MainActor
    private static func copyNumberStyle() {
        let key = "didCopyNumberStyle"
        guard !Settings.defaults.bool(forKey: key) else { return }
        let style = UserDefaults.standard.integer(forKey: "durationStyle")
        let context = container.mainContext
        for counter in (try? context.fetch(FetchDescriptor<Counter>())) ?? [] {
            counter.durationStyleRaw = style
        }
        for countdown in (try? context.fetch(FetchDescriptor<Countdown>())) ?? [] {
            countdown.durationStyleRaw = style
        }
        if (try? context.save()) != nil {
            Settings.defaults.set(true, forKey: key)
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
