import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("autoSendOnStop") private var autoSend = false
    @State private var systemStatus: SystemStatus?
    @State private var statusIsLoading = true
    @State private var statusError: String?
    @State private var pendingMemoryCount = 0
    @State private var reminderCount: Int?

    // Read from the bundle so the About row cannot drift from MARKETING_VERSION again
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var memoriesDetail: String {
        switch pendingMemoryCount {
        case 0:  return "View and manage stored knowledge"
        case 1:  return "1 memory awaiting your approval"
        default: return "\(pendingMemoryCount) memories awaiting your approval"
        }
    }

    private var remindersDetail: String {
        switch reminderCount {
        case nil: return "Timers and reminders Nova is holding"
        case 0:   return "Nothing pending"
        case 1:   return "1 pending"
        case let count?: return "\(count) pending"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        pageHeader

                        sectionLabel("SYSTEM")
                        systemStatusRow
                        NavigationLink {
                            SystemView()
                        } label: {
                            navRow(icon: "cpu", label: "DIAGNOSTICS", detail: "Services, uptime, temperature, latency")
                        }

                        sectionLabel("MEMORY BANK")
                        NavigationLink {
                            MemoriesView()
                                .toolbar(.hidden, for: .navigationBar)
                        } label: {
                            navRow(icon: "brain", label: "MEMORIES", detail: memoriesDetail)
                        }

                        sectionLabel("PLANNING")
                        NavigationLink {
                            CalendarView()
                        } label: {
                            navRow(icon: "calendar", label: "YOUR WEEK", detail: "Every calendar, with edits on MILES")
                        }
                        NavigationLink {
                            RemindersView()
                        } label: {
                            navRow(icon: "timer", label: "REMINDERS AND TIMERS", detail: remindersDetail)
                        }

                        sectionLabel("VOICE")
                        autoSendRow

                        sectionLabel("ACCOUNT")
                        logoutRow

                        sectionLabel("ABOUT")
                        infoRow(icon: "app.badge", label: "NOVA", detail: "v\(appVersion)  M.I.L.E.S. Interface")
                    }
                    .padding(.bottom, 32)
                    // onAppear rather than task, so the count updates after returning from Memory Bank
                    .onAppear {
                        Task { await loadPendingMemoryCount() }
                        Task { await loadReminderCount() }
                    }
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
                .novaFont(13, weight: .bold, design: .monospaced)
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
                .novaFont(9, weight: .medium, design: .monospaced)
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
                .novaFont(16)
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("SYSTEM STATUS")
                    .novaFont(12, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)

                if statusIsLoading {
                    Text("CONNECTING...")
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                } else if let err = statusError {
                    Text(err)
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                } else if let s = systemStatus {
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundColor(Theme.accent)
                            .shadow(color: Theme.accentGlow, radius: 4)
                        Text(s.status.uppercased())
                            .novaFont(10, design: .monospaced)
                            .foregroundColor(Theme.accent)
                    }
                }
            }

            Spacer()

            Button {
                Task { await loadStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .novaFont(13)
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
                .novaFont(16)
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .novaFont(12, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text(detail)
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .novaFont(11, weight: .medium)
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
                .novaFont(16)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .novaFont(12, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text(detail)
                    .novaFont(10, design: .monospaced)
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
                .novaFont(16)
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("AUTO-SEND ON STOP")
                    .novaFont(12, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(1)
                Text("Send transcript automatically when recording stops")
                    .novaFont(10, design: .monospaced)
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
                    .novaFont(16)
                    .foregroundColor(Theme.accent)
                    .frame(width: 24)

                Text("LOG OUT")
                    .novaFont(12, weight: .bold, design: .monospaced)
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

    private func loadReminderCount() async {
        // Same as the memory count: a hint, silent if it fails
        if let reminders = try? await APIService.fetchReminders() {
            reminderCount = reminders.count
        }
    }

    private func loadPendingMemoryCount() async {
        // A hint on a row, not worth an error message if it fails
        if let pending = try? await APIService.fetchPendingMemories() {
            pendingMemoryCount = pending.count
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
