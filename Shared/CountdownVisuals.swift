import SwiftUI

/// How a countdown shows the wait, chosen per countdown.
nonisolated enum CountdownStyle: String, CaseIterable, Identifiable {
    /// A calendar page with the day marked.
    case calendar
    /// The card fills up with color as the day comes closer.
    case fill
    /// A line from the start of the wait to the day, with today on it.
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .fill: "Fill"
        case .timeline: "Timeline"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .fill: "square.bottomhalf.filled"
        case .timeline: "flag.checkered"
        }
    }

    var explanation: String {
        switch self {
        case .calendar: "The month of the day, with the days still to wait tinted."
        case .fill: "The card fills up with color as the day comes closer."
        case .timeline: "A line from the start of the wait to the day, marked in weeks or months."
        }
    }
}

/// A month as a calendar page: the days still to wait tinted, the day itself filled, today outlined.
/// Fills the space it's given; the rows share the height.
struct MonthGrid: View {
    let month: Date
    let target: Date
    let tint: Color
    var now: Date = .now
    var showsTitle = false
    var spacing: CGFloat = 3
    /// The days it can come on, all marked like the day itself.
    var window: ClosedRange<Date>? = nil

    var body: some View {
        let calendar = Calendar.app
        let rows = DayMath.monthGrid(of: month, today: now, target: target, window: window)
        let letters = (0..<7).map { calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + $0) % 7] }

        VStack(alignment: .leading, spacing: spacing) {
            if showsTitle {
                Text(calendar.isDate(month, equalTo: now, toGranularity: .year)
                     ? month.formatted(.dateTime.month(.wide))
                     : month.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: spacing) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            Color.clear
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: MonthDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            switch day.state {
            case .target:
                shape.fill(tint).widgetAccentable()
            case .waiting:
                shape.fill(tint.opacity(0.2))
            case .gone, .later:
                Color.clear
            }
            Text(day.number, format: .number)
                .font(.system(size: 11, weight: day.state == .target ? .bold : .medium))
                .minimumScaleFactor(0.6)
                .foregroundStyle(numberStyle(day.state))
            if day.isToday {
                shape.strokeBorder(.primary.opacity(0.85), lineWidth: 1.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func numberStyle(_ state: MonthDay.State) -> AnyShapeStyle {
        switch state {
        case .target: AnyShapeStyle(.black.opacity(0.75))
        case .waiting: AnyShapeStyle(.primary)
        case .gone: AnyShapeStyle(.tertiary)
        case .later: AnyShapeStyle(.secondary)
        }
    }
}

/// Color rising from the bottom of a card up to `level` (0…1), with a bright edge on top.
/// Meant as a background, clipped by whatever holds it.
struct FillLevel: View {
    let level: Double
    let tint: Color

    @State private var shown: Double

    init(level: Double, tint: Color, animated: Bool = false) {
        self.level = level
        self.tint = tint
        _shown = State(initialValue: animated ? 0 : level)
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * min(1, max(0, shown))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(tint)
                    .frame(height: height > 0 ? 1.5 : 0)
                    .widgetAccentable()
                Rectangle()
                    .fill(tint.opacity(0.28))
                    .frame(height: max(0, height - 1.5))
            }
        }
        .onAppear {
            guard shown != level else { return }
            withAnimation(.spring(duration: 1.1, bounce: 0.15).delay(0.15)) { shown = level }
        }
        .onChange(of: level) {
            withAnimation(.smooth) { shown = level }
        }
        .allowsHitTesting(false)
    }
}

/// A line from the start of the wait to the day: the part behind filled, today as a dot,
/// marks for the days, weeks or months still ahead, and a flag at the end.
struct TimelineTrack: View {
    let waited: Int
    let daysLeft: Int
    let tint: Color
    var thickness: CGFloat = 4
    var now: Date = .now

    @State private var isShown: Bool

    init(waited: Int, daysLeft: Int, tint: Color, thickness: CGFloat = 4, animated: Bool = false, now: Date = .now) {
        self.waited = waited
        self.daysLeft = daysLeft
        self.tint = tint
        self.thickness = thickness
        self.now = now
        _isShown = State(initialValue: !animated)
    }

    var body: some View {
        let total = waited + max(0, daysLeft)
        let fraction = total > 0 ? Double(waited) / Double(total) : 1
        let ticks = DayMath.timelineTicks(daysLeft: daysLeft, from: now)
        let dot = thickness * 3

        GeometryReader { proxy in
            // The flag sits past the end of the line, the dot is centered on today.
            let width = max(1, proxy.size.width - 14)
            let todayX = width * fraction * (isShown ? 1 : 0)
            let middle = proxy.size.height / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: width, height: thickness)
                    .offset(y: middle - thickness / 2)
                Capsule()
                    .fill(tint)
                    .frame(width: max(thickness, todayX), height: thickness)
                    .offset(y: middle - thickness / 2)
                    .widgetAccentable()
                ForEach(ticks, id: \.self) { tick in
                    Capsule()
                        .fill(tint.mix(with: .white, by: 0.5).opacity(0.55))
                        .frame(width: 1.5, height: thickness * 2.5)
                        .offset(x: width * Double(waited + tick) / Double(max(total, 1)) - 0.75,
                                y: middle - thickness * 1.25)
                }
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .offset(x: width - 2, y: middle - 15)
                    .widgetAccentable()
                Circle()
                    .fill(.white)
                    .frame(width: dot, height: dot)
                    .offset(x: todayX - dot / 2, y: middle - dot / 2)
            }
        }
        .frame(height: max(20, thickness * 4))
        .onAppear {
            guard !isShown else { return }
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.2)) { isShown = true }
        }
        .accessibilityHidden(true)
    }
}

