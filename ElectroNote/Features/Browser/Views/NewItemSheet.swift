import SwiftUI

struct NewItemSheet: View {
    let title: String
    let placeholder: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $name)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .onSubmit { submit() }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen", action: submit)
                        .disabled(name.trimmed.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
        .onAppear { isFocused = true }
    }

    private func submit() {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        onConfirm(n)
        dismiss()
    }
}
