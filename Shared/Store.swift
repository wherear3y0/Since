import Foundation
import SwiftData

enum Store {
    static let appGroup = "group.me.wherar3y0.since"

    private static var cachedContainer: ModelContainer?

    /// Cache only a successful open. A protected or temporarily unavailable store can be retried
    /// without deleting data, falling back to a different database, or crashing an extension.
    static func open() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil else {
            throw OpenError.appGroupUnavailable
        }
        let schema = Schema([Counter.self, Reset.self, Countdown.self])
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
        let container = try ModelContainer(for: schema, configurations: configuration)
        cachedContainer = container
        return container
    }

    enum OpenError: LocalizedError {
        case appGroupUnavailable
        var errorDescription: String? {
            "Since couldn’t access its shared storage. Open the main app and try again."
        }
    }

    /// One-time fixes to data saved by earlier versions, run at launch.
    @MainActor
    static func upgradeData() {
        copyNumberStyle()
        guessHabits()
        let defaults = Settings.defaults
        let birthdaysKey = "didMarkBirthdays"
        guard !defaults.bool(forKey: birthdaysKey) else { return }
        // Birthdays added before the Birthdays section existed: yearly countdowns with the cake icon.
        guard let context = try? open().mainContext else { return }
        guard let countdowns = try? context.fetch(FetchDescriptor<Countdown>()) else { return }
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
        guard let context = try? open().mainContext else { return }
        guard let counters = try? context.fetch(FetchDescriptor<Counter>()) else { return }
        for counter in counters where counter.kind == .quit && counter.habitRaw.isEmpty {
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
        guard let context = try? open().mainContext else { return }
        guard let counters = try? context.fetch(FetchDescriptor<Counter>()),
              let countdowns = try? context.fetch(FetchDescriptor<Countdown>()) else { return }
        for counter in counters {
            counter.durationStyleRaw = style
        }
        for countdown in countdowns {
            countdown.durationStyleRaw = style
        }
        if (try? context.save()) != nil {
            Settings.defaults.set(true, forKey: key)
        }
    }

    /// All counters in the app's order, read in a fresh context (for widgets and intents).
    /// Owned things that are gone are left out: they're only kept in Past.
    @MainActor
    static func counters() -> [Counter] {
        guard let container = try? open() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Counter>(sortBy: [SortDescriptor(\.sortOrder)])
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isGone }
    }

    /// All countdowns in the app's order, read in a fresh context (for widgets and intents).
    /// Timers are left out: they're only for the Until tab and the Lock Screen.
    @MainActor
    static func countdowns() -> [Countdown] {
        guard let container = try? open() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.sortOrder)])
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isTimer }
    }

    /// Timers that have ended go away; run when the app comes back.
    @MainActor
    static func removeEndedTimers(_ context: ModelContext, now: Date = .now) {
        let ended = ((try? context.fetch(FetchDescriptor<Countdown>())) ?? []).filter { $0.isTimer && $0.date <= now }
        guard !ended.isEmpty else { return }
        for timer in ended {
            context.delete(timer)
        }
        try? context.save()
    }
}
