import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Counter.sortOrder) private var counters: [Counter]
    @Query(sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    @AppStorage("durationStyle") private var styleRaw = DurationStyle.days.rawValue
    @AppStorage(Settings.firstWeekdayKey, store: Settings.defaults) private var firstWeekday = 0
    @AppStorage(Settings.reminderTimeKey, store: Settings.defaults) private var reminderMinutes = Settings.defaultReminderTime

    @State private var notificationsDenied = false
    @State private var exportDocument: BackupDocument?
    @State private var isImporting = false
    @State private var pendingImport: Backup?
    @State private var message: String?
    /// Turns true just after the sheet opens; the sections then blur in one after another.
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                remindersSection
                if countdowns.contains(where: { !$0.isArchived }) {
                    countdownRemindersSection
                }
                if countdowns.contains(where: { !$0.isArchived }) {
                    liveActivitiesSection
                }
                syncSection
                backupSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: styleRaw)
            .sensoryFeedback(.selection, trigger: firstWeekday)
            .task(id: scenePhase) {
                notificationsDenied = await Milestones.isDenied()
            }
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                isRevealed = true
            }
            .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                          document: exportDocument, contentType: .json,
                          defaultFilename: "Since \(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))") { result in
                if case .success = result { message = "Backup saved." }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
            .confirmationDialog("Replace all counters and countdowns?", isPresented: Binding(get: { pendingImport != nil },
                                                                              set: { if !$0 { pendingImport = nil } }),
                                titleVisibility: .visible) {
                Button("Replace with Backup", role: .destructive) {
                    restorePendingImport()
                }
            } message: {
                Text("Everything on this iPhone is deleted and replaced with the \(pendingImport?.counters.count ?? 0) counters "
                     + "and \(pendingImport?.countdowns?.count ?? 0) countdowns from the backup.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var displaySection: some View {
        Section {
            Picker(selection: $styleRaw) {
                Text("127 days").tag(DurationStyle.days.rawValue)
                Text("18w 1d").tag(DurationStyle.weeks.rawValue)
                Text("4m 5d").tag(DurationStyle.months.rawValue)
            } label: {
                Label("Default Number Format", systemImage: "number")
            }
            Picker(selection: $firstWeekday) {
                Text("System").tag(0)
                Text("Monday").tag(2)
                Text("Sunday").tag(1)
            } label: {
                Label("Week Starts On", systemImage: "calendar")
            }
            .onChange(of: firstWeekday) {
                saveChanges(context)
            }
        } header: {
            Text("Display")
        } footer: {
            Text("For new counters and countdowns. Each one can have its own: pick it in its editor, or tap the number on its screen.")
        }
        .sectionReveal(isRevealed, delay: 0.05)
    }

    private var remindersSection: some View {
        Section {
            if notificationsDenied {
                Button {
                    openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                } label: {
                    Label("Turn On Notifications in Settings", systemImage: "bell.slash")
                }
            }
            DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                Label("Time", systemImage: "clock")
            }
            ForEach(counters) { counter in
                Toggle(isOn: reminderBinding(for: counter)) {
                    Label {
                        Text(counter.title)
                    } icon: {
                        Image(systemName: counter.symbol)
                            .foregroundStyle(counter.color.color)
                    }
                }
                .tint(counter.color.color)
            }
        } header: {
            Text("Milestone Reminders")
        } footer: {
            Text("A notification at half a year and on every anniversary of the current streak.")
        }
        .sectionReveal(isRevealed, delay: 0.12)
    }

    private var countdownRemindersSection: some View {
        Section {
            // Kept ones get no reminders, so they aren't listed.
            ForEach(countdowns.filter { !$0.isArchived && !$0.isTimer }) { countdown in
                Toggle(isOn: reminderBinding(for: countdown)) {
                    Label {
                        Text(countdown.title)
                    } icon: {
                        Image(systemName: countdown.symbol)
                            .foregroundStyle(countdown.color.color)
                    }
                }
                .tint(countdown.color.color)
            }
        } header: {
            Text("Countdown Reminders")
        } footer: {
            Text("A notification a week before, the day before and on the day, at the time above.")
        }
        .sectionReveal(isRevealed, delay: 0.16)
    }

    /// Off for every countdown until turned on here or in its editor.
    private var liveActivitiesSection: some View {
        Section {
            if !LiveActivities.areEnabled {
                Button {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("Turn On Live Activities in Settings", systemImage: "exclamationmark.circle")
                }
            }
            ForEach(countdowns.filter { !$0.isArchived && !$0.isTimer }) { countdown in
                Picker(selection: liveActivityBinding(for: countdown)) {
                    Text("Off").tag(-1)
                    Text("On the Day").tag(0)
                    Text("1 Day Before").tag(1)
                    Text("3 Days Before").tag(3)
                    Text("A Week Before").tag(7)
                } label: {
                    Label {
                        Text(countdown.title)
                    } icon: {
                        Image(systemName: countdown.symbol)
                            .foregroundStyle(countdown.color.color)
                    }
                }
            }
        } header: {
            Text("Live Activities")
        } footer: {
            Text("On the Lock Screen and in the Dynamic Island, on the day or from some days before it. It appears "
                 + "when you open Since, once a day, and iOS takes it away after a few hours. Keep it for the days "
                 + "that matter most.")
        }
        .sectionReveal(isRevealed, delay: 0.18)
    }

    private var syncSection: some View {
        Section {
            NavigationLink {
                SyncSettingsView()
            } label: {
                LabeledContent {
                    let count = SyncSettings.ranges.count
                    Text(count == 0 ? "Off" : "\(count)")
                } label: {
                    Label("Calendars & Reminders", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Events and tasks from the calendars and lists you choose appear on the Until tab by themselves.")
        }
        .sectionReveal(isRevealed, delay: 0.185)
    }

    private var backupSection: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try Backup(counters: counters, countdowns: countdowns).encoded())
                } catch {
                    message = "The backup couldn’t be created."
                }
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
            }
            .disabled(counters.isEmpty && countdowns.isEmpty)
            Button {
                isImporting = true
            } label: {
                Label("Import Backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Counters and countdowns live only on this iPhone. Export a backup to Files to keep a copy.")
        }
        .sectionReveal(isRevealed, delay: 0.19)
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            LabeledContent("Counters", value: "\(counters.count)")
            LabeledContent("Countdowns", value: "\(countdowns.count)")
        } header: {
            Text("About")
        }
        .sectionReveal(isRevealed, delay: 0.26)
    }

    // MARK: - Reminders

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.app.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.app.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            refreshMirrors(context)
        }
    }

    private func reminderBinding(for counter: Counter) -> Binding<Bool> {
        Binding {
            counter.notifyMilestones
        } set: { isOn in
            counter.notifyMilestones = isOn
            saveChanges(context)
            if isOn {
                Task {
                    let allowed = await Milestones.requestPermission()
                    notificationsDenied = !allowed
                    refreshMirrors(context)
                }
            }
        }
    }

    private func reminderBinding(for countdown: Countdown) -> Binding<Bool> {
        Binding {
            countdown.notifyBefore
        } set: { isOn in
            countdown.notifyBefore = isOn
            saveChanges(context)
            if isOn {
                Task {
                    let allowed = await Milestones.requestPermission()
                    notificationsDenied = !allowed
                    refreshMirrors(context)
                }
            }
        }
    }

    /// -1 for off, otherwise how many days before the day it starts.
    private func liveActivityBinding(for countdown: Countdown) -> Binding<Int> {
        Binding {
            countdown.showsLiveActivity ? countdown.liveActivityLead : -1
        } set: { lead in
            if lead >= 0 {
                LiveActivities.allowRestart(of: countdown.id)
                countdown.liveActivityLead = lead
            } else {
                countdown.liveActivityForced = false
            }
            countdown.showsLiveActivity = lead >= 0
            saveChanges(context)
        }
    }

    // MARK: - Backup

    private func readBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try Backup.decode(Data(contentsOf: url))
        } catch {
            message = (error as? Backup.RestoreError)?.localizedDescription ?? "That file isn’t a Since backup."
        }
    }

    private func restorePendingImport() {
        guard let backup = pendingImport else { return }
        do {
            try backup.restoreAndSave(into: context)
            WidgetCenter.shared.reloadAllTimelines()
            refreshMirrors(context)
            message = "Restored \(backup.counters.count) counters and \(backup.countdowns?.count ?? 0) countdowns."
            // On a new iPhone nothing has asked for notifications yet, so restored reminders would never show.
            if backup.counters.contains(where: \.notifyMilestones) || (backup.countdowns ?? []).contains(where: \.notifyBefore) {
                Task {
                    let allowed = await Milestones.requestPermission()
                    notificationsDenied = !allowed
                    refreshMirrors(context)
                }
            }
        } catch {
            message = (error as? Backup.RestoreError)?.localizedDescription ?? "The backup couldn’t be restored. Your previous data has been kept."
        }
        pendingImport = nil
    }
}

#Preview(traits: .sampleData) {
    SettingsView()
}
