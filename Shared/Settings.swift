import Foundation

/// App-wide preferences. Stored in the App Group so the widgets follow them too.
nonisolated enum Settings {
    // UserDefaults is thread-safe; Swift just can't prove it.
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: "group.me.wherar3y0.since") ?? .standard

    /// 0 = follow the system, otherwise 1 = Sunday … 7 = Saturday.
    static let firstWeekdayKey = "firstWeekday"
    /// Minutes after midnight when milestone reminders arrive.
    static let reminderTimeKey = "reminderTime"
    static let defaultReminderTime = 9 * 60
}

extension Calendar {
    /// The current calendar with the week start chosen in Settings.
    nonisolated static var app: Calendar {
        var calendar = Calendar.current
        let firstWeekday = Settings.defaults.integer(forKey: Settings.firstWeekdayKey)
        if (1...7).contains(firstWeekday) {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }
}
