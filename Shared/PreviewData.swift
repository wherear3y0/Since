import SwiftUI
import SwiftData

/// Sample counters with reset history and sample countdowns, used by SwiftUI previews.
struct SampleData: PreviewModifier {
    static func makeSharedContext() throws -> ModelContainer {
        let container = try ModelContainer(for: Counter.self, Reset.self, Countdown.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        insertSamples(into: container.mainContext)
        insertCountdownSamples(into: container.mainContext)
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }

    static func insertSamples(into context: ModelContext) {
        func daysAgo(_ n: Int) -> Date {
            Calendar.app.date(byAdding: .day, value: -n, to: .now)!
        }

        let samples: [(String, String, CounterColor, CounterKind, Int, [Int], String?)] = [
            ("Smoke-free", "lungs.fill", .mint, .quit, 210, [160, 95, 41], "Every cigarette not smoked counts."),
            ("Coffee", "cup.and.saucer.fill", .orange, .quit, 70, [52, 30, 12], nil),
            ("Alcohol-free", "wineglass.fill", .purple, .quit, 400, [], "Since the trip to Lisbon."),
            ("Doomscrolling", "iphone", .red, .quit, 35, [24, 17, 9, 4], nil),
            ("Haircut", "scissors", .green, .lastTime, 120, [92, 61, 28], nil),
            ("Called mom", "phone.fill", .blue, .lastTime, 45, [37, 30, 22, 16], nil),
        ]

        for (index, sample) in samples.enumerated() {
            let (title, symbol, color, kind, start, resets, note) = sample
            let counter = Counter(title: title, symbol: symbol, color: color, kind: kind,
                                  startDate: daysAgo(start), note: note, sortOrder: index)
            context.insert(counter)
            for reset in resets {
                counter.resets.append(Reset(date: daysAgo(reset)))
            }
        }
    }

    static func insertCountdownSamples(into context: ModelContext) {
        func days(_ n: Int) -> Date {
            Calendar.app.date(byAdding: .day, value: n, to: .now)!
        }
        let birthday = Calendar.app.date(byAdding: .year, value: -58, to: days(12))!

        // Title, symbol, color, date, repeat, added (days from now), size.
        let samples: [(String, String, CounterColor, Date, RepeatRule, Int, CardSize)] = [
            ("Vacation", "airplane", .cyan, days(42), .never, -20, .m),
            ("Mom’s birthday", "birthday.cake.fill", .pink, birthday, RepeatRule(frequency: .yearly), -200, .m),
            ("Concert", "music.note", .purple, days(5), .never, -30, .l),
            ("Payday", "creditcard.fill", .green, days(-20), RepeatRule(frequency: .monthly), -60, .m),
            ("Sugar-free", "carrot.fill", .lime, days(-2), .never, -14, .m),
        ]
        for (index, sample) in samples.enumerated() {
            let (title, symbol, color, date, rule, added, size) = sample
            let countdown = Countdown(title: title, symbol: symbol, color: color, date: date,
                                      rule: rule, sortOrder: index)
            countdown.createdAt = days(added)
            countdown.size = size
            countdown.style = CountdownStyle.allCases[index % CountdownStyle.allCases.count]
            context.insert(countdown)
        }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var sampleData: Self = .modifier(SampleData())
}