/// "32% … Day 20 of 62" at the bottom of a filling card.
struct CountdownFillFooter: View {
    let waited: Int
    let daysLeft: Int
    let progress: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.title2.bold())
                .contentTransition(.numericText(value: progress))
            Spacer(minLength: 4)
            // "356 of 365" where "Day 356 of 365" doesn't fit, like on a small widget.
            ViewThatFits(in: .horizontal) {
                Text(daysLeft > 0 ? "Day \(waited) of \(waited + daysLeft)" : "The day")
                Text(daysLeft > 0 ? "\(waited) of \(waited + daysLeft)" : "The day")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

/// "6 weeks to go" over a timeline from the start of the wait to the day, with both dates underneath.
struct CountdownTimeline: View {
    let start: Date
    let target: Date
    let waited: Int
    let daysLeft: Int
    let tint: Color
    var thickness: CGFloat = 4
    var animated = false
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(daysLeft > 0 ? "\(DayMath.toGo(from: now, to: target)) to go" : (daysLeft == 0 ? "It’s today" : "Gone by"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TimelineTrack(waited: waited, daysLeft: daysLeft, tint: tint, thickness: thickness, animated: animated, now: now)
            TimelineLabels(start: start, target: target)
        }
    }
}

/// "Oct 15 … Nov 26" under a timeline: where the wait started and the day, with the year when it isn't this one.
struct TimelineLabels: View {
    let start: Date
    let target: Date

    var body: some View {
        HStack {
            Text(start.sinceFormat)
            Spacer(minLength: 4)
            Text(target.sinceFormat)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

extension Calendar {
    /// The months a two-month calendar shows: this month and the day's month,
    /// or the day's month and the next when it falls in this month (or is already gone).
    func monthsShown(now: Date, target: Date) -> [Date] {
        let thisMonth = dateInterval(of: .month, for: now)!.start
        let targetMonth = dateInterval(of: .month, for: target)!.start
        if targetMonth > thisMonth {
            return [thisMonth, targetMonth]
        }
        return [targetMonth, date(byAdding: .month, value: 1, to: targetMonth)!]
    }
}

/// "2:41:05" ticking down to the moment it comes, then "Now".
struct MomentCountdown: View {
    let moment: Date
    var size: CGFloat = 40

    var body: some View {
        // Drawn again right at the moment, to turn into "Now"; the timer text ticks by itself until then.
        // (The schedule's own date is the moment itself even before it, so the clock is read instead; and the
        // redraw is asked for a moment after it, as it can come a little early.)
        TimelineView(.explicit([moment, moment.addingTimeInterval(1)])) { _ in
            let now = Date.now
            Group {
                if now < moment {
                    Text(timerInterval: now...moment, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text("Now")
                }
            }
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
        }
    }
}
