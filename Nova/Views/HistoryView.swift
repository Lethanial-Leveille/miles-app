import SwiftUI

struct HistoryView: View {
    @State private var messages:       [Message] = []
    @State private var isLoading:      Bool = true
    @State private var isLoadingMore:  Bool = false
    @State private var hasMorePages:   Bool = true
    @State private var currentPage:    Int = 1
    @State private var errorMessage:   String? = nil
    @State private var searchText:     String = ""

    private var displayed: [Message] {
        guard !searchText.isEmpty else { return messages }
        return messages.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

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
                } else if messages.isEmpty {
                    Spacer()
                    Text("NO HISTORY YET")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    historyList
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CONVERSATION LOG")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(4)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                TextField("Search messages...", text: $searchText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tint(Theme.accent)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: List

    private var historyList: some View {
        List {
            ForEach(displayed) { message in
                HistoryRow(message: message)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.accent.opacity(0.1))
                    .onAppear {
                        // Trigger next page when near the bottom
                        if message.id == displayed.suffix(5).first?.id {
                            Task { await loadMore() }
                        }
                    }
            }

            // Pagination footer
            if !searchText.isEmpty && displayed.count < messages.count {
                // Search result hint
                Section {
                    Text("\(displayed.count) of \(messages.count) loaded messages match")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                }
            }

            if hasMorePages && searchText.isEmpty {
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
        currentPage = 1
        hasMorePages = true
        do {
            messages = try await APIService.fetchHistory(page: 1)
            // If the first page returned fewer than 20, there are no more pages
            if messages.count < 20 { hasMorePages = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let batch = try await APIService.fetchHistory(page: nextPage)
            if batch.isEmpty {
                hasMorePages = false
            } else {
                messages.append(contentsOf: batch)
                currentPage = nextPage
                if batch.count < 20 { hasMorePages = false }
            }
        } catch {
            // Pagination errors do not replace the existing list
        }
        isLoadingMore = false
    }
}

// MARK: History row

private struct HistoryRow: View {
    let message: Message

    private var isUser: Bool { message.role == "user" }

    // Mic icon if sourceDevice indicates voice; phone icon otherwise
    private var sourceIcon: String {
        if let device = message.sourceDevice?.lowercased(),
           device.contains("voice") || device.contains("mic") {
            return "mic.fill"
        }
        return "iphone"
    }

    private var bodyText: String {
        guard !isUser else { return message.content }
        let stripped = message.content.replacingOccurrences(
            of: "\\[[^\\]]*\\]\\s*",
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(isUser ? "YOU" : "NOVA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isUser ? Theme.accent : Theme.accent.opacity(0.55))
                .tracking(2)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 2)

            Text(bodyText)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(4)

            Spacer()

            Image(systemName: sourceIcon)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    HistoryView()
}
