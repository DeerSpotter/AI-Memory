import SwiftUI

struct ChatGPTTabView: View {
    @StateObject private var webViewStore = ChatGPTWebViewStore()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            Button {
                webViewStore.reloadCurrentSession()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(radius: 2)
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityLabel("Reload ChatGPT session")
            .accessibilityHint("Reloads the current ChatGPT WebView page if the app feels frozen")
        }
    }
}
