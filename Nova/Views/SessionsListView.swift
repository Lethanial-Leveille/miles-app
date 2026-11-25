import Combine
import SwiftUI

// Where a session push, a nova:// link, or a Shortcut lands. Built like ApprovalRouter: one shared
// object the app delegate and onOpenURL can drive from outside SwiftUI, and that MainTabView
// watches. It holds the request until the tab view is on screen, so a cold launch from a push,
// with the login still to come, opens the session once he is in.
@MainActor
final class SessionRouter: ObservableObject {
    static let shared = SessionRouter()

    // The session to show over everything, from a push or nova://session/<id>
    @Published var presented: SessionLink?
    // Set by nova://sessions; MainTabView switches to the Sessions tab and clears it
    @Published var wantsList = false
    // Bumped whenever a session changes, so an open list reloads
    @Published var revision = 0

    func open(sessionID: Int) {
        // Two sheets cannot show at once, so a session tap takes the place of an approvals one
        ApprovalRouter.shared.isOpen = false
        ApprovalRouter.shared.errorNote = nil
        presented = SessionLink(id: sessionID)
    }

    func openList() {
        presented = nil
        wantsList = true
    }

    // nova://session/12 and nova://sessions. Returns false for anything else.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "nova" else { return false }
        // In nova://session/12 the word after the slashes is the host, and 12 is the path
        let host = url.host?.lowercased() ?? ""
        let rest = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "session":
            guard let first = rest.first, let id = Int(first) else { return false }
            open(sessionID: id)
            return true
        case "sessions":
            openList()
            return true
        default:
            return false
        }
    }

    nonisolated func refresh() { Task { @MainActor in self.revision += 1 } }
}

// A session id that can drive sheet(item:)
struct SessionLink: Identifiable, Equatable {
    let id: Int
}

// Sessions the Pi started with a purpose, open ones first. Each can be opened, or closed from
// here, which writes its summary.
struct SessionsListView: View {
    @ObservedObject private var router = SessionRouter.shared

    enum Filter: String, CaseIterable, Identifiable {
        case open, closed, missed, all
        var id: String { rawValue }
    }

    @State private var filter: Filter = .open
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var closing: Set<Int> = []
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    filterBar
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
        .task(id: TaskKey(filter: filter, revision: router.revision)) { await load() }
    }

    private struct TaskKey: Equatable {
        let filter: Filter
        let revision: Int
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && sessions.isEmpty {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if sessions.isEmpty {
                        Text(filter == .open ? "NOTHING OPEN" : "NONE")
                            .novaFont(12, design: .monospaced)
                            .foregroundColor(Theme.textSecondary)
                            .tracking(3)
                            .padding(.top, 60)
                    }
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionView(sessionID: session.id)
                        } label: {
                            row(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack {
            Text("SESSIONS")
                .novaFont(13, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(4)
            Spacer()
            // Starts tonight's review by hand. The Pi hands back today's if one exists already.
            Button {
                Task { await startNightlyReview() }
            } label: {
                if isStarting {
                    ProgressView().tint(Theme.accent)
                } else {
                    Label("REVIEW", systemImage: "plus")
                        .novaFont(10, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.accent)
                }
            }
            .disabled(isStarting)
            .accessibilityLabel("Start the nightly review")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.textSecondary.opacity(0.18))
        }
    }

    private var filterBar: some View {
        Picker("Show", selection: $filter) {
            ForEach(Filter.allCases) { item in
                Text(item.rawValue.uppercased()).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func row(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.typeLabel)
                    .novaFont(10, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(2)
                Spacer()
                Text(whenText(session))
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            }
            Text(session.title ?? session.purpose)
                .novaFont(15)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            if session.title != nil {
                Text(session.purpose)
                    .novaFont(12)
                    .foregroundColor(Theme.textSecondary)
            }
            HStack {
                Text(session.status.uppercased())
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(session.isOpen ? Theme.listening : Theme.textSecondary)
                Spacer()
                if session.isOpen {
                    Button {
                        Task { await close(session) }
                    } label: {
                        if closing.contains(session.id) {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Text("CLOSE")
                                .novaFont(10, weight: .bold, design: .monospaced)
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(closing.contains(session.id))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    // A nightly review is about a day, so it shows that day; other types show when they began
    private func whenText(_ session: Session) -> String {
        if let day = session.forDay { return SessionTime.dayText(day) }
        if let created = session.created { return SessionTime.momentText(created) }
        return ""
    }

    private func load() async {
        do {
            sessions = try await APIService.fetchSessions(status: filter.rawValue)
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func close(_ session: Session) async {
        closing.insert(session.id)
        defer { closing.remove(session.id) }
        do {
            let closed = try await APIService.closeSession(id: session.id)
            let summary = closed.summary ?? ""
            message = summary.isEmpty ? "Closed." : "Closed. \(summary)"
        } catch {
            message = error.localizedDescription
        }
        await load()
    }

    private func startNightlyReview() async {
        isStarting = true
        defer { isStarting = false }
        do {
            let detail = try await APIService.startSession(type: "nightly_review")
            await load()
            router.open(sessionID: detail.session.id)
        } catch {
            message = error.localizedDescription
        }
    }
}
