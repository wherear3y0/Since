import SwiftUI
import WidgetKit

/// A countdown frozen at one moment of the timeline, so a widget can show tomorrow's numbers ahead of time.
struct CountdownSnapshot {
    let id: UUID
    let title: String
    let symbol: String
    let color: CounterColor
    let tinted: Bool
    let style: CountdownStyle
    /// The day being counted down to at `date`.
    let target: Date
    let waitStart: Date
    let date: Date
    var numberStyle: DurationStyle = .days
    /// The days it can come on, when it's due in a window.
    var window: ClosedRange<Date>? = nil
    /// When it comes, when it has a time.
    var moment: Date? = nil

    var daysLeft: Int { DayMath.daysUntil(target, from: date) }
    var waited: Int { DayMath.days(from: waitStart, to: date) }
    /// A window's wait is up to its middle.
    var total: Int {
        let end = window.map { Calendar.app.date(byAdding: .day, value: DayMath.days(from: $0.lowerBound, to: $0.upperBound) / 2,
                                                  to: $0.lowerBound)! } ?? target
        return DayMath.days(from: waitStart, to: end)
    }
    var isApproximate: Bool { window.map { Calendar.app.startOfDay(for: date) < $0.lowerBound } ?? false }
    var isInWindow: Bool { window?.contains(Calendar.app.startOfDay(for: date)) ?? false }
    var progress: Double { total == 0 ? 1 : min(1, Double(waited) / Double(total)) }
    var timeLeft: TimeLeft { DayMath.timeLeft(until: target, from: date) }

    var tint: Color { color.color.onCard(tinted: tinted) }
    var url: URL { URL(string: "since://countdown/\(id.uuidString)")! }

    /// The time in weeks or months ("6w 1d"), when the countdown is written that way.
    var displayParts: [DurationPart]? {
        guard numberStyle != .days, daysLeft != 0 else { return nil }
        return daysLeft > 0 ? DayMath.parts(from: date, to: target, style: numberStyle)
                            : DayMath.parts(from: target, to: date, style: numberStyle)
    }

    /// "until Nov 26 · Thu", the date itself on the day, "on …" after it; the time or the window when it has one.
    var dateLine: String {
        DayMath.dateLine(target: target, window: window, moment: moment, now: date)
    }
}

extension CountdownSnapshot {
    init(_ countdown: Countdown, at date: Date) {
        self.init(id: countdown.id, title: countdown.title, symbol: countdown.symbol, color: countdown.color,
                  tinted: countdown.tinted, style: countdown.style, target: countdown.target(now: date),
                  waitStart: countdown.waitStart(now: date), date: date, numberStyle: countdown.numberStyle,
                  window: countdown.window(), moment: countdown.moment(now: date))
    }

    /// A stand-in for the widget gallery and placeholders.
    static func sample(at date: Date = .now) -> CountdownSnapshot {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: date)
        return CountdownSnapshot(id: UUID(), title: "Vacation", symbol: "airplane", color: .cyan, tinted: true,
                                 style: .calendar,
                                 target: calendar.date(byAdding: .day, value: 42, to: today)!,
                                 waitStart: calendar.date(byAdding: .day, value: -20, to: today)!, date: date)
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    /// nil when there are no countdowns yet.
    let countdown: CountdownSnapshot?
}

/// One chosen countdown (or the first upcoming one). Refreshes at local midnight.
struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, countdown: .sample())
    }

    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> CountdownEntry {
        let entry = entry(for: configuration, at: .now)
        // The widget gallery shows a sample until the first countdown exists.
        if entry.countdown == nil && context.isPreview {
            return placeholder(in: context)
        }
        return entry
    }

    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<CountdownEntry> {
        // Also at the moment it comes, when it has a time, to turn the ticking time into "Now".
        let moments = entry(for: configuration, at: .now).countdown?.moment.map { [$0] } ?? []
        let entries = WidgetData.timelineDates(adding: moments).map { entry(for: configuration, at: $0) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectCountdownIntent, at date: Date) -> CountdownEntry {
        let countdowns = Store.countdowns()
        // Without a choice: the first pinned one, else the first one ahead.
        let chosen = countdowns.first { $0.id == configuration.countdown?.id }
            ?? countdowns.first { $0.isPinned && !$0.isArchived }
            ?? countdowns.first { !$0.isArchived }
        return CountdownEntry(date: date, countdown: chosen.map { CountdownSnapshot($0, at: date) })
    }
}

