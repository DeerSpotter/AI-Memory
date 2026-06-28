import SwiftUI
import UIKit

struct SupabaseSetupView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var projectURLText = ""
    @State private var publishableKey = ""
    @State private var setupLink = ""
    @State private var browserURL: URL?

    private let appCallbackURL = "chatgptwebview://auth-callback"

    var body: some View {
        NavigationView {
            Form {
                Section("Setup Helper") {
                    Text("Open setup pages without leaving the app. Use Done to return here.")
                        .font(.footnote)

                    Button("Open Supabase Dashboard") {
                        browserURL = URL(string: "https://supabase.com/dashboard")
                    }

                    Button("Open GitHub OAuth Apps") {
                        browserURL = URL(string: "https://github.com/settings/developers")
                    }

                    Button("Open This Repo") {
                        browserURL = URL(string: "https://github.com/DeerSpotter/ChatGPT-WebView")
                    }
                }

                Section("Your Supabase Project") {
                    TextField("https://project-ref.supabase.co", text: $projectURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    SecureField("Publishable key", text: $publishableKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Run Diagnostics") {
                        Task {
                            await appModel.runDiagnostics(
                                projectURLText: projectURLText,
                                publishableKey: publishableKey
                            )
                        }
                    }
                    .disabled(appModel.isBusy || projectURLText.isEmpty || publishableKey.isEmpty)

                    Button("Save Supabase Project") {
                        appModel.saveConfig(
                            projectURLText: projectURLText,
                            publishableKey: publishableKey
                        )
                    }
                    .disabled(projectURLText.isEmpty || publishableKey.isEmpty)
                }

                Section("Diagnostics") {
                    if appModel.diagnostics.isEmpty {
                        Text("Run diagnostics before logging in. The app will check the project URL, publishable key, auth settings, and memory function.")
                            .font(.footnote)
                    } else {
                        ForEach(appModel.diagnostics) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.status.rawValue)
                                        .font(.caption)
                                        .bold()
                                    Text(item.name)
                                        .font(.headline)
                                }
                                Text(item.detail)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Import Setup Link") {
                    Text("Advanced setup can be imported with a link like this. It must include only the project URL and publishable key.")
                        .font(.footnote)

                    Button("Generate Setup Link Preview") {
                        setupLink = appModel.setupDeepLink(
                            projectURLText: projectURLText,
                            publishableKey: publishableKey
                        ) ?? "Invalid project URL or key."
                    }
                    .disabled(projectURLText.isEmpty || publishableKey.isEmpty)

                    if !setupLink.isEmpty {
                        Text(setupLink)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        Button("Copy Setup Link") {
                            UIPasteboard.general.string = setupLink
                            appModel.statusMessage = "Setup link copied."
                        }
                    }
                }

                Section("Callback URLs") {
                    Text("Supabase Auth URL Configuration should allow this app callback:")
                    Text(appCallbackURL)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)

                    Button("Copy App Callback URL") {
                        UIPasteboard.general.string = appCallbackURL
                        appModel.statusMessage = "App callback URL copied."
                    }

                    if let providerCallback = providerCallbackURLText() {
                        Text("GitHub OAuth App callback URL:")
                        Text(providerCallback)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)

                        Button("Copy Provider Callback URL") {
                            UIPasteboard.general.string = providerCallback
                            appModel.statusMessage = "Provider callback URL copied."
                        }
                    }
                }

                Section("If Login Opens Localhost") {
                    Text("That means Supabase finished GitHub login but redirected to the default Site URL instead of back to this app.")
                    Text("In Supabase Auth URL Configuration, replace localhost with the app callback URL above, or add the app callback URL to the redirect allow list.")
                    Text("The GitHub OAuth App callback should stay as the Supabase /auth/v1/callback URL, not localhost.")
                }

                Section("Important") {
                    Text("Use your own Supabase project. Do not paste a secret key or service role key into the app.")
                    Text("The memory schema and Edge Function must be deployed to this project before memory search/save will work.")
                }

                Section("Status") {
                    if appModel.isBusy {
                        ProgressView()
                    }
                    Text(appModel.statusMessage.isEmpty ? "Add a Supabase project to continue." : appModel.statusMessage)
                        .font(.footnote)
                }
            }
            .navigationTitle("Supabase Setup")
        }
        .sheet(item: $browserURL) { url in
            InAppBrowserView(url: url)
        }
        .onAppear {
            if let config = appModel.configStore.config {
                projectURLText = config.projectURL.absoluteString
                publishableKey = config.publishableKey
            }
        }
    }

    private func providerCallbackURLText() -> String? {
        guard let config = try? SupabaseConfigValidation.normalize(
            projectURLText: projectURLText,
            publishableKey: publishableKey
        ) else {
            return nil
        }

        return config.projectURL.appendingPathComponent("auth/v1/callback").absoluteString
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
