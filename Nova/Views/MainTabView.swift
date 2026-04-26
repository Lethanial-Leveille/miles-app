import SwiftUI

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    var onLogout: () -> Void

    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }

            StatusView()
                .tabItem {
                    Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                }

            MemoriesView()
                .tabItem {
                    Label("Memories", systemImage: "brain")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
        .tint(Theme.accent(colorScheme))
    }
}
