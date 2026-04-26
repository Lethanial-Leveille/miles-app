import SwiftUI

struct StatusView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var status:       SystemStatus? = nil
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
                .foregroundColor(Theme.textPrimary(colorScheme))
                .tracking(4)
            Spacer()
            Button(action: { Task { await loadStatus() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent(colorScheme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func statusGrid(_ status: SystemStatus) -> some View {
        ScrollView {
            VStack(spacing: 1) {
                StatusRow(label: "VERSION",      value: status.version,               colorScheme: colorScheme)
                StatusRow(label: "UPTIME",       value: formattedUptime(status.uptime), colorScheme: colorScheme)
                StatusRow(label: "MEMORIES",     value: "\(status.memoryCount)",      colorScheme: colorScheme)
                StatusRow(label: "LAST ACTIVE",  value: formattedDate(status.lastInteraction), colorScheme: colorScheme)
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

    private func formattedUptime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct StatusRow: View {
    let label: String
    let value: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary(colorScheme))
                .tracking(2)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.textPrimary(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface(colorScheme))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent(colorScheme).opacity(0.08)),
            alignment: .bottom
        )
    }
}

#Preview {
    StatusView()
}
