import SwiftUI
import SwiftData

/// A countdown on the Until tab: days to go, and the wait drawn in the countdown's style
/// (a calendar page, a fill rising up the card, or a timeline).
/// Once a one-off day has passed, it offers to count days since it or to move it to Past.
struct CountdownCard: View {
    let countdown: Countdown
    /// The card is changing size: its content is faded out meanwhile.
    var isReshaping = false
    let onOpen: () -> Void
    var onCountSince: () -> Void = {}
    var onArchive: () -> Void = {}

    var body: some View {
        let tint = countdown.color.color.onCard(tinted: countdown.tinted)
        let fills = countdown.style == .fill && !needsDecision

        // A new style swaps in through a blur.
        ZStack(alignment: .topLeading) {
            Group {
                switch countdown.size {
                case .m: compact(tint: tint)
                case .l: wide(tint: tint)
                case .xl: large(tint: tint)
                }
            }
            .id(countdown.style)
            .transition(.blurReplace)
        }
        .reshaping(isReshaping)
        .homeCard(size: countdown.size, color: countdown.color.color, tinted: countdown.tinted,
                  fillLevel: fills ? countdown.progress() : nil, onOpen: onOpen)
    }

    /// A one-off day that has gone by and still waits for a choice.
    private var needsDecision: Bool {
        countdown.hasPassed() && !countdown.isArchived
    }

    // MARK: - Sizes

