import AppIntents
import SwiftUI
import SwiftData

/// One countdown: the calendar up to the day, how much of the wait is behind, what's left, and details.
struct CountdownDetailView: View {
    let countdown: Countdown
    let onDelete: () -> Void
    let onCountedSince: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isEditing = false
    @State private var converting: Countdown?
    /// The calendar wave plays once per opening, not again when the card scrolls back into view.
    @State private var heroRevealed = false
    /// Turns true when the page opens; the blocks under the calendar then blur in one after another.
    @State private var contentShown = false

    var body: some View {
        let tint = countdown.color.color

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CountdownHeroCard(countdown: countdown, animated: !heroRevealed)
                    .onAppear { heroRevealed = true }
                    .detailCard {
                        if countdown.tinted {
                            Color.cardBackground
                            tint.opacity(0.16)
                        } else {
                            SoftColorFill(tint: tint.onCard(tinted: false))
                        }
                        if countdown.style == .fill {
                            FillLevel(level: countdown.progress(), tint: tint.onCard(tinted: countdown.tinted),
                                      animated: !heroRevealed)
                        }
                    }

                Group {
                    if countdown.hasPassed() {
                        passedCard(tint: tint)
                    } else {
                        TimeLeftCard(countdown: countdown)
                    }
                }
                .detailCard()
                .blurIn(contentShown, delay: 0.1)

                if countdown.rule.repeats && !countdown.hasPassed() {
                    ComingUpCard(countdown: countdown)
                        .detailCard()
                        .blurIn(contentShown, delay: 0.14)
                }

                Group {
                    sectionHeader("Summary")
                    summary
                        .detailCard(vertical: 4)
                }
                .blurIn(contentShown, delay: 0.17)

                if let note = countdown.note {
                    Group {
                        sectionHeader("Note")
                        Text(note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .detailCard()
                    }
                    .blurIn(contentShown, delay: 0.24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(countdown.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: countdown.symbol)
                        .foregroundStyle(tint)
                    Text(countdown.title)
                }
                .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
            if !countdown.isArchived {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(countdown.isPinned ? "Unpin" : "Pin to Top",
                           systemImage: countdown.isPinned ? "pin.fill" : "pin") {
                        countdown.isPinned.toggle()
                        saveChanges(context)
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: countdown.isArchived)
        .sensoryFeedback(.selection, trigger: countdown.isPinned)
        .onAppear { contentShown = true }
        // Siri knows this is the countdown on screen: "how long until this".
        .userActivity("me.wherar3y0.since.countdown") { activity in
            activity.title = countdown.title
            activity.appEntityIdentifier = EntityIdentifier(for: CountdownEntity.self, identifier: countdown.id)
        }
        .sheet(isPresented: $isEditing) {
            CountdownEditor(countdown: countdown, onDelete: onDelete)
        }
        .countSinceAlert($converting, onDone: onCountedSince)
    }

    /// A one-off day gone by: count days since it, or keep it in Past.
    private func passedCard(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "It’s Been", symbol: "party.popper.fill", tint: tint,
                       text: countdown.isArchived
                           ? "This day has passed and is kept in Past. You can still count days since it."
                           : "This day has passed. Count the days since it, or keep it in Past.")
            HStack(spacing: 8) {
                Button {
                    converting = countdown
                } label: {
                    Label("Count Since", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.black.opacity(0.8))
                }
                .buttonStyle(.glassProminent)
                .tint(tint)

                Button {
                    withAnimation(.smooth) { countdown.isArchived.toggle() }
                    saveChanges(context)
                } label: {
                    Label(countdown.isArchived ? "Move Out of Past" : "Move to Past",
                          systemImage: countdown.isArchived ? "tray.and.arrow.up" : "archivebox")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.interpolate)
                }
                .buttonStyle(.glass)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }

    private var summary: some View {
        let target = countdown.target()
        let start = countdown.waitStart()

        var rows: [SummaryRow] = [
            SummaryRow(symbol: "calendar", title: "Date",
                       subtitle: target.formatted(date: .long, time: .omitted),
                       value: target.formatted(.dateTime.weekday(.wide))),
            SummaryRow(symbol: "repeat", title: "Repeats",
                       subtitle: countdown.rule.end.map { "Until \($0.formatted(date: .long, time: .omitted))" },
                       value: countdown.rule.summary()),
        ]
        if let turns = countdown.turns() {
            rows.append(SummaryRow(symbol: "birthday.cake", title: "Turns", value: "\(turns)"))
        }
        rows.append(SummaryRow(symbol: "hourglass.bottomhalf.filled",
                               title: countdown.previousTime() != nil ? "Last time round" : "Counting from",
                               subtitle: start.formatted(date: .long, time: .omitted),
                               value: start.relativeDayDescription))
        rows.append(SummaryRow(symbol: countdown.notifyBefore ? "bell" : "bell.slash", title: "Reminders",
                               value: countdown.notifyBefore ? "On" : "Off"))
        if countdown.isPinned {
            rows.append(SummaryRow(symbol: "pin", title: "Pinned", value: "On top of Until"))
        }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 42)
                }
                row
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}

/// The calendar up to the day, with the days to go and how much of the wait is behind underneath.
struct CountdownHeroCard: View {
    let countdown: Countdown
    var animated = true

