import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("autoSendOnStop") private var autoSend = false
    @State private var systemStatus: SystemStatus?
    @State private var statusIsLoading = true
    @State private var statusError: String?
    @State private var pendingMemoryCount = 0
    @State private var reminderCount: Int?
    @State private var testPushDetail = "Check that the Pi can reach this phone"
    @State private var testPushIsSending = false
    @State private var healthDetail = HealthService.statusLine()
    @State private var healthIsSyncing = false

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

                        sectionLabel("NOTIFICATIONS")
                        testPushRow

                        sectionLabel("HEALTH")
                        healthRow

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
                .foregroundColor(Theme.textSecondary.opacity(0.18))
        }
    }

    // MARK: Row pieces

    // Every row's icon sits in a thin ring, the shape the whole app is drawn in. Blue marks
    // something you can use; grey is information only
    private func ringIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .novaFont(13)
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(color.opacity(0.45), lineWidth: 1))
    }

    // Rows sit straight on black and are told apart by a hairline, not by boxes. It starts under
    // the text, past the icon, the way the system's own lists do
    private var rowDivider: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(Theme.textSecondary.opacity(0.14))
            .padding(.leading, 66)
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
            ringIcon("antenna.radiowaves.left.and.right", color: Theme.accent)

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
                        .foregroundColor(Theme.alert)
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
        .overlay(alignment: .bottom) { rowDivider }
    }

    // MARK: Nav row (chevron)

    private func navRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ringIcon(icon, color: Theme.accent)

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
        .overlay(alignment: .bottom) { rowDivider }
    }

    // MARK: Info row (no chevron, non-interactive)

    private func infoRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ringIcon(icon, color: Theme.textSecondary)

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
        .overlay(alignment: .bottom) { rowDivider }
    }

    // MARK: Auto-send toggle

    private var autoSendRow: some View {
        HStack(spacing: 14) {
            ringIcon("mic.fill", color: Theme.accent)

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
        .overlay(alignment: .bottom) { rowDivider }
    }

    // MARK: Test notification

    private var testPushRow: some View {
        Button {
            Task { await sendTestPush() }
        } label: {
            HStack(spacing: 14) {
                ringIcon("bell.badge", color: Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("SEND TEST NOTIFICATION")
                        .novaFont(12, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .tracking(1)
                    Text(testPushDetail)
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { rowDivider }
        }
        .disabled(testPushIsSending)
    }

    // MARK: Apple Health

    private var healthRow: some View {
        Button {
            Task { await syncHealth() }
        } label: {
            HStack(spacing: 14) {
                ringIcon("heart.text.square", color: Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("APPLE HEALTH")
                        .novaFont(12, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .tracking(1)
                    Text(healthDetail)
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { rowDivider }
        }
        .disabled(healthIsSyncing || !HealthService.isAvailable)
    }

    // MARK: Logout

    private var logoutRow: some View {
        Button {
            // Unregister first: it needs the login that logout is about to remove
            Task {
                await PushService.unregister()
                authManager.logout()
            }
        } label: {
            HStack(spacing: 14) {
                ringIcon("rectangle.portrait.and.arrow.right", color: Theme.textSecondary)

                Text("LOG OUT")
                    .novaFont(12, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(2)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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

    private func syncHealth() async {
        healthIsSyncing = true
        healthDetail = "SYNCING..."
        defer { healthIsSyncing = false }
        do {
            // The first tap asks for access; later taps just sync
            if HealthService.isEnabled {
                try await HealthService.sync()
            } else {
                try await HealthService.connect()
            }
            healthDetail = HealthService.statusLine()
        } catch {
            healthDetail = error.localizedDescription
        }
    }

    private func sendTestPush() async {
        testPushIsSending = true
        testPushDetail = "SENDING..."
        defer { testPushIsSending = false }

        if await PushService.permissionDenied() {
            testPushDetail = "Notifications are off for Nova. Turn them on in iOS Settings."
            return
        }
        do {
            let sent = try await PushService.sendTest()
            testPushDetail = "Sent to \(sent) \(sent == 1 ? "phone" : "phones"). It should arrive in a few seconds."
        } catch {
            testPushDetail = error.localizedDescription
        }
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
