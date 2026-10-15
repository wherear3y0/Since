import ActivityKit
import Foundation

/// Live Activities for the countdowns that have one turned on, on their day. An app can only start one
/// while it's open, so this runs whenever Since comes to the foreground and after every change.
/// Each countdown gets one a day: once it's ended or swiped away, it isn't brought back that day
/// unless its switch is turned on again.
enum LiveActivities {
    /// Countdown IDs and the day their activity was last started, so it starts only once a day.
    private static let startedKey = "liveActivityStarted"

    static func refresh(_ countdowns: [Countdown], now: Date = .now) {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: today)!

        var wanted: [UUID: CountdownActivityAttributes.ContentState] = [:]
        for countdown in countdowns where countdown.wantsLiveActivity(now: now, calendar: calendar) {
            wanted[countdown.id] = CountdownActivityAttributes.ContentState(
                title: countdown.title, symbol: countdown.symbol, colorName: countdown.colorName,
                day: countdown.target(now: now, calendar: calendar), turns: countdown.turns(now: now, calendar: calendar),
                isBirthday: countdown.isBirthday)
        }
        let started = startedDays()
        let mayStart = Set(wanted.keys.filter { started[$0.uuidString] != today.timeIntervalSince1970 })

        Task {
            let newlyStarted = await LiveActivityRunner.sync(wanted: wanted, mayStart: mayStart, until: endOfDay)
            remember(newlyStarted, on: today)
        }
    }

    /// Lets a countdown's activity start again today, when its switch is turned back on.
    static func allowRestart(of id: UUID) {
        var started = startedDays()
        started[id.uuidString] = nil
        Settings.defaults.set(started, forKey: startedKey)
    }

    static var areEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static func startedDays() -> [String: Double] {
        Settings.defaults.dictionary(forKey: startedKey) as? [String: Double] ?? [:]
    }

    private static func remember(_ ids: Set<UUID>, on day: Date) {
        // Only today's entries matter; older ones are dropped.
        var started = startedDays().filter { $0.value == day.timeIntervalSince1970 }
        for id in ids {
            started[id.uuidString] = day.timeIntervalSince1970
        }
        Settings.defaults.set(started, forKey: startedKey)
    }
}

/// The ActivityKit calls, made off the main actor.
nonisolated enum LiveActivityRunner {
    /// Updates the running activities that are still wanted, ends the rest, and starts the wanted ones
    /// that may start and aren't running. Returns the IDs of the countdowns it started.
    @concurrent
    static func sync(wanted: [UUID: CountdownActivityAttributes.ContentState], mayStart: Set<UUID>,
                     until endOfDay: Date) async -> Set<UUID> {
        var running = Set<UUID>()
        for activity in Activity<CountdownActivityAttributes>.activities {
            let id = activity.attributes.countdownID
            let isLive = activity.activityState == .active || activity.activityState == .stale
            if let state = wanted[id], isLive, !running.contains(id) {
                running.insert(id)
                if activity.content.state != state {
                    await activity.update(ActivityContent(state: state, staleDate: endOfDay))
                }
            } else if isLive {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }
        var started = Set<UUID>()
        for (id, state) in wanted where mayStart.contains(id) && !running.contains(id) {
            // Fails when the app isn't in the foreground (like when Siri changed something); tried again next time.
            if (try? Activity<CountdownActivityAttributes>.request(
                attributes: CountdownActivityAttributes(countdownID: id),
                content: ActivityContent(state: state, staleDate: endOfDay),
                pushType: nil)) != nil {
                started.insert(id)
            }
        }
        return started
    }
}
