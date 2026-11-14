import SwiftUI

// What is left to do today. The Pi's day starts at 4am, so just after midnight this is
// still yesterday's list, and the header says so rather than leaving last night's
// vitamins looking done.
struct TasksView: View {
    @State private var taskDay: TaskDay?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    // Finishing a task has no undo on the Pi, so a tap only arms it and a second tap sends
    @State private var armedID: Int?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "TODAY")

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
                } else if let taskDay {
                    content(taskDay)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load(showSpinner: true) }
    }

    @ViewBuilder
    private func content(_ taskDay: TaskDay) -> some View {
        if let note = Self.dayNote(taskDay.day) {
            Text(note)
                .novaFont(10, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 12)
        }

        if taskDay.tasks.isEmpty {
            Spacer()
            Text("ALL DONE")
                .novaFont(12, design: .monospaced)
                .foregroundColor(Theme.done)
                .tracking(3)
            Text("Nothing left for today. Ask Nova to add a task, daily or one time")
                .novaFont(11, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)
            Spacer()
        } else {
            List {
                ForEach(taskDay.tasks) { task in
                    Button {
                        tap(task)
                    } label: {
                        TaskRow(task: task, armed: armedID == task.id)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.textSecondary.opacity(0.14))
                    .accessibilityHint(armedID == task.id ? "Tap again to mark it done" : "Tap twice to mark it done")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load(showSpinner: false) }
        }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        do {
            taskDay = try await APIService.fetchTasksToday()
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

    private func tap(_ task: TaskItem) {
        actionError = nil
        guard armedID == task.id else {
            withAnimation(.easeInOut(duration: 0.15)) { armedID = task.id }
            return
        }
        armedID = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.2)) {
            if let current = taskDay {
                taskDay = TaskDay(day: current.day, tasks: current.tasks.filter { $0.id != task.id })
            }
        }
        Task {
            do {
                try await APIService.completeTask(id: task.id)
            } catch {
                actionError = "Could not finish \(task.text): \(error.localizedDescription)"
            }
            // Reload either way: a daily task finished just before 4am is back for the new day
            await load(showSpinner: false)
        }
    }

    // Only worth a line when the Pi's day is not the phone's calendar date
    private static func dayNote(_ day: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day), !Calendar.current.isDateInToday(date) else {
            return nil
        }
        let name = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
        return "STILL \(name). A NEW DAY STARTS AT 4 AM"
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let armed: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: armed ? "checkmark.circle" : "circle")
                .novaFont(20)
                .foregroundColor(armed ? Theme.done : Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
                if armed {
                    Text("TAP AGAIN TO MARK DONE")
                        .novaFont(9, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.done)
                        .tracking(2)
                }
            }

            Spacer(minLength: 8)

            if task.isDaily {
                Image(systemName: "repeat")
                    .novaFont(11)
                    .foregroundColor(Theme.textSecondary)
                    .accessibilityLabel("Daily")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { TasksView() }
}
