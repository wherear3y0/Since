import SwiftUI
import WidgetKit

/// One counter, in every size: home screen small, medium and large, plus the Lock Screen.
struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CounterWidget", intent: SelectCounterIntent.self, provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Counter")
        .description("Days since, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CounterWidgetView: View {
    let entry: CounterEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let counter = entry.counter {
            content(for: counter)
                .widgetURL(counter.url)
                .containerBackground(for: .widget) {
                    if isAccessory {
                        Color.clear
                    } else {
                        WidgetBackground(counter: counter)
                    }
                }
        } else {
            NoCountersView()
                .containerBackground(for: .widget) {
                    isAccessory ? Color.clear : Color.cardBackground
                }
        }
    }

    private var isAccessory: Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    @ViewBuilder
    private func content(for counter: CounterSnapshot) -> some View {
        switch family {
        case .systemMedium: MediumCounterView(counter: counter)
        case .systemLarge: LargeCounterView(counter: counter)
        case .accessoryCircular: CircularCounterView(counter: counter)
        case .accessoryRectangular: RectangularCounterView(counter: counter)
        case .accessoryInline: InlineCounterView(counter: counter)
        default: SmallCounterView(counter: counter)
        }
    }
}

// MARK: - Home Screen

struct SmallCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(counter: counter)
            Spacer(minLength: 4)
            WidgetDayCount(days: counter.days, parts: counter.displayParts)
            Text("since \(counter.since.sinceFormat)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if counter.kind == .lastTime && counter.average > 0 {
                UsualGapPill(counter: counter)
            } else {
                WeekStrip(counter: counter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetTitle(counter: counter)
                Spacer(minLength: 4)
                WidgetDayCount(days: counter.days, parts: counter.displayParts)
                Text("since \(counter.since.sinceFormat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if counter.kind == .lastTime {
                    if counter.average > 0 {
                        UsualGapPill(counter: counter)
                    }
                } else {
                    WidgetProgressBar(counter: counter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            WidgetHeatmap(counter: counter, weeks: 8)
                .frame(maxHeight: .infinity)
        }
    }
}

/// The title and the number share the top row, so the heatmap gets all the height in between.
struct LargeCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetTitle(counter: counter, font: .headline)
                    Text("since \(counter.since.sinceFormat)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                WidgetDayCount(days: counter.days, size: 46, parts: counter.displayParts)
                    .fixedSize()
            }

            FillingWidgetHeatmap(counter: counter)

            if counter.kind != .lastTime || counter.average > 0 {
                WidgetProgressBar(counter: counter)
            }
            if counter.kind == .owned {
                HStack(alignment: .top) {
                    stat("Got", counter.start.formatted(date: .abbreviated, time: .omitted))
                    stat("Next Year", "in \(counter.nextYear.days - counter.days)d")
                }
            } else {
                HStack(alignment: .top) {
                    stat(counter.kind == .quit ? "Best" : "Longest", "\(counter.best)d")
                    stat("Average", "\(counter.average)d")
                    stat(counter.kind.resetsTitle, "\(counter.resetDates.count)")
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

/// The number in a ring that fills toward the best streak (or the usual gap, or an owned thing's next year).
struct CircularCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        let target = switch counter.kind {
        case .quit: counter.best
        case .lastTime: counter.average
        case .owned: counter.nextYear.days
        }
        let progress = target == 0 ? 1 : min(1, Double(counter.days) / Double(target))
        Gauge(value: progress) {
            Image(systemName: counter.symbol)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: counter.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(counter.days, format: .number)
                    .font(.system(size: 18, weight: .bold))
                    .minimumScaleFactor(0.5)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

struct RectangularCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(counter.title, systemImage: counter.symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            Text("\(counter.days) \(counter.days == 1 ? "day" : "days")")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: String {
        let since = "since \(counter.since.sinceFormat)"
        switch counter.kind {
        case .quit: return "\(since) · best \(counter.best)"
        case .lastTime: return counter.average > 0 ? "\(since) · usually \(counter.average)" : since
        case .owned: return since
        }
    }
}

struct InlineCounterView: View {
    let counter: CounterSnapshot

    var body: some View {
        Label("\(counter.title) · \(counter.days) \(counter.days == 1 ? "day" : "days")",
              systemImage: counter.symbol)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CounterWidget()
} timeline: {
    let samples = CounterSnapshot.samples()
    CounterEntry(date: .now, counter: samples[0])
    CounterEntry(date: .now, counter: samples[5])
}

#Preview("Medium", as: .systemMedium) {
    CounterWidget()
} timeline: {
    let samples = CounterSnapshot.samples()
    CounterEntry(date: .now, counter: samples[1])
    CounterEntry(date: .now, counter: samples[5])
}

#Preview("Large", as: .systemLarge) {
    CounterWidget()
} timeline: {
    CounterEntry(date: .now, counter: CounterSnapshot.samples()[0])
}

#Preview("Circular", as: .accessoryCircular) {
    CounterWidget()
} timeline: {
    CounterEntry(date: .now, counter: CounterSnapshot.samples()[0])
}

#Preview("Rectangular", as: .accessoryRectangular) {
    CounterWidget()
} timeline: {
    CounterEntry(date: .now, counter: CounterSnapshot.samples()[1])
}
