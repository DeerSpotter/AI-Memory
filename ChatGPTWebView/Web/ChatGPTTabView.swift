import SwiftUI

struct ChatGPTTabView: View {
    @StateObject private var webViewStore = ChatGPTWebViewStore()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            HStack(spacing: 10) {
                CircleIconButton(
                    systemImage: "stop.circle",
                    accessibilityLabel: "Stop ChatGPT activity",
                    accessibilityHint: "Attempts to stop the current WebView activity quickly"
                ) {
                    webViewStore.stopCurrentActivity()
                }

                CircleIconButton(
                    systemImage: "arrow.clockwise",
                    accessibilityLabel: "Reload ChatGPT session",
                    accessibilityHint: "Reloads the current ChatGPT WebView page if the app feels frozen"
                ) {
                    webViewStore.reloadCurrentSession()
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
