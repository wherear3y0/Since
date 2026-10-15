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

extension Countdown {
    /// A yearly countdown to someone's birthday, from the first one when the contact has the year.
    /// Nil for a contact without a birthday or a name.
    static func birthday(of contact: CNContact, color: CounterColor, sortOrder: Int,
                         calendar: Calendar = .app) -> Countdown? {
        guard contact.isKeyAvailable(CNContactBirthdayKey),
              let birthday = contact.birthday, let month = birthday.month, let day = birthday.day else { return nil }
        // Reading a field the picker didn't fetch would crash, so each one is checked first.
        let field = { (key: String, value: () -> String) in contact.isKeyAvailable(key) ? value() : "" }
        let name = [field(CNContactGivenNameKey) { contact.givenName }, field(CNContactFamilyNameKey) { contact.familyName }]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let title = name.isEmpty ? field(CNContactOrganizationNameKey) { contact.organizationName } : name
        guard !title.isEmpty else { return nil }

        let year = birthday.year ?? calendar.component(.year, from: .now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let countdown = Countdown(title: title, symbol: "birthday.cake.fill", color: color, date: date,
                                  rule: RepeatRule(frequency: .yearly), sortOrder: sortOrder)
        countdown.countsYears = birthday.year != nil
        return countdown
    }
}
