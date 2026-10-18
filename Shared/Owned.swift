import Foundation

/// Why an owned thing is gone.
nonisolated enum GoneReason: String, CaseIterable, Identifiable {
    case sold, gaveAway, broke, lost, retired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sold: "Sold"
        case .gaveAway: "Gave Away"
        case .broke: "Broke"
        case .lost: "Lost"
        case .retired: "Stopped Using"
        }
    }

    var symbol: String {
        switch self {
        case .sold: "banknote"
        case .gaveAway: "gift"
        case .broke: "exclamationmark.triangle"
        case .lost: "questionmark.circle"
        case .retired: "archivebox"
        }
    }
}

extension Counter {
    /// A thing owned from a parcel that came: its name, icon, color and picture, counted from the day it came.
    convenience init(owning parcel: Countdown, sortOrder: Int, now: Date = .now) {
        self.init(title: parcel.title, symbol: parcel.symbol, color: parcel.color, kind: .owned,
                  startDate: parcel.doneDay ?? min(parcel.target(), now), note: parcel.note, sortOrder: sortOrder)
        tinted = parcel.tinted
        photoData = parcel.photoData
    }

    var isOwned: Bool { kind == .owned }

    /// An owned thing that's gone: it's kept in Past, its count stopped on that day.
    var isGone: Bool { goneDate != nil }

    var goneReason: GoneReason? {
        get { GoneReason(rawValue: goneReasonRaw) }
        set { goneReasonRaw = newValue?.rawValue ?? "" }
    }

    /// It's gone from that day on; never before the day it was got.
    func letGo(on date: Date, reason: GoneReason?) {
        goneDate = max(date, startDate)
        goneReason = reason
    }

    /// Still had after all.
    func keep() {
        goneDate = nil
        goneReason = nil
    }

    /// The next whole year it will have been had, and the day that comes. Nil once it's gone.
    func nextAnniversary(now: Date = .now, calendar: Calendar = .app) -> (years: Int, date: Date)? {
        guard !isGone else { return nil }
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        var years = 1
        while let date = calendar.date(byAdding: .year, value: years, to: start), date < today {
            years += 1
        }
        return calendar.date(byAdding: .year, value: years, to: start).map { (years, $0) }
    }

    /// How long it's been had, spelled out: "2 years 3 months 5 days".
    func hadFor(until end: Date? = nil, now: Date = .now, calendar: Calendar = .app) -> String {
        DayMath.parts(from: startDate, to: end ?? countEnd(now), style: .months, calendar: calendar)
            .map { "\($0.value) \($0.longUnit)" }
            .joined(separator: " ")
    }

    /// "Sold · Oct 18, 2026", or just the day when no reason was given.
    var goneLine: String? {
        guard let goneDate else { return nil }
        let day = goneDate.formatted(date: .abbreviated, time: .omitted)
        return goneReason.map { "\($0.title) · \(day)" } ?? "Gone · \(day)"
    }
}
