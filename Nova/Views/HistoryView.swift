import SwiftUI

struct HistoryView: View {
    @State private var messages:       [Message] = []
    @State private var isLoading:      Bool = true
    @State private var isLoadingMore:  Bool = false
    @State private var hasMorePages:   Bool = true
    @State private var errorMessage:   String? = nil
    @State private var refreshError:   String? = nil
    @State private var searchText:     String = ""
    @State private var expanded:       Set<UUID> = []

    // Matches the server's default, so a short page reliably means the end
    private let pageSize = 50

    private var displayed: [Message] {
        guard !searchText.isEmpty else { return messages }
        return messages.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.accent.opacity(0.15))

                if let refreshError {
                    Text(refreshError)
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
                } else if let error = errorMessage {
                    Spacer()
                    Text(error)
                        .novaFont(13, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Button("RETRY") {
                        Task { await loadInitial(showSpinner: true) }
                    }
                    .novaFont(11, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.accent)
                    .tracking(2)
                    Spacer()
                } else if messages.isEmpty {
                    Spacer()
                    Text("NO HISTORY YET")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Spacer()
                } else {
                    historyList
                }
            }
        }
        .task { await loadInitial(showSpinner: true) }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CONVERSATION LOG")
                    .novaFont(13, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(4)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .novaFont(13)
                    .foregroundColor(Theme.textSecondary)
                TextField("Search messages...", text: $searchText)
                    .novaFont(13, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tint(Theme.accent)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .novaFont(13)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: List

    private var historyList: some View {
        List {
            ForEach(DaySection.group(displayed)) { section in
                Section {
                    ForEach(section.messages) { message in
                        HistoryRow(message: message, isExpanded: expanded.contains(message.id))
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(message) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(expanded.contains(message.id) ? "Collapses the message" : "Shows the full message")
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.accent.opacity(0.1))
                            .onAppear {
                                // Trigger next page when near the bottom
                                if message.id == displayed.suffix(5).first?.id {
                                    Task { await loadMore() }
                                }
                            }
                    }
                } header: {
                    dayHeader(section.title)
                }
            }

            // Pagination footer
            if !searchText.isEmpty && displayed.count < messages.count {
                // Search result hint
                Section {
                    Text("\(displayed.count) of \(messages.count) loaded messages match")
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                }
            }

            if hasMorePages && searchText.isEmpty {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView().tint(Theme.accent).scaleEffect(0.8)
                    } else {
                        Button("LOAD MORE") {
                            Task { await loadMore() }
                        }
                        .novaFont(11, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.accent)
                        .tracking(2)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await loadInitial(showSpinner: false) }
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .novaFont(9, weight: .medium, design: .monospaced)
            .foregroundColor(Theme.textSecondary)
            .tracking(3)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
    }

    private func toggle(_ message: Message) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expanded.contains(message.id) {
                expanded.remove(message.id)
            } else {
                expanded.insert(message.id)
            }
        }
    }

    // MARK: Data loading

    private func loadInitial(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        refreshError = nil
        do {
            let batch = try await APIService.fetchHistory(limit: pageSize, offset: 0)
            // Each page arrives oldest first; the log reads newest first
            messages = batch.reversed()
            hasMorePages = batch.count == pageSize
            // Every decode makes new ids, so old expansion state would point at nothing
            expanded = []
        } catch {
            // A failed pull to refresh keeps the list on screen and reports above it
            if messages.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                refreshError = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        do {
            // The server counts offset back from the newest message, so everything already
            // on screen is exactly what to skip
            let batch = try await APIService.fetchHistory(limit: pageSize, offset: messages.count)
            messages.append(contentsOf: batch.reversed())
            hasMorePages = batch.count == pageSize
        } catch {
            // Pagination errors do not replace the existing list
        }
        isLoadingMore = false
    }
}

// MARK: Day grouping

// Consecutive messages that share a calendar day. Input is newest first, and so is the output.
private struct DaySection: Identifiable {
    let id: String
    let day: Date?
    var messages: [Message]

    var title: String {
        guard let day else { return "UNDATED" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }

        let thisYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        let style = thisYear
            ? Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
            : Date.FormatStyle().month(.abbreviated).day().year()
        return day.formatted(style).uppercased()
    }

    static func group(_ messages: [Message]) -> [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []

        for message in messages {
            let day = message.date.map { calendar.startOfDay(for: $0) }
            if let last = sections.last, last.day == day {
                sections[sections.count - 1].messages.append(message)
            } else {
                // The index keeps ids unique even if undated rows split a day in two
                let id = "\(day?.timeIntervalSince1970 ?? -1)-\(sections.count)"
                sections.append(DaySection(id: id, day: day, messages: [message]))
            }
        }
        return sections
    }
}

// MARK: History row

private struct HistoryRow: View {
    let message: Message
    let isExpanded: Bool

    // Grows with Dynamic Type so "NOVA" never wraps inside its column
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 40

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var sourceIcon: String {
        message.isFromRoom ? "hifispeaker.fill" : "iphone"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(message.isUser ? "YOU" : "NOVA")
                    .novaFont(9, weight: .bold, design: .monospaced)
                    .foregroundColor(message.isUser ? Theme.accent : Theme.accent.opacity(0.55))
                    .tracking(2)

                if let date = message.date {
                    Text(Self.timeFormatter.string(from: date))
                        .novaFont(9, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.top, 2)

            messageText
                .novaFont(14)
                .foregroundColor(Theme.textPrimary)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: sourceIcon)
                .novaFont(10)
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var messageText: some View {
        if isExpanded && !message.isUser {
            MarkdownText(source: message.content)
        } else if isExpanded {
            Text(message.content)
        } else {
            Text(preview)
                .lineLimit(4)
        }
    }

    // Collapsed rows use inline styling only; full blocks would not survive a four line cutoff
    private var preview: AttributedString {
        guard !message.isUser else { return AttributedString(message.content) }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.content, options: options)) ?? AttributedString(message.content)
    }
}

#Preview {
    HistoryView()
}
