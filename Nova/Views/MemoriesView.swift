import SwiftUI

struct MemoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var memories:      [Memory] = []
    @State private var pending:       [Memory] = []
    @State private var pairs:         [MemoryPair] = []
    @State private var total:         Int = 0
    @State private var isLoading:     Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage:  String? = nil
    @State private var actionError:   String? = nil
    @State private var isAdding:      Bool = false
    // The pending memory whose editor is open
    @State private var editingPending: Memory? = nil
    // The two memories whose merge editor is open
    @State private var merging: MergeRequest? = nil

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
        .sheet(isPresented: $isAdding) {
            MemoryEditor(title: "NEW MEMORY") { text in
                try await APIService.addMemory(content: text)
                await load(showSpinner: false)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingPending) { memory in
            MemoryEditor(title: "EDIT MEMORY", initial: memory.content,
                         note: "Saving your wording also approves it.") { text in
                _ = try await APIService.editMemory(id: memory.id, content: text)
                await load(showSpinner: false)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $merging) { request in
            MemoryEditor(title: request.title, initial: request.initial,
                         combine: { try await APIService.draftMerge(aID: request.keepID, bID: request.dropID) }) { text in
                _ = try await APIService.mergeMemories(keepID: request.keepID, dropID: request.dropID, content: text)
                await load(showSpinner: false)
            }
            .presentationDetents([.medium, .large])
        }
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
            Button {
                isAdding = true
            } label: {
                Image(systemName: "plus")
                    .novaFont(14, weight: .semibold)
                    .foregroundColor(Theme.accent)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Add memory")
            .disabled(isLoading)

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
                        Group {
                            if let stored = memory.similarTo {
                                PendingSimilarRow(
                                    memory: memory,
                                    stored: stored,
                                    onReplace: {
                                        merging = MergeRequest(keepID: stored.id, dropID: memory.id,
                                                               title: "REPLACE MEMORY", initial: memory.content)
                                    },
                                    onKeepBoth: { keepBoth(memory, stored: stored) },
                                    onDiscard: { reject(memory) }
                                )
                            } else {
                                PendingRow(
                                    memory: memory,
                                    onApprove: { approve(memory) },
                                    onReject: { reject(memory) }
                                )
                            }
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.accent.opacity(0.1))
                        // Nova's guess is often almost right; fixing the wording is quicker than
                        // rejecting it and adding a new one
                        .swipeActions(edge: .leading) {
                            Button {
                                editingPending = memory
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.accent)
                        }
                    }
                } header: {
                    sectionHeader("AWAITING APPROVAL", count: pending.count)
                }
            }

            if !pairs.isEmpty {
                Section {
                    ForEach(pairs) { pair in
                        DuplicatePairCard(
                            pair: pair,
                            onMerge: {
                                // Opens empty so the editor drafts straight away
                                merging = MergeRequest(keepID: pair.a.id, dropID: pair.b.id,
                                                       title: "MERGE MEMORIES", initial: "")
                            },
                            onKeepBoth: { keepBoth(pair) },
                            onKeepOne: { kept in keepOne(kept, of: pair) }
                        )
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.accent.opacity(0.1))
                    }
                } header: {
                    sectionHeader("POSSIBLE DUPLICATES", count: pairs.count)
                }
            }

            Section {
                ForEach(memories) { memory in
                    NavigationLink {
                        MemoryDetailView(memory: memory) { await load(showSpinner: false) }
                    } label: {
                        MemoryRow(memory: memory)
                    }
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
            // Only suggestions, so a failure here hides the section instead of the whole bank
            async let similar = try? APIService.fetchSimilarMemories()
            let (firstPage, pendingRows) = try await (page, queued)
            memories = firstPage.memories
            total    = firstPage.total
            pending  = pendingRows
            pairs    = await similar ?? []
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

    // Dismiss before approving, so the fact he just judged never shows up as a possible
    // duplicate of the one it was judged against
    private func keepBoth(_ memory: Memory, stored: MemoryRef) {
        actionError = nil
        pending.removeAll { $0.id == memory.id }
        Task {
            do {
                try await APIService.dismissSimilar(aID: stored.id, bID: memory.id)
                try await APIService.approveMemory(id: memory.id)
            } catch {
                actionError = "Could not keep both: \(error.localizedDescription)"
            }
            await load(showSpinner: false)
        }
    }

    private func keepBoth(_ pair: MemoryPair) {
        actionError = nil
        pairs.removeAll { $0.id == pair.id }
        Task {
            do {
                try await APIService.dismissSimilar(aID: pair.a.id, bID: pair.b.id)
            } catch {
                actionError = "Could not keep both: \(error.localizedDescription)"
            }
            await load(showSpinner: false)
        }
    }

    private func keepOne(_ kept: MemoryRef, of pair: MemoryPair) {
        actionError = nil
        let other = kept.id == pair.a.id ? pair.b : pair.a
        pairs.removeAll { $0.id == pair.id }
        Task {
            do {
                try await APIService.deleteMemory(id: other.id)
            } catch {
                actionError = "Could not delete: \(error.localizedDescription)"
            }
            // Reload either way: one memory can sit in several pairs, and those went with it
            await load(showSpinner: false)
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

// A pending memory close to one already stored. Approving it blindly would store the same
// fact twice, so the stored one is shown and the choice is about the pair.
private struct PendingSimilarRow: View {
    let memory: Memory
    let stored: MemoryRef
    let onReplace: () -> Void
    let onKeepBoth: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(memory.content)
                .novaFont(14)
                .foregroundColor(Theme.textPrimary)

            MemoryDetails(memory: memory)

            MemoryQuote(label: "ALREADY STORED", content: stored.content)

            HStack(spacing: 8) {
                CardButton(title: "REPLACE IT", action: onReplace)
                CardButton(title: "KEEP BOTH", action: onKeepBoth)
                CardButton(title: "DISCARD", quiet: true, action: onDiscard)
            }
        }
        .padding(.vertical, 6)
    }
}

// Two stored memories that may say the same thing. Both texts are shown whole, since
// reading them is the entire decision.
private struct DuplicatePairCard: View {
    let pair: MemoryPair
    let onMerge: () -> Void
    let onKeepBoth: () -> Void
    let onKeepOne: (MemoryRef) -> Void

    // Keep one deletes the other, so it takes a second tap on the one to keep
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            side(pair.a, label: "OLDER")
            side(pair.b, label: "NEWER")

            if choosing {
                HStack {
                    Text("TAP THE ONE TO KEEP")
                        .novaFont(10, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.accent)
                        .tracking(2)
                    Spacer()
                    Button("CANCEL") { choosing = false }
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .buttonStyle(.borderless)
                }
            } else {
                // Keep both is the most common answer, so it sits beside Merge at the same size
                HStack(spacing: 8) {
                    CardButton(title: "MERGE", action: onMerge)
                    CardButton(title: "KEEP BOTH", action: onKeepBoth)
                    CardButton(title: "KEEP ONE", quiet: true) { choosing = true }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func side(_ memory: MemoryRef, label: String) -> some View {
        if choosing {
            Button {
                onKeepOne(memory)
            } label: {
                MemoryQuote(label: "KEEP \(label)", content: memory.content, highlighted: true)
            }
            .buttonStyle(.borderless)
        } else {
            MemoryQuote(label: label, content: memory.content)
        }
    }
}

// A memory quoted inside a card, with a small label over it and a rule down its left edge
private struct MemoryQuote: View {
    let label: String
    let content: String
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .novaFont(9, weight: .medium, design: .monospaced)
                .foregroundColor(highlighted ? Theme.accent : Theme.textSecondary)
                .tracking(2)
            Text(content)
                .novaFont(13)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.background.opacity(0.5))
        .overlay(alignment: .leading) {
            Rectangle()
                .frame(width: 2)
                .foregroundColor(Theme.accent.opacity(highlighted ? 1 : 0.4))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.accent.opacity(highlighted ? 0.6 : 0), lineWidth: 1)
        )
    }
}

// An outlined text button that shares a row evenly with its neighbours. Quiet is for the
// one that removes something: grey, never red.
private struct CardButton: View {
    let title: String
    var quiet = false
    let action: () -> Void

    var body: some View {
        // Borderless, or a tap anywhere on the row would fire every button in it
        Button(action: action) {
            Text(title)
                .novaFont(10, weight: .bold, design: .monospaced)
                .foregroundColor(quiet ? Theme.textSecondary : Theme.accent)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke((quiet ? Theme.textSecondary : Theme.accent).opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.borderless)
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

// Which two memories a merge editor joins. keep is superseded by the new text; drop is deleted.
private struct MergeRequest: Identifiable {
    let keepID: Int
    let dropID: Int
    let title: String
    // Empty means the editor starts from a draft of both
    let initial: String

    var id: String { "\(keepID)-\(dropID)" }
}

#Preview {
    MemoriesView()
}
