import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("autoSendOnStop") private var autoSend = false
    @State private var systemStatus: SystemStatus?
    @State private var statusIsLoading = true
    @State private var statusError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        pageHeader

                        sectionLabel("SYSTEM")
                        systemStatusRow

                        sectionLabel("MEMORY BANK")
                        NavigationLink {
                            MemoriesView()
                                .toolbar(.hidden, for: .navigationBar)
                        } label: {
                            navRow(icon: "brain", label: "MEMORIES", detail: "View and manage stored knowledge")
                        }

                        sectionLabel("VOICE")
                        autoSendRow

                        sectionLabel("ACCOUNT")
                        logoutRow

                        sectionLabel("ABOUT")
                        infoRow(icon: "app.badge", label: "NOVA", detail: "v0.8  M.I.L.E.S. Interface")
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
        .task { await loadStatus() }
    }

    // MARK: Page header

    private var pageHeader: some View {
        HStack {
            Text("SETTINGS")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.15))
        }
    }

    // MARK: Section label

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .tracking(3)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 6)
    }

    // MARK: System status

    private var systemStatusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 16))
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("SYSTEM STATUS")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)

                if statusIsLoading {
                    Text("CONNECTING...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                } else if let err = statusError {
                    Text(err)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                } else if let s = systemStatus {
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundColor(Theme.accent)
                            .shadow(color: Theme.accentGlow, radius: 4)
                        Text("\(s.status.uppercased())  v\(s.version)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.accent)
                    }
                }
            }

            Spacer()

            Button {
                Task { await loadStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.08))
        }
    }

    // MARK: Nav row (chevron)

    private func navRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.08))
        }
    }

    // MARK: Info row (no chevron, non-interactive)

    private func infoRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.08))
        }
    }

    // MARK: Auto-send toggle

    private var autoSendRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("AUTO-SEND ON STOP")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text("Send transcript automatically when recording stops")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $autoSend)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.08))
        }
    }

    // MARK: Logout

    private var logoutRow: some View {
        Button {
            authManager.logout()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.accent)
                    .frame(width: 24)

                Text("LOG OUT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .tracking(2)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Theme.surface)
        }
    }

    // MARK: Data loading

    private func loadStatus() async {
        statusIsLoading = true
        statusError = nil
        do {
            systemStatus = try await APIService.fetchStatus()
        } catch {
            statusError = error.localizedDescription
        }
        statusIsLoading = false
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
