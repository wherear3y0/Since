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
        let dialog: IntentDialog = switch days {
        case 0: "\(found.title) is today!"
        case 1...: "\(days) \(unit) until \(found.title), on \(date)."
        default: "\(found.title) was \(-days) \(unit) ago, on \(date)."
        }
        return .result(dialog: dialog) {
            CountdownSnippet(title: found.title, symbol: found.symbol, tint: found.color.color,
                             days: days, target: target)
        }
    }
}

/// The card Siri shows under its answer about a countdown.
struct CountdownSnippet: View {
    let title: String
    let symbol: String
    let tint: Color
    let days: Int
    let target: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(target.untilFormat)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DaysLeftText(days: days, size: 40)
        }
        .padding()
        .snippetCard(tint: tint)
    }
}

/// Phrases that work without any setup. Siri fills in names from the app's counters and countdowns.
struct SinceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
