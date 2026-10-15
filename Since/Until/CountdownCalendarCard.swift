import EventKit
import EventKitUI
import SwiftUI

/// The countdown's day in Calendar: a button that opens the day there and, for a countdown picked from
/// Calendar, the event itself, with a note when it has been moved or deleted there. A countdown picked
/// before links were kept is offered the event with its name on its day.
struct CountdownCalendarCard: View {
    let countdown: Countdown

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: LinkState = .loading
    @State private var shownEvent: ShownEvent?

    /// What's known about the countdown's event.
    private enum LinkState {
        case loading
        /// Not picked from Calendar, and nothing like it found there.
        case unlinked
        /// Linked, but Since isn't allowed to read the calendars.
        case needsAccess
        /// Not linked, but there's an event with the same name on its day.
        case match(EKEvent)
        /// The linked event: its next time, for a repeating one.
        case linked(EKEvent)
        /// Linked, but the event is gone from Calendar.
        case deleted
        /// Linked to a repeating event that doesn't come round anymore (in the next two years).
        case ended
    }

    private var store: EKEventStore { .shared }

    private struct ShownEvent: Identifiable {
        let id = UUID()
        let event: EKEvent
    }

    var body: some View {
        let tint = countdown.color.color
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Calendar", symbol: "calendar", tint: tint, text: headline)
            details(tint: tint)
            Button {
                openDay()
            } label: {
                Label("Open in Calendar", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.vertical, 8)
        // Again whenever the link or the day changes, and after the event was shown (it may have been edited).
        .task(id: "\(countdown.calendarItemID ?? "")|\(countdown.target().timeIntervalSince1970)") {
            load()
        }
        // Coming back from Calendar (after Open in Calendar, say), the event may have been moved or deleted.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                load()
            }
        }
        .sheet(item: $shownEvent, onDismiss: load) { shown in
            CalendarEventView(event: shown.event) {
                shownEvent = nil
            }
        }
    }

    // MARK: - Parts

    private var headline: String? {
        switch state {
        case .loading, .unlinked:
            return nil
        case .needsAccess:
            return "This countdown came from Calendar. Allow Since to read your calendars to see the event."
        case .match:
            return "There’s an event with this name on the same day."
        case .linked(let event):
            if isMoved(event) {
                return "It was moved in Calendar to \(dayText(event.startDate ?? countdown.target()))."
            }
            return "From your “\(event.calendar?.title ?? "")” calendar."
        case .deleted:
            return "The event this countdown came from is no longer in Calendar."
        case .ended:
            return "The event this countdown came from doesn’t come round in Calendar anymore."
        }
    }

    @ViewBuilder
    private func details(tint: Color) -> some View {
        switch state {
        case .loading, .unlinked:
            EmptyView()
        case .needsAccess:
            Button(EKEventStore.authorizationStatus(for: .event) == .notDetermined ? "Allow Access" : "Open Settings",
                   systemImage: "lock.open") {
                requestAccess()
            }
            .buttonStyle(.glass)
        case .match(let event):
            eventRow(event)
            Button("Link to This Event", systemImage: "link") {
                linkEvent(event)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
        case .linked(let event):
            eventRow(event)
            HStack(spacing: 8) {
                if isMoved(event) && canUseDate(of: event) {
                    Button {
                        useDate(of: event)
                    } label: {
                        Label("Use New Date", systemImage: "calendar.badge.checkmark")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                }
                Button {
                    shownEvent = ShownEvent(event: event)
                } label: {
                    Label("Show Event", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .lineLimit(1)
        case .deleted, .ended:
            Button("Unlink", systemImage: "link.badge.plus") {
                unlink()
            }
            .buttonStyle(.glass)
        }
    }

    /// The event's calendar color, title, time, place and calendar.
    private func eventRow(_ event: EKEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(event.calendar.map { Color(cgColor: $0.cgColor) } ?? Color.secondary)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? countdown.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(timeText(event))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Reading Calendar

    private var isLinked: Bool {
        countdown.calendarItemID != nil || countdown.calendarExternalID != nil
    }

    private func load() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            state = isLinked ? .needsAccess : .unlinked
            return
        }
        if isLinked {
            if let event = linkedEvent() {
                state = occurrence(of: event).map(LinkState.linked) ?? .ended
            } else {
                state = .deleted
            }
        } else if let event = sameNameEvent() {
            state = .match(event)
        } else {
            state = .unlinked
        }
    }

    private func linkedEvent() -> EKEvent? {
        if let id = countdown.calendarItemID, let event = store.calendarItem(withIdentifier: id) as? EKEvent {
            return event
        }
        // After a full resync the local identifier changes, while the server's one stays.
        if let external = countdown.calendarExternalID, !external.isEmpty,
           let event = store.calendarItems(withExternalIdentifier: external).compactMap({ $0 as? EKEvent }).first {
            countdown.calendarItemID = event.calendarItemIdentifier
            try? context.save()
            return event
        }
        return nil
    }

    /// The time of the event that goes with the countdown: for a repeating event, the one on the countdown's
    /// day if there is one (a countdown made from "next time only" stays on its day), otherwise the next one
    /// from today. Nil when a repeating event has no time left in the coming two years.
    private func occurrence(of event: EKEvent) -> EKEvent? {
        guard event.hasRecurrenceRules, let calendar = event.calendar else { return event }
        let cal = Calendar.app
        let day = cal.startOfDay(for: countdown.target())
        let today = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .year, value: 2, to: max(day, today)) else { return event }
        let predicate = store.predicateForEvents(withStart: min(day, today), end: end, calendars: [calendar])
        let times = store.events(matching: predicate)
            .filter { $0.calendarItemIdentifier == event.calendarItemIdentifier }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        if let onDay = times.first(where: { $0.startDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }) {
            return onDay
        }
        return times.first { ($0.startDate ?? .distantPast) >= today }
    }

    /// An event with the countdown's name on its day, for one picked from Calendar before links were kept.
    /// Only when there's exactly one, so it's not a guess.
    private func sameNameEvent() -> EKEvent? {
        let day = Calendar.app.startOfDay(for: countdown.target())
        guard let end = Calendar.app.date(byAdding: .day, value: 1, to: day) else { return nil }
        let events = store.events(matching: store.predicateForEvents(withStart: day, end: end, calendars: nil))
        // Only an event that repeats like the countdown: a one-off linked to a yearly countdown would look
        // moved from the next year on.
        let same = events.filter {
            $0.hasRecurrenceRules == countdown.rule.repeats
                && ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(countdown.title) == .orderedSame
        }
        return same.count == 1 ? same[0] : nil
    }

    /// The event no longer falls on the countdown's day.
    private func isMoved(_ event: EKEvent) -> Bool {
        guard let start = event.startDate else { return false }
        return !Calendar.app.isDate(start, inSameDayAs: countdown.target())
    }

    private func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Fri, Nov 28 · All day" or "Fri, Nov 28 · 10:00 – 11:30".
    private func timeText(_ event: EKEvent) -> String {
        let start = event.startDate ?? countdown.target()
        let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if event.isAllDay {
            return "\(day) · All day"
        }
        let end = event.endDate ?? start
        return "\(day) · \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Actions

    /// Calendar opens on the day given as seconds since 2001, through the calshow: link it has long handled.
    private func openDay() {
        var day = countdown.target()
        if case .linked(let event) = state, let start = event.startDate {
            day = start
        }
        if let url = URL(string: "calshow:\(Int(day.timeIntervalSinceReferenceDate))") {
            openURL(url)
        }
    }

    private func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            return
        }
        Task {
            _ = try? await store.requestFullAccessToEvents()
            load()
        }
    }

    private func linkEvent(_ event: EKEvent) {
        countdown.calendarItemID = event.calendarItemIdentifier
        countdown.calendarExternalID = event.calendarItemExternalIdentifier
        saveChanges(context)
    }

    private func unlink() {
        countdown.calendarItemID = nil
        countdown.calendarExternalID = nil
        saveChanges(context)
    }

    /// One time of a repeating event moved on its own can't be followed by a repeat rule: only the note shows.
    private func canUseDate(of event: EKEvent) -> Bool {
        !(countdown.rule.repeats && event.isDetached)
    }

    /// Moves the countdown to the day the event now falls on. For a repeating one the whole series moved,
    /// so its first day shifts by as much and the years still count from it.
    private func useDate(of event: EKEvent) {
        guard let start = event.startDate else { return }
        let cal = Calendar.app
        withAnimation(.smooth) {
            if countdown.rule.repeats {
                let shift = DayMath.daysUntil(start, from: countdown.target(), calendar: cal)
                countdown.date = cal.date(byAdding: .day, value: shift, to: countdown.date) ?? countdown.date
            } else {
                countdown.date = cal.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
            }
            if !countdown.hasPassed() {
                countdown.isArchived = false
            }
        }
        saveChanges(context)
    }
}

/// Calendar's own view of an event, where it can also be edited or deleted.
struct CalendarEventView: UIViewControllerRepresentable {
    let event: EKEvent
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}

extension EKEventStore {
    /// One store for the whole app, as EventKit recommends: it's slow to make.
    static let shared = EKEventStore()
}
