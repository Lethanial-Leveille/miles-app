import SwiftUI

struct HistoryView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var messages:     [Message] = []
    @State private var isLoading:    Bool = true
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Theme.background(colorScheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider().background(Theme.accent(colorScheme).opacity(0.2))

                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.accent(colorScheme))
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    Text(error)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else if messages.isEmpty {
                    Spacer()
                    Text("NO HISTORY YET")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary(colorScheme))
                        .tracking(3)
                    Spacer()
                } else {
                    historyList
                }
            }
        }
        .task { await loadHistory() }
    }

    private var header: some View {
        HStack {
            Text("CONVERSATION LOG")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary(colorScheme))
                .tracking(4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var historyList: some View {
        List(messages) { message in
            HistoryRow(message: message, colorScheme: colorScheme)
                .listRowBackground(Theme.surface(colorScheme))
                .listRowSeparatorTint(Theme.accent(colorScheme).opacity(0.1))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            messages = try await APIService.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct HistoryRow: View {
    let message: Message
    let colorScheme: ColorScheme

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(isUser ? "YOU" : "NOVA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isUser ? Theme.accent(colorScheme) : Theme.gold(colorScheme))
                .tracking(2)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 2)

            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary(colorScheme))
                .lineLimit(4)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    HistoryView()
}
