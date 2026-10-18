import SwiftData
import SwiftUI
import UIKit

/// Extensions insert into the App Group store from another process. Give queries a fresh context
/// when that happens, both on return to Since and while it is open (for example, in multitasking).
struct SharedDatabaseView: View {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer
    @State private var context: ModelContext
    @State private var revision = ExtensionChanges.revision

    init(container: ModelContainer) {
        self.container = container
        _context = State(initialValue: container.mainContext)
    }

    var body: some View {
        RootView()
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Widgets, Siri and the Lock Screen may have written while Since was away.
                let context = refresh(force: true) ?? context
                Store.removeEndedTimers(context)
                refreshMirrors(context)
                Task { await CalendarSyncRunner.run(context) }
            }
            .saveFailureAlert()
            .environment(\.modelContext, context)
            .task {
                Store.upgradeData()
                #if DEBUG
                if CommandLine.arguments.contains("-seedSampleData") {
                    if (try? context.fetchCount(FetchDescriptor<Counter>())) == 0 {
                        SampleData.insertSamples(into: context)
                    }
                    if (try? context.fetchCount(FetchDescriptor<Countdown>())) == 0 {
                        SampleData.insertCountdownSamples(into: context)
                    }
                    saveChanges(context)
                }
                if CommandLine.arguments.contains("-seedCalendarEvents") { SampleCalendarEvents.insert() }
                #endif
                Store.removeEndedTimers(context)
                refreshMirrors(context)
                await CalendarSyncRunner.run(context)
            }
            // Started again with every phase, so it sees the current one: a task that ran from launch
            // kept the phase it started with and never looked. It also stops while Since is away.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    if let context = refresh() { refreshMirrors(context) }
                }
            }
    }

    /// A fresh context for the queries after an extension wrote, or when forced. Nil when it was kept.
    private func refresh(force: Bool = false) -> ModelContext? {
        let latest = ExtensionChanges.revision
        guard force || latest != revision, !context.hasChanges else { return nil }
        // Never discard an editor's unsaved @State values, or dismiss a sheet under someone's fingers.
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard !windows.contains(where: { $0.rootViewController?.presentedViewController != nil }) else { return nil }
        let fresh = ModelContext(container)
        context = fresh
        revision = latest
        return fresh
    }
}
