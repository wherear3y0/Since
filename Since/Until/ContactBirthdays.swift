import SwiftUI
import Contacts
import ContactsUI

/// The system's contact picker, limited to people with a birthday. It runs outside the app,
/// so it needs no access to Contacts: only the chosen people come back.
struct ContactBirthdayPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "birthday != nil")
        picker.displayedPropertyKeys = [CNContactBirthdayKey]
        // Presented on the next turn, once the host is in the window.
        DispatchQueue.main.async {
            host.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactBirthdayPicker

        init(parent: ContactBirthdayPicker) {
            self.parent = parent
        }

        // Having this one (not the single-contact one) lets several people be picked at once.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.isPresented = false
            parent.onPick(contacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// How a birthday countdown is titled.
enum BirthdayNameStyle: String, CaseIterable, Identifiable {
    /// "Anna Haro"
    case fullName
    /// "Anna"
    case firstName
    /// "Anna’s Birthday"
    case birthdayOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullName: "Full Name"
        case .firstName: "First Name"
        case .birthdayOf: "Name’s Birthday"
        }
    }
}

extension Countdown {
    /// What a contact's birthday countdown would be: its title, the first day and whether the year is known.
    struct BirthdayInfo {
        let title: String
        /// The day of birth, or this year's birthday when the contact has no year.
        let date: Date
        let knowsYear: Bool
        /// For telling whether the person already has a countdown.
        let firstName: String
    }

    /// Nil for a contact without a birthday or a name.
    static func birthdayInfo(of contact: CNContact, nameStyle: BirthdayNameStyle = .fullName,
                             calendar: Calendar = .app) -> BirthdayInfo? {
        guard contact.isKeyAvailable(CNContactBirthdayKey),
              let birthday = contact.birthday, let month = birthday.month, let day = birthday.day else { return nil }
        // Reading a field the picker didn't fetch would crash, so each one is checked first.
        let field = { (key: String, value: () -> String) in contact.isKeyAvailable(key) ? value() : "" }
        let given = field(CNContactGivenNameKey) { contact.givenName }
        let name = [given, field(CNContactFamilyNameKey) { contact.familyName }]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fullName = name.isEmpty ? field(CNContactOrganizationNameKey) { contact.organizationName } : name
        guard !fullName.isEmpty else { return nil }
        let firstName = given.isEmpty ? fullName : given

        let title = switch nameStyle {
        case .fullName: fullName
        case .firstName: firstName
        case .birthdayOf: "\(firstName)’s Birthday"
        }
        let year = birthday.year ?? calendar.component(.year, from: .now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return BirthdayInfo(title: title, date: date, knowsYear: birthday.year != nil, firstName: firstName)
    }

    /// A yearly countdown to someone's birthday, from the first one when the contact has the year.
    /// Nil for a contact without a birthday or a name.
    static func birthday(of contact: CNContact, color: CounterColor, sortOrder: Int,
                         nameStyle: BirthdayNameStyle = .fullName, calendar: Calendar = .app) -> Countdown? {
        guard let info = birthdayInfo(of: contact, nameStyle: nameStyle, calendar: calendar) else { return nil }
        let countdown = Countdown(title: info.title, symbol: "birthday.cake.fill", color: color, date: info.date,
                                  rule: RepeatRule(frequency: .yearly), sortOrder: sortOrder)
        countdown.countsYears = info.knowsYear
        countdown.isBirthday = true
        return countdown
    }
}

/// Asked after people are picked from Contacts: how their birthdays should look on the Until tab.
struct BirthdayImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let contacts: [CNContact]
    /// The countdowns already there, to skip people who have one and to put the new ones on top.
    let existing: [Countdown]

    // The last choices are offered again next time.
    @AppStorage("birthdayNameStyle") private var nameStyleRaw = BirthdayNameStyle.fullName.rawValue
    @AppStorage("birthdayCountdownStyle") private var styleRaw = CountdownStyle.calendar.rawValue
    @AppStorage("birthdayCardSize") private var sizeRaw = CardSize.m.rawValue
    @State private var notifyBefore = false

