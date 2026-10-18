import SwiftUI
import SwiftData

/// A countdown on the Until tab: days to go, and the wait drawn in the countdown's style
/// (a calendar page, a fill rising up the card, or a timeline).
/// Once a one-off day has passed, it offers to count days since it or to move it to Past.
struct CountdownCard: View {
    let countdown: Countdown
    /// The card is changing size: its content is faded out meanwhile.
    var isReshaping = false
    /// A timer that has just ended, about to go.
    var isFinishing = false
    let onOpen: () -> Void
    var onCountSince: () -> Void = {}
    var onArchive: () -> Void = {}
    /// On the day: marks it done.
    var onDone: () -> Void = {}

    var body: some View {
        let tint = countdown.color.color.onCard(tinted: countdown.tinted)
        let fills = countdown.style == .fill && !needsDecision

        // A new style swaps in through a blur.
        ZStack(alignment: .topLeading) {
            Group {
                if countdown.isTimer {
                    timer(tint: tint)
                } else {
                    switch countdown.size {
                    case .m: compact(tint: tint)
                    case .l: wide(tint: tint)
                    case .xl: large(tint: tint)
                    }
                }
            }
            .id(countdown.style)
            .transition(.blurReplace)
        }
        .reshaping(isReshaping)
        .homeCard(size: countdown.size, color: countdown.color.color, tinted: countdown.tinted,
                  fillLevel: fills ? countdown.progress() : nil, onOpen: onOpen)
        // A timer that has ended blurs away after its burst. Only the blur is slow; "Time's up" comes at once.
        .animation(.easeIn(duration: 1.2).delay(0.4)) { card in
            card
                .blur(radius: isFinishing ? 8 : 0)
                .opacity(isFinishing ? 0.5 : 1)
        }
        // A timer ending, Done, or a day's time coming while it's on screen.
        .completionBurst(isActive: isFinishing || countdown.isDone(),
                         at: countdown.isTimer ? nil : countdown.moment(), symbol: countdown.symbol,
                         tint: countdown.color.color)
    }

    /// A one-off day that has gone by and still waits for a choice.
    private var needsDecision: Bool {
        countdown.hasPassed() && !countdown.isArchived
    }

    /// Today's the day (or a day of its window): the card offers to mark it done.
    private var isTheDay: Bool {
        countdown.isTheDay() && !countdown.isArchived
    }

    private func doneButton(tint: Color) -> some View {
        Button(action: onDone) {
            Label("Done", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.black.opacity(0.8))
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }

    // MARK: - Sizes

    /// A timer: the time left ticking down, when it ends, and a bar that fills as it runs.
    private func timer(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: countdown.title, symbol: countdown.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                MomentCountdown(moment: countdown.date, size: 40)
                Text(isFinishing ? "Time’s up" : "ends at \(countdown.date.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            if countdown.createdAt < countdown.date {
                ProgressView(timerInterval: countdown.createdAt...countdown.date, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(tint)
            }
        }
    }

    /// M: title, days to go, the date, and the wait in the countdown's style.
    private func compact(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: countdown.title, symbol: countdown.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                DaysLeftText(countdown, size: 40)
                dateLine
            }
            if needsDecision {
                Spacer(minLength: 0)
                decision(tint: tint, vertical: true)
            } else if isTheDay {
                Spacer(minLength: 0)
                doneButton(tint: tint)
            } else {
                switch countdown.style {
                case .calendar:
                    MonthGrid(month: countdown.target(), target: countdown.target(), tint: tint,
                              window: countdown.window())
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
                DaysLeftText(countdown, size: 40)
            }
            if needsDecision {
                decision(tint: tint, vertical: false)
            } else if isTheDay {
                doneButton(tint: tint)
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
                DaysLeftText(countdown, size: 56)
                dateLine
            }
            if needsDecision {
                decision(tint: tint, vertical: false)
            } else if isTheDay {
                doneButton(tint: tint)
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
        return HStack(spacing: 4) {
            Text(countdown.dateLine())
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
                MonthGrid(month: month, target: target, tint: tint, showsTitle: true, window: countdown.window())
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

/// "42 days" to go, "Today" on the day, "3 days ago" after it. "~14 days" ahead of a window, "Any Day" inside it,
/// and on a day with a time, a live countdown to it.
struct DaysLeftText: View {
    let days: Int
    var size: CGFloat = 40
    /// The same time in weeks or months ("6w 1d"), when the countdown is written that way.
    var parts: [DurationPart]?
    /// Counted to the middle of a window, so only about right: "~14 days".
    var isApproximate = false
    /// Inside the window it should come in.
    var isInWindow = false
    /// The moment it comes, on the day: counted down to the second instead of "Today".
    var moment: Date?

    var body: some View {
        let count = abs(days)
        Group {
            if isInWindow {
                word("Any Day")
            } else if days == 0, let moment {
                MomentCountdown(moment: moment, size: size)
            } else if days == 0 {
                word("Today")
            } else if let parts {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    approximately
                    DurationPartsText(parts: parts, size: size, suffix: days < 0 ? "ago" : nil)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        approximately
                        Text(count, format: .number)
                            .font(.system(size: size, weight: .bold))
                            .contentTransition(.numericText(value: Double(count)))
                    }
                    Text(days > 0 ? (count == 1 ? "day" : "days") : (count == 1 ? "day ago" : "days ago"))
                        .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
    }

    private func word(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var approximately: some View {
        if isApproximate {
            Text("~")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

extension DaysLeftText {
    /// A countdown's days as its card shows them.
    init(_ countdown: Countdown, size: CGFloat = 40, now: Date = .now) {
        self.init(days: countdown.daysLeft(now: now), size: size, parts: countdown.durationParts(now: now),
                  isApproximate: countdown.isApproximate(now: now), isInWindow: countdown.isInWindow(now: now),
                  moment: countdown.moment(now: now))
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
            DaysLeftText(countdown, size: 40)
                .minimumScaleFactor(0.5)
            Text(countdown.dateLine())
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
