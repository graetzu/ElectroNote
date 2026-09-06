import SwiftUI
import UIKit

struct CircuitSymbolPickerView: View {
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCategory: CircuitCategory = .passives
    @State private var searchText: String = ""
    @State private var selectedColorKey: CircuitColorChoice = .adaptive
    @State private var isBoldStroke: Bool = false

    enum CircuitColorChoice: String, CaseIterable, Identifiable {
        case adaptive = "Standard"
        case black    = "Schwarz"
        case blue     = "Blau"
        case red      = "Rot"
        case green    = "Grün"
        case orange   = "Orange"

        var id: String { rawValue }

        func uiColor(for scheme: ColorScheme) -> UIColor {
            switch self {
            case .adaptive:
                return scheme == .dark ? .white : .black
            case .black:
                return .black
            case .blue:
                return UIColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 1.0)
            case .red:
                return UIColor(red: 0.92, green: 0.22, blue: 0.22, alpha: 1.0)
            case .green:
                return UIColor(red: 0.16, green: 0.68, blue: 0.32, alpha: 1.0)
            case .orange:
                return UIColor(red: 0.95, green: 0.52, blue: 0.12, alpha: 1.0)
            }
        }

        var previewColor: Color {
            switch self {
            case .adaptive: return .primary
            case .black:    return .black
            case .blue:     return .blue
            case .red:      return .red
            case .green:    return .green
            case .orange:   return .orange
            }
        }
    }

    private var filteredSymbols: [CircuitSymbolType] {
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return CircuitSymbolType.allCases.filter { sym in
                sym.displayName.lowercased().contains(q) ||
                sym.normKuerzel.lowercased().contains(q) ||
                sym.keywords.contains { $0.contains(q) }
            }
        }
        return CircuitSymbolType.allCases.filter { $0.category == selectedCategory }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Customization Controls (Category Tabs & Options)
                VStack(spacing: 10) {
                    // Category Picker Tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CircuitCategory.allCases) { cat in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedCategory = cat
                                        searchText = ""
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.iconName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(cat.rawValue)
                                            .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedCategory == cat ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Options Bar: Color choice & Stroke thickness
                    HStack(spacing: 16) {
                        // Color picker chips
                        HStack(spacing: 8) {
                            Text("Farbe:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            ForEach(CircuitColorChoice.allCases) { choice in
                                Button {
                                    selectedColorKey = choice
                                } label: {
                                    Circle()
                                        .fill(choice.previewColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                        )
                                        .overlay(
                                            selectedColorKey == choice ?
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .black))
                                                    .foregroundColor(choice == .adaptive && colorScheme == .dark ? .black : .white)
                                                : nil
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        // Stroke width toggle
                        Toggle(isOn: $isBoldStroke) {
                            Text("Kräftige Linien")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(.button)
                        .tint(.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                .padding(.top, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                Divider()

                // Symbols & Circuits Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredSymbols) { symbol in
                            CircuitSymbolCard(
                                symbol: symbol,
                                strokeColor: selectedColorKey.uiColor(for: colorScheme),
                                lineWidth: isBoldStroke ? 4.2 : 2.6
                            ) {
                                let strokeCol = selectedColorKey.uiColor(for: colorScheme)
                                let lw: CGFloat = isBoldStroke ? 4.2 : 2.6
                                let img = CircuitSymbolRenderer.shared.render(
                                    symbol: symbol,
                                    strokeColor: strokeCol,
                                    lineWidth: lw,
                                    targetSize: symbol.category == .circuits ? CGSize(width: 320, height: 220) : CGSize(width: 220, height: 140)
                                )
                                onInsert(img)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dismiss()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Schaltsymbole & Stromkreise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Bauteil oder Schaltung suchen (z. B. Widerstand, Op-Amp, Diode)...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Symbol Card View

private struct CircuitSymbolCard: View {
    let symbol: CircuitSymbolType
    let strokeColor: UIColor
    let lineWidth: CGFloat
    let onSelect: () -> Void

    @State private var previewImage: UIImage? = nil

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .tertiarySystemBackground))

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(symbol.category == .circuits ? 6 : 10)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .frame(height: symbol.category == .circuits ? 115 : 85)

                VStack(spacing: 2) {
                    Text(symbol.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 4) {
                        Text(symbol.normKuerzel)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())

                        Text("DIN / IEC")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            generatePreview()
        }
        .onChange(of: strokeColor) { _, _ in
            generatePreview()
        }
        .onChange(of: lineWidth) { _, _ in
            generatePreview()
        }
    }

    private func generatePreview() {
        let size = symbol.category == .circuits ? CGSize(width: 280, height: 190) : CGSize(width: 180, height: 110)
        self.previewImage = CircuitSymbolRenderer.shared.render(
            symbol: symbol,
            strokeColor: strokeColor,
            lineWidth: lineWidth,
            targetSize: size
        )
    }
}
