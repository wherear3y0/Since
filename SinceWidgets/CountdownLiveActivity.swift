import ActivityKit
import SwiftUI
import WidgetKit

/// A countdown's day on the Lock Screen and in the Dynamic Island. Started by the app on the day itself,
/// only for the countdowns that have it turned on.
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            CountdownActivityView(state: context.state)
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
                    Text(Self.detail(of: state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

/// The Lock Screen banner: the countdown's icon and title, what the day marks, and "Today".
struct CountdownActivityView: View {
    let state: CountdownActivityAttributes.ContentState

    var body: some View {
        let tint = CountdownLiveActivity.tint(of: state)
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
        .padding(16)
    }
}
