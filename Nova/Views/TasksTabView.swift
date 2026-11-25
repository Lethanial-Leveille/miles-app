import SwiftUI

// Today, the next two days and the backlog. The Pi's day starts at 4am, so just after
// midnight "Today" is still yesterday's date; the server's labels are shown as sent.
struct TasksTabView: View {
    @State private var overview: TasksOverview?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var message: String?
    @State private var busy: Set<Int> = []
    @State private var showingNew = false
    @State private var loadSequence = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if let message {
                        Text(message)
                            .novaFont(12, design: .monospaced)
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .onTapGesture { self.message = nil }
                    }
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await load() }
        .sheet(isPresented: $showingNew) {
            NewTaskSheet { await load() }
        }
    }

    private var header: some View {
        HStack {
            Text("TASKS")
                .novaFont(13, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            Button {
                showingNew = true
            } label: {
                Image(systemName: "plus")
                    .novaFont(16, weight: .medium)
                    .foregroundColor(Theme.accent)
                    .frame(width: 44, height: 32)
            }
            .accessibilityLabel("New task")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.textSecondary.opacity(0.18))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let overview {
            List {
                ForEach(overview.days) { day in
                    Section {
                        if day.tasks.isEmpty {
                            emptyRow
                        }
                        ForEach(day.tasks) { task in
                            row(task, swipeToBacklog: !task.daily && !task.isDone)
                        }
                    } header: {
                        sectionHeader(day.label)
                    }
                }
                Section {
                    if overview.backlog.isEmpty {
                        emptyRow
                    }
                    ForEach(overview.backlog) { task in
                        row(task, swipeToBacklog: false)
                    }
                } header: {
                    sectionHeader("Backlog")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        } else if isLoading {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else {
            Spacer()
            Text(loadError ?? "Could not load tasks.")
                .novaFont(13, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(24)
            Button("Try again") { Task { await load() } }
                .novaFont(12, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.accent)
            Spacer()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .novaFont(10, weight: .medium, design: .monospaced)
            .foregroundColor(Theme.textSecondary)
            .tracking(2)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var emptyRow: some View {
        Text("Nothing")
            .novaFont(12, design: .monospaced)
            .foregroundColor(Theme.textSecondary)
            .listRowBackground(Theme.background)
            .listRowSeparator(.hidden)
    }

    private func row(_ task: NovaTask, swipeToBacklog: Bool) -> some View {
        TaskRowView(task: task, isBusy: busy.contains(task.id)) {
            Task { await toggle(task) }
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.textSecondary.opacity(0.14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if swipeToBacklog {
                Button {
                    Task { await moveToBacklog(task) }
                } label: {
                    Label("Backlog", systemImage: "tray.and.arrow.down")
                }
                .tint(Theme.textSecondary)
            }
        }
    }

    // Reading again after every action, success or not, so the screen is the Pi's word
    // and never a guess
    private func load() async {
        // Answers can arrive out of order; only the newest request may change the screen
        loadSequence += 1
        let mine = loadSequence
        do {
            let fresh = try await APIService.fetchTasksOverview()
            guard mine == loadSequence else { return }
            overview = fresh
            loadError = nil
        } catch {
            guard mine == loadSequence else { return }
            if overview == nil {
                loadError = error.localizedDescription
            } else {
                message = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func toggle(_ task: NovaTask) async {
        guard !busy.contains(task.id) else { return }
        busy.insert(task.id)
        message = nil
        do {
            if task.isDone {
                _ = try await APIService.reopenTask(id: task.id)
            } else {
                _ = try await APIService.completeTask(id: task.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            message = error.localizedDescription
        }
        await load()
        busy.remove(task.id)
    }

    private func moveToBacklog(_ task: NovaTask) async {
        guard !busy.contains(task.id) else { return }
        busy.insert(task.id)
        message = nil
        do {
            _ = try await APIService.backlogTask(id: task.id)
        } catch {
            message = error.localizedDescription
        }
        await load()
        busy.remove(task.id)
    }
}

private struct TaskRowView: View {
    let task: NovaTask
    let isBusy: Bool
    let onToggle: () -> Void

    private var circleColor: Color {
        if task.isDone { return Theme.done }
        return task.overdue ? Theme.alert : Theme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .novaFont(22)
                    .foregroundColor(circleColor)
                    .frame(width: 44, height: 44)
                    .opacity(isBusy ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(task.isDone ? "Reopen \(task.displayTitle)" : "Complete \(task.displayTitle)")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.displayTitle)
                    .novaFont(14)
                    .foregroundColor(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                badges
            }
            .padding(.top, 11)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var badges: some View {
        if task.dueDate != nil || task.mustDo || task.hasBlock || task.daily {
            HStack(spacing: 10) {
                if let due = task.dueDate {
                    badge("Due \(TaskDate.display(due))",
                          color: task.overdue ? Theme.alert : Theme.textSecondary)
                } else if task.overdue {
                    badge("Overdue", color: Theme.alert)
                }
                if task.mustDo {
                    badge("Must do", color: Theme.speaking)
                }
                if task.hasBlock {
                    badge("Block", color: Theme.textSecondary, icon: "calendar")
                }
                if task.daily {
                    badge("Daily", color: Theme.textSecondary, icon: "repeat")
                }
            }
        }
    }

    private func badge(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).novaFont(9)
            }
            Text(text).novaFont(10, weight: .medium, design: .monospaced)
        }
        .foregroundColor(color)
    }
}

// The plus button's sheet: a title, today or backlog, and an optional due date
private struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: () async -> Void

    @State private var title = ""
    @State private var place = "today"
    @State private var hasDue = false
    @State private var due = Date()
    @State private var isSending = false
    @State private var error: String?

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !trimmed.isEmpty && trimmed.unicodeScalars.count <= 200 && !isSending }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Title", text: $title, axis: .vertical)
                            .novaFont(15)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1...4)
                            .onChange(of: title) {
                                if title.unicodeScalars.count > 200 {
                                    title = String(String.UnicodeScalarView(title.unicodeScalars.prefix(200)))
                                }
                            }
                    } footer: {
                        Text("\(title.unicodeScalars.count) of 200")
                            .novaFont(10, design: .monospaced)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        Picker("Where", selection: $place) {
                            Text("Today").tag("today")
                            Text("Backlog").tag("backlog")
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        Toggle("Due date", isOn: $hasDue)
                            .tint(Theme.accent)
                            .foregroundColor(Theme.textPrimary)
                        if hasDue {
                            DatePicker("Due", selection: $due, displayedComponents: .date)
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                    .listRowBackground(Theme.surface)

                    if let error {
                        Section {
                            Text(error)
                                .novaFont(12, design: .monospaced)
                                .foregroundColor(Theme.alert)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await submit() } }
                        .foregroundColor(canSubmit ? Theme.accent : Theme.textSecondary)
                        .disabled(!canSubmit)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSending = true
        error = nil
        do {
            let dueString = hasDue ? TaskDate.string(fromPicker: due) : nil
            _ = try await APIService.createTask(title: trimmed, where: place, dueDate: dueString)
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            // The Pi may have saved it before the answer was lost, so read it again
            await onCreated()
        }
        isSending = false
    }
}

#Preview {
    TasksTabView()
}
