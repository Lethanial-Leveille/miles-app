import SwiftUI

struct MainTabView: View {
    @ObservedObject private var router = ApprovalRouter.shared
    @ObservedObject private var sessions = SessionRouter.shared

    enum Tab: Hashable {
        case chat, sessions, history, settings
    }

    @State private var tab: Tab = .chat

    var body: some View {
        TabView(selection: $tab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }
                .tag(Tab.chat)

            SessionsListView()
                .tabItem {
                    Label("Sessions", systemImage: "moon.stars.fill")
                }
                .tag(Tab.sessions)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        // A tap on a MILES push lands here: the request it was about, or the problem in full
        .sheet(isPresented: $router.isOpen) {
            ApprovalsView()
        }
        .sheet(item: $router.errorNote) { note in
            ErrorDetailView(note: note)
        }
        // A session push or nova://session/<id>, including one that launched the app
        .sheet(item: $sessions.presented) { link in
            SessionView(sessionID: link.id)
        }
        // nova://sessions. Checked on appear too, for a link that arrived before the login did.
        .onAppear { showListIfAsked() }
        .onChange(of: sessions.wantsList) { showListIfAsked() }
    }

    private func showListIfAsked() {
        guard sessions.wantsList else { return }
        tab = .sessions
        sessions.wantsList = false
    }
}
