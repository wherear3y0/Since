import AppIntents
import SwiftData
import SwiftUI

// Things Siri can do in the app, besides answering how long it's been (SiriIntents.swift).
// Each runs on the main context, so the open app shows the change right away.

/// "Reset Smoke-free" — or, on a "last time" counter, "log today". Siri asks to confirm first.
struct ResetCounterIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Counter"
    static let description = IntentDescription("Starts a counter again from today. On a “last time” counter, logs today.")

    @Parameter(title: "Counter", requestValueDialog: "Which counter?")
    var counter: CounterEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reset \(\.$counter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let found = Store.counter(counter.id) else {
            return .result(dialog: "That counter no longer exists.") { EmptyView() }
        }
        let kind = found.kind
        if found.isDoneToday() {
            let dialog: IntentDialog = kind == .quit
                ? "\(found.title) was already reset today."
                : "\(found.title) is already logged for today."
            return .result(dialog: dialog) { CounterSnippet(found) }
        }

        let days = found.days()
        let unit = days == 1 ? "day" : "days"
        let question: IntentDialog = kind == .quit
            ? "Reset \(found.title)? This ends a streak of \(days) \(unit)."
            : "Log today for \(found.title)?"
        try await requestConfirmation(actionName: kind == .quit ? .continue : .log, dialog: question)

        found.resets.append(Reset(date: .now))
        saveChanges(Store.container.mainContext)
        let done: IntentDialog = kind == .quit
            ? "Done. \(found.title) starts again from today, after \(days) \(unit)."
            : "Logged. It had been \(days) \(unit) since the last time."
        return .result(dialog: done) { CounterSnippet(found) }
    }
}

/// "Log a slip for Smoke-free" — the count starts again, the clean days so far still count; another slip the same
/// day adds one to today's. No confirmation: a slip doesn't wipe anything, and it can be undone in the app.
struct LogSlipIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Slip"
    static let description = IntentDescription("Logs a slip on a counter: the count starts again, but the days so far stay.")

    @Parameter(title: "Counter", requestValueDialog: "Which counter?")
    var counter: CounterEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log a slip for \(\.$counter)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let found = Store.counter(counter.id) else {
            return .result(dialog: "That counter no longer exists.") { EmptyView() }
        }
        guard found.kind == .quit else {
            return .result(dialog: "\(found.title) counts since the last time, so it has no slips. Log it instead.") {
                CounterSnippet(found)
            }
        }
        guard found.canSlipToday() else {
            return .result(dialog: "\(found.title) was reset today, so it starts over from today anyway.") {
                CounterSnippet(found)
            }
        }

        let days = found.days()
        let logged = found.logSlip()
        saveChanges(Store.container.mainContext)
        if logged.addedToToday {
            let dialog: IntentDialog = "Logged one more. That’s \(logged.slip.amount) today for \(found.title)."
            return .result(dialog: dialog) { CounterSnippet(found) }
        }
        let clean = found.cleanDays()
        let unit = days == 1 ? "day" : "days"
        let kept = clean == 1 ? "1 clean day still counts" : "\(clean) clean days still count"
        let dialog: IntentDialog = "Logged. \(found.title) starts again after \(days) \(unit), and your \(kept)."
        return .result(dialog: dialog) { CounterSnippet(found) }
    }
}

