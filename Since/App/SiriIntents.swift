import AppIntents
import SwiftUI

/// "How long since Smoke-free?" — Siri answers out loud and shows a small card.
struct CounterDaysIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Counter"
    static let description = IntentDescription("Tells how many days have passed on a counter.")

    @Parameter(title: "Counter", requestValueDialog: "Which counter?")
    var counter: CounterEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$counter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let found = Store.counters().first(where: { $0.id == counter.id }) else {
            return .result(dialog: "That counter no longer exists.") { EmptyView() }
        }
        let days = found.days()
        let unit = days == 1 ? "day" : "days"
        let since = found.currentStreakStart.formatted(date: .long, time: .omitted)
        let dialog: IntentDialog = switch found.kind {
        case .quit: "\(found.title): \(days) \(unit), since \(since)."
        case .lastTime: "It’s been \(days) \(unit) since \(found.title), on \(since)."
        case .owned: "You’ve had \(found.title) for \(days) \(unit), since \(since)."
        }
        return .result(dialog: dialog) {
            CounterSnippet(title: found.title, symbol: found.symbol, tint: found.color.color,
                           days: days, since: found.currentStreakStart)
        }
    }
}

/// The card Siri shows under its answer.
struct CounterSnippet: View {
    let title: String
    let symbol: String
    let tint: Color
    let days: Int
    let since: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text("since \(since.sinceFormat)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(days, format: .number)
                    .font(.system(size: 40, weight: .bold))
                Text(days == 1 ? "day" : "days")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .snippetCard(tint: tint)
    }
}

/// "How many days until Vacation?" — Siri answers out loud and shows a small card.
struct CountdownDaysIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Countdown"
    static let description = IntentDescription("Tells how many days are left until a countdown's day.")

    @Parameter(title: "Countdown", requestValueDialog: "Which countdown?")
    var countdown: CountdownEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$countdown)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let found = Store.countdowns().first(where: { $0.id == countdown.id }) else {
            return .result(dialog: "That countdown no longer exists.") { EmptyView() }
        }
        let days = found.daysLeft()
        let target = found.target()
        let date = target.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let unit = abs(days) == 1 ? "day" : "days"
        let time = found.moment().map { " at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        let dialog: IntentDialog
        if let window = found.window(), found.isApproximate() {
            dialog = "\(found.title) is due \(window.rangeFormat), in about \(days) \(unit)."
        } else if let window = found.window(), found.isInWindow() {
            dialog = "\(found.title) can come any day now, by \(window.upperBound.formatted(.dateTime.weekday(.wide).month(.wide).day()))."
        } else {
            dialog = switch days {
            case 0: "\(found.title) is today\(time)!"
            case 1...: "\(days) \(unit) until \(found.title), on \(date)\(time)."
            default: "\(found.title) was \(-days) \(unit) ago, on \(date)."
            }
        }
        return .result(dialog: dialog) {
            CountdownSnippet(found)
        }
    }
}

/// The card Siri shows under its answer about a countdown.
struct CountdownSnippet: View {
    let title: String
    let symbol: String
    let tint: Color
    let days: DaysLeftText
    let dateLine: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            days
        }
        .padding()
        .snippetCard(tint: tint)
    }
}

/// "What's in Since?" — every counter and the countdowns coming up, read out and shown as a list,
/// for when you don't name one.
struct OverviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Overview"
    static let description = IntentDescription("Tells how long each counter has been going and what's coming up.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let counters = Store.counters().map {
            OverviewRow(id: $0.id, title: $0.title, symbol: $0.symbol, tint: $0.color.color, days: $0.days(),
                        isCountdown: false)
        }
        let countdowns = Store.countdowns()
            .filter { !$0.isArchived && !$0.hasPassed() }
            .sorted { $0.daysLeft() < $1.daysLeft() }
            .map {
                OverviewRow(id: $0.id, title: $0.title, symbol: $0.symbol, tint: $0.color.color, days: $0.daysLeft(),
                            isCountdown: true)
            }
        guard !counters.isEmpty || !countdowns.isEmpty else {
            return .result(dialog: "There’s nothing in Since yet.") { EmptyView() }
        }
        // A few of each, so a long list of counters doesn't crowd out what's coming up; the card shows more.
        let spoken = (counters.prefix(3) + countdowns.prefix(3)).map(\.spoken).joined(separator: " ")
        return .result(dialog: "\(spoken)") {
            OverviewSnippet(rows: Array(counters.prefix(6) + countdowns.prefix(4)))
        }
    }
}

