import SwiftUI

struct MemoriesView: View {
    @State private var memories:     [Memory] = []
    @State private var isLoading:    Bool = true
    @State private var errorMessage: String? = nil

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
        .task { await loadMemories() }
    }

    private var header: some View {
        HStack {
            Text("MEMORY BANK")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            Text("\(memories.count)")
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

    private var memoryList: some View {
        List {
            ForEach(memories) { memory in
                MemoryRow(memory: memory)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.accent.opacity(0.1))
            }
            .onDelete(perform: deleteMemories)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadMemories() async {
        isLoading = true
        errorMessage = nil
        do {
            memories = try await APIService.fetchMemories()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteMemories(at offsets: IndexSet) {
        let toDelete = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
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

            if let date = memory.createdAt {
                Text(date)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    MemoriesView()
}
