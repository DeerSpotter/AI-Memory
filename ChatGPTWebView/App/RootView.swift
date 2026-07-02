import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: AppTab = .chatgpt

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatGPTTabView()
                .tabItem {
                    Label("ChatGPT", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(AppTab.chatgpt)

            MemoryTestView()
                .tabItem {
                    Label("Memory", systemImage: "externaldrive.connected.to.line.below")
                }
                .tag(AppTab.memory)

            SupabaseSetupView()
                .tabItem {
                    Label("Setup", systemImage: "gearshape")
                }
                .tag(AppTab.setup)
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            selectedTab = .chatgpt
        }
    }
}

private enum AppTab: Hashable {
    case chatgpt
    case memory
    case setup
}

struct SupabaseSetupRequiredView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

                Text("Supabase setup optional")
                    .font(.headline)

                Text("Local Device Memory Vault works without Supabase. Open Setup only when you want Supabase sync, diagnostics, and login.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Memory")
        }
    }
}