    /// M: title, days to go, the date, and the wait in the countdown's style.
    private func compact(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: countdown.title, symbol: countdown.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                DaysLeftText(days: countdown.daysLeft(), size: 40, parts: countdown.durationParts())
                dateLine
            }
            if needsDecision {
                Spacer(minLength: 0)
                decision(tint: tint, vertical: true)
            } else {
                switch countdown.style {
                case .calendar:
                    MonthGrid(month: countdown.target(), target: countdown.target(), tint: tint)
                case .fill:
                    Spacer(minLength: 0)
                    fillFooter
                case .timeline:
                    Spacer(minLength: 0)
                    if countdown.daysLeft() > 0 {
                        let left = DayMath.timeLeft(until: countdown.target(), from: .now)
                        HStack(alignment: .top) {
                            stat("Weekends", value: "\(left.weekends)")
                            stat("Workdays", value: "\(left.workdays)")
                        }
                    }
                    timeline(tint: tint)
                }
            }
        }
    }

    /// L: title and date on the left, days on the right, the wait across the width underneath.
    private func wide(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CardTitle(title: countdown.title, symbol: countdown.symbol, tint: tint)
                    dateLine
                }
                Spacer(minLength: 8)
                DaysLeftText(days: countdown.daysLeft(), size: 40, parts: countdown.durationParts())
            }
            if needsDecision {
                decision(tint: tint, vertical: false)
            } else {
                switch countdown.style {
                case .calendar:
                    twoMonths(tint: tint)
                        .frame(height: 150)
                case .fill:
                    fillFooter
                        .padding(.top, 18)
                case .timeline:
                    timeline(tint: tint)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// XL: a big number, the wait in the countdown's style, and the weeks, weekends and workdays still to go.
    private func large(tint: Color) -> some View {
        let target = countdown.target()
        let daysLeft = countdown.daysLeft()
        let waited = countdown.waited()
        let total = DayMath.days(from: countdown.waitStart(), to: target)
        let left = DayMath.timeLeft(until: target, from: .now)

        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: countdown.title, symbol: countdown.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                DaysLeftText(days: daysLeft, size: 56, parts: countdown.durationParts())
                dateLine
            }
            if needsDecision {
                decision(tint: tint, vertical: false)
            } else {
                switch countdown.style {
                case .calendar:
                    twoMonths(tint: tint)
                        .frame(height: 170)
                    if daysLeft > 0 && total > 0 {
                        VStack(spacing: 8) {
                            WaitPills(waited: waited, total: total, tint: tint)
                            RecordTrack(current: waited, target: total, tint: tint, animated: false)
                        }
                    }
                case .fill:
                    fillFooter
                        .padding(.top, 56)
                case .timeline:
                    timeline(tint: tint, thickness: 5)
                        .padding(.vertical, 6)
                }
                if daysLeft > 0 {
                    HStack(alignment: .top) {
                        stat("Weeks", value: "\(daysLeft / 7)")
                        stat("Weekends", value: "\(left.weekends)")
                        stat("Workdays", value: "\(left.workdays)")
                    }
                }
            }
        }
    }

    // MARK: - Parts

    private var dateLine: some View {
        let target = countdown.target()
        let days = countdown.daysLeft()
        let text = days > 0 ? "until \(target.untilFormat)" : (days == 0 ? target.untilFormat : "on \(target.untilFormat)")
        return HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
            if countdown.rule.repeats {
                Image(systemName: "repeat")
                    .imageScale(.small)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        // A repeating day rolling over to its next time swaps through a blur.
        .id(target)
        .transition(.blurReplace)
    }

    /// This month and the day's month side by side.
    private func twoMonths(tint: Color) -> some View {
        let target = countdown.target()
        return HStack(spacing: 16) {
            ForEach(Calendar.app.monthsShown(now: .now, target: target), id: \.self) { month in
                MonthGrid(month: month, target: target, tint: tint, showsTitle: true)
            }
        }
    }

    /// "32%" over the fill, with how far into the wait it is.
    private var fillFooter: some View {
        CountdownFillFooter(waited: countdown.waited(), daysLeft: countdown.daysLeft(), progress: countdown.progress())
    }

    private func timeline(tint: Color, thickness: CGFloat = 4) -> some View {
        CountdownTimeline(start: countdown.waitStart(), target: countdown.target(), waited: countdown.waited(),
                          daysLeft: countdown.daysLeft(), tint: tint, thickness: thickness)
    }

    private func decision(tint: Color, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button(action: onCountSince) {
                Label("Count Since", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black.opacity(0.8))
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            Button(action: onArchive) {
                Label("Move to Past", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "42 days" to go, "Today" on the day, "3 days ago" after it.
struct DaysLeftText: View {
    let days: Int
    var size: CGFloat = 40
    /// The same time in weeks or months ("6w 1d"), when the countdown is written that way.
    var parts: [DurationPart]?

    var body: some View {
        let count = abs(days)
        Group {
            if days == 0 {
                Text("Today")
                    .font(.system(size: size, weight: .bold))
                    .minimumScaleFactor(0.6)
            } else if let parts {
                DurationPartsText(parts: parts, size: size, suffix: days < 0 ? "ago" : nil)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(count, format: .number)
                        .font(.system(size: size, weight: .bold))
                        .contentTransition(.numericText(value: Double(count)))
                    Text(days > 0 ? (count == 1 ? "day" : "days") : (count == 1 ? "day ago" : "days ago"))
                        .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
    }
}

/// "Day 38 of 60 … 63%": how much of the wait is already behind.
struct WaitPills: View {
    let waited: Int
    let total: Int
    let tint: Color
    /// Off where the percentage is already shown big.
    var showsPercent = true

    var body: some View {
        let percent = Int((Double(waited) / Double(max(total, 1)) * 100).rounded())
        HStack(alignment: .firstTextBaseline) {
            pill("Day \(waited) of \(total)")
            Spacer(minLength: 4)
            if showsPercent {
                pill("\(min(percent, 100))%")
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.25), in: Capsule())
    }
}

/// What a countdown card shrinks into above its context menu: the same layout as the small widget.
struct CountdownMenuPreview: View {
    let countdown: Countdown

    var body: some View {
        let tint = countdown.color.color.onCard(tinted: countdown.tinted)
        let target = countdown.target()

        VStack(alignment: .leading, spacing: 0) {
            Label(countdown.title, systemImage: countdown.symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(tint)
            Spacer(minLength: 4)
            DaysLeftText(days: countdown.daysLeft(), size: 40)
                .minimumScaleFactor(0.5)
            Text(target.untilFormat)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            switch countdown.style {
            case .calendar:
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.25))
                        Capsule().fill(tint)
                            .frame(width: max(6, proxy.size.width * countdown.progress()))
                    }
                }
                .frame(height: 6)
            case .fill:
                Text("\(Int((countdown.progress() * 100).rounded()))%")
                    .font(.headline)
            case .timeline:
                TimelineTrack(waited: countdown.waited(), daysLeft: countdown.daysLeft(), tint: tint)
            }
        }
        .padding(16)
        .frame(width: 170, height: 170, alignment: .leading)
        // The card keeps its edge as it lifts into the menu.
        .cardEdge(tint: tint)
        .background {
            ZStack {
                if countdown.tinted {
                    Color.pageBackground
                    tint.opacity(0.17)
                } else {
                    SoftColorFill(tint: tint)
                }
                if countdown.style == .fill {
                    FillLevel(level: countdown.progress(), tint: tint)
                }
            }
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \Countdown.sortOrder) var countdowns: [Countdown]
    ScrollView {
        CardGridLayout {
            ForEach(countdowns) { countdown in
                CountdownCard(countdown: countdown, onOpen: {})
                    .cardSize(countdown.size)
            }
        }
        .padding()
    }
    .background(Color.pageBackground)
}
