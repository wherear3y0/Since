import EventKit
import SwiftData
import SwiftUI

/// Picks the calendars and Reminders lists whose events and tasks appear on the Until tab by themselves,
/// and how far ahead for each.
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var calendars: [EKCalendar] = []
    @State private var lists: [EKCalendar] = []
    @State private var ranges = SyncSettings.ranges
    @State private var eventsStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)

    private var store: EKEventStore { .shared }

    var body: some View {
        Form {
            Section {
                if eventsStatus == .fullAccess {
                    ForEach(grouped(calendars), id: \.source) { group in
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            row(calendar)
                        }
                    }
                } else {
                    access("Allow Calendar Access", status: eventsStatus) {
                        _ = try? await store.requestFullAccessToEvents()
                    }
                }
            } header: {
                Text("Calendars")
            } footer: {
                Text("Events from these calendars appear in a Calendar section on the Until tab. When one moves, "
                     + "its countdown follows and keeps the old day in its history; when one is deleted, so is the countdown.")
            }

            Section {
                if remindersStatus == .fullAccess {
                    ForEach(lists, id: \.calendarIdentifier) { list in
                        row(list)
                    }
                } else {
                    access("Allow Reminders Access", status: remindersStatus) {
                        _ = try? await store.requestFullAccessToReminders()
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Tasks with a due date from these lists appear in a Reminders section. Done here ticks them off "
                     + "in Reminders too.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle("Calendars & Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sensoryFeedback(.selection, trigger: ranges)
    }

    /// A calendar or list with how far ahead it's synced, or Off.
    private func row(_ calendar: EKCalendar) -> some View {
        Picker(selection: binding(for: calendar.calendarIdentifier)) {
            Text("Off").tag(0)
            ForEach(SyncSettings.choices, id: \.days) { choice in
                Text(choice.title).tag(choice.days)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(calendar.title)
                    Text(calendar.source.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func binding(for id: String) -> Binding<Int> {
        Binding {
            ranges[id] ?? 0
        } set: { days in
            SyncSettings.setRange(days == 0 ? nil : days, for: id)
            ranges = SyncSettings.ranges
            Task { await CalendarSyncRunner.run(context) }
        }
    }

    private func access(_ title: String, status: EKAuthorizationStatus, request: @escaping () async -> Void) -> some View {
        Button {
            if status == .notDetermined {
                Task {
                    await request()
                    load()
                }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label(status == .notDetermined ? title : "Turn On Access in Settings", systemImage: "lock.open")
        }
    }

    /// The calendars that can be synced, birthdays aside (those come from Contacts).
    private func load() {
        eventsStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        if eventsStatus == .fullAccess {
            calendars = store.calendars(for: .event).filter { $0.type != .birthday }
                .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
        }
        if remindersStatus == .fullAccess {
            lists = store.calendars(for: .reminder).sorted { $0.title < $1.title }
        }
    }

    private func grouped(_ calendars: [EKCalendar]) -> [(source: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars, by: \.source.title)
            .map { (source: $0.key, calendars: $0.value) }
            .sorted { $0.source < $1.source }
    }
}
