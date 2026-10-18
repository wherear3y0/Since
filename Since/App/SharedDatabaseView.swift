import SwiftData
import SwiftUI
import UIKit

/// Extensions insert into the App Group store from another process. Give queries a fresh context
/// when that happens, both on return to Since and while it is open (for example, in multitasking).
struct SharedDatabaseView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var context = Store.container.mainContext
    @State private var revision = ExtensionChanges.revision

    var body: some View {
        RootView()
            .id(revision)
            .environment(\.modelContext, context)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .task {
                while !Task.isCancelled {
                    refresh()
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { break }
                }
            }
    }

    private func refresh() {
        guard scenePhase == .active else { return }
        let latest = ExtensionChanges.revision
        guard latest != revision, !context.hasChanges else { return }
        // Never discard an editor's unsaved @State values, or dismiss a sheet under someone's fingers.
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard !windows.contains(where: { $0.rootViewController?.presentedViewController != nil }) else { return }
        context = ModelContext(Store.container)
        revision = latest
        refreshMirrors(context)
    }
}
