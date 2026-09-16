import SwiftUI

struct MemoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var memories:      [Memory] = []
    @State private var pending:       [Memory] = []
    @State private var total:         Int = 0
    @State private var isLoading:     Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage:  String? = nil
    @State private var actionError:   String? = nil

    private let pageSize = 50

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.accent.opacity(0.15))

                if let actionError {
                    Text(actionError)
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    Text(error)
                        .novaFont(13, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else if memories.isEmpty && pending.isEmpty {
                    Spacer()
                    Text("NO MEMORIES STORED")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    memoryList
                }
            }
        }
        .task { await load(showSpinner: true) }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .novaFont(14, weight: .medium)
                    .foregroundColor(Theme.accent)
            }
            .padding(.trailing, 8)

            Text("MEMORY BANK")
                .novaFont(13, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            Text("\(total)")
                .novaFont(11, design: .monospaced)
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var memoryList: some View {
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { memory in
                        PendingRow(
                            memory: memory,
                            onApprove: { approve(memory) },
                            onReject: { reject(memory) }
                        )
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.accent.opacity(0.1))
                    }
                } header: {
                    sectionHeader("AWAITING APPROVAL", count: pending.count)
                }
            }

            Section {
                ForEach(memories) { memory in
                    MemoryRow(memory: memory)
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.accent.opacity(0.1))
                        .onAppear {
                            if memory.id == memories.last?.id {
                                Task { await loadMore() }
                            }
                        }
                }
                .onDelete(perform: deleteMemories)

                if isLoadingMore {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("ACTIVE", count: total)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(showSpinner: false) }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .novaFont(9, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(3)
            Spacer()
            Text("\(count)")
                .novaFont(9, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Data loading

    private func load(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        do {
            async let page   = APIService.fetchMemories(limit: pageSize, offset: 0)
            async let queued = APIService.fetchPendingMemories()
            let (firstPage, pendingRows) = try await (page, queued)
            memories = firstPage.memories
            total    = firstPage.total
            pending  = pendingRows
        } catch {
            // A background reload (pull to refresh, or after an action) keeps the list on
            // screen and reports above it rather than replacing everything with an error
            if showSpinner {
                errorMessage = error.localizedDescription
            } else {
                actionError = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore && memories.count < total else { return }
        isLoadingMore = true
        do {
            let page = try await APIService.fetchMemories(limit: pageSize, offset: memories.count)
            // An approval between pages shifts every later offset by one, so skip ids already shown
            let shown = Set(memories.map(\.id))
            memories.append(contentsOf: page.memories.filter { !shown.contains($0.id) })
            // An empty page means the count moved under us; trust what is loaded so paging stops
            total = page.memories.isEmpty ? memories.count : page.total
        } catch {
            actionError = error.localizedDescription
        }
        isLoadingMore = false
    }

    // MARK: Actions

    private func approve(_ memory: Memory) {
        actionError = nil
        pending.removeAll { $0.id == memory.id }
        Task {
            do {
                try await APIService.approveMemory(id: memory.id)
            } catch {
                actionError = "Could not approve: \(error.localizedDescription)"
            }
            // Reload either way: success moves the row into the active list, failure puts it back
            await load(showSpinner: false)
        }
    }

    private func reject(_ memory: Memory) {
        actionError = nil
        pending.removeAll { $0.id == memory.id }
        Task {
            do {
                try await APIService.deleteMemory(id: memory.id)
            } catch {
                actionError = "Could not reject: \(error.localizedDescription)"
                await load(showSpinner: false)
            }
        }
    }

    private func deleteMemories(at offsets: IndexSet) {
        actionError = nil
        let toDelete = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
        total -= toDelete.count
        Task {
            for memory in toDelete {
                do {
                    try await APIService.deleteMemory(id: memory.id)
                } catch {
                    // The list already dropped the row, so reload rather than show something false
                    actionError = "Could not delete: \(error.localizedDescription)"
                    await load(showSpinner: false)
                    return
                }
            }
        }
    }
}

// MARK: Rows

private struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.content)
                .novaFont(14)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3)

            MemoryDetails(memory: memory)
        }
        .padding(.vertical, 6)
    }
}

private struct PendingRow: View {
    let memory: Memory
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(memory.content)
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)

                MemoryDetails(memory: memory)
            }

            Spacer(minLength: 4)

            // Borderless, or a tap anywhere on the row would fire both buttons
            Button(action: onReject) {
                Image(systemName: "xmark")
                    .novaFont(13, weight: .semibold)
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.textSecondary.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reject memory")

            Button(action: onApprove) {
                Image(systemName: "checkmark")
                    .novaFont(13, weight: .bold)
                    .foregroundColor(Theme.background)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: Theme.accentGlow, radius: 6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Approve memory")
        }
        .padding(.vertical, 6)
    }
}

// Category, source and confidence on one quiet line, skipping whichever are missing
private struct MemoryDetails: View {
    let memory: Memory

    private var parts: [String] {
        [memory.category, memory.source, memory.confidence.map { "\($0) confidence" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  ").uppercased())
                .novaFont(9, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(1)
        }
    }
}

#Preview {
    MemoriesView()
}
