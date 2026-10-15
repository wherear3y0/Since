import SwiftUI

/// Two tabs: days since (counters) and days until (countdowns).
struct RootView: View {
    enum Page: Hashable {
        case since, until
    }

    @State private var page: Page = .since
    /// Replays the cards' wave on the tab that comes on screen.
    @State private var arrival = TabArrival()
    /// Set by a link from a widget or a notification; each tab opens its item and clears it.
    @State private var openedCounter: UUID?
    @State private var openedCountdown: UUID?

    var body: some View {
        TabView(selection: Binding { page } set: { show($0) }) {
            Tab("Since", systemImage: "clock.arrow.circlepath", value: .since) {
                HomeView(opened: $openedCounter, arrival: arrival)
            }
            Tab("Until", systemImage: "hourglass", value: .until) {
                UntilView(opened: $openedCountdown, arrival: arrival) {
                    // The new counter blurs in on the Since tab.
                    show(.since)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: page)
        .onOpenURL(perform: open)
        // Siri's "open" actions hand over the same links.
        .onChange(of: AppNavigator.shared.link, initial: true) {
            guard let link = AppNavigator.shared.link else { return }
            AppNavigator.shared.link = nil
            open(link)
        }
    }

    /// Switches tabs. The new tab's cards are hidden in the same update, with no animation,
    /// so they never flash before blurring in from the side the highlight moved toward.
    private func show(_ newPage: Page) {
        guard newPage != page else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            arrival = TabArrival(edge: newPage == .until ? .trailing : .leading)
            page = newPage
        }
    }

    /// since://counter/<id> or since://countdown/<id>: shows that tab and opens the item.
    private func open(_ url: URL) {
        guard url.scheme == "since", let id = UUID(uuidString: url.lastPathComponent) else { return }
        switch url.host {
        case "counter":
            show(.since)
            openedCounter = id
        case "countdown":
            show(.until)
            openedCountdown = id
        default:
            break
        }
    }
}

/// Where an App Intent asks the app to go, for intents that open it (like "open Smoke-free").
@MainActor @Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var link: URL?
}

#Preview(traits: .sampleData) {
    RootView()
}