    var body: some View {
        let tint = countdown.color.color.onCard(tinted: countdown.tinted)
        let target = countdown.target()
        let days = countdown.daysLeft()
        let start = countdown.waitStart()
        let waited = DayMath.days(from: start, to: .now)
        let total = DayMath.days(from: start, to: target)

        VStack(alignment: .leading, spacing: 18) {
            // The wait in the countdown's style, swapping through a blur when the style changes.
            Group {
                switch countdown.style {
                case .calendar:
                    HStack(spacing: 18) {
                        ForEach(Calendar.app.monthsShown(now: .now, target: target), id: \.self) { month in
                            MonthGrid(month: month, target: target, tint: tint, showsTitle: true)
                        }
                    }
                    .frame(height: 190)
                case .fill:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int((countdown.progress() * 100).rounded()))%")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(tint)
                        Text(days > 0 ? "of the wait is behind" : "The wait is over")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                case .timeline:
                    CountdownTimeline(start: start, target: target, waited: waited, daysLeft: days, tint: tint,
                                      thickness: 6, animated: animated)
                        .padding(.vertical, 12)
                }
            }
            .id(countdown.style)
            .transition(.blurReplace)

            // Two rows, so each side lines up with the other, like the counter's card.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(days > 0 ? "until \(target.untilFormat)" : (days == 0 ? target.untilFormat : "on \(target.untilFormat)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .id(target)
                        .transition(.blurReplace)
                    Spacer(minLength: 0)
                    if days > 0 && total > 0 {
                        WaitPills(waited: waited, total: total, tint: tint, showsPercent: countdown.style != .fill)
                            .frame(width: 170)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if days == 0 {
                        Text("Today")
                            .font(.system(size: 34, weight: .bold))
                    } else if days > 0 {
                        DurationButton(from: .now, to: target)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            DurationButton(from: target, to: .now)
                            Text("ago")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    // The calendar doesn't show how far into the wait it is; the other styles do.
                    if days > 0 && total > 0 && countdown.style == .calendar {
                        RecordTrack(current: waited, target: total, tint: tint, animated: animated)
                            .frame(width: 170)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

/// The next few times a repeating day comes round, like a counter's history the other way.
struct ComingUpCard: View {
    let countdown: Countdown

    var body: some View {
        let tint = countdown.color.color
        let rule = countdown.rule
        let calendar = Calendar.app
        let first = rule.targetIndex(from: countdown.date, now: .now)
        let end = rule.end.map { calendar.startOfDay(for: $0) }
        let indices = (first..<(first + 5)).filter { index in
            end.map { rule.occurrence(index, from: countdown.date) <= $0 } ?? true
        }

        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Coming Up", symbol: "calendar.badge.clock", tint: tint,
                       text: rule.end.map { "\(rule.summary()), until \($0.formatted(date: .abbreviated, time: .omitted))." }
                           ?? "\(rule.summary()).")
            VStack(spacing: 0) {
                ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                    let date = rule.occurrence(index, from: countdown.date)
                    let days = DayMath.daysUntil(date, from: .now)
                    if position > 0 {
                        Divider()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(calendar.isDate(date, equalTo: .now, toGranularity: .year)
                                 ? date.formatted(.dateTime.weekday(.wide).month(.wide).day())
                                 : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                            if let years = years(at: date) {
                                Text(years == 1 ? "1 year" : "\(years) years")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(days == 0 ? "Today" : (days == 1 ? "Tomorrow" : "in \(days) days"))
                            .foregroundStyle(position == 0 ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                            .fontWeight(position == 0 ? .semibold : .regular)
                    }
                    .frame(minHeight: 44)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// For a yearly day: how many years that time marks.
    private func years(at date: Date) -> Int? {
        guard countdown.rule.frequency == .yearly, countdown.countsYears else { return nil }
        let calendar = Calendar.app
        let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: countdown.date), to: date).year ?? 0
        return years > 0 ? years : nil
    }
}

/// Weeks, weekends and workdays still to go.
struct TimeLeftCard: View {
    let countdown: Countdown

    var body: some View {
        let tint = countdown.color.color
        let days = countdown.daysLeft()
        let left = DayMath.timeLeft(until: countdown.target(), from: .now)

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Time Left", symbol: "hourglass", tint: tint, text: insight(days: days, left: left))
            if days > 0 {
                HStack(alignment: .top) {
                    stat("Weeks", value: days / 7, detail: days % 7 > 0 ? "+ \(days % 7)d" : nil, tint: tint)
                    stat("Weekends", value: left.weekends, tint: tint)
                    stat("Workdays", value: left.workdays, tint: tint)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func insight(days: Int, left: TimeLeft) -> String {
        if days == 0 {
            return "It’s today."
        }
        if days == 1 {
            return "Tomorrow."
        }
        let weekends = left.weekends == 1 ? "1 weekend" : "\(left.weekends) weekends"
        let workdays = left.workdays == 1 ? "1 workday" : "\(left.workdays) workdays"
        return "\(weekends) and \(workdays) to go, counting today."
    }

    private func stat(_ label: String, value: Int, detail: String? = nil, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(value)))
                if let detail {
                    Text(detail)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \Countdown.sortOrder) var countdowns: [Countdown]
    NavigationStack {
        if let countdown = countdowns.first {
            CountdownDetailView(countdown: countdown, onDelete: {}, onCountedSince: {})
        }
    }
}
