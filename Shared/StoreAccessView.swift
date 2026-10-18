import OSLog
import SwiftData
import SwiftUI

struct StoreAccessView<Content: View>: View {
    @ViewBuilder let content: (ModelContainer) -> Content
    @State private var container: ModelContainer?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let container {
                content(container)
            } else if failed {
                ContentUnavailableView {
                    Label("Couldn’t Open Since", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your data hasn’t been deleted. Unlock your iPhone, open Since, then try again.")
                } actions: {
                    Button("Try Again") { attempt += 1 }
                }
            } else {
                ProgressView("Opening Since…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: attempt) {
            failed = false
            for retry in 0..<3 {
                guard !Task.isCancelled else { return }
                do {
                    container = try Store.open()
                    return
                } catch {
                    Logger(subsystem: "me.wherar3y0.since", category: "Storage")
                        .error("Database open failed: \(error.localizedDescription, privacy: .public)")
                    if retry < 2 {
                        do { try await Task.sleep(for: .milliseconds(300 * (retry + 1))) }
                        catch { return }
                    }
                }
            }
            failed = true
        }
    }
}
