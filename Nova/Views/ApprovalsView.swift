import Combine
import SwiftUI

// Opens the approvals screen when an approval push is tapped, and tells an open screen to reload
// after a decision made from the lock screen.
@MainActor
final class ApprovalRouter: ObservableObject {
    static let shared = ApprovalRouter()
    @Published var isOpen = false
    @Published var revision = 0

    func open() { isOpen = true }
    nonisolated func refresh() { Task { @MainActor in self.revision += 1 } }
}

// Everything the Mac is waiting on, each with the exact words and the chat they go to. One tap
// approves one request; there is no approve all, on purpose.
struct ApprovalsView: View {
    @ObservedObject private var router = ApprovalRouter.shared
    @State private var approvals: [Approval] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var busy: Set<Int> = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title: "APPROVALS")
                if let message {
                    Text(message)
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
                } else if approvals.isEmpty {
                    Spacer()
                    Text("NOTHING WAITING")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(approvals) { card($0) }
                        }
                        .padding(16)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: router.revision) { await load() }
    }

    private func card(_ a: Approval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if a.isText, let chat = a.chatName {
                Text("TEXT TO \(chat.uppercased())")
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                Text(a.text ?? "")
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text("EVALLO")
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                Text(a.summary)
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)
            }
            if let expires = a.expiresDate {
                Text("Expires \(expires.formatted(date: .omitted, time: .shortened))")
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                Button { decide(a, approve: false) } label: {
                    Text("Skip").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundColor(Theme.textPrimary)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button { decide(a, approve: true) } label: {
                    Text("Approve").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundColor(.black)
                .background(Theme.done)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(busy.contains(a.id))
        }
        .padding(14)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        do {
            approvals = try await APIService.fetchApprovals()
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func decide(_ a: Approval, approve: Bool) {
        busy.insert(a.id)
        Task {
            do {
                try await APIService.decideApproval(id: a.id, approve: approve)
                message = approve ? "Approved. The Mac will do it now." : "Skipped."
                approvals.removeAll { $0.id == a.id }
            } catch {
                message = error.localizedDescription
                await load()
            }
            busy.remove(a.id)
        }
    }
}
