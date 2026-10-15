import SwiftUI

/// A tab coming on screen: its cards blur in as a wave, row by row from the top and across each row
/// from the side the tab bar's highlight moved toward. A new value replays the wave.
struct TabArrival: Equatable {
    var id = UUID()
    /// The side the page comes in from; nil on launch, when the wave just runs down the page.
    var edge: HorizontalEdge?

    /// How long a card waits before blurring in.
    func delay(for slot: CardSlot) -> Double {
        // 0 at the left, 1 at the right; a card across the width sits in the middle.
        var across = slot.column.map(Double.init) ?? 0.5
        if edge == .trailing {
            across = 1 - across
        }
        // Rows below the first screen don't wait longer than the last visible one.
        return Double(min(slot.row, 5)) * 0.045 + across * 0.05
    }
}

/// Where a card lands in a `CardGridLayout`.
struct CardSlot {
    var row: Int
    /// 0 on the left, 1 on the right; nil for an L or XL card across the width.
    var column: Int?
}

extension CardGridLayout {
    /// The row and column of each card, packed the way the layout packs them.
    static func slots(for sizes: [CardSize], firstRow: Int = 0) -> [CardSlot] {
        var slots: [CardSlot] = []
        var row = firstRow
        var leftTaken = false
        for size in sizes {
            if size == .m {
                slots.append(CardSlot(row: row, column: leftTaken ? 1 : 0))
                if leftTaken {
                    row += 1
                }
                leftTaken.toggle()
            } else {
                if leftTaken {
                    row += 1
                    leftTaken = false
                }
                slots.append(CardSlot(row: row, column: nil))
                row += 1
            }
        }
        return slots
    }
}

extension View {
    /// Blurs in from the side a tab came in from: sharpens, fades in and settles into place.
    /// Hidden at once (without animation) when `isShown` turns false, so a wave can replay.
    func waveIn(_ isShown: Bool, delay: Double, from edge: HorizontalEdge?) -> some View {
        let shift: CGFloat = switch edge {
        case .trailing: 24
        case .leading: -24
        case nil: 0
        }
        return self
            .blur(radius: isShown ? 0 : 10)
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown ? 1 : 0.96)
            .offset(x: isShown ? 0 : shift, y: isShown ? 0 : 10)
            // Fast out of the gate and long to settle: a spring starting from rest would keep
            // the cards invisible for the first moments after the tap.
            .animation(isShown ? .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.5).delay(delay) : nil, value: isShown)
    }
}
