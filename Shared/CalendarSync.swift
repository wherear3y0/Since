import CoreLocation
import EventKit
import Foundation

/// Where a synced countdown comes from.
nonisolated enum SyncSource: String {
    case calendar, reminders
}

/// An event or a reminder, copied out of EventKit, as a countdown made from it should be.
nonisolated struct SyncedItem {
    /// Its `calendarItemIdentifier`.
    var id: String
    var externalID: String?
    var source: SyncSource
    /// The calendar or Reminders list it's in.
    var calendarID: String
    var title: String
    /// The next time it happens, or when a reminder is due.
    var date: Date
    var isAllDay: Bool
    /// The repeat, when Since can follow it.
    var rule: RepeatRule?
    /// It repeats there, whether or not Since can follow the repeat.
    var repeats: Bool
    var location: String?
    var coordinate: CLLocationCoordinate2D?
    var color: CounterColor
    var symbol: String
}

extension Countdown {
    var syncSource: SyncSource? {
        SyncSource(rawValue: syncSourceRaw)
    }

    var isSynced: Bool {
        syncSource != nil
    }

    /// A task from Reminders: while it isn't done it never counts as gone by, just overdue.
    var isReminder: Bool {
        syncSource == .reminders
    }
}

/// Keeps the countdowns made from the chosen calendars and Reminders lists in step with them, one way:
/// new ones appear, moved ones follow (the old day kept in their history), deleted ones go. What's set here
/// (color, size, style, pins) stays. Only the deciding is here, so it can be tested without EventKit.
nonisolated enum CalendarSync {
    /// What became of an item that's no longer among the ones found.
    enum Missing {
        /// Deleted there.
        case deleted
        /// A reminder ticked off there.
        case completed
        /// Still there, but gone by or further ahead than the calendar is synced for.
        case outOfRange
    }

    /// What to do, worked out from the items found and the countdowns there are.
    struct Changes {
        var inserts: [Countdown] = []
        var deletes: [Countdown] = []
    }

    /// - Parameters:
    ///   - items: everything found in the synced calendars and lists, within their range.
    ///   - synced: the IDs of the calendars and lists that are synced now.
    ///   - skipped: items whose countdown was deleted here; they aren't brought back.
    ///   - missing: what became of an item that wasn't found.
    @MainActor
    static func apply(_ items: [SyncedItem], synced: Set<String>, to countdowns: [Countdown], skipped: Set<String>,
                      missing: (Countdown) -> Missing, now: Date = .now, calendar: Calendar = .app) -> Changes {
        var changes = Changes()
        let found = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: now)
        var known = Set<String>()

        for countdown in countdowns {
            // Made by hand from the same event: left alone, and not made a second time.
            guard countdown.isSynced else {
                if let id = countdown.calendarItemID {
                    known.insert(id)
                }
                continue
            }
            guard let id = countdown.calendarItemID, let from = countdown.syncCalendarID, synced.contains(from) else {
                changes.deletes.append(countdown)
                continue
            }
            known.insert(id)
            if let item = found[id] {
                update(countdown, from: item, today: today, calendar: calendar)
                continue
            }
            switch missing(countdown) {
            case .deleted:
                changes.deletes.append(countdown)
            case .completed:
                if !countdown.isArchived {
                    countdown.markDone(now: now, calendar: calendar)
                }
            case .outOfRange:
                // Gone by: it stays, like any other day gone by. Further ahead: it comes back when it's in range.
                if calendar.startOfDay(for: countdown.date) >= today && !countdown.isArchived {
                    changes.deletes.append(countdown)
                }
            }
        }

        let first = (countdowns.map(\.sortOrder).min() ?? 0) - items.count
        for (index, item) in items.enumerated() where !known.contains(item.id) && !skipped.contains(item.id) {
            let countdown = Countdown(title: item.title, symbol: item.symbol, color: item.color, date: item.date,
                                      rule: item.rule ?? .never, sortOrder: first + index)
            countdown.syncSourceRaw = item.source.rawValue
            countdown.syncCalendarID = item.calendarID
            countdown.calendarItemID = item.id
            countdown.calendarExternalID = item.externalID
            // Calendar gives the next time, not the first, so there's no telling how many years it's been.
            countdown.countsYears = false
            countdown.isBirthday = countdown.looksLikeBirthday
            fill(countdown, from: item, calendar: calendar)
            changes.inserts.append(countdown)
            known.insert(item.id)
        }
        return changes
    }

    /// Follows a change made there. A one-off moved to another day keeps the old one in its history,
    /// and comes back out of Past if it's ahead again. A repeating reminder ticked off here comes back
    /// for its next time.
    @MainActor
    private static func update(_ countdown: Countdown, from item: SyncedItem, today: Date, calendar: Calendar) {
        countdown.title = item.title
        let moved = countdown.date != item.date
        if moved {
            if countdown.isReminder && countdown.isArchived {
                // Its next time: not a postponement.
                countdown.doneDay = nil
                countdown.isArchived = false
            } else if !item.repeats && calendar.startOfDay(for: countdown.date) != calendar.startOfDay(for: item.date) {
                countdown.postponedFrom.append(countdown.date)
            }
            countdown.date = item.date
            if !item.repeats && calendar.startOfDay(for: item.date) >= today && !countdown.isReminder {
                countdown.isArchived = false
                countdown.doneDay = nil
            }
        }
        if !item.repeats || item.rule != nil {
            countdown.rule = item.rule ?? .never
        }
        fill(countdown, from: item, calendar: calendar)
    }

    /// The time and the place, from the item.
    @MainActor
    private static func fill(_ countdown: Countdown, from item: SyncedItem, calendar: Calendar) {
        countdown.hasTime = !item.isAllDay
        if let location = item.location, !location.isEmpty {
            let lines = location.components(separatedBy: "\n")
            if countdown.placeName != lines[0] {
                countdown.placeName = lines[0]
                countdown.placeAddress = lines.count > 1 ? lines.dropFirst().joined(separator: ", ") : nil
                countdown.coordinate = item.coordinate
                countdown.travelMinutes = nil
            }
        } else if countdown.placeName != nil && item.location != nil {
            countdown.removePlace()
        }
    }
}

/// Ticks a task off in Reminders when it's done here, and back when that's undone.
enum RemindersBridge {
    private static let store = EKEventStore()

    @MainActor
    static func setCompleted(_ isCompleted: Bool, for countdown: Countdown) {
        guard countdown.isReminder, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let id = countdown.calendarItemID,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
              reminder.isCompleted != isCompleted else { return }
        reminder.isCompleted = isCompleted
        try? store.save(reminder, commit: true)
    }
}
