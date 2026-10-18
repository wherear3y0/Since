import SwiftUI
import WidgetKit

struct CountdownsEntry: TimelineEntry {
    let date: Date
    let countdowns: [CountdownSnapshot]
}

/// Up to six chosen countdowns or, by default, the six soonest. Refreshes at local midnight.
struct CountdownsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownsEntry {
        CountdownsEntry(date: .now, countdowns: CountdownSnapshot.samples())
    }

    func snapshot(for configuration: SelectCountdownsIntent, in context: Context) async -> CountdownsEntry {
        let entry = entry(for: configuration, at: .now)
        if entry.countdowns.isEmpty && context.isPreview {
            return placeholder(in: context)
        }
        return entry
    }

    func timeline(for configuration: SelectCountdownsIntent, in context: Context) async -> Timeline<CountdownsEntry> {
        let entries = WidgetData.timelineDates().map { entry(for: configuration, at: $0) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectCountdownsIntent, at date: Date) -> CountdownsEntry {
        let countdowns = Store.countdowns()
        let chosenIDs = (configuration.countdowns ?? []).map(\.id)
        // Chosen ones keep the order they were picked in; otherwise the days still ahead, soonest first,
        // leaving out the ones already done or moved to Past.
        let chosen = chosenIDs.isEmpty
            ? countdowns.filter { !$0.isArchived }.map { CountdownSnapshot($0, at: date) }
                .filter { $0.daysLeft >= 0 }
                .sorted { $0.daysLeft < $1.daysLeft }
            : chosenIDs.compactMap { id in countdowns.first { $0.id == id } }.map { CountdownSnapshot($0, at: date) }
        return CountdownsEntry(date: date, countdowns: Array(chosen.prefix(6)))
    }
}

/// Up to six countdowns as small tiles, each in its own color.
struct CountdownGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CountdownGridWidget", intent: SelectCountdownsIntent.self,
                               provider: CountdownsProvider()) { entry in
            CountdownGridView(entry: entry)
                .containerBackground(Color.cardBackground, for: .widget)
        }
        .configurationDisplayName("Countdown Grid")
        .description("Several countdowns side by side: three in medium, six in large.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Up to six countdowns as a list.
struct CountdownListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CountdownListWidget", intent: SelectCountdownsIntent.self,
                               provider: CountdownsProvider()) { entry in
            CountdownListView(entry: entry)
                .containerBackground(Color.cardBackground, for: .widget)
        }
        .configurationDisplayName("Countdown List")
        .description("The days ahead in a list: three in medium, six in large.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CountdownGridView: View {
    let entry: CountdownsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.countdowns.isEmpty {
            NoCountersView(text: "Add a countdown in Since")
        } else {
            let columns = family == .systemMedium ? 3 : 2
            let rows = family == .systemMedium ? 1 : 3
            VStack(spacing: 8) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<columns, id: \.self) { column in
                            if let countdown = entry.countdowns[safe: row * columns + column] {
                                Link(destination: countdown.url) {
                                    CountdownTile(countdown: countdown)
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

/// A small countdown widget in miniature.
struct CountdownTile: View {
    let countdown: CountdownSnapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(title: countdown.title, symbol: countdown.symbol, tint: countdown.tint,
                        font: .caption.weight(.semibold))
            WidgetDaysLeft(days: countdown.daysLeft, size: 24)
                .padding(.top, 2)
            Text(countdown.target.sinceFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            WaitBar(progress: countdown.progress, tint: countdown.tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if countdown.tinted {
                shape.fill(countdown.tint.opacity(0.18))
            } else {
                SoftColorFill(tint: countdown.tint).clipShape(shape)
            }
        }
        .overlay {
            shape.strokeBorder(countdown.color.color.mix(with: .white, by: 0.45).opacity(0.2), lineWidth: 0.75)
        }
    }
}

struct CountdownListView: View {
    let entry: CountdownsEntry

    @Environment(\.widgetFamily) private var family

    private var rowCount: Int { family == .systemMedium ? 3 : 6 }

    var body: some View {
        if entry.countdowns.isEmpty {
            NoCountersView(text: "Add a countdown in Since")
        } else {
            let shown = Array(entry.countdowns.prefix(rowCount))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, countdown in
                    if index > 0 {
                        Divider()
                    }
                    Link(destination: countdown.url) {
                        CountdownRow(countdown: countdown)
                            .frame(maxHeight: .infinity)
                    }
                }
                // Keep rows the same height when there are fewer countdowns than rows.
                ForEach(shown.count..<rowCount, id: \.self) { _ in
                    Color.clear.frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct CountdownRow: View {
    let countdown: CountdownSnapshot

    var body: some View {
        let days = countdown.daysLeft
        HStack(spacing: 10) {
            Image(systemName: countdown.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(countdown.tint)
                .frame(width: 30, height: 30)
                .background(countdown.tint.opacity(0.2), in: Circle())
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(countdown.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(countdown.tint)
                    .lineLimit(1)
                Text(countdown.target.untilFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            WaitBar(progress: countdown.progress, tint: countdown.tint)
                .frame(width: 60)
            Group {
                if days == 0 {
                    Text("Today")
                        .font(.headline)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(abs(days), format: .number)
                            .font(.title3.bold())
                        Text(days > 0 ? "d" : "d ago")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 56, alignment: .trailing)
        }
    }
}

/// A thin bar of how much of the wait is behind.
struct WaitBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint)
                    .frame(width: max(4, proxy.size.width * progress))
                    .widgetAccentable()
            }
        }
        .frame(height: 5)
    }
}

extension CountdownSnapshot {
    /// Stand-ins for the widget gallery and placeholders.
    static func samples(at date: Date = .now) -> [CountdownSnapshot] {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: date)
        let day = { (n: Int) in calendar.date(byAdding: .day, value: n, to: today)! }
        let rows: [(String, String, CounterColor, Int, Int)] = [
            ("Concert", "music.note", .purple, 5, -30),
            ("Mom’s birthday", "birthday.cake.fill", .pink, 12, -353),
            ("Payday", "creditcard.fill", .green, 16, -15),
            ("Vacation", "airplane", .cyan, 42, -20),
            ("New Year", "sparkles", .yellow, 78, -287),
            ("Marathon", "figure.run", .orange, 120, -60),
        ]
        return rows.map { title, symbol, color, ahead, started in
            CountdownSnapshot(id: UUID(), title: title, symbol: symbol, color: color, tinted: true, style: .calendar,
                              target: day(ahead), waitStart: day(started), date: date)
        }
    }
}

#Preview("Grid", as: .systemLarge) {
    CountdownGridWidget()
} timeline: {
    CountdownsEntry(date: .now, countdowns: CountdownSnapshot.samples())
}

#Preview("Grid medium", as: .systemMedium) {
    CountdownGridWidget()
} timeline: {
    CountdownsEntry(date: .now, countdowns: CountdownSnapshot.samples())
}

#Preview("List medium", as: .systemMedium) {
    CountdownListWidget()
} timeline: {
    CountdownsEntry(date: .now, countdowns: CountdownSnapshot.samples())
}

#Preview("List", as: .systemLarge) {
    CountdownListWidget()
} timeline: {
    CountdownsEntry(date: .now, countdowns: CountdownSnapshot.samples())
}