/// One counter or countdown in the overview.
struct OverviewRow: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let tint: Color
    /// Days since, for a counter; days to go, for a countdown.
    let days: Int
    let isCountdown: Bool

    private var dayWord: String { days == 1 ? "day" : "days" }

    var value: String {
        if !isCountdown { return "\(days) \(dayWord)" }
        return days == 0 ? "Today" : "in \(days) \(dayWord)"
    }

    var spoken: String {
        if !isCountdown { return "\(title): \(days) \(dayWord)." }
        return days == 0 ? "\(title) is today." : "\(title) in \(days) \(dayWord)."
    }
}

/// The list Siri shows under the overview.
struct OverviewSnippet: View {
    let rows: [OverviewRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack {
                    Label(row.title, systemImage: row.symbol)
                        .foregroundStyle(row.tint)
                        .lineLimit(1)
                    Spacer()
                    Text(row.value)
                        .monospacedDigit()
                }
                .font(.body.weight(.semibold))
            }
        }
        .padding()
        .snippetCard(tint: .gray)
    }
}

/// Phrases that work without any setup. Siri fills in names from the app's counters and countdowns.
struct SinceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OverviewIntent(),
            phrases: [
                "What's in \(.applicationName)",
                "Show everything in \(.applicationName)",
                "\(.applicationName) overview",
            ],
            shortTitle: "Overview",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: CounterDaysIntent(),
            phrases: [
                "How long since \(\.$counter) in \(.applicationName)",
                "How many days since \(\.$counter) in \(.applicationName)",
                "Check \(\.$counter) in \(.applicationName)",
                "\(.applicationName) \(\.$counter)",
                // Without the name Siri asks which counter, which works whatever form the name is said in.
                "Check a counter in \(.applicationName)",
            ],
            shortTitle: "Check Counter",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: CountdownDaysIntent(),
            phrases: [
                "How many days until \(\.$countdown) in \(.applicationName)",
                "How long until \(\.$countdown) in \(.applicationName)",
                "When is \(\.$countdown) in \(.applicationName)",
                "Check a countdown in \(.applicationName)",
            ],
            shortTitle: "Check Countdown",
            systemImageName: "hourglass"
        )
        AppShortcut(
            intent: ResetCounterIntent(),
            phrases: [
                "Reset \(\.$counter) in \(.applicationName)",
                "Log \(\.$counter) in \(.applicationName)",
                "Log today for \(\.$counter) in \(.applicationName)",
                "Reset a counter in \(.applicationName)",
            ],
            shortTitle: "Reset Counter",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: LogSlipIntent(),
            phrases: [
                "Log a slip for \(\.$counter) in \(.applicationName)",
                "I slipped on \(\.$counter) in \(.applicationName)",
                "Log a slip in \(.applicationName)",
            ],
            shortTitle: "Log a Slip",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: AddPastResetIntent(),
            phrases: [
                "Add a reset to \(\.$counter) in \(.applicationName)",
                "Log a past day for \(\.$counter) in \(.applicationName)",
            ],
            shortTitle: "Add Past Reset",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: CreateCountdownIntent(),
            phrases: [
                "Add a countdown in \(.applicationName)",
                "New countdown in \(.applicationName)",
                "Count down in \(.applicationName)",
            ],
            shortTitle: "Add Countdown",
            systemImageName: "hourglass.badge.plus"
        )
        AppShortcut(
            intent: OpenCounterIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Counter",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: OpenCountdownIntent(),
            phrases: [
                "Open \(\.$target) countdown in \(.applicationName)",
                "Show \(\.$target) countdown in \(.applicationName)",
            ],
            shortTitle: "Open Countdown",
            systemImageName: "arrow.up.forward.app"
        )
    }
}

extension View {
    /// Siri's cards draw their own background, like a widget, so the text stays readable
    /// whatever Siri puts behind them.
    func snippetCard(tint: Color) -> some View {
        self
            .background {
                ZStack {
                    Color.cardBackground
                    tint.opacity(0.16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .cardEdge(tint: tint)
    }
}
