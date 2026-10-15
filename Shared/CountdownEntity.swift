import AppIntents
import CoreSpotlight
import SwiftData

/// A countdown as it appears in widget settings, to Siri and in Spotlight.
/// Indexed like counters, so Siri can find it by meaning ("when is mom's birthday").
struct CountdownEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static let defaultQuery = CountdownQuery()

    let id: UUID
    @Property(title: "Title", indexingKey: \.title)
    var title: String
    let symbol: String
    /// Days to go; negative once a one-off day has passed.
    @Property(title: "Days Left")
    var daysLeft: Int
    @Property(title: "Date")
    var date: Date
    @Property(title: "Repeats")
    var repeats: String

    init(id: UUID, title: String, symbol: String, daysLeft: Int, date: Date, repeats: String) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.daysLeft = daysLeft
        self.date = date
        self.repeats = repeats
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = switch daysLeft {
        case 0: "Today"
        case 1...: "In \(daysLeft) \(daysLeft == 1 ? "day" : "days")"
        default: "\(-daysLeft) \(daysLeft == -1 ? "day" : "days") ago"
        }
        return DisplayRepresentation(title: "\(title)", subtitle: subtitle, image: .init(systemName: symbol))
    }

    /// What Spotlight and Siri's semantic index know beyond the title.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = "\(title) is on \(date.formatted(date: .complete, time: .omitted)), "
            + (daysLeft >= 0 ? "in \(daysLeft) days." : "\(-daysLeft) days ago.")
            + (repeats == "Never" ? "" : " Repeats: \(repeats).")
        attributes.keywords = ["countdown", "days until", "date", "event"]
        return attributes
    }
}

extension CountdownEntity {
    @MainActor
    init(_ countdown: Countdown) {
        self.init(id: countdown.id, title: countdown.title, symbol: countdown.symbol, daysLeft: countdown.daysLeft(),
                  date: countdown.target(), repeats: countdown.rule.summary())
    }
}

struct CountdownQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        await allCountdowns().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        await allCountdowns()
    }

    func defaultResult() async -> CountdownEntity? {
        await allCountdowns().first
    }

    /// The database is read on the main actor, like everywhere else in the app.
    @MainActor
    private func allCountdowns() -> [CountdownEntity] {
        Store.countdowns().map(CountdownEntity.init)
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Countdown"
    static let description = IntentDescription("Choose the countdown to show.")

    @Parameter(title: "Countdown")
    var countdown: CountdownEntity?
}

struct SelectCountdownsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Countdowns"
    static let description = IntentDescription("Choose up to six countdowns. Leave empty to show the soonest.")

    @Parameter(title: "Countdowns", size: 6)
    var countdowns: [CountdownEntity]?
}
