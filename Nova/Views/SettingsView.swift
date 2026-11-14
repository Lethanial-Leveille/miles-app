import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("autoSendOnStop") private var autoSend = false
    @State private var systemStatus: SystemStatus?
    @State private var statusIsLoading = true
    @State private var statusError: String?
    @State private var pendingMemoryCount = 0
    @State private var reminderCount: Int?
    @State private var taskCount: Int?
    @State private var listSummary: (lists: Int, left: Int)?

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

    private var tasksDetail: String {
        switch taskCount {
        case nil: return "Tasks left for today"
        case 0:   return "All done for today"
        case 1:   return "1 task left"
        case let count?: return "\(count) tasks left"
        }
    }

    private var listsDetail: String {
        switch listSummary {
        case nil: return "Grocery and every other list"
        case let (lists, left)?:
            let listWord = lists == 1 ? "list" : "lists"
            let itemWord = left == 1 ? "item" : "items"
            return "\(lists) \(listWord), \(left) \(itemWord) to get"
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
                        NavigationLink {
                            TasksView()
                        } label: {
                            navRow(icon: "checkmark.circle", label: "TODAY", detail: tasksDetail)
                        }
                        NavigationLink {
                            ListsView()
                        } label: {
                            navRow(icon: "checklist", label: "LISTS", detail: listsDetail)
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
                        Task { await loadPlanningCounts() }
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

    // MARK: Logout

    private var logoutRow: some View {
        Button {
            authManager.logout()
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

    private func loadReminderCount() async {
        // Same as the memory count: a hint, silent if it fails
        if let reminders = try? await APIService.fetchReminders() {
            reminderCount = reminders.count
        }
    }

    private func loadPlanningCounts() async {
        // Hints on rows like the others, silent if they fail
        if let today = try? await APIService.fetchTasksToday() {
            taskCount = today.tasks.count
        }
        if let lists = try? await APIService.fetchLists() {
            listSummary = (lists.count, lists.reduce(0) { $0 + $1.unchecked })
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
