import ActivityKit
import SwiftUI
import WidgetKit

/// A countdown on the Lock Screen and in the Dynamic Island: on its day, from some days before it,
/// or while a timer runs. Started by the app, only for the countdowns that have it turned on.
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            CountdownActivityView(state: context.state, countdownID: context.attributes.countdownID,
                                  isOver: context.isStale)
                .widgetURL(Self.url(for: context.attributes))
        } dynamicIsland: { context in
            let state = context.state
            let tint = Self.tint(of: state)
            let isOver = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimeLeft(state: state, isOver: isOver)
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                        .frame(maxWidth: 110, alignment: .trailing)
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
                            Text(Self.detail(of: state, isOver: isOver))
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
                        if Self.isTheDay(state) {
                            DoneButton(countdownID: context.attributes.countdownID, tint: tint)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(tint)
            } compactTrailing: {
                ActivityTimeLeft(state: state, isOver: isOver, isShort: true)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
            .widgetURL(Self.url(for: context.attributes))
        }
    }

    /// On the day (not a timer): it can be marked done.
    nonisolated static func isTheDay(_ state: CountdownActivityAttributes.ContentState) -> Bool {
        state.isTimer != true && (state.daysLeft ?? 0) == 0
    }

    /// "After 42 days of waiting", only on the day.
    nonisolated static func waitText(of state: CountdownActivityAttributes.ContentState) -> String? {
        guard isTheDay(state), let waited = state.waited, waited > 0 else { return nil }
        return waited == 1 ? "After 1 day of waiting" : "After \(waited) days of waiting"
    }

    nonisolated static func tint(of state: CountdownActivityAttributes.ContentState) -> Color {
        (CounterColor(rawValue: state.colorName) ?? .blue).color
    }

    /// "Turns 42 today", "10 years today", "Today at 7:30 PM", "Oct 25", or a timer's end.
    nonisolated static func detail(of state: CountdownActivityAttributes.ContentState, isOver: Bool = false) -> String {
        if state.isTimer == true {
            return isOver ? "Time’s up" : "Ends at \(state.moment?.formatted(date: .omitted, time: .shortened) ?? "")"
        }
        if isTheDay(state), let turns = state.turns {
            return state.isBirthday ? "Turns \(turns) today" : (turns == 1 ? "1 year today" : "\(turns) years today")
        }
        if isTheDay(state), let moment = state.moment {
            return "Today at \(moment.formatted(date: .omitted, time: .shortened))"
        }
        // Ahead of the day: "Tue, Oct 27", with the time when it has one.
        let day = state.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return state.moment.map { "\(day) · \($0.formatted(date: .omitted, time: .shortened))" } ?? day
    }

    nonisolated static func url(for attributes: CountdownActivityAttributes) -> URL? {
        URL(string: "since://countdown/\(attributes.countdownID.uuidString)")
    }
}

/// What's left: "3 days" ahead of the day, the time ticking down on a day with a time (or a timer),
/// "Now" once it's come, "Today" otherwise.
struct ActivityTimeLeft: View {
    let state: CountdownActivityAttributes.ContentState
    var isOver = false
    /// For the Dynamic Island: "3d".
    var isShort = false

    var body: some View {
        let days = state.daysLeft ?? 0
        Group {
            if days > 0 && state.isTimer != true {
                Text(isShort ? "\(days)d" : (days == 1 ? "1 day" : "\(days) days"))
            } else if let moment = state.moment {
                if !isOver && moment > .now {
                    Text(timerInterval: Date.now...moment, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("Now")
                }
            } else {
                Text("Today")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The Lock Screen banner: the countdown's icon, title and what the day marks, what's left, the wait
/// and Done on the day. A timer shows its time ticking down over a bar. In StandBy (the iPhone on its side,
/// charging) it fills the screen with bigger type instead.
struct CountdownActivityView: View {
    let state: CountdownActivityAttributes.ContentState
    let countdownID: UUID
    var isOver = false

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
                Image(systemName: isOver ? "checkmark" : state.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(CountdownLiveActivity.detail(of: state, isOver: isOver))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ActivityTimeLeft(state: state, isOver: isOver)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            HStack(spacing: 10) {
                bar
                if let wait = CountdownLiveActivity.waitText(of: state) {
                    Text(wait)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if CountdownLiveActivity.isTheDay(state) {
                    DoneButton(countdownID: countdownID, tint: tint)
                }
            }
        }
        .padding(16)
    }

    /// How much of the wait is behind: a timer's fills by itself as it runs.
    @ViewBuilder
    private var bar: some View {
        if state.isTimer == true, let start = state.start, let moment = state.moment, !isOver, start < moment {
            ProgressView(timerInterval: start...moment, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        } else {
            let waited = Double(state.waited ?? 0)
            let days = Double(state.daysLeft ?? 0)
            let progress = isOver || days == 0 ? 1 : waited / max(1, waited + days)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.25))
                    Capsule().fill(tint)
                        .frame(width: max(6, proxy.size.width * progress))
                }
            }
            .frame(height: 6)
        }
    }

    private var standBy: some View {
        HStack(spacing: 24) {
            Image(systemName: isOver ? "checkmark" : state.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 110, height: 110)
                .background(tint.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                ActivityTimeLeft(state: state, isOver: isOver)
                    .font(.system(size: 17, weight: .heavy))
                    .textCase(.uppercase)
                    .kerning(2)
                    .foregroundStyle(tint)
                Text(state.title)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(CountdownLiveActivity.detail(of: state, isOver: isOver))
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
