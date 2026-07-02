import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isShowingSaveContext = false

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            HStack(spacing: 10) {
                SaveContextOverlayButton {
                    isShowingSaveContext = true
                }

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
            .padding(.horizontal, 12)
        }
        .sheet(isPresented: $isShowingSaveContext) {
            SaveContextSheet()
                .environmentObject(appModel)
        }
    }
}

private struct SaveContextOverlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Save Context")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 2)
        .accessibilityLabel("Save context to local memory")
        .accessibilityHint("Opens a local memory save sheet for pasted ChatGPT session context")
    }
}

private struct SaveContextSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = "ChatGPT session context"
    @State private var content = ""
    @State private var source = "chatgpt_web"
    @State private var tags = "local, chatgpt-session, quick-save"
    @State private var importance = 5

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Save this session context to the on-device Local Vault. The app cannot safely scrape ChatGPT's page, so paste the context you want saved.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextField("Source", text: $source)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Tags, comma separated", text: $tags)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Stepper("Importance: \(importance)/5", value: $importance, in: 1...5)

                    Text("Context")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    TextEditor(text: $content)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        Button {
                            if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                                content = pasted
                                appModel.statusMessage = "Pasted clipboard into Save Context."
                            } else {
                                appModel.statusMessage = "Clipboard does not contain text."
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            content = ""
                            appModel.statusMessage = "Cleared Save Context text."
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        appModel.saveLocalSessionContext(
                            title: title,
                            content: content,
                            source: source,
                            tagsText: tags,
                            importance: importance
                        )
                        if appModel.lastLocalMemorySave != nil {
                            dismiss()
                        }
                    } label: {
                        Label("Save Local Context", systemImage: "externaldrive.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Save Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if content.isEmpty, let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                content = pasted
            }
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
