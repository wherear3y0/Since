import ActivityKit
import Foundation

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
    }

    var countdownID: UUID
}