    private var nameStyle: BirthdayNameStyle { BirthdayNameStyle(rawValue: nameStyleRaw) ?? .fullName }
    private var style: CountdownStyle { CountdownStyle(rawValue: styleRaw) ?? .calendar }
    private var size: CardSize { CardSize(rawValue: sizeRaw) ?? .m }

    private struct Person: Identifiable {
        let contact: CNContact
        let info: Countdown.BirthdayInfo
        /// Already has a countdown, so it's skipped.
        let isAdded: Bool

        var id: String { contact.identifier }
    }

    /// The picked people who have a birthday and a name.
    private var people: [Person] {
        contacts.compactMap { contact in
            guard let info = Countdown.birthdayInfo(of: contact, nameStyle: nameStyle) else { return nil }
            return Person(contact: contact, info: info, isAdded: isAlreadyAdded(info))
        }
    }

    var body: some View {
        let picked = people
        let newCount = picked.filter { !$0.isAdded }.count

        NavigationStack {
            Form {
                Section("Name") {
                    Picker("Name", selection: $nameStyleRaw) {
                        ForEach(BirthdayNameStyle.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("Style", selection: $styleRaw) {
                        ForEach(CountdownStyle.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Show As")
                } footer: {
                    Text(style.explanation)
                }

                Section("Card Size") {
                    Picker("Card Size", selection: $sizeRaw) {
                        ForEach(CardSize.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Reminders", isOn: $notifyBefore)
                } footer: {
                    Text("A notification a week before, the day before and on the day.")
                }

                Section("Birthdays") {
                    ForEach(picked) { person in
                        row(person.info, isAdded: person.isAdded)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle(newCount == 1 ? "Add Birthday" : "Add \(newCount) Birthdays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", role: .confirm) {
                        add(picked.filter { !$0.isAdded }.map(\.contact))
                    }
                    .disabled(newCount == 0)
                }
            }
            .sensoryFeedback(.selection, trigger: nameStyleRaw)
            .sensoryFeedback(.selection, trigger: styleRaw)
            .sensoryFeedback(.selection, trigger: sizeRaw)
        }
    }

    /// The title as it will read, the next birthday and the age it marks.
    private func row(_ info: Countdown.BirthdayInfo, isAdded: Bool) -> some View {
        let calendar = Calendar.app
        let rule = RepeatRule(frequency: .yearly)
        let next = rule.occurrence(rule.targetIndex(from: info.date, now: .now), from: info.date)
        let turns = calendar.dateComponents([.year], from: calendar.startOfDay(for: info.date), to: next).year ?? 0

        return HStack {
            Image(systemName: "birthday.cake.fill")
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                Text(isAdded ? "Already added" : next.untilFormat)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if info.knowsYear && turns > 0 && !isAdded {
                Text("turns \(turns)")
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isAdded ? 0.5 : 1)
    }

    /// Someone already counted down to: a yearly countdown on the same day with their name in the title.
    private func isAlreadyAdded(_ info: Countdown.BirthdayInfo) -> Bool {
        let calendar = Calendar.app
        let day = calendar.dateComponents([.month, .day], from: info.date)
        return existing.contains { countdown in
            countdown.rule.frequency == .yearly
                && calendar.dateComponents([.month, .day], from: countdown.date) == day
                && countdown.title.localizedStandardContains(info.firstName)
        }
    }

    /// A yearly countdown per person, on top of the tab, each in its own color.
    private func add(_ contacts: [CNContact]) {
        let colors: [CounterColor] = [.pink, .purple, .orange, .cyan, .yellow, .mint, .red, .blue, .lime, .green]
        let orders = Countdown.topOrders(contacts.count, above: existing)
        for (index, contact) in contacts.enumerated() {
            guard let countdown = Countdown.birthday(of: contact, color: colors[(existing.count + index) % colors.count],
                                                     sortOrder: orders[index], nameStyle: nameStyle) else { continue }
            countdown.style = style
            countdown.size = size
            countdown.notifyBefore = notifyBefore
            context.insert(countdown)
        }
        saveChanges(context)
        if notifyBefore {
            Task {
                _ = await Milestones.requestPermission()
                refreshMirrors(context)
            }
        }
        dismiss()
    }
}
