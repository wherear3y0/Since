import Testing
@testable import Since

struct SiriTests {
    @Test func spokenNamesMatchInOtherForms() {
        #expect(SpokenName.matches(title: "Курение", spoken: "курения"))
        #expect(SpokenName.matches(title: "Звонок маме", spoken: "звонка маме"))
        #expect(SpokenName.matches(title: "Smoke-free", spoken: "smoke free"))
        #expect(SpokenName.matches(title: "Mom’s birthday", spoken: "mom birthday"))
        #expect(SpokenName.matches(title: "Ёлка", spoken: "елка"))
    }

    @Test func otherNamesDontMatch() {
        #expect(!SpokenName.matches(title: "Coffee", spoken: "alcohol"))
        #expect(!SpokenName.matches(title: "Отпуск", spoken: "отпор"))
        #expect(!SpokenName.matches(title: "Vacation", spoken: ""))
    }
}
