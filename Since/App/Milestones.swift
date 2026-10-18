import Foundation
import SwiftData
import UserNotifications

/// Local notifications for round dates (half a year and every anniversary of a counter's current streak)
/// and for countdowns (a week before, the day before and on the day).
enum Milestones {
    /// Asks for permission the first time a counter turns reminders on. Returns whether they're allowed.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Replaces every pending reminder with fresh ones. Cheap, so it runs after every change.
    static func reschedule(_ counters: [Counter], countdowns: [Countdown]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for counter in counters where counter.notifyMilestones && !counter.isGone {
            let since = counter.currentStreakStart.formatted(date: .long, time: .omitted)
            for milestone in upcoming(for: counter).prefix(3) {
                schedule(title: counter.title,
                         body: counter.isOwned ? "\(milestone.name) with it, since \(since)." : "\(milestone.name) since \(since).",
                         on: milestone.date, id: counter.id, url: "since://counter/\(counter.id.uuidString)")
            }
        }
        // A timer always says when it's up; that's what it's for.
        for countdown in countdowns where !countdown.isArchived {
            var due = countdown.notifyBefore || countdown.isTimer ? reminders(for: countdown) : []
            if let leave = leaveReminder(for: countdown) {
                due.append(leave)
            }
            // A pickup point's last day is always worth a reminder: the parcel goes back after it.
            due += storageReminders(for: countdown)
            for reminder in due {
                schedule(title: countdown.title, body: reminder.name, on: reminder.date, exactly: reminder.isExact,
                         id: countdown.id, url: "since://countdown/\(countdown.id.uuidString)")
            }
        }
    }

    /// One notification at the reminder time from Settings, or at `date` itself when `exactly`.
    private static func schedule(title: String, body: String, on date: Date, exactly: Bool = false, id: UUID,
                                 url: String) {
        let minutes = Settings.defaults.object(forKey: Settings.reminderTimeKey) as? Int ?? Settings.defaultReminderTime
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url]

        var components = Calendar.app.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if !exactly {
            components.hour = minutes / 60
            components.minute = minutes % 60
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "\(id.uuidString)-\(date.timeIntervalSince1970)",
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// "Time to leave": when to set off, from the travel time, if it's turned on and still ahead.
    static func leaveReminder(for countdown: Countdown, now: Date = .now, calendar: Calendar = .app) -> Milestone? {
        guard countdown.remindsToLeave, let leave = countdown.leaveTime(now: now, calendar: calendar), leave > now,
              let minutes = countdown.travelMinutes else { return nil }
        let place = countdown.placeName.map { " to \($0)" } ?? ""
        return Milestone(name: "Time to leave: \(minutes) min\(place) \(countdown.travelMode.phrase).", date: leave,
                         isExact: true)
    }

    struct Milestone {
        let name: String
        let date: Date
        /// At `date`'s own time rather than the reminder time from Settings.
        var isExact = false
    }

    /// Half a year, then 1 year, 2 years… counted by calendar from the start of the current streak.
    static func upcoming(for counter: Counter, now: Date = .now, calendar: Calendar = .app) -> [Milestone] {
        let start = calendar.startOfDay(for: counter.currentStreakStart)
        let today = calendar.startOfDay(for: now)
        var milestones = [Milestone(name: "Half a year", date: calendar.date(byAdding: .month, value: 6, to: start)!)]
        for year in 1...100 {
            let name = year == 1 ? "One year" : "\(year) years"
            milestones.append(Milestone(name: name, date: calendar.date(byAdding: .year, value: year, to: start)!))
        }
        return milestones.filter { $0.date >= today }
    }

    /// The day before a pickup point stops keeping a parcel, and its last day, with the code to show there.
    static func storageReminders(for countdown: Countdown, now: Date = .now, calendar: Calendar = .app) -> [Milestone] {
        guard countdown.isParcel, !countdown.isArchived, let until = countdown.storageUntil else { return [] }
        let last = calendar.startOfDay(for: until)
        let code = countdown.pickupCode.map { " Code \($0)." } ?? ""
        return [
            Milestone(name: "Pick it up by tomorrow.\(code)", date: calendar.date(byAdding: .day, value: -1, to: last)!),
            Milestone(name: "Last day to pick it up.\(code)", date: last),
        ].filter { $0.date >= calendar.startOfDay(for: now) }
    }

    /// A week before, the day before and on the day, for the next times a countdown's day comes round
    /// (up to three, for a repeating day). Skips days already gone, and days before the time round
    /// ahead of them: a daily countdown only gets "It's today!".
    static func reminders(for countdown: Countdown, now: Date = .now, calendar: Calendar = .app) -> [Milestone] {
        let rule = countdown.rule
        let today = calendar.startOfDay(for: now)
        if countdown.isTimer {
            return countdown.date > now ? [Milestone(name: "Time’s up.", date: countdown.date, isExact: true)] : []
        }
        // A window: ahead of its first day, and on it.
        if let window = countdown.window(calendar: calendar) {
            let start = window.lowerBound
            return [
                Milestone(name: "Due in a week: \(window.rangeFormat).", date: calendar.date(byAdding: .day, value: -7, to: start)!),
                Milestone(name: "Due from tomorrow: \(window.rangeFormat).", date: calendar.date(byAdding: .day, value: -1, to: start)!),
                Milestone(name: "Could come any day now, by \(window.upperBound.formatted(.dateTime.month(.abbreviated).day())).",
                          date: start),
            ].filter { $0.date >= today }
        }
        let time = countdown.hasTime ? calendar.dateComponents([.hour, .minute], from: countdown.date) : nil
        // A day marked done gets no more reminders: they start from its next time.
        let first = countdown.currentIndex(now: now, calendar: calendar)
        var reminders: [Milestone] = []
        for index in first..<(first + (rule.repeats ? 3 : 1)) {
            let target = rule.occurrence(index, from: countdown.date, calendar: calendar)
            if target < today || rule.end.map({ target > calendar.startOfDay(for: $0) }) == true {
                break
            }
            let previous = index > 0 ? rule.occurrence(index - 1, from: countdown.date, calendar: calendar) : nil
            let weekday = target.formatted(.dateTime.weekday(.wide))
            // With a time, the one on the day comes right at it.
            let moment = time.flatMap { calendar.date(bySettingHour: $0.hour ?? 0, minute: $0.minute ?? 0, second: 0, of: target) }
            let candidates = [
                Milestone(name: "In a week, on \(weekday).", date: calendar.date(byAdding: .day, value: -7, to: target)!),
                Milestone(name: "Tomorrow.", date: calendar.date(byAdding: .day, value: -1, to: target)!),
                moment.map { Milestone(name: "It’s time!", date: $0, isExact: true) } ?? Milestone(name: "It’s today!", date: target),
            ]
            reminders += candidates.filter { candidate in
                (candidate.isExact ? candidate.date > now : candidate.date >= today)
                    && (previous.map { candidate.date > $0 } ?? true)
            }
        }
        return reminders
    }
}
