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

/// Hand-picked SF Symbols for the icon picker.
let counterSymbols: [String] = [
    "star.fill", "heart.fill", "flame.fill", "bolt.fill", "leaf.fill", "drop.fill",
    "sun.max.fill", "moon.fill", "cloud.rain.fill", "snowflake",
    "lungs.fill", "brain.head.profile", "pills.fill", "cross.case.fill", "bandage.fill", "bed.double.fill",
    "figure.run", "figure.strengthtraining.traditional", "figure.yoga", "bicycle", "dumbbell.fill",
    "cup.and.saucer.fill", "wineglass.fill", "mug.fill", "fork.knife", "birthday.cake.fill", "carrot.fill",
    "smoke.fill", "nosign", "iphone", "gamecontroller.fill", "tv.fill", "laptopcomputer",
    "book.fill", "graduationcap.fill", "music.note", "paintbrush.fill",
    "house.fill", "car.fill", "airplane", "cart.fill", "creditcard.fill",
    "phone.fill", "person.2.fill", "pawprint.fill", "scissors", "sparkles", "trophy.fill",
]
