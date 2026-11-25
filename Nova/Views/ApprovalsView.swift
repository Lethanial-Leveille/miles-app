import Combine
import SwiftUI

// Where a tapped MILES push lands: the approvals sheet on that request, or the error screen. Also
// tells an open screen to reload after a decision made from the lock screen.
@MainActor
final class ApprovalRouter: ObservableObject {
    static let shared = ApprovalRouter()
    @Published var isOpen = false
    @Published var revision = 0
    // The request the push was about; the sheet scrolls to it and marks it.
    @Published var selectedID: Int?
    @Published var errorNote: PushNote?

    func open(approvalID: Int? = nil) {
        errorNote = nil
        selectedID = approvalID
        revision += 1
        isOpen = true
    }

    func showError(_ note: PushNote) {
        isOpen = false
        errorNote = note
    }

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
    // The tapped request when it is no longer waiting (done, failed, skipped, expired).
    @State private var settled: Approval?

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
                } else if approvals.isEmpty && settled == nil {
                    Spacer()
                    Text("NOTHING WAITING")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14) {
                                if let settled { settledCard(settled) }
                                ForEach(approvals) { card($0).id($0.id) }
                            }
                            .padding(16)
                        }
                        .refreshable { await load() }
                        .onAppear { scrollToSelected(proxy) }
                        .onChange(of: approvals.map(\.id)) { _, _ in scrollToSelected(proxy) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: router.revision) { await load() }
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let id = router.selectedID, approvals.contains(where: { $0.id == id }) else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    // Each message as it will arrive, in order: the words, then the Zoom link on its own.
    private func messages(_ a: Approval) -> some View {
        let parts = a.messages
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if parts.count > 1 {
                    Text("MESSAGE \(i + 1) OF \(parts.count)")
                        .novaFont(9, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                }
                Text(part)
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func settledCard(_ a: Approval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REQUEST #\(a.id) · \(a.status.uppercased())")
                .novaFont(10, weight: .medium, design: .monospaced)
                .foregroundColor(a.status == "failed" ? Theme.alert : Theme.textSecondary)
            if a.isText, let chat = a.chatName {
                Text("TEXT TO \(chat.uppercased())")
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                messages(a)
            } else {
                Text(a.summary).novaFont(14).foregroundColor(Theme.textPrimary)
            }
            if let result = a.result {
                Text(result)
                    .novaFont(12, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            Text("Nothing to decide: this request is \(a.status).")
                .novaFont(10, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func card(_ a: Approval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if a.isText, let chat = a.chatName {
                Text("TEXT TO \(chat.uppercased())")
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                messages(a)
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
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.accent, lineWidth: router.selectedID == a.id ? 1.5 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        do {
            approvals = try await APIService.fetchApprovals()
            if let id = router.selectedID, !approvals.contains(where: { $0.id == id }) {
                settled = try? await APIService.fetchApproval(id: id)
            } else {
                settled = nil
            }
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
