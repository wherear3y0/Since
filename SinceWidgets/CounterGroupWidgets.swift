import SwiftUI
import WidgetKit

/// Up to six counters as small tiles, each in its own color.
struct CounterGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CounterGridWidget", intent: SelectCountersIntent.self, provider: CountersProvider()) { entry in
            CounterGridView(entry: entry)
                .containerBackground(Color.cardBackground, for: .widget)
        }
        .configurationDisplayName("Counter Grid")
        .description("Several counters side by side: three in medium, six in large.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Up to six counters as a list.
struct CounterListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CounterListWidget", intent: SelectCountersIntent.self, provider: CountersProvider()) { entry in
            CounterListView(entry: entry)
                .containerBackground(Color.cardBackground, for: .widget)
        }
        .configurationDisplayName("Counter List")
        .description("Several counters in a list: three in medium, six in large.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CounterGridView: View {
    let entry: CountersEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.counters.isEmpty {
            NoCountersView()
        } else if family == .systemMedium {
            // Medium: one row of three tiles.
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    if let counter = entry.counters[safe: index] {
                        Link(destination: counter.url) {
                            CounterTile(counter: counter)
                        }
                    } else {
                        Color.clear
                    }
                }
            }
        } else {
            let rows = stride(from: 0, to: 6, by: 2).map { index in
                [entry.counters[safe: index], entry.counters[safe: index + 1]]
            }
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { column in
                            if let counter = rows[row][column] {
                                Link(destination: counter.url) {
                                    CounterTile(counter: counter)
                                }
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A small widget in miniature.
struct CounterTile: View {
    let counter: CounterSnapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(counter: counter, font: .caption.weight(.semibold))
            WidgetDayCount(days: counter.days, size: 24)
                .padding(.top, 2)
            Spacer(minLength: 4)
            WeekStrip(counter: counter, spacing: 3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if counter.tinted {
                shape.fill(counter.tint.opacity(0.18))
            } else {
                SoftColorFill(tint: counter.tint).clipShape(shape)
            }
        }
        .overlay {
            shape.strokeBorder(counter.color.color.mix(with: .white, by: 0.45).opacity(0.2), lineWidth: 0.75)
        }
    }
}

struct CounterListView: View {
    let entry: CountersEntry

    @Environment(\.widgetFamily) private var family

    private var rowCount: Int { family == .systemMedium ? 3 : 6 }

    var body: some View {
        if entry.counters.isEmpty {
            NoCountersView()
        } else {
            let shown = Array(entry.counters.prefix(rowCount))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, counter in
                    if index > 0 {
                        Divider()
                    }
                    Link(destination: counter.url) {
                        CounterRow(counter: counter)
                            .frame(maxHeight: .infinity)
                    }
                }
                // Keep rows the same height when there are fewer counters than rows.
                ForEach(shown.count..<rowCount, id: \.self) { _ in
                    Color.clear.frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct CounterRow: View {
    let counter: CounterSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: counter.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(counter.tint)
                .frame(width: 30, height: 30)
                .background(counter.tint.opacity(0.2), in: Circle())
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(counter.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(counter.tint)
                    .lineLimit(1)
                Text("since \(counter.since.sinceFormat)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            WeekStrip(counter: counter, spacing: 2, cornerRadius: 2)
                .frame(width: 68)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(counter.days, format: .number)
                    .font(.title3.bold())
                    .widgetAccentable()
                Text("d")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 56, alignment: .trailing)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Grid", as: .systemLarge) {
    CounterGridWidget()
} timeline: {
    CountersEntry(date: .now, counters: CounterSnapshot.samples())
}

#Preview("Grid medium", as: .systemMedium) {
    CounterGridWidget()
} timeline: {
    CountersEntry(date: .now, counters: CounterSnapshot.samples())
}

#Preview("List medium", as: .systemMedium) {
    CounterListWidget()
} timeline: {
    CountersEntry(date: .now, counters: CounterSnapshot.samples())
}

#Preview("List", as: .systemLarge) {
    CounterListWidget()
} timeline: {
    CountersEntry(date: .now, counters: CounterSnapshot.samples())
}
