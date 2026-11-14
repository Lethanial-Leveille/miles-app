import SwiftUI

// Every list Nova keeps, from "add eggs to my grocery list". Adding stays voice only,
// so this screen reads and checks off; it never creates a list.
struct ListsView: View {
    @State private var lists: [ShoppingList] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "LISTS")

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
                } else if lists.isEmpty {
                    Spacer()
                    Text("NO LISTS YET")
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(3)
                    Text("Ask Nova to add something to a list, like eggs to your grocery list")
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    List {
                        ForEach(lists) { list in
                            NavigationLink {
                                ListDetailView(list: list)
                            } label: {
                                ListRow(list: list)
                            }
                            .listRowBackground(Theme.background)
                            .listRowSeparatorTint(Theme.textSecondary.opacity(0.14))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load(showSpinner: false) }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // onAppear rather than task, so counts are fresh after checking items off inside a list
        .onAppear { Task { await load(showSpinner: lists.isEmpty) } }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        do {
            lists = try await APIService.fetchLists()
            errorMessage = nil
        } catch {
            // A failed refresh keeps the lists already on screen
            if lists.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }
}

private struct ListRow: View {
    let list: ShoppingList

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checklist")
                .novaFont(13)
                .foregroundColor(Theme.accent)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.accent.opacity(0.45), lineWidth: 1))

            Text(list.name.uppercased())
                .novaFont(12, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(1)

            Spacer()

            Text(list.unchecked == 0 ? "DONE" : "\(list.unchecked) LEFT")
                .novaFont(10, design: .monospaced)
                .foregroundColor(list.unchecked == 0 ? Theme.done : Theme.textSecondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// One list: what is left to get, and below it what was already bought. A tap moves an
// item between the two, and both routes are safe to repeat, so a retry is never an error.
struct ListDetailView: View {
    let list: ShoppingList

    @State private var items: [ListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showBought = false

    private var toGet: [ListItem] { items.filter { !$0.checked } }
    // The Pi sends these most recently checked first
    private var bought: [ListItem] { items.filter(\.checked) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: list.name.uppercased())

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
                } else {
                    content
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load(showSpinner: true) }
    }

    private var content: some View {
        List {
            Section {
                if toGet.isEmpty {
                    Text("NOTHING LEFT TO GET")
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(2)
                        .padding(.vertical, 10)
                        .listRowBackground(Theme.background)
                } else {
                    ForEach(toGet) { item in
                        row(item)
                    }
                }
            } header: {
                header("TO GET")
            }

            if !bought.isEmpty {
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showBought.toggle() }
                    } label: {
                        HStack {
                            Text(showBought ? "HIDE BOUGHT" : "SHOW BOUGHT (\(bought.count))")
                                .novaFont(10, weight: .medium, design: .monospaced)
                                .foregroundColor(Theme.accent)
                                .tracking(2)
                            Spacer()
                            Image(systemName: showBought ? "chevron.up" : "chevron.down")
                                .novaFont(10, weight: .medium)
                                .foregroundColor(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)

                    if showBought {
                        ForEach(bought) { item in
                            row(item)
                        }
                    }
                } header: {
                    header("BOUGHT")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(showSpinner: false) }
    }

    private func header(_ title: String) -> some View {
        SectionLabel(title: title)
            .padding(.top, -12)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
    }

    private func row(_ item: ListItem) -> some View {
        Button {
            toggle(item)
        } label: {
            ItemRow(item: item)
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.textSecondary.opacity(0.14))
        .accessibilityHint(item.checked ? "Puts it back on the list" : "Checks it off")
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        do {
            items = try await APIService.fetchListItems(listID: list.id, includeChecked: true)
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

    // Moves the row at once and tells the Pi after. Both calls are idempotent, so a slow
    // network or a double tap cannot leave a wrong error on screen; a failure reloads
    // what the Pi really has.
    private func toggle(_ item: ListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        actionError = nil
        let checking = !item.checked
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            var moved = items.remove(at: index)
            moved.checked = checking
            moved.checkedAt = checking ? Self.nowString() : nil
            // Mirror the Pi's order with one insert at the boundary: a newly checked item
            // tops the history, and an unchecked one goes to the end of what is left to get
            let boundary = items.firstIndex(where: \.checked) ?? items.endIndex
            items.insert(moved, at: boundary)
        }
        Task {
            do {
                if checking {
                    try await APIService.checkListItem(id: item.id)
                } else {
                    try await APIService.uncheckListItem(id: item.id)
                }
            } catch {
                actionError = "Could not update \(item.text): \(error.localizedDescription)"
                await load(showSpinner: false)
            }
        }
    }

    private static func nowString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: .now)
    }
}

private struct ItemRow: View {
    let item: ListItem

    var body: some View {
        HStack(spacing: 14) {
            // Green only when it is true: the item really is bought
            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                .novaFont(20)
                .foregroundColor(item.checked ? Theme.done : Theme.accent)
                .frame(width: 32)

            Text(item.text)
                .novaFont(14)
                .foregroundColor(item.checked ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(item.checked, color: Theme.textSecondary)
                .lineLimit(3)

            Spacer(minLength: 8)

            if item.checked, let when = item.checkedDate {
                Text(Self.when(when))
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }
}

#Preview {
    NavigationStack { ListsView() }
}
