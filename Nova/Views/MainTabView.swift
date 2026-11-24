import SwiftUI

struct MainTabView: View {
    @ObservedObject private var router = ApprovalRouter.shared

    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(Theme.accent)
        // A tap on an approval push lands here
        .sheet(isPresented: $router.isOpen) {
            ApprovalsView()
        }
    }
}