/// "Add a reset to Coffee on Monday" — for a slip (or a "last time") that wasn't logged on the day.
struct AddPastResetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Past Reset"
    static let description = IntentDescription("Adds a reset on an earlier day. On a “last time” counter, logs that day.")

    @Parameter(title: "Counter", requestValueDialog: "Which counter?")
    var counter: CounterEntity

    @Parameter(title: "Date", kind: .date, requestValueDialog: "On which day?")
    var date: Date

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add a reset to \(\.$counter) on \(\.$date)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let found = Store.counter(counter.id) else {
            return .result(dialog: "That counter no longer exists.") { EmptyView() }
        }
        let calendar = Calendar.app
        let day = calendar.startOfDay(for: date)
        let when = date.formatted(date: .long, time: .omitted)
        if day > calendar.startOfDay(for: .now) {
            return .result(dialog: "That day hasn’t come yet.") { CounterSnippet(found) }
        }
        if day < calendar.startOfDay(for: found.startDate) {
            let started = found.startDate.formatted(date: .long, time: .omitted)
            return .result(dialog: "\(found.title) started on \(started), after that day.") { CounterSnippet(found) }
        }
        if found.resetDates.contains(where: { calendar.isDate($0, inSameDayAs: day) })
            || (found.kind == .lastTime && calendar.isDate(found.startDate, inSameDayAs: day)) {
            return .result(dialog: "\(found.title) already has \(when).") { CounterSnippet(found) }
        }

        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        found.resets.append(Reset(date: date, note: trimmed?.isEmpty == false ? trimmed : nil))
        saveChanges(Store.container.mainContext)
        let days = found.days()
        return .result(dialog: "Added \(when) to \(found.title). It’s now \(days) \(days == 1 ? "day" : "days").") {
            CounterSnippet(found)
        }
    }
}

/// "Add a countdown to Vacation on November 26".
struct CreateCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Countdown"
    static let description = IntentDescription("Adds a countdown to a day, like a trip or a birthday.")

    @Parameter(title: "Title", requestValueDialog: "What are you counting down to?")
    var name: String

    @Parameter(title: "Date", kind: .date, requestValueDialog: "When is it?")
    var date: Date

    @Parameter(title: "Repeats Every Year", default: false)
    var repeatsYearly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add a countdown to \(\.$name) on \(\.$date)") {
            \.$repeatsYearly
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.app
        if !repeatsYearly && calendar.startOfDay(for: date) < calendar.startOfDay(for: .now) {
            return .result(dialog: "That day has already passed.") { EmptyView() }
        }

        let context = Store.container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Countdown>())) ?? []
        // Colors take turns, so countdowns added one after another don't all look the same.
        let colors: [CounterColor] = [.cyan, .pink, .purple, .orange, .mint, .yellow, .blue, .lime, .green, .red]
        let countdown = Countdown(title: title, symbol: CalendarEvent.symbol(for: title),
                                  color: colors[existing.count % colors.count], date: date,
                                  rule: repeatsYearly ? RepeatRule(frequency: .yearly) : .never,
                                  sortOrder: Countdown.topOrders(1, above: existing)[0])
        countdown.isBirthday = countdown.looksLikeBirthday
        context.insert(countdown)
        saveChanges(context)

        let days = countdown.daysLeft()
        let target = countdown.target().formatted(.dateTime.weekday(.wide).month(.wide).day())
        let dialog: IntentDialog = days == 0
            ? "Added \(title). It’s today!"
            : "Added \(title): \(days) \(days == 1 ? "day" : "days") to go, until \(target)."
        return .result(dialog: dialog) { CountdownSnippet(countdown) }
    }
}

/// "Open Smoke-free".
struct OpenCounterIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Counter"

    @Parameter(title: "Counter")
    var target: CounterEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.link = URL(string: "since://counter/\(target.id.uuidString)")
        return .result()
    }
}

/// "Open Vacation".
struct OpenCountdownIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Countdown"

    @Parameter(title: "Countdown")
    var target: CountdownEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.link = URL(string: "since://countdown/\(target.id.uuidString)")
        return .result()
    }
}

extension Store {
    /// A counter in the main context, for changes the app shows right away.
    @MainActor
    static func counter(_ id: UUID) -> Counter? {
        try? container.mainContext.fetch(FetchDescriptor<Counter>(predicate: #Predicate { $0.id == id })).first
    }
}

extension CounterSnippet {
    @MainActor
    init(_ counter: Counter) {
        self.init(title: counter.title, symbol: counter.symbol, tint: counter.color.color,
                  days: counter.days(), since: counter.currentStreakStart)
    }
}

extension CountdownSnippet {
    @MainActor
    init(_ countdown: Countdown) {
        self.init(title: countdown.title, symbol: countdown.symbol, tint: countdown.color.color,
                  days: countdown.daysLeft(), target: countdown.target())
    }
}
