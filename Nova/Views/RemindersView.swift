import SwiftUI

// Everything Nova is waiting to say: timers counting down, reminders with a time, and notes
// saved without one. The Pi already sorts them soonest first with notes last.
struct RemindersView: View {
    @State private var reminders: [Reminder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?

    private var timers: [Reminder] { reminders.filter(\.isTimer) }
    private var scheduled: [Reminder] { reminders.filter { !$0.isTimer && $0.dueAt != nil } }
    private var notes: [Reminder] { reminders.filter { !$0.isTimer && $0.dueAt == nil } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "REMINDERS")

                if let actionError {
                    Text(actionError)
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
                } else if let errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .novaFont(13, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else if reminders.isEmpty {
                    Spacer()
                    Text("NOTHING PENDING")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Text("Ask Nova to set a timer or remind you of something")
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    list
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load(showSpinner: true) }
    }

    private var list: some View {
        List {
            group("TIMERS", timers)
            group("REMINDERS", scheduled)
            group("NOTES", notes)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(showSpinner: false) }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [Reminder]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { reminder in
                    ReminderRow(reminder: reminder)
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.accent.opacity(0.1))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                cancel(reminder)
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                            }
                            .tint(Theme.textSecondary)
                        }
                }
            } header: {
                SectionLabel(title: title)
                    .padding(.top, -12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        do {
            reminders = try await APIService.fetchReminders()
            errorMessage = nil
        } catch {
            if showSpinner {
                errorMessage = error.localizedDescription
            } else {
                actionError = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func cancel(_ reminder: Reminder) {
        actionError = nil
        reminders.removeAll { $0.id == reminder.id }
        Task {
            do {
                try await APIService.cancelReminder(id: reminder.id)
            } catch {
                // A 404 usually means it already fired, and the reload shows that truthfully
                actionError = "Could not cancel: \(error.localizedDescription)"
                await load(showSpinner: false)
            }
        }
    }
}

private struct ReminderRow: View {
    let reminder: Reminder

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: reminder.isTimer ? "timer" : reminder.dueAt == nil ? "note.text" : "bell")
                .novaFont(15)
                .foregroundColor(Theme.accent)
                .frame(width: 22)

            Text(reminder.content)
                .novaFont(14)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3)

            Spacer(minLength: 8)

            if let due = reminder.dueDate {
                if reminder.isTimer {
                    // Only a timer is worth a ticking clock; a reminder days out just needs its time
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown(to: due, now: context.date))
                            .novaFont(15, weight: .medium, design: .monospaced)
                            .monospacedDigit()
                            .foregroundColor(Theme.accent)
                    }
                } else {
                    Text(when(due))
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func countdown(to due: Date, now: Date) -> String {
        let left = Int(due.timeIntervalSince(now).rounded(.up))
        guard left > 0 else { return "DUE" }
        let hours = left / 3600, minutes = left % 3600 / 60, seconds = left % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private func when(_ due: Date) -> String {
        let calendar = Calendar.current
        let time = due.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(due) { return "TODAY \(time)" }
        if calendar.isDateInTomorrow(due) { return "TOMORROW \(time)" }
        let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day.uppercased())\n\(time)"
    }
}

#Preview {
    RemindersView()
}
