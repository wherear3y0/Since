import CoreSpotlight
import SwiftData
import WidgetKit

/// Writes changes to disk and brings everything that mirrors the data up to date:
/// widgets, reminders and the names Siri knows. Call after every edit.
func saveChanges(_ context: ModelContext) {
    try? context.save()
    WidgetCenter.shared.reloadAllTimelines()
    refreshMirrors(context)
}

/// Reminders, Live Activities, Siri phrases and the Spotlight index, without saving. Also run when the app comes to the foreground,
/// so a new day's milestones get scheduled.
func refreshMirrors(_ context: ModelContext) {
    let counters = (try? context.fetch(FetchDescriptor<Counter>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    let countdowns = (try? context.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    Milestones.reschedule(counters, countdowns: countdowns)
    LiveActivities.refresh(countdowns)
    SinceShortcuts.updateAppShortcutParameters()

    // Siri and Spotlight find counters and countdowns by meaning. Their day counts go stale overnight,
    // and there are only a handful, so everything is indexed afresh.
    let counterEntities = counters.map(CounterEntity.init)
    let countdownEntities = countdowns.filter { !$0.isTimer }.map(CountdownEntity.init)
    Task {
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: CounterEntity.self)
        try? await index.deleteAppEntities(ofType: CountdownEntity.self)
        try? await index.indexAppEntities(counterEntities)
        try? await index.indexAppEntities(countdownEntities)
    }
}
