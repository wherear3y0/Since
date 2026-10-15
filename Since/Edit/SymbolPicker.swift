import SwiftUI

/// Grid of the hand-picked SF Symbols, shown as a sheet from the editor's icon button.
struct SymbolPicker: View {
    @Binding var selection: String
    let tint: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(symbolGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                                      spacing: 10) {
                                ForEach(group.symbols, id: \.self) { name in
                                    symbolButton(name)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.pageBackground)
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func symbolButton(_ name: String) -> some View {
        let isSelected = name == selection
        return Button {
            selection = name
            dismiss()
        } label: {
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSelected ? tint : .primary)
                .frame(width: 50, height: 50)
                .background(isSelected ? tint.opacity(0.22) : Color.cardBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var symbol = "flame.fill"
    SymbolPicker(selection: $symbol, tint: .orange)
}
