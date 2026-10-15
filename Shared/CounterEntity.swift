import AppIntents
import CoreSpotlight
import SwiftData

/// A counter as it appears in widget settings, to Siri and in Spotlight.
/// Indexed into the system's semantic index, so Siri can find it by meaning ("how long have I not smoked")
/// and answer questions about it from its properties.
struct CounterEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Counter"
    static let defaultQuery = CounterQuery()

    let id: UUID
    @Property(title: "Title", indexingKey: \.title)
    var title: String
    let symbol: String
    @Property(title: "Days")
    var days: Int
    @Property(title: "Since")
    var since: Date
    @Property(title: "Best Streak")
    var best: Int
    /// "Quit" or "Last Time".
    @Property(title: "Type")
    var kind: String

    init(id: UUID, title: String, symbol: String, days: Int, since: Date, best: Int, kind: String) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.days = days
        self.since = since
        self.best = best
        self.kind = kind
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(days) \(days == 1 ? "day" : "days")",
                              image: .init(systemName: symbol))
    }

    /// What Spotlight and Siri's semantic index know beyond the title.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = kind == CounterKind.quit.title
            ? "\(days) days without \(title), since \(since.formatted(date: .long, time: .omitted)). Best streak \(best) days."
            : "\(days) days since \(title), last on \(since.formatted(date: .long, time: .omitted))."
        attributes.keywords = ["days since", "streak", "counter", kind]
        return attributes
    }
}

extension CounterEntity {
    @MainActor
    init(_ counter: Counter) {
        self.init(id: counter.id, title: counter.title, symbol: counter.symbol, days: counter.days(),
                  since: counter.currentStreakStart, best: counter.streaks().map(\.days).max() ?? 0,
                  kind: counter.kind.title)
    }
}

struct CounterQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CounterEntity] {
        await allCounters().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CounterEntity] {
        await allCounters()
    }

    func defaultResult() async -> CounterEntity? {
        await allCounters().first
    }

    /// The database is read on the main actor, like everywhere else in the app.
    @MainActor
    private func allCounters() -> [CounterEntity] {
        Store.counters().map(CounterEntity.init)
    }
}

struct SelectCounterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Counter"
    static let description = IntentDescription("Choose the counter to show.")

    @Parameter(title: "Counter")
    var counter: CounterEntity?
}

struct SelectCountersIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Counters"
    static let description = IntentDescription("Choose up to six counters. Leave empty to show the first six.")

    @Parameter(title: "Counters", size: 6)
    var counters: [CounterEntity]?
}
