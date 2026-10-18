import EventKit
import SwiftData
import SwiftUI

/// Which calendars and Reminders lists are synced, and how far ahead.
enum SyncSettings {
    /// Calendar or list identifier → days ahead.
    private static let key = "syncedCalendars"
    /// Items whose countdown was deleted here, so they aren't brought back.
    private static let skippedKey = "syncSkipped"

    static var ranges: [String: Int] {
        Settings.defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    static func setRange(_ days: Int?, for id: String) {
        var ranges = ranges
        ranges[id] = days
        Settings.defaults.set(ranges, forKey: key)
    }

    static var skipped: Set<String> {
        Set(Settings.defaults.stringArray(forKey: skippedKey) ?? [])
    }

    /// A synced countdown deleted here stays deleted.
    static func skip(_ countdown: Countdown) {
        guard countdown.isSynced, let id = countdown.calendarItemID else { return }
        skip(id: id)
    }

    static func skip(id: String) {
        Settings.defaults.set(Array(skipped.union([id])), forKey: skippedKey)
    }

    /// The choices of how far ahead: a week to a year.
    static let choices: [(title: String, days: Int)] = [
        ("A Week", 7), ("A Month", 31), ("3 Months", 92), ("A Year", 366),
    ]
}

/// Reads the chosen calendars and Reminders lists and brings the Until tab in step with them. Runs when
/// Since comes to the foreground and whenever Calendar or Reminders change while it's open.
enum CalendarSyncRunner {
    private static var isRunning = false

    static func run(_ context: ModelContext) async {
        let ranges = SyncSettings.ranges
        let countdowns = (try? context.fetch(FetchDescriptor<Countdown>())) ?? []
        guard !isRunning, !ranges.isEmpty || countdowns.contains(where: \.isSynced) else { return }
        isRunning = true
        defer { isRunning = false }

        let store = EKEventStore.shared
        let eventsAllowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let remindersAllowed = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        var items: [SyncedItem] = []
        if eventsAllowed {
            for calendar in store.calendars(for: .event) {
                guard let days = ranges[calendar.calendarIdentifier] else { continue }
                items += CalendarEvent.upcoming(in: store, calendars: [calendar], days: days).map(SyncedItem.init)
            }
        }
        if remindersAllowed {
            for list in store.calendars(for: .reminder) {
                guard let days = ranges[list.calendarIdentifier] else { continue }
                items += await reminders(in: list, days: days, store: store)
            }
        }

        // Without access nothing can be told about what's there, so those countdowns are left as they are.
        let readable = countdowns.filter { countdown in
            switch countdown.syncSource {
            case .calendar: eventsAllowed
            case .reminders: remindersAllowed
            case nil: true
            }
        }
        let changes = CalendarSync.apply(items, synced: Set(ranges.keys), to: readable,
                                         skipped: SyncSettings.skipped) { countdown in
            guard let id = countdown.calendarItemID, let item = store.calendarItem(withIdentifier: id),
                  item.calendar.calendarIdentifier == countdown.syncCalendarID else { return .deleted }
            if let reminder = item as? EKReminder, reminder.isCompleted {
                return .completed
            }
            return .outOfRange
        }
        guard !changes.inserts.isEmpty || !changes.deletes.isEmpty || context.hasChanges else { return }
        withAnimation(.smooth) {
            for countdown in changes.inserts {
                context.insert(countdown)
            }
            for countdown in changes.deletes {
                context.delete(countdown)
            }
        }
        saveChanges(context)
    }

    /// Tasks not done yet with a due date up to `days` ahead (overdue ones too).
    private static func reminders(in list: EKCalendar, days: Int, store: EKEventStore) async -> [SyncedItem] {
        let calendar = Calendar.app
        let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now))!
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: [list])
        return await ReminderFetcher.fetch(predicate, from: store, listID: list.calendarIdentifier,
                                           color: CounterColor.nearest(to: UIColor(cgColor: list.cgColor)))
    }
}

/// EventKit hands reminders over on a queue of its own, so they're read here, away from the main actor.
nonisolated enum ReminderFetcher {
    static func fetch(_ predicate: NSPredicate, from store: EKEventStore, listID: String,
                      color: CounterColor) async -> [SyncedItem] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap { item(from: $0, listID: listID, color: color) })
            }
        }
    }

    private static func item(from reminder: EKReminder, listID: String, color: CounterColor) -> SyncedItem? {
        let calendar = Calendar.app
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, let due = reminder.dueDateComponents, let date = calendar.date(from: due) else { return nil }
        let hasTime = due.hour != nil
        return SyncedItem(id: reminder.calendarItemIdentifier, externalID: reminder.calendarItemExternalIdentifier,
                          source: .reminders, calendarID: listID, title: title,
                          date: hasTime ? date : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date,
                          isAllDay: !hasTime, rule: nil, repeats: reminder.hasRecurrenceRules,
                          location: reminder.location, coordinate: nil, color: color, symbol: "checklist")
    }
}

extension SyncedItem {
    init(_ event: CalendarEvent) {
        self.init(id: event.id, externalID: event.externalID, source: .calendar, calendarID: event.calendarID,
                  title: event.title,
                  date: event.isAllDay
                      ? Calendar.app.date(bySettingHour: 12, minute: 0, second: 0, of: event.date) ?? event.date
                      : event.date,
                  isAllDay: event.isAllDay, rule: event.rule, repeats: event.repeatsInCalendar,
                  location: event.location, coordinate: event.coordinate, color: event.color, symbol: event.symbol)
    }
}
