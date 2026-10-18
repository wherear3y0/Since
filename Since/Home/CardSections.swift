import SwiftUI
import UIKit

/// A section's heading over its cards; tapping it folds the section away (showing how many it holds) and back.
/// The folded sections are remembered between launches under `storageKey`.
struct CardSectionHeading: View {
    let title: String
    let id: String
    let count: Int
    @Binding var collapsed: Set<String>
    let storageKey: String

    var body: some View {
        let isCollapsed = collapsed.contains(id)
        Button {
            withAnimation(.smooth(duration: 0.4)) {
                if isCollapsed {
                    collapsed.remove(id)
                } else {
                    collapsed.insert(id)
                }
            }
            UserDefaults.standard.set(Array(collapsed), forKey: storageKey)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Spacer(minLength: 0)
                if isCollapsed {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.blurReplace)
                }
            }
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isCollapsed)
        .accessibilityHint(isCollapsed ? "Shows the \(title.lowercased())" : "Hides the \(title.lowercased())")
    }
}

extension CardGridLayout {
    /// The row each section's first card lands on, counting the cards and headings above it, for the wave.
    static func firstRows(of sections: [(hasTitle: Bool, sizes: [CardSize])]) -> [Int] {
        var rows: [Int] = []
        var next = 0
        for section in sections {
            if section.hasTitle {
                next += 1
            }
            rows.append(next)
            next = (slots(for: section.sizes, firstRow: next).last?.row ?? next - 1) + 1
        }
        return rows
    }
}

/// A thing's picture (a parcel's, an owned thing's), or its icon when there isn't one, in a rounded square.
struct ItemPhoto: View {
    let data: Data?
    let symbol: String
    let tint: Color
    var side: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: side > 40 ? "photo.badge.plus" : symbol)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(0.18))
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
    }
}

/// A title with a thing's picture in place of its icon; the plain card title when there's no picture.
struct PhotoCardTitle: View {
    let title: String
    let symbol: String
    let photo: Data?
    let tint: Color

    var body: some View {
        if photo != nil {
            HStack(spacing: 7) {
                ItemPhoto(data: photo, symbol: symbol, tint: tint, side: 22)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
        } else {
            CardTitle(title: title, symbol: symbol, tint: tint)
        }
    }
}
