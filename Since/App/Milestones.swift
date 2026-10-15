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

        for counter in counters where counter.notifyMilestones {
            for milestone in upcoming(for: counter).prefix(3) {
                schedule(title: counter.title,
                         body: "\(milestone.name) since \(counter.currentStreakStart.formatted(date: .long, time: .omitted)).",
                         on: milestone.date, id: counter.id, url: "since://counter/\(counter.id.uuidString)")
            }
        }
        for countdown in countdowns where countdown.notifyBefore && !countdown.isArchived {
            for reminder in reminders(for: countdown) {
                schedule(title: countdown.title, body: reminder.name, on: reminder.date, id: countdown.id,
                         url: "since://countdown/\(countdown.id.uuidString)")
            }
        }
    }

    /// One notification at the reminder time from Settings.
    private static func schedule(title: String, body: String, on date: Date, id: UUID, url: String) {
        let minutes = Settings.defaults.object(forKey: Settings.reminderTimeKey) as? Int ?? Settings.defaultReminderTime
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url]

        var components = Calendar.app.dateComponents([.year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "\(id.uuidString)-\(date.timeIntervalSince1970)",
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    struct Milestone {
        let name: String
        let date: Date
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

    /// A week before, the day before and on the day, for the next times a countdown's day comes round
    /// (up to three, for a repeating day). Skips days already gone, and days before the time round
    /// ahead of them: a daily countdown only gets "It's today!".
    static func reminders(for countdown: Countdown, now: Date = .now, calendar: Calendar = .app) -> [Milestone] {
        let rule = countdown.rule
        let today = calendar.startOfDay(for: now)
        let first = rule.targetIndex(from: countdown.date, now: now, calendar: calendar)
        var reminders: [Milestone] = []
        for index in first..<(first + (rule.repeats ? 3 : 1)) {
            let target = rule.occurrence(index, from: countdown.date, calendar: calendar)
            if target < today || rule.end.map({ target > calendar.startOfDay(for: $0) }) == true {
                break
            }
            let previous = index > 0 ? rule.occurrence(index - 1, from: countdown.date, calendar: calendar) : nil
            let weekday = target.formatted(.dateTime.weekday(.wide))
            let candidates = [
                Milestone(name: "In a week, on \(weekday).", date: calendar.date(byAdding: .day, value: -7, to: target)!),
                Milestone(name: "Tomorrow.", date: calendar.date(byAdding: .day, value: -1, to: target)!),
                Milestone(name: "It’s today!", date: target),
            ]
            reminders += candidates.filter { candidate in
                candidate.date >= today && (previous.map { candidate.date > $0 } ?? true)
            }
        }
        return reminders
    }
}
