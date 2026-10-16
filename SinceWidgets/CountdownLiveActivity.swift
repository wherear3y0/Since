import ActivityKit
import SwiftUI
import WidgetKit

/// A countdown's day on the Lock Screen and in the Dynamic Island. Started by the app on the day itself,
/// only for the countdowns that have it turned on.
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            CountdownActivityView(state: context.state, countdownID: context.attributes.countdownID)
                .widgetURL(Self.url(for: context.attributes))
        } dynamicIsland: { context in
            let state = context.state
            let tint = Self.tint(of: state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Today")
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.detail(of: state))
                                .font(.subheadline)
                                .lineLimit(1)
                            if let wait = Self.waitText(of: state) {
                                Text(wait)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        DoneButton(countdownID: context.attributes.countdownID, tint: tint)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text("Today")
                    .font(.caption.bold())
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
            .widgetURL(Self.url(for: context.attributes))
        }
    }

    /// "After 42 days of waiting".
    nonisolated static func waitText(of state: CountdownActivityAttributes.ContentState) -> String? {
        guard let waited = state.waited, waited > 0 else { return nil }
        return waited == 1 ? "After 1 day of waiting" : "After \(waited) days of waiting"
    }

    nonisolated static func tint(of state: CountdownActivityAttributes.ContentState) -> Color {
        (CounterColor(rawValue: state.colorName) ?? .blue).color
    }

    /// "Turns 42 today", "10 years today", or the date.
    nonisolated static func detail(of state: CountdownActivityAttributes.ContentState) -> String {
        if let turns = state.turns {
            return state.isBirthday ? "Turns \(turns) today" : (turns == 1 ? "1 year today" : "\(turns) years today")
        }
        return state.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    nonisolated static func url(for attributes: CountdownActivityAttributes) -> URL? {
        URL(string: "since://countdown/\(attributes.countdownID.uuidString)")
    }
}

/// The Lock Screen banner: the countdown's icon, title and what the day marks, "Today", the wait behind it
/// and Done. In StandBy (the iPhone on its side, charging) it fills the screen with bigger type instead.
struct CountdownActivityView: View {
    let state: CountdownActivityAttributes.ContentState
    let countdownID: UUID

    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        if isFullscreen {
            standBy
        } else {
            banner
        }
    }

    private var tint: Color { CountdownLiveActivity.tint(of: state) }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: state.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(CountdownLiveActivity.detail(of: state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Today")
                    .font(.title2.bold())
                    .foregroundStyle(tint)
            }
            HStack(spacing: 10) {
                // The wait, all filled in.
                Capsule()
                    .fill(tint)
                    .frame(height: 6)
                if let wait = CountdownLiveActivity.waitText(of: state) {
                    Text(wait)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                DoneButton(countdownID: countdownID, tint: tint)
            }
        }
        .padding(16)
    }

    private var standBy: some View {
        HStack(spacing: 24) {
            Image(systemName: state.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 110, height: 110)
                .background(tint.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(.system(size: 17, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(tint)
                Text(state.title)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(CountdownLiveActivity.detail(of: state))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let wait = CountdownLiveActivity.waitText(of: state) {
                    Text(wait)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

/// Marks the countdown done right from the Live Activity, without opening the app.
struct DoneButton: View {
    let countdownID: UUID
    let tint: Color

    var body: some View {
        Button(intent: CompleteCountdownIntent(countdownID: countdownID)) {
            Label("Done", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}
