import Foundation

/// What a habit cost a day, so a "quit" counter can say what's been saved over its clean days.
/// For smoking: cigarettes a day, the price of a pack and how many are in it, minutes per cigarette.
nonisolated struct Savings: Equatable {
    var unitsPerDay: Double
    /// What `unitsPerPrice` units cost, like a pack of 20.
    var price: Double
    var unitsPerPrice: Int
    var minutesPerUnit: Double

    var moneyPerDay: Double {
        unitsPerPrice > 0 ? unitsPerDay / Double(unitsPerPrice) * price : 0
    }

    /// Cigarettes (or cups, or drinks) not had over `days` days.
    func units(days: Int) -> Double {
        unitsPerDay * Double(max(0, days))
    }

    func money(days: Int) -> Double {
        moneyPerDay * Double(max(0, days))
    }

    func minutes(days: Int) -> Double {
        unitsPerDay * minutesPerUnit * Double(max(0, days))
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
