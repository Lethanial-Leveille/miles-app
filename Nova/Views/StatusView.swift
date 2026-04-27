import SwiftUI

struct StatusView: View {
    @State private var status:       SystemStatus? = nil
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
                } else if let status {
                    statusGrid(status)
                }
            }
        }
        .task { await loadStatus() }
    }

    private var header: some View {
        HStack {
            Text("SYSTEM STATUS")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            Button(action: { Task { await loadStatus() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func statusGrid(_ status: SystemStatus) -> some View {
        ScrollView {
            VStack(spacing: 1) {
                StatusRow(label: "STATUS",  value: status.status.uppercased())
                StatusRow(label: "VERSION", value: status.version)
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)
        }
    }

    private func loadStatus() async {
        isLoading = true
        errorMessage = nil
        do {
            status = try await APIService.fetchStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .tracking(2)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.08))
        }
    }
}

#Preview {
    StatusView()
}