/// One countdown in every size: home screen small, medium and large, plus the Lock Screen.
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CountdownWidget", intent: SelectCountdownIntent.self,
                               provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        .description("Days until, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownWidgetView: View {
    let entry: CountdownEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let countdown = entry.countdown {
            content(for: countdown)
                .widgetURL(countdown.url)
                .containerBackground(for: .widget) {
                    if isAccessory {
                        Color.clear
                    } else {
                        WidgetBackground(color: countdown.color, tinted: countdown.tinted,
                                         fillLevel: countdown.style == .fill ? countdown.progress : nil)
                    }
                }
        } else {
            NoCountersView(text: "Add a countdown in Since")
                .containerBackground(for: .widget) {
                    isAccessory ? Color.clear : Color.cardBackground
                }
        }
    }

    private var isAccessory: Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    @ViewBuilder
    private func content(for countdown: CountdownSnapshot) -> some View {
        switch family {
        case .systemMedium: MediumCountdownView(countdown: countdown)
        case .systemLarge: LargeCountdownView(countdown: countdown)
        case .accessoryCircular: CircularCountdownView(countdown: countdown)
        case .accessoryRectangular: RectangularCountdownView(countdown: countdown)
        case .accessoryInline: InlineCountdownView(countdown: countdown)
        default: SmallCountdownView(countdown: countdown)
        }
    }
}

// MARK: - Home Screen

/// "42 days" to go, "Today" on the day, "3 days ago" after it: a big number with a small gray unit.
/// "~14 days" ahead of a window and "Any Day" inside it; on a day with a time, the time ticking down to it.
struct WidgetDaysLeft: View {
    let days: Int
    var size: CGFloat = 40
    /// The time in weeks or months instead, when the countdown is written that way.
    var parts: [DurationPart]?
    var isApproximate = false
    var isInWindow = false
    var moment: Date?
    /// When the widget is drawn, for the ticking time.
    var date: Date = .now

