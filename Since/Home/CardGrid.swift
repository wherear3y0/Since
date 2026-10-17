import SwiftUI
import SwiftData

/// Cards in order, packed into rows: M cards two to a row, L and XL across the whole width.
/// An M card followed by a wide one keeps its half and leaves the other half empty.
/// M rows are as tall as an M card is wide, plus room for its text; L and XL are as tall as their content.
/// Shared by the Since and Until tabs; each card says its size with `.cardSize(_:)`.
nonisolated struct CardGridLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 370
        let bottom = frames(for: subviews, width: width).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: bottom)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        let half = (width - spacing) / 2
        let rowHeight = half + 110
        var frames: [CGRect] = []
        var y: CGFloat = 0
        /// An M card took the left half of the current row.
        var leftTaken = false

        for subview in subviews {
            if subview[CardSizeKey.self] == .m {
                frames.append(CGRect(x: leftTaken ? half + spacing : 0, y: y, width: half, height: rowHeight))
                if leftTaken {
                    y += rowHeight + spacing
                }
                leftTaken.toggle()
            } else {
                if leftTaken {
                    y += rowHeight + spacing
                    leftTaken = false
                }
                let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height + spacing
            }
        }
        return frames
    }
}

private nonisolated struct CardSizeKey: LayoutValueKey {
    static let defaultValue = CardSize.m
}

extension View {
    /// How much room this card takes in a `CardGridLayout`.
    func cardSize(_ size: CardSize) -> some View {
        layoutValue(key: CardSizeKey.self, value: size)
    }
}

extension CardSize {
    /// Inner padding of a card.
    var padding: CGFloat { self == .xl ? 18 : 14 }

    /// The cell size of an M card's heatmap for a grid `rowWidth` wide: an M card is half the row less
    /// the 12-point gap, with its padding and 7 columns 3 points apart. L and XL cards use the same size
    /// and fit more weeks instead of bigger cells.
    static func mCellSize(rowWidth: CGFloat) -> CGFloat {
        let mContentWidth = (rowWidth - 12) / 2 - 2 * CardSize.m.padding
        return (mContentWidth - 6 * 3) / 7
    }

    /// How many weeks of M-sized cells fit across this card, with the 30-point weekday labels.
    func weeksAcross(rowWidth: CGFloat) -> Int {
        let content = rowWidth - 2 * padding
        let cell = CardSize.mCellSize(rowWidth: rowWidth)
        return max(Int((content - 30 + 3) / (cell + 3)), 1)
    }
}

extension View {
    /// A card's content while the card changes size: faded out while the card takes its new shape,
    /// then back in, already laid out for the new size, so it doesn't jump.
    func reshaping(_ isReshaping: Bool) -> some View {
        self
            .opacity(isReshaping ? 0 : 1)
            .blur(radius: isReshaping ? 6 : 0)
    }
}

extension View {
    /// The frame every home card shares: padding, colored background and edge, tap to open,
    /// and shapes for dragging and the context menu. `fillLevel` raises color from the bottom.
    /// The grids add the glow under the finger (`pressEffect`) outside the zoom transition source.
    func homeCard(size: CardSize, color: Color, tinted: Bool, fillLevel: Double? = nil,
                  onOpen: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return self
            .padding(size.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // While a card changes size, its content never spills over the neighbors.
            .clipShape(shape)
            .background {
                if let fillLevel {
                    FillLevel(level: fillLevel, tint: color.onCard(tinted: tinted))
                        .clipShape(shape)
                }
            }
            .counterCardBackground(tint: color.onCard(tinted: tinted), tinted: tinted)
            .contentShape(shape)
            .onTapGesture(perform: onOpen)
            .contentShape(.dragPreview, shape)
            .contentShape(.contextMenuPreview, shape)
    }
}

/// Icon and title at the top of a card.
struct CardTitle: View {
    let title: String
    let symbol: String
    let tint: Color

    /// Tall symbols (a cake, a trophy) get the same height as the rest, so numbers line up across a row.
    @ScaledMetric(relativeTo: .headline) private var iconHeight: CGFloat = 21

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .frame(height: iconHeight)
        }
        .font(.headline)
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
    }
}

/// Size choices for a card's context menu. Plain buttons rather than a Picker: a Picker's binding
/// in a context menu can outlive the card it was made for and change a different one.
struct SizeMenu: View {
    let current: CardSize
    let onSelect: (CardSize) -> Void

    var body: some View {
        Menu {
            ForEach(CardSize.allCases) { size in
                Button {
                    onSelect(size)
                } label: {
                    if current == size {
                        Label(size.title, systemImage: "checkmark")
                    } else {
                        Text(size.title)
                    }
                }
            }
        } label: {
            Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }
}

/// Anything the home grids can reorder by dragging.
protocol Sortable: PersistentModel {
    var sortOrder: Int { get set }
}

extension Counter: Sortable {}
extension Countdown: Sortable {}

/// Moves the dragged card live as it passes over other cards, then renumbers `sortOrder`.
struct ReorderDropDelegate<Item: Sortable>: DropDelegate {
    let target: Item
    let items: [Item]
    @Binding var dragged: Item?
    let onMove: () -> Void
    let onFinish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged !== target,
              let from = items.firstIndex(of: dragged),
              let to = items.firstIndex(of: target) else { return }

        var reordered = items
        reordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy) {
            for (index, item) in reordered.enumerated() {
                item.sortOrder = index
            }
        }
        onMove()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        onFinish()
        return true
    }
}
