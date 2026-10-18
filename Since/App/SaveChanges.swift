import CoreSpotlight
import SwiftData
import WidgetKit
import SwiftUI
import OSLog

/// Writes changes to disk and brings everything that mirrors the data up to date:
/// widgets, reminders and the names Siri knows. Call after every edit.
@discardableResult
func saveChanges(_ context: ModelContext, onFailure: ((Error) -> Void)? = nil) -> Bool {
    do {
        try persistChanges(context)
        return true
    } catch {
        Logger(subsystem: "me.wherar3y0.since", category: "Storage")
            .error("Save failed: \(error.localizedDescription, privacy: .public)")
        if let onFailure { onFailure(error) }
        else { SaveFailure.shared.message = "Your changes couldn’t be saved. Please try again before closing Since." }
        return false
    }
}

/// Throwing path for Siri and other operations that must not report success after a failed save.
func persistChanges(_ context: ModelContext) throws {
    try context.save()
    WidgetCenter.shared.reloadAllTimelines()
    refreshMirrors(context)
}

@Observable
final class SaveFailure {
    static let shared = SaveFailure()
    var message: String?
}

private struct SaveFailureAlert: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var failure = SaveFailure.shared

    func body(content: Content) -> some View {
        content.alert("Couldn’t Save", isPresented: Binding(
            get: { failure.message != nil }, set: { if !$0 { failure.message = nil } }
        )) {
            Button("Retry") { saveChanges(context) }
            Button("OK", role: .cancel) { }
        } message: { Text(failure.message ?? "") }
    }
}

extension View {
    func saveFailureAlert() -> some View { modifier(SaveFailureAlert()) }
}

/// Reminders, Live Activities, Siri phrases and the Spotlight index, without saving. Also run when the app comes to the foreground,
/// so a new day's milestones get scheduled.
func refreshMirrors(_ context: ModelContext) {
    // A failed read is not an empty database: keep existing notifications and indexes intact.
    guard let counters = try? context.fetch(FetchDescriptor<Counter>(sortBy: [SortDescriptor(\.sortOrder)])),
          let countdowns = try? context.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.sortOrder)])) else { return }
    Milestones.reschedule(counters, countdowns: countdowns)
    LiveActivities.refresh(countdowns)
    SinceShortcuts.updateAppShortcutParameters()

    // Siri and Spotlight find counters and countdowns by meaning. Their day counts go stale overnight,
    // and there are only a handful, so everything is indexed afresh.
    let counterEntities = counters.filter { !$0.isGone }.map(CounterEntity.init)
    let countdownEntities = countdowns.filter { !$0.isTimer }.map(CountdownEntity.init)
    Task {
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: CounterEntity.self)
        try? await index.deleteAppEntities(ofType: CountdownEntity.self)
        try? await index.indexAppEntities(counterEntities)
        try? await index.indexAppEntities(countdownEntities)
    }
}