    var body: some View {
        let count = abs(days)
        Group {
            if isInWindow {
                word("Any Day")
            } else if days == 0, let moment {
                if date < moment {
                    Text(timerInterval: date...moment, countsDown: true)
                        .font(.system(size: size, weight: .bold))
                        .monospacedDigit()
                        .widgetAccentable()
                } else {
                    word("Now")
                }
            } else if let parts, days != 0 {
                DurationPartsText(parts: parts, size: size, suffix: days < 0 ? "ago" : nil)
            } else if days == 0 {
                word("Today")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        if isApproximate {
                            Text("~")
                                .font(.system(size: size * 0.7, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(count, format: .number)
                            .font(.system(size: size, weight: .bold))
                            .widgetAccentable()
                    }
                    Text(days > 0 ? (count == 1 ? "day" : "days") : (count == 1 ? "day ago" : "days ago"))
                        .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private func word(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .widgetAccentable()
    }
}

extension WidgetDaysLeft {
    init(_ countdown: CountdownSnapshot, size: CGFloat = 40) {
        self.init(days: countdown.daysLeft, size: size, parts: countdown.displayParts,
                  isApproximate: countdown.isApproximate, isInWindow: countdown.isInWindow,
                  moment: countdown.moment, date: countdown.date)
    }
}

/// "Day 20 of 62 … 32%" over a bar showing how much of the wait is behind.
struct WidgetWaitBar: View {
    let countdown: CountdownSnapshot

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Day \(countdown.waited) of \(countdown.total)")
                Spacer(minLength: 4)
                Text("\(Int((countdown.progress * 100).rounded()))%")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(countdown.tint.opacity(0.25))
                    Capsule().fill(countdown.tint)
                        .frame(width: max(6, proxy.size.width * countdown.progress))
                        .widgetAccentable()
                }
            }
            .frame(height: 6)
        }
    }
}

struct SmallCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(title: countdown.title, symbol: countdown.symbol, tint: countdown.tint)
            Spacer(minLength: 4)
            WidgetDaysLeft(countdown)
            Text(countdown.dateLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            switch countdown.style {
            case .calendar:
                WidgetWaitBar(countdown: countdown)
            case .fill:
                CountdownFillFooter(waited: countdown.waited, daysLeft: countdown.daysLeft, progress: countdown.progress)
            case .arc:
                CountdownArc(progress: countdown.progress, tint: countdown.tint, height: 42)
            case .timeline:
                TimelineTrack(waited: countdown.waited, daysLeft: countdown.daysLeft, tint: countdown.tint,
                              now: countdown.date)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        switch countdown.style {
        case .calendar:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 8)
                    WidgetWaitBar(countdown: countdown)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                MonthGrid(month: countdown.target, target: countdown.target, tint: countdown.tint,
                          now: countdown.date, spacing: 2)
                    .frame(width: 140)
            }
        case .fill:
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                CountdownFillFooter(waited: countdown.waited, daysLeft: countdown.daysLeft, progress: countdown.progress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .arc:
            HStack(spacing: 14) {
                header
                CountdownArc(progress: countdown.progress, tint: countdown.tint, height: 100)
                    .frame(width: 140)
            }
        case .timeline:
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                CountdownTimeline(start: countdown.waitStart, target: countdown.target, waited: countdown.waited,
                                  daysLeft: countdown.daysLeft, tint: countdown.tint, now: countdown.date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(title: countdown.title, symbol: countdown.symbol, tint: countdown.tint)
            Spacer(minLength: 4)
            WidgetDaysLeft(countdown)
            Text(countdown.dateLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The title and the days share the top row, so the wait (in the countdown's style) gets the height in between.
struct LargeCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        let left = countdown.timeLeft
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetTitle(title: countdown.title, symbol: countdown.symbol, tint: countdown.tint, font: .headline)
                    Text(countdown.dateLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                WidgetDaysLeft(countdown, size: 46)
                    .fixedSize()
            }

            switch countdown.style {
            case .calendar:
                HStack(spacing: 14) {
                    ForEach(Calendar.app.monthsShown(now: countdown.date, target: countdown.target), id: \.self) { month in
                        MonthGrid(month: month, target: countdown.target, tint: countdown.tint, now: countdown.date,
                                  showsTitle: true, spacing: 2)
                    }
                }
                .frame(maxHeight: .infinity)
                if countdown.daysLeft > 0 {
                    WidgetWaitBar(countdown: countdown)
                }
            case .fill:
                // The color rising up the background shows the wait; the number says it.
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int((countdown.progress * 100).rounded()))%")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(countdown.tint)
                        .widgetAccentable()
                    Text(countdown.daysLeft > 0 ? "of the wait is behind · day \(countdown.waited) of \(countdown.total)"
                                                : "The wait is over")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            case .arc:
                CountdownArc(progress: countdown.progress, tint: countdown.tint, height: 170)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .timeline:
                VStack(alignment: .leading, spacing: 16) {
                    CountdownTimeline(start: countdown.waitStart, target: countdown.target, waited: countdown.waited,
                                      daysLeft: countdown.daysLeft, tint: countdown.tint, thickness: 6,
                                      now: countdown.date)
                    if countdown.daysLeft > 0 {
                        WidgetWaitBar(countdown: countdown)
                    }
                }
                .frame(maxHeight: .infinity)
            }

            if countdown.daysLeft > 0 {
                HStack(alignment: .top) {
                    stat("Weeks", "\(countdown.daysLeft / 7)")
                    stat("Weekends", "\(left.weekends)")
                    stat("Workdays", "\(left.workdays)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock Screen

/// The days to go in a ring that fills as the day comes closer.
struct CircularCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        Gauge(value: countdown.progress) {
            Image(systemName: countdown.symbol)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: countdown.symbol)
                    .font(.system(size: 10, weight: .semibold))
                if countdown.daysLeft == 0 {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .bold))
                } else {
                    Text(abs(countdown.daysLeft), format: .number)
                        .font(.system(size: 18, weight: .bold))
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

struct RectangularCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(countdown.title, systemImage: countdown.symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            WidgetDaysLeft(countdown, size: 22)
            Text(countdown.dateLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineCountdownView: View {
    let countdown: CountdownSnapshot

    var body: some View {
        let days = countdown.daysLeft
        let text = switch days {
        case 0: "\(countdown.title) · today"
        case 1...: "\(countdown.title) in \(days) \(days == 1 ? "day" : "days")"
        default: "\(countdown.title) · \(-days) \(days == -1 ? "day" : "days") ago"
        }
        Label(text, systemImage: countdown.symbol)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CountdownWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}

#Preview("Medium", as: .systemMedium) {
    CountdownWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}

#Preview("Large", as: .systemLarge) {
    CountdownWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}

#Preview("Circular", as: .accessoryCircular) {
    CountdownWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    CountdownWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}
