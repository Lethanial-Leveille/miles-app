import SwiftUI

// A tapped MILES error push in full: the whole message (the lock screen cuts it short) and, when it
// was about a request, what became of that request.
struct ErrorDetailView: View {
    let note: PushNote
    @State private var approval: Approval?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title: "PROBLEM")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(note.title.uppercased())
                            .novaFont(11, weight: .medium, design: .monospaced)
                            .foregroundColor(Theme.alert)
                        Text(note.detail)
                            .novaFont(14)
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let id = note.approvalID { request(id) }
                    }
                    .padding(16)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard let id = note.approvalID else { return }
            do { approval = try await APIService.fetchApproval(id: id) }
            catch { loadError = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func request(_ id: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = approval {
                Text("REQUEST #\(a.id) · \(a.status.uppercased())")
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                if let chat = a.chatName {
                    Text("To \(chat)").novaFont(12).foregroundColor(Theme.textSecondary)
                }
                ForEach(Array(a.messages.enumerated()), id: \.offset) { _, part in
                    Text(part)
                        .novaFont(13)
                        .foregroundColor(Theme.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if let result = a.result {
                    Text(result)
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            } else if let loadError {
                Text("Request #\(id) could not be loaded: \(loadError)")
                    .novaFont(11, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ProgressView().tint(Theme.accent)
            }
            Button { ApprovalRouter.shared.open(approvalID: id) } label: {
                Text("Open in Approvals").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .foregroundColor(Theme.textPrimary)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
