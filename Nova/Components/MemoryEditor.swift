import SwiftUI

// The sheet for writing a memory, new or edited. save throws so the server's reason, like
// "That memory is already stored", lands under the text instead of closing the sheet.
struct MemoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    // Said under the field when saving does more than save, like approving a pending memory
    var note: String? = nil
    let save: (String) async throws -> Void

    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    private let original: String

    init(title: String, initial: String = "", note: String? = nil, save: @escaping (String) async throws -> Void) {
        self.title = title
        self.note = note
        self.save = save
        self.original = initial
        _text = State(initialValue: initial)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !isSaving && !trimmed.isEmpty && trimmed != original }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("CANCEL") { dismiss() }
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(title)
                        .novaFont(12, weight: .bold, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .tracking(3)
                    Spacer()
                    Button {
                        Task { await commit() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Text("SAVE")
                                .novaFont(11, weight: .bold, design: .monospaced)
                                .foregroundColor(canSave ? Theme.accent : Theme.textSecondary)
                        }
                    }
                    .disabled(!canSave)
                }
                .padding(.top, 20)

                TextEditor(text: $text)
                    .novaFont(15)
                    .foregroundColor(Theme.textPrimary)
                    .tint(Theme.accent)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 140, maxHeight: 260)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.accent.opacity(focused ? 0.6 : 0.3), lineWidth: 1)
                    )
                    .focused($focused)

                Text("Stored exactly as written. Nova treats it as something you told her.")
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)

                if let note {
                    Text(note)
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.accent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .onAppear { focused = true }
        .interactiveDismissDisabled(isSaving)
    }

    private func commit() async {
        isSaving = true
        errorMessage = nil
        do {
            try await save(trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
