import SwiftUI

nonisolated enum CounterColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, lime, green, mint, cyan, blue, purple, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:    Color(red: 1.00, green: 0.22, blue: 0.37)
        case .orange: Color(red: 1.00, green: 0.48, blue: 0.16)
        case .yellow: Color(red: 1.00, green: 0.80, blue: 0.00)
        case .lime:   Color(red: 0.62, green: 0.84, blue: 0.13)
        case .green:  Color(red: 0.19, green: 0.82, blue: 0.35)
        case .mint:   Color(red: 0.00, green: 0.82, blue: 0.75)
        case .cyan:   Color(red: 0.25, green: 0.78, blue: 0.95)
        case .blue:   Color(red: 0.04, green: 0.52, blue: 1.00)
        case .purple: Color(red: 0.62, green: 0.40, blue: 1.00)
        case .pink:   Color(red: 0.93, green: 0.36, blue: 0.85)
        }
    }
}

/// A group of icons in the icon picker.
struct SymbolGroup: Identifiable {
    let title: String
    let symbols: [String]

    var id: String { title }
}

/// Hand-picked SF Symbols for the icon picker, by what they're for. Only symbols that exist on every
/// supported system: a name SF Symbols doesn't know draws nothing.
let symbolGroups: [SymbolGroup] = [
    SymbolGroup(title: "Habits", symbols: [
        "smoke.fill", "lungs.fill", "nosign", "wineglass.fill", "mug.fill", "cup.and.saucer.fill",
        "cube.fill", "birthday.cake.fill", "popcorn.fill", "takeoutbag.and.cup.and.straw.fill", "fork.knife",
        "pills.fill", "syringe.fill", "dice.fill", "suit.spade.fill", "cart.fill", "bag.fill", "creditcard.fill",
        "banknote.fill", "iphone", "gamecontroller.fill", "tv.fill", "play.rectangle.fill", "laptopcomputer",
        "bubble.left.and.bubble.right.fill", "moon.zzz.fill",
    ]),
    SymbolGroup(title: "Health", symbols: [
        "heart.fill", "bolt.heart.fill", "brain.head.profile", "cross.case.fill", "bandage.fill", "stethoscope",
        "bed.double.fill", "drop.fill", "carrot.fill", "leaf.fill", "eyes", "mouth.fill",
    ]),
    SymbolGroup(title: "Activity", symbols: [
        "figure.run", "figure.walk", "figure.yoga", "figure.strengthtraining.traditional", "dumbbell.fill",
        "bicycle", "figure.mind.and.body",
    ]),
    SymbolGroup(title: "Life", symbols: [
        "house.fill", "phone.fill", "person.2.fill", "pawprint.fill", "scissors", "book.fill",
        "graduationcap.fill", "music.note", "paintbrush.fill", "car.fill", "tshirt.fill", "alarm.fill",
    ]),
    SymbolGroup(title: "Days", symbols: [
        "star.fill", "sparkles", "trophy.fill", "gift.fill", "party.popper.fill", "airplane", "suitcase.fill",
        "beach.umbrella.fill", "tent.fill", "ticket.fill", "flame.fill", "bolt.fill",
    ]),
    SymbolGroup(title: "Nature", symbols: [
        "sun.max.fill", "moon.fill", "cloud.rain.fill", "snowflake", "tree.fill",
    ]),
]
