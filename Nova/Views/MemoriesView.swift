import SwiftUI

struct MemoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var memories:      [Memory] = []
    @State private var total:         Int = 0
    @State private var isLoading:     Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var hasMorePages:  Bool = true
    @State private var errorMessage:  String? = nil

    private let pageSize = 20

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.accent.opacity(0.15))

                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    Text(error)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else if memories.isEmpty {
                    Spacer()
                    Text("NO MEMORIES STORED")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    memoryList
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: Header

    // Shows loaded against server total while a page is still outstanding,
    // so 20/137 reads as "there is more" without needing a second label.
    private var countLabel: String {
        memories.count < total ? "\(memories.count)/\(total)" : "\(total)"
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .padding(.trailing, 8)

            Text("MEMORY BANK")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            Text(countLabel)
                .font(.system(size: 11, design: .monospaced))
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

    // MARK: List

    private var memoryList: some View {
        List {
            ForEach(memories) { memory in
                MemoryRow(memory: memory)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.accent.opacity(0.1))
                    .onAppear {
                        // Trigger next page when near the bottom
                        if memory.id == memories.suffix(5).first?.id {
                            Task { await loadMore() }
                        }
                    }
            }
            .onDelete(perform: deleteMemories)

            if hasMorePages {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView().tint(Theme.accent).scaleEffect(0.8)
                    } else {
                        Button("LOAD MORE") {
                            Task { await loadMore() }
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.accent)
                        .tracking(2)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: Data loading

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        hasMorePages = true
        do {
            let response = try await APIService.fetchMemories(limit: pageSize, offset: 0)
            memories = response.memories
            total    = response.total
            // The envelope reports the real total, so there is no need to
            // infer "more pages" from whether this page came back full.
            hasMorePages = memories.count < total
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        do {
            let response = try await APIService.fetchMemories(limit: pageSize,
                                                             offset: memories.count)
            // Re-read total: it moves if the Pi saved or dropped a memory
            // between pages.
            total = response.total
            if response.memories.isEmpty {
                hasMorePages = false
            } else {
                memories.append(contentsOf: response.memories)
                hasMorePages = memories.count < total
            }
        } catch {
            // Pagination errors do not replace the existing list
        }
        isLoadingMore = false
    }

    private func deleteMemories(at offsets: IndexSet) {
        let toDelete = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
        // Keep the header honest, and keep the paging offset aligned with
        // what the server will report on the next request.
        total = max(0, total - toDelete.count)
        Task {
            for memory in toDelete {
                try? await APIService.deleteMemory(id: memory.id)
            }
        }
    }
}

private struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.content)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3)

            // category is the one nullable column, so it may be absent
            if let category = memory.category {
                Text(category.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(2)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    MemoriesView()
}
