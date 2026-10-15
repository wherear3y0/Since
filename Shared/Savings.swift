import Foundation

/// What a habit cost a day, so a "quit" counter can say what's been saved over its clean days.
/// For smoking: cigarettes a day, the price of a pack and how many are in it, minutes per cigarette.
nonisolated struct Savings: Equatable {
    var unitsPerDay: Double
    /// What `unitsPerPrice` units cost, like a pack of 20.
    var price: Double
    var unitsPerPrice: Int
    var minutesPerUnit: Double

    var moneyPerUnit: Double {
        unitsPerPrice > 0 ? price / Double(unitsPerPrice) : 0
    }

    var moneyPerDay: Double {
        unitsPerDay * moneyPerUnit
    }

    /// Cigarettes (or cups, or drinks) not had over `days` days, less the ones had in slips.
    func units(days: Int, less slipped: Double = 0) -> Double {
        max(0, unitsPerDay * Double(max(0, days)) - slipped)
    }

    func money(units: Double) -> Double {
        units * moneyPerUnit
    }

    func minutes(units: Double) -> Double {
        units * minutesPerUnit
    }

    /// The currency prices are entered and shown in: the one of the iPhone's region.
    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// "45 min", "7 h 30 min", "3 d 4 h".
    static func timeText(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 {
            return "\(total) min"
        }
        let hours = total / 60
        if hours < 24 {
            return total % 60 == 0 ? "\(hours) h" : "\(hours) h \(total % 60) min"
        }
        return hours % 24 == 0 ? "\(hours / 24) d" : "\(hours / 24) d \(hours % 24) h"
    }
}

/// A step in how the body recovers after the last cigarette, as the WHO lists them.
nonisolated struct HealthMilestone: Identifiable, Hashable {
    let id: Int
    /// How long after the last cigarette.
    let after: DateComponents
    /// "20 minutes", "2 weeks".
    let when: String
    let text: String

    /// When this step is reached for a streak that started at `start`.
    func date(from start: Date, calendar: Calendar = .app) -> Date {
        calendar.date(byAdding: after, to: start) ?? start
    }

    static let smoking: [HealthMilestone] = [
        HealthMilestone(id: 0, after: DateComponents(minute: 20), when: "20 minutes",
                        text: "Heart rate and blood pressure drop."),
        HealthMilestone(id: 1, after: DateComponents(hour: 12), when: "12 hours",
                        text: "Carbon monoxide in the blood drops to normal."),
        HealthMilestone(id: 2, after: DateComponents(day: 14), when: "2 weeks",
                        text: "Circulation improves and the lungs work better, over the next weeks."),
        HealthMilestone(id: 3, after: DateComponents(month: 1), when: "1 month",
                        text: "Coughing and shortness of breath decrease, over the next months."),
        HealthMilestone(id: 4, after: DateComponents(year: 1), when: "1 year",
                        text: "The risk of coronary heart disease is about half that of a smoker."),
        HealthMilestone(id: 5, after: DateComponents(year: 5), when: "5 years",
                        text: "The risk of stroke can fall to that of a non-smoker."),
        HealthMilestone(id: 6, after: DateComponents(year: 10), when: "10 years",
                        text: "The risk of dying from lung cancer is about half that of a smoker."),
        HealthMilestone(id: 7, after: DateComponents(year: 15), when: "15 years",
                        text: "The risk of coronary heart disease is that of a non-smoker."),
    ]

    /// The steps reached by `now`, and the next one with how far along the way to it is (0…1).
    static func progress(since start: Date, now: Date = .now, calendar: Calendar = .app)
        -> (reached: [HealthMilestone], next: HealthMilestone?, fraction: Double) {
        let reached = smoking.filter { $0.date(from: start, calendar: calendar) <= now }
        guard let next = smoking.first(where: { $0.date(from: start, calendar: calendar) > now }) else {
            return (reached, nil, 1)
        }
        let from = reached.last.map { $0.date(from: start, calendar: calendar) } ?? start
        let to = next.date(from: start, calendar: calendar)
        let total = to.timeIntervalSince(from)
        let fraction = total > 0 ? min(1, max(0, now.timeIntervalSince(from) / total)) : 0
        return (reached, next, fraction)
    }
}
