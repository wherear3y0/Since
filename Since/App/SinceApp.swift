import EventKit
import SwiftUI
import SwiftData
import UserNotifications

@main
struct SinceApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Launch with -seedSampleData to fill an empty database with the preview counters and countdowns.
        if CommandLine.arguments.contains("-seedSampleData") {
            let context = Store.container.mainContext
            if (try? context.fetchCount(FetchDescriptor<Counter>())) == 0 {
                SampleData.insertSamples(into: context)
            }
            if (try? context.fetchCount(FetchDescriptor<Countdown>())) == 0 {
                SampleData.insertCountdownSamples(into: context)
            }
            try? context.save()
        }
        if CommandLine.arguments.contains("-seedCalendarEvents") {
            SampleCalendarEvents.insert()
        }
        #endif
        Store.upgradeData()
    }

    var body: some Scene {
        WindowGroup {
            SharedDatabaseView()
        }
        .modelContainer(Store.container)
        .onChange(of: scenePhase) { _, phase in
            // A new day can bring a new milestone into the scheduling window.
            if phase == .active {
                let context = ModelContext(Store.container)
                Store.removeEndedTimers(context)
                refreshMirrors(context)
                Task { await CalendarSyncRunner.run(context) }
            }
        }
    }
}

/// Opens the counter a milestone notification is about, and shows reminders while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
