import SwiftUI

// One memory and every wording it has had. An edit never rewrites a row on the Pi: it saves
// a new one and links the old, so the id this screen follows changes with each edit.
struct MemoryDetailView: View {
    let memory: Memory
    // Lets Memory Bank reload, since the edited memory now has a different id
    let onChange: () async -> Void

    @State private var currentID: Int
    @State private var versions: [MemoryVersion] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isEditing = false

    init(memory: Memory, onChange: @escaping () async -> Void) {
        self.memory = memory
        self.onChange = onChange
        _currentID = State(initialValue: memory.id)
    }

    // The chain comes newest first, so its head is what the memory says now
    private var currentText: String { versions.first?.content ?? memory.content }
    private var earlier: [MemoryVersion] { Array(versions.dropFirst()) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "MEMORY") {
                    Button("EDIT") { isEditing = true }
                        .novaFont(11, weight: .bold, design: .monospaced)
                        .foregroundColor(Theme.accent)
                        .disabled(isLoading)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(currentText)
                            .novaFont(16)
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(Theme.surface)
                            .overlay(alignment: .leading) {
                                Rectangle().frame(width: 2).foregroundColor(Theme.accent)
                            }

                        if let head = versions.first {
                            Text(stamp("SAVED", head.createdDate) ?? "")
                                .novaFont(9, design: .monospaced)
                                .foregroundColor(Theme.textSecondary)
                                .tracking(1)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .novaFont(11, design: .monospaced)
                                .foregroundColor(Theme.textPrimary)
                                .padding(20)
                        }

                        if isLoading {
                            ProgressView()
                                .tint(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                        } else if earlier.isEmpty {
                            Text("NEVER CHANGED")
                                .novaFont(10, design: .monospaced)
                                .foregroundColor(Theme.textSecondary)
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                        } else {
                            SectionLabel(title: "EARLIER WORDING")
                            ForEach(earlier) { version in
                                versionRow(version)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                .refreshable { await load() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(isPresented: $isEditing) {
            MemoryEditor(title: "EDIT MEMORY", initial: currentText,
                         note: "The current wording is kept below as history.") { text in
                let edit = try await APIService.editMemory(id: currentID, content: text)
                if edit.changed {
                    currentID = edit.id
                    await load()
                    await onChange()
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func versionRow(_ version: MemoryVersion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(version.content)
                .novaFont(14)
                .foregroundColor(Theme.textSecondary)
                .strikethrough(true, color: Theme.textSecondary.opacity(0.5))
                .textSelection(.enabled)

            Text([stamp("SAVED", version.createdDate), stamp("REPLACED", version.supersededDate)]
                    .compactMap { $0 }
                    .joined(separator: "  ·  "))
                .novaFont(9, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 1).foregroundColor(Theme.accent.opacity(0.08))
        }
    }

    private func stamp(_ label: String, _ date: Date?) -> String? {
        guard let date else { return nil }
        return "\(label) \(date.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())"
    }

    private func load() async {
        do {
            versions = try await APIService.fetchMemoryHistory(id: currentID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
