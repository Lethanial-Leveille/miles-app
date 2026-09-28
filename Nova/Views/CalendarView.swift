import SwiftUI

// The week from the start of today across every calendar Nova reads. Only MILES calendar
// events can be changed here, the same rule Nova follows by voice, and the Pi enforces it.
struct CalendarView: View {
    @State private var week: CalendarWeek?
    @State private var isLoading = true
    @State private var errorMessage: String?
    // The Pi's own sentence about the last change, like "Moved Gym to 4 PM"
    @State private var lastResult: String?
    @State private var editing: CalendarEvent?

    private let days = 7

    // Every day of the window, empty ones included, so a free day reads as free
    private var sections: [(day: Date, events: [CalendarEvent])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // A multi day event that began before today is still happening, so it belongs under today
        let byDay = Dictionary(grouping: week?.events ?? []) { max($0.day ?? today, today) }
        return (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { ($0, byDay[$0] ?? []) }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "YOUR WEEK")

                if let lastResult {
                    banner(lastResult, color: Theme.accent)
                }
                if let errorMessage, week != nil {
                    banner(errorMessage, color: Theme.textPrimary)
                }
                if let unreadable = week?.unreadable, !unreadable.isEmpty {
                    // A calendar Google refused would otherwise just look like a quiet week
                    banner("Could not read \(unreadable.joined(separator: ", ")). This week may be missing events.",
                           color: Theme.textPrimary)
                }

                if isLoading && week == nil {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if let errorMessage, week == nil {
                    Spacer()
                    Text(errorMessage)
                        .novaFont(13, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sections, id: \.day) { section in
                                SectionLabel(title: dayTitle(section.day))
                                if section.events.isEmpty {
                                    Text("Nothing scheduled")
                                        .novaFont(12, design: .monospaced)
                                        .foregroundColor(Theme.textSecondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                } else {
                                    ForEach(section.events) { event in
                                        EventRow(event: event) { editing = event }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: $editing) { event in
            EventEditor(event: event) { result in
                lastResult = result
                await load()
            }
            .presentationDetents([.large])
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .novaFont(11, design: .monospaced)
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        if calendar.isDateInToday(day) { return "TODAY  ·  \(date)" }
        if calendar.isDateInTomorrow(day) { return "TOMORROW  ·  \(date)" }
        return date
    }

    private func load() async {
        isLoading = true
        do {
            week = try await APIService.fetchCalendar(days: days)
            errorMessage = nil
        } catch {
            // A 502 carries Google's reason, which is the thing to see when a token expires
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: Row

private struct EventRow: View {
    let event: CalendarEvent
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                // An accent edge marks what can be changed here
                Rectangle()
                    .frame(width: 2)
                    .foregroundColor(event.editable ? Theme.accent : Theme.textSecondary.opacity(0.3))

                Text(timeText)
                    .novaFont(11, design: .monospaced)
                    .monospacedDigit()
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 72, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .novaFont(14, weight: .medium)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(details)
                        .novaFont(9, design: .monospaced)
                        .foregroundColor(event.editable ? Theme.accent : Theme.textSecondary)
                        .tracking(1)
                }

                Spacer(minLength: 4)

                if event.editable {
                    Image(systemName: "pencil")
                        .novaFont(11)
                        .foregroundColor(Theme.accent)
                        .padding(.top, 3)
                }
            }
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .padding(.leading, 20)
            .background(Theme.surface)
            .overlay(alignment: .bottom) {
                Rectangle().frame(height: 1).foregroundColor(Theme.accent.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .disabled(!event.editable)
        .accessibilityHint(event.editable ? "Edit this event" : "Read only")
    }

    private var timeText: String {
        guard !event.allDay, let start = event.startDate else { return "ALL DAY" }
        let first = start.formatted(date: .omitted, time: .shortened)
        guard let end = event.endDate else { return first }
        return "\(first)\n\(end.formatted(date: .omitted, time: .shortened))"
    }

    private var details: String {
        var parts = [event.calendar.uppercased()]
        if event.repeating { parts.append("REPEATS") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: Editor

private struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    // Receives the Pi's sentence about what happened
    let onDone: (String) async -> Void

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    private let originalStart: Date
    private let originalEnd: Date

    init(event: CalendarEvent, onDone: @escaping (String) async -> Void) {
        self.event = event
        self.onDone = onDone
        let first = event.startDate ?? .now
        let last = event.endDate ?? first.addingTimeInterval(3600)
        originalStart = first
        originalEnd = last
        _title = State(initialValue: event.title)
        _start = State(initialValue: first)
        _end = State(initialValue: last)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var titleChanged: Bool { trimmedTitle != event.title }
    private var timesChanged: Bool { start != originalStart || end != originalEnd }
    private var canSave: Bool {
        !isWorking && !trimmedTitle.isEmpty && (titleChanged || timesChanged) && (event.allDay || end > start)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button("CANCEL") { dismiss() }
                            .novaFont(11, design: .monospaced)
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("EDIT EVENT")
                            .novaFont(12, weight: .bold, design: .monospaced)
                            .foregroundColor(Theme.textPrimary)
                            .tracking(3)
                        Spacer()
                        Button {
                            Task { await save() }
                        } label: {
                            if isWorking {
                                ProgressView().tint(Theme.accent)
                            } else {
                                Text("SAVE")
                                    .novaFont(11, weight: .bold, design: .monospaced)
                                    .foregroundColor(canSave ? Theme.accent : Theme.textSecondary)
                            }
                        }
                        .disabled(!canSave)
                    }
                    .padding(.top, 20)

                    fieldLabel("TITLE")
                    TextField("", text: $title)
                        .novaFont(15)
                        .foregroundColor(Theme.textPrimary)
                        .tint(Theme.accent)
                        .padding(12)
                        .background(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent.opacity(0.3), lineWidth: 1))

                    if event.allDay {
                        note("An all day event can only have its title changed.")
                    } else {
                        fieldLabel("STARTS")
                        DatePicker("", selection: $start)
                            .labelsHidden()
                            .tint(Theme.accent)
                            // Moving the start carries the end along, the same as "move it to 4" by voice
                            .onChange(of: start) { old, new in
                                end = end.addingTimeInterval(new.timeIntervalSince(old))
                            }

                        fieldLabel("ENDS")
                        DatePicker("", selection: $end, in: start.addingTimeInterval(60)...)
                            .labelsHidden()
                            .tint(Theme.accent)
                    }

                    if event.repeating {
                        note("This event repeats. The change applies to this occurrence.")
                    }
                    note("Changes happen at once and are not part of Nova's spoken undo.")

                    if let errorMessage {
                        Text(errorMessage)
                            .novaFont(11, design: .monospaced)
                            .foregroundColor(Theme.textPrimary)
                    }

                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("DELETE EVENT")
                            .novaFont(12, weight: .bold, design: .monospaced)
                            .tracking(2)
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.textSecondary.opacity(0.5), lineWidth: 1))
                    }
                    .disabled(isWorking)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .confirmationDialog("Delete \(event.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            // No destructive role: the system draws that in red, which this app never shows
            Button("Delete") { Task { await delete() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("It is removed from your MILES calendar right away.")
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .novaFont(9, weight: .medium, design: .monospaced)
            .foregroundColor(Theme.textSecondary)
            .tracking(3)
            .padding(.top, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .novaFont(10, design: .monospaced)
            .foregroundColor(Theme.textSecondary)
    }

    private func save() async {
        await run {
            // Only what changed goes up, so a title fix never rewrites the times
            try await APIService.changeEvent(
                id: event.id,
                title: titleChanged ? trimmedTitle : nil,
                start: timesChanged ? start : nil,
                end: timesChanged ? end : nil
            )
        }
    }

    private func delete() async {
        await run { try await APIService.deleteEvent(id: event.id) }
    }

    private func run(_ work: () async throws -> String) async {
        isWorking = true
        errorMessage = nil
        do {
            let result = try await work()
            await onDone(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

#Preview {
    CalendarView()
}
