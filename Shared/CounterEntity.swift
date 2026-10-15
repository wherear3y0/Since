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

/// A string query too, so a name said to Siri ("which counter?" — "курение") finds the counter
/// even in another grammatical form.
struct CounterQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [CounterEntity] {
        await allCounters().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CounterEntity] {
        await allCounters().filter { SpokenName.matches(title: $0.title, spoken: string) }
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

/// Whether a name said to Siri means a counter's or countdown's title. Forgives case, punctuation,
/// "ё" for "е" and word endings, so "курения" finds "Курение" and "smoke free" finds "Smoke-free".
nonisolated enum SpokenName {
    static func matches(title: String, spoken: String) -> Bool {
        let titleWords = words(of: title)
        let spokenWords = words(of: spoken)
        guard !titleWords.isEmpty, !spokenWords.isEmpty else { return false }
        if titleWords.joined(separator: " ").contains(spokenWords.joined(separator: " ")) {
            return true
        }
        // Every word of the title is said, in some form. Short words ("s" from "Mom’s", "в", "on") can be left out.
        let required = titleWords.filter { $0.count > 2 }
        return (required.isEmpty ? titleWords : required).allSatisfy { word in
            spokenWords.contains { isSameWord($0, word) }
        }
    }

    /// The same word with another ending: one stem starts with the other.
    private static func isSameWord(_ a: String, _ b: String) -> Bool {
        let (short, long) = stem(a).count <= stem(b).count ? (stem(a), stem(b)) : (stem(b), stem(a))
        return short == long || (short.count >= 4 && long.hasPrefix(short))
    }

    private static func words(of text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Longer words without their last two letters, where Russian (and English) endings change.
    private static func stem(_ word: String) -> String {
        word.count > 4 ? String(word.dropLast(2)) : word
    }
}
