import SwiftUI

struct TextInsertionSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (String, CGFloat) -> Void

    @State private var text      = ""
    @State private var fontSize: CGFloat = 22
    @FocusState private var focused: Bool

    private let sizes: [(String, CGFloat)] = [
        ("Klein",     16),
        ("Normal",    22),
        ("Groß",      28),
        ("Sehr groß", 36),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(size: fontSize))
                        .focused($focused)
                }
                Section("Schriftgröße") {
                    Picker("Größe", selection: $fontSize) {
                        ForEach(sizes, id: \.1) { label, size in
                            Text("\(label)  (\(Int(size)) pt)").tag(size)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Text eingeben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onConfirm(trimmed, fontSize)
                        isPresented = false
                    }
                    .bold()
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
