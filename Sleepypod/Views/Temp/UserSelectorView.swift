import SwiftUI

struct UserSelectorView: View {
    @State private var presented = false
    var body: some View {
        Button("Settings", systemImage: "gearshape") { presented = true }
            .sheet(isPresented: $presented) { SettingsSheet() }
    }
}

// MARK: - Side Name Text Field

/// A text field that manages its own state from an initial value and saves on submit/blur.
struct SideNameTextField: View {
    let placeholder: String
    let initialValue: String
    let onCommit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.subheadline)
            .foregroundColor(Theme.text1)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { text = initialValue }
            .onChange(of: initialValue) { _, newVal in text = newVal }
            .onSubmit { commitIfChanged() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commitIfChanged() }
            }
    }

    private func commitIfChanged() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != initialValue {
            onCommit(trimmed)
        }
    }
}
