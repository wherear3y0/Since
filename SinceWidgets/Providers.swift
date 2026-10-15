import WidgetKit

struct CounterEntry: TimelineEntry {
    let date: Date
    /// nil when there are no counters yet.
    let counter: CounterSnapshot?
}

struct CountersEntry: TimelineEntry {
    let date: Date
    let counters: [CounterSnapshot]
}

/// One chosen counter (or the first one). Refreshes at local midnight.
struct CounterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, counter: CounterSnapshot.samples().first)
    }

    func snapshot(for configuration: SelectCounterIntent, in context: Context) async -> CounterEntry {
        let entry = entry(for: configuration, at: .now)
        // The widget gallery shows a sample until the first counter exists.
        if entry.counter == nil && context.isPreview {
            return placeholder(in: context)
        }
        return entry
    }

    func timeline(for configuration: SelectCounterIntent, in context: Context) async -> Timeline<CounterEntry> {
        let entries = WidgetData.timelineDates().map { entry(for: configuration, at: $0) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectCounterIntent, at date: Date) -> CounterEntry {
        let counters = WidgetData.counters()
        let chosen = counters.first { $0.id == configuration.counter?.id } ?? counters.first
        return CounterEntry(date: date, counter: chosen.map { CounterSnapshot($0, at: date) })
    }
}

/// Up to six chosen counters, or the first six. Refreshes at local midnight.
struct CountersProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountersEntry {
        CountersEntry(date: .now, counters: CounterSnapshot.samples())
    }

    func snapshot(for configuration: SelectCountersIntent, in context: Context) async -> CountersEntry {
        let entry = entry(for: configuration, at: .now)
        if entry.counters.isEmpty && context.isPreview {
            return placeholder(in: context)
        }
        return entry
    }

    func timeline(for configuration: SelectCountersIntent, in context: Context) async -> Timeline<CountersEntry> {
        let entries = WidgetData.timelineDates().map { entry(for: configuration, at: $0) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectCountersIntent, at date: Date) -> CountersEntry {
        let counters = WidgetData.counters()
        let chosenIDs = (configuration.counters ?? []).map(\.id)
        // Chosen counters keep the order they were picked in; deleted ones drop out.
        let chosen = chosenIDs.isEmpty
            ? Array(counters.prefix(6))
            : chosenIDs.compactMap { id in counters.first { $0.id == id } }
        return CountersEntry(date: date, counters: chosen.map { CounterSnapshot($0, at: date) })
    }
}
