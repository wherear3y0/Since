import SwiftUI
import SwiftData
import EventKit

/// Upcoming events from the calendars on this iPhone (Google ones too, once the account is added
/// in Settings), to pick and add as countdowns. The countdowns are copies: later changes in Calendar
/// don't follow them.
struct CalendarImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    private enum Access { case unknown, granted, denied }

    @State private var store = EKEventStore()
    @State private var access = Access.unknown
    @State private var events: [CalendarEvent] = []
    @State private var selected: Set<String> = []
    @State private var search = ""
    /// Turns true once events are loaded; the months then blur in one after another.
    @State private var isShown = false

    private var shown: [CalendarEvent] {
        search.isEmpty ? events : events.filter { $0.title.localizedStandardContains(search) }
    }

    /// Shown events by month, soonest first.
    private var months: [(month: Date, events: [CalendarEvent])] {
        let calendar = Calendar.app
        let grouped = Dictionary(grouping: shown) { calendar.dateInterval(of: .month, for: $0.date)!.start }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(months.enumerated()), id: \.element.month) { index, month in
                    Section(monthTitle(month.month)) {
                        ForEach(month.events) { event in
                            row(event)
                        }
                    }
                    .sectionReveal(isShown, delay: 0.04 + Double(min(index, 6)) * 0.06)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .overlay { emptyState }
            .navigationTitle("From Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button(action: add) {
                        Text(selected.count == 1 ? "Add 1 Countdown" : "Add \(selected.count) Countdowns")
                            .font(.headline)
                            .contentTransition(.numericText(value: Double(selected.count)))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.blurRise)
                }
            }
            .animation(.smooth, value: selected.isEmpty)
            .sensoryFeedback(.selection, trigger: selected)
            .task {
                await load()
            }
        }
    }

    // MARK: - Parts

    private func row(_ event: CalendarEvent) -> some View {
        let isAdded = alreadyAdded(event)
        let isSelected = selected.contains(event.id)
        let days = DayMath.daysUntil(event.date, from: .now)

        return Button {
            withAnimation(.snappy) {
                if isSelected {
                    selected.remove(event.id)
                } else {
                    selected.insert(event.id)
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected || isAdded ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? event.color.color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: event.symbol)
                            .foregroundStyle(event.color.color)
                            .font(.subheadline)
                        Text(event.title)
                            .lineLimit(1)
                    }
                    Text(detail(event))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(isAdded ? "Added" : (days == 0 ? "Today" : (days == 1 ? "Tomorrow" : "in \(days)d")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .disabled(isAdded)
    }

    /// "Oct 27 · Every Year · Family", or the next time only when Calendar's repeat is too fine to follow.
    private func detail(_ event: CalendarEvent) -> String {
        var parts = [event.date.formatted(.dateTime.month(.abbreviated).day())]
        if let rule = event.rule {
            parts.append(rule.summary())
        } else if event.repeatsInCalendar {
            parts.append("Next time only")
        }
        parts.append(event.calendarTitle)
        return parts.joined(separator: " · ")
    }

    private func monthTitle(_ month: Date) -> String {
        Calendar.app.isDate(month, equalTo: .now, toGranularity: .year)
            ? month.formatted(.dateTime.month(.wide))
            : month.formatted(.dateTime.month(.wide).year())
    }

    @ViewBuilder
    private var emptyState: some View {
        switch access {
        case .unknown:
            ProgressView()
        case .denied:
            ContentUnavailableView {
                Label("No Access to Calendars", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Allow full access to calendars in Settings to pick events. They stay on this iPhone.")
            } actions: {
                Button("Open Settings") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.glass)
            }
        case .granted:
            if events.isEmpty {
                ContentUnavailableView("No Upcoming Events", systemImage: "calendar",
                                       description: Text("Events from the next year show up here. For Google Calendar, add the account in Settings → Apps → Calendar."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            let allowed = (try? await store.requestFullAccessToEvents()) ?? false
            access = allowed ? .granted : .denied
        default:
            access = .denied
        }
        guard access == .granted else { return }
        events = CalendarEvent.upcoming(in: store)
        try? await Task.sleep(for: .milliseconds(80))
        isShown = true
    }

    /// Already a countdown with the same name on the same day.
    private func alreadyAdded(_ event: CalendarEvent) -> Bool {
        countdowns.contains { countdown in
            countdown.title.localizedCaseInsensitiveCompare(event.title) == .orderedSame
                && Calendar.app.isDate(countdown.target(), inSameDayAs: event.date)
        }
    }

    private func add() {
        let picked = events.filter { selected.contains($0.id) }
        // New countdowns go on top, in the order of the list.
        for (event, order) in zip(picked, Countdown.topOrders(picked.count, above: countdowns)) {
            let countdown = Countdown(title: event.title, symbol: event.symbol, color: event.color,
                                      date: event.date, rule: event.rule ?? .never, sortOrder: order)
            // Calendar gives the next time, not the first, so there's no telling how many years it's been.
            countdown.countsYears = false
            countdown.isBirthday = event.symbol == "birthday.cake.fill" && event.rule?.frequency == .yearly
            context.insert(countdown)
        }
        saveChanges(context)
        dismiss()
    }
}

/// An event from Calendar, copied out of EventKit for the list.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    /// The next time it happens.
    let date: Date
    /// Calendar's repeat as Since can follow it; nil for a one-off, or a repeat too fine to follow.
    let rule: RepeatRule?
    let repeatsInCalendar: Bool
    let calendarTitle: String
    let color: CounterColor
    let symbol: String

    /// Events in the next year, one per repeating series (its next time), soonest first.
    /// Birthdays are left out: they come from Contacts, with the year.
    static func upcoming(in store: EKEventStore, now: Date = .now) -> [CalendarEvent] {
        let calendar = Calendar.app
        let calendars = store.calendars(for: .event).filter { $0.type != .birthday }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .year, value: 1, to: start)!
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
            .sorted { $0.startDate < $1.startDate }
        // The last time each series comes round within the year, for repeats that end after a number of times.
        var lastTime: [String: Date] = [:]
        for event in found {
            lastTime[event.calendarItemIdentifier] = event.startDate
        }

        var seen = Set<String>()
        return found.compactMap { event in
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // A repeating event comes back once per time; only the next one is kept.
            guard !title.isEmpty, seen.insert(event.calendarItemIdentifier).inserted else { return nil }
            let calendarRule = event.recurrenceRules?.first
            return CalendarEvent(id: event.calendarItemIdentifier, title: title, date: event.startDate,
                                 rule: calendarRule.flatMap {
                                     RepeatRule($0, start: event.startDate, lastTime: lastTime[event.calendarItemIdentifier])
                                 },
                                 repeatsInCalendar: calendarRule != nil,
                                 calendarTitle: event.calendar.title,
                                 color: CounterColor.nearest(to: UIColor(cgColor: event.calendar.cgColor)),
                                 symbol: symbol(for: title))
        }
    }

    /// A fitting icon for common kinds of events, in English or Russian; a star otherwise.
    static func symbol(for title: String) -> String {
        let lowercased = title.lowercased()
        let guesses: [(words: [String], symbol: String)] = [
            (["birthday", "день рожд"], "birthday.cake.fill"),
            (["flight", "trip", "vacation", "travel", "holiday", "отпуск", "поездк", "рейс", "путешеств"], "airplane"),
            (["concert", "festival", "gig", "концерт", "фестивал"], "music.note"),
            (["wedding", "anniversary", "date night", "свадьб", "годовщин", "свидани"], "heart.fill"),
            (["exam", "deadline", "defense", "экзамен", "дедлайн", "защит", "сесси"], "graduationcap.fill"),
            (["doctor", "dentist", "врач", "стоматолог", "анализ"], "cross.case.fill"),
            (["gym", "run", "marathon", "workout", "трениров", "марафон", "зал"], "figure.run"),
            (["party", "new year", "вечеринк", "новый год", "праздник"], "sparkles"),
            (["rent", "salary", "pay", "аренд", "зарплат", "оплат"], "creditcard.fill"),
        ]
        return guesses.first { guess in guess.words.contains { lowercased.contains($0) } }?.symbol ?? "star.fill"
    }
}

extension RepeatRule {
    /// Calendar's repeat when Since can follow it: every N days, weeks (on some weekdays), months or years,
    /// ending on a day or after a number of times. Nil for finer ones, like "the second Tuesday of every month".
    /// `lastTime` is the last time the event comes round in the year ahead, for repeats that end after a count.
    init?(_ rule: EKRecurrenceRule, start: Date, lastTime: Date?) {
        let onWeekdays = rule.daysOfTheWeek ?? []
        let isSimple = rule.daysOfTheMonth == nil && rule.monthsOfTheYear == nil && rule.weeksOfTheYear == nil
            && rule.daysOfTheYear == nil && rule.setPositions == nil && onWeekdays.allSatisfy { $0.weekNumber == 0 }
        guard isSimple, onWeekdays.isEmpty || rule.frequency == .weekly else { return nil }

        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        interval = max(1, rule.interval)
        weekdays = Set(onWeekdays.map(\.dayOfTheWeek.rawValue))
        if let endDate = rule.recurrenceEnd?.endDate {
            end = endDate
        } else if rule.recurrenceEnd?.occurrenceCount ?? 0 > 0 {
            // How many times are already behind isn't known, so it ends with its last time in the coming year.
            end = lastTime ?? start
        }
    }
}

extension CounterColor {
    /// The palette color closest to a calendar's color.
    static func nearest(to color: UIColor) -> CounterColor {
        func components(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return (red, green, blue)
        }
        let target = components(color)
        return allCases.min { first, second in
            let a = components(UIColor(first.color)), b = components(UIColor(second.color))
            let distanceA = pow(a.0 - target.0, 2) + pow(a.1 - target.1, 2) + pow(a.2 - target.2, 2)
            let distanceB = pow(b.0 - target.0, 2) + pow(b.1 - target.1, 2) + pow(b.2 - target.2, 2)
            return distanceA < distanceB
        }!
    }
}

#if DEBUG
/// Launch with -seedCalendarEvents, after allowing calendar access, to fill the default calendar
/// with a few events to try the import on.
enum SampleCalendarEvents {
    static func insert() {
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return }
        let existing = Set(CalendarEvent.upcoming(in: store).map(\.title))
        let day = { (n: Int) in Calendar.app.date(byAdding: .day, value: n, to: Calendar.app.startOfDay(for: .now))! }

        let samples: [(String, Date, EKRecurrenceRule?)] = [
            ("Dentist", day(9), nil),
            ("Team offsite", day(20), nil),
            ("Отпуск в Грузии", day(55), nil),
            ("Yoga", day(1), EKRecurrenceRule(recurrenceWith: .weekly, interval: 1,
                                              daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday), EKRecurrenceDayOfWeek(.thursday)],
                                              daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                              daysOfTheYear: nil, setPositions: nil, end: nil)),
            ("Rent", day(17), EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)),
            ("Wedding anniversary", day(40), EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)),
            ("Book club", day(12), EKRecurrenceRule(recurrenceWith: .monthly, interval: 1,
                                                    daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)],
                                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                                    daysOfTheYear: nil, setPositions: nil, end: nil)),
        ]
        for (title, date, rule) in samples where !existing.contains(title) {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = date
            event.endDate = date
            event.isAllDay = true
            event.calendar = calendar
            if let rule {
                event.addRecurrenceRule(rule)
            }
            try? store.save(event, span: .futureEvents)
        }
    }
}
#endif
