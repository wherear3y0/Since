import SwiftUI
import WidgetKit

/// Icon and title in the counter's (or countdown's) color.
struct WidgetTitle: View {
    let title: String
    let symbol: String
    let tint: Color
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
        }
        .font(font)
        .foregroundStyle(tint)
        .widgetAccentable()
    }
}

extension WidgetTitle {
    init(counter: CounterSnapshot, font: Font = .subheadline.weight(.semibold)) {
        self.init(title: counter.title, symbol: counter.symbol, tint: counter.tint, font: font)
    }
}

/// "41 days": a big number with a small gray unit.
struct WidgetDayCount: View {
    let days: Int
    var size: CGFloat = 40
    /// The count in weeks or months instead, when the counter is written that way.
    var parts: [DurationPart]?

    var body: some View {
        if let parts {
            DurationPartsText(parts: parts, size: size)
        } else {
            daysText
        }
    }

    private var daysText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(days, format: .number)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(days == 1 ? "day" : "days")
                .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// One square of a heatmap, matching the app: bright = current streak (or a day a "last time" counter
/// was logged), faint = before it, gray = a day before a slip, dot = the slip, outlined = today.
struct WidgetDayCell: View {
    let day: HeatmapDay
    let tint: Color
    var cornerRadius: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            switch day.state {
            case .clean, .logged:
                shape.fill(tint).widgetAccentable()
            case .before:
                shape.fill(tint.opacity(0.22))
            case .slipped:
                shape.fill(tint.slippedDay)
            case .slip:
                shape.fill(tint.opacity(0.22))
                Circle().fill(tint).scaleEffect(0.34).widgetAccentable()
            case .future:
                Color.clear
            }
            if day.isToday {
                shape.strokeBorder(.primary.opacity(0.85), lineWidth: 1.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The last 7 days in a row.
struct WeekStrip: View {
    let counter: CounterSnapshot
    var spacing: CGFloat = 4
    var cornerRadius: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(counter.lastWeek) { day in
                WidgetDayCell(day: day, tint: counter.tint, cornerRadius: cornerRadius)
            }
        }
    }
}

/// A grid of weeks, one column per week, with square days. Sizes itself to the space it's given.
struct WidgetHeatmap: View {
    let grid: [[HeatmapDay]]
    let tint: Color
    var spacing: CGFloat = 3
    var showsWeekdays = false

    /// Room for the weekday letters and the gap after them.
    static let labelWidth: CGFloat = 14

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(week) { day in
                        WidgetDayCell(day: day, tint: tint)
                    }
                }
            }
        }
        .aspectRatio(CGFloat(grid.count) / 7, contentMode: .fit)
        // The letters sit in an overlay, so they stretch to exactly the grid's height and each one lines up
        // with its row. In the stack they used to stretch to all the free height instead.
        .padding(.leading, showsWeekdays ? Self.labelWidth : 0)
        .overlay(alignment: .leading) {
            if showsWeekdays {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(weekdayLetters, id: \.offset) { _, letter in
                        Text(letter)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: Self.labelWidth - 4, alignment: .leading)
            }
        }
    }

    private var weekdayLetters: [(offset: Int, element: String)] {
        let calendar = Calendar.app
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array((0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }.enumerated())
    }
}

extension WidgetHeatmap {
    init(counter: CounterSnapshot, weeks: Int, showsWeekdays: Bool = false) {
        self.init(grid: counter.heatmap(weeks: weeks), tint: counter.tint, showsWeekdays: showsWeekdays)
    }
}

/// A heatmap that fills the space it's given: days as tall as the height allows (up to a limit),
/// and as many weeks as then fit across, today's column at the trailing edge.
struct FillingWidgetHeatmap: View {
    let counter: CounterSnapshot
    var spacing: CGFloat = 3
    var maxCell: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let labels = WidgetHeatmap.labelWidth
            let cell = max(4, min(maxCell, (proxy.size.height - 6 * spacing) / 7))
            let weeks = max(1, Int((proxy.size.width - labels + spacing) / (cell + spacing)))
            WidgetHeatmap(counter: counter, weeks: weeks, showsWeekdays: true)
                .frame(width: labels + CGFloat(weeks) * (cell + spacing) - spacing, height: 7 * cell + 6 * spacing)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .trailing)
        }
    }
}

/// "Now 12d … Best 22d" over a bar showing how far the current count is toward the target.
struct WidgetRecordBar: View {
    let current: Int
    let target: Int
    let targetLabel: String
    let tint: Color

    var body: some View {
        let fraction = target == 0 ? 1 : min(1, Double(current) / Double(target))
        VStack(spacing: 4) {
            HStack {
                Text("Now \(current)d")
                Spacer(minLength: 4)
                Text("\(targetLabel) \(target)d")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.25))
                    Capsule().fill(tint)
                        .frame(width: max(6, proxy.size.width * fraction))
                        .widgetAccentable()
                }
            }
            .frame(height: 6)
        }
    }
}

/// Progress toward the best streak or, for "last time" counters, toward the usual gap; for an owned thing,
/// toward its next whole year.
struct WidgetProgressBar: View {
    let counter: CounterSnapshot

    var body: some View {
        switch counter.kind {
        case .quit:
            WidgetRecordBar(current: counter.days, target: counter.best, targetLabel: "Best", tint: counter.tint)
        case .lastTime:
            WidgetRecordBar(current: counter.days, target: counter.average, targetLabel: "Avg", tint: counter.tint)
        case .owned:
            let next = counter.nextYear
            WidgetRecordBar(current: counter.days, target: next.days, targetLabel: "\(next.years)y", tint: counter.tint)
        }
    }
}

/// "usually 7d" — stronger once the current gap runs longer than usual.
struct UsualGapPill: View {
    let counter: CounterSnapshot

    var body: some View {
        Text("usually \(counter.average)d")
            .font(.caption.weight(.semibold))
            .foregroundStyle(counter.isOverdue ? Color.white : counter.tint.mix(with: .white, by: 0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(counter.tint.opacity(counter.isOverdue ? 0.7 : 0.3), in: Capsule())
            .widgetAccentable(counter.isOverdue)
    }
}

/// The widget's own background: the counter's tint, or the plain card with a soft color patch.
struct WidgetBackground: View {
    let color: CounterColor
    let tinted: Bool
    /// For countdowns shown as a fill: how far up the color rises.
    var fillLevel: Double?

    var body: some View {
        let tint = color.color.onCard(tinted: tinted)
        let edge = color.color.mix(with: .white, by: 0.45)
        ZStack {
            if tinted {
                Color.pageBackground
                tint.opacity(0.17)
            } else {
                SoftColorFill(tint: tint)
            }
            if let fillLevel {
                FillLevel(level: fillLevel, tint: tint)
            }
            ContainerRelativeShape()
                .strokeBorder(LinearGradient(colors: [edge.opacity(0.25), edge.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 0.75)
        }
    }
}

extension WidgetBackground {
    init(counter: CounterSnapshot) {
        self.init(color: counter.color, tinted: counter.tinted)
    }
}

struct NoCountersView: View {
    var text = "Add a counter in Since"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
