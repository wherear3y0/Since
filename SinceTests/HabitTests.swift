import Foundation
import Testing
@testable import Since

@MainActor
struct HabitTests {
    @Test func packPriceIsShared() {
        // 300 for a pack of 20, 10 a day: 150 a day.
        let savings = Savings(unitsPerDay: 10, price: 300, unitsPerPrice: 20, minutesPerUnit: 5)
        #expect(savings.moneyPerUnit == 15)
        #expect(savings.moneyPerDay == 150)
        #expect(savings.money(units: savings.units(days: 4, less: 3)) == 555)
    }

    @Test func oldSmokingCountersAreRecognized() {
        #expect(Habit.guess(unitName: "cigarettes", title: "Free", symbol: "star.fill", showsHealth: false) == .smoking)
        #expect(Habit.guess(unitName: "", title: "Не курю", symbol: "star.fill", showsHealth: false) == .smoking)
        #expect(Habit.guess(unitName: "", title: "Smoke-free", symbol: "star.fill", showsHealth: false) == .smoking)
        #expect(Habit.guess(unitName: "", title: "Anything", symbol: "lungs.fill", showsHealth: false) == .smoking)
        #expect(Habit.guess(unitName: "", title: "Anything", symbol: "star.fill", showsHealth: true) == .smoking)
        #expect(Habit.guess(unitName: "cups", title: "Coffee", symbol: "mug.fill", showsHealth: false) == .other)
    }

    @Test func unitWords() {
        let counter = Counter(title: "Smoke-free", symbol: "lungs.fill", color: .mint, startDate: .now)
        counter.habit = .smoking
        #expect(counter.amountText(1) == "1 cigarette")
        #expect(counter.amountText(3) == "3 cigarettes")

        let other = Counter(title: "Chips", symbol: "star.fill", color: .orange, startDate: .now)
        #expect(other.amountText(2) == "2")
        other.unitName = "bags"
        #expect(other.amountText(2) == "2 bags")
    }
}
