import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// A countdown's day as a Live Activity, on the Lock Screen and in the Dynamic Island, on the day itself.
/// Shared by the app, which starts and ends it, and the widgets, which draw it.
nonisolated struct CountdownActivityAttributes: ActivityAttributes {
    /// Everything shown, so an edit made in the app on the day can update the activity.
    nonisolated struct ContentState: Codable, Hashable {
        var title: String
        var symbol: String
        var colorName: String
        /// The day, at its start.
        var day: Date
        /// The age a birthday marks, or the year an anniversary marks; nil when it isn't known.
        var turns: Int?
        var isBirthday: Bool
        /// How many days the wait took. Optional, so a state saved by an earlier version still reads.
        var waited: Int? = nil
        /// Days still to go, when it's shown ahead of the day; nil or 0 on the day.
        var daysLeft: Int? = nil
        /// When it comes, when it has a time (or when a timer ends): ticks down to it.
        var moment: Date? = nil
        /// A quick timer, counted from `start` to `moment`.
        var isTimer: Bool? = nil
        var start: Date? = nil
    }

    var countdownID: UUID
}

/// Done on the Live Activity: marks the countdown done and ends the activity. A Live Activity intent runs
/// in the app's process, even when it's tapped on the Lock Screen, so it changes the app's own database.
struct CompleteCountdownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Countdown Done"
    static let isDiscoverable = false

    @Parameter(title: "Countdown")
    var countdownID: String

    init() {}

    init(countdownID: UUID) {
        self.countdownID = countdownID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: countdownID) else { return .result() }
        let context = Store.container.mainContext
        if let countdown = try? context.fetch(FetchDescriptor<Countdown>(predicate: #Predicate { $0.id == id })).first {
            countdown.markDone()
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        await CountdownActivityEnder.end(countdownID: id)
        return .result()
    }
}

/// Ends a countdown's Live Activities, off the main actor like the other ActivityKit calls.
nonisolated enum CountdownActivityEnder {
    @concurrent
    static func end(countdownID: UUID) async {
        for activity in Activity<CountdownActivityAttributes>.activities
        where activity.attributes.countdownID == countdownID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
