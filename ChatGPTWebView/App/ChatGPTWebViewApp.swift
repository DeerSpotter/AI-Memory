import SwiftUI

@main
struct ChatGPTWebViewApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var updateChecker = AppUpdateChecker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(updateChecker)
                .task {
                    await appModel.restoreSession()
                }
                .task {
                    await updateChecker.checkForUpdateOnStartup()
                }
                .onOpenURL { url in
                    appModel.handleOpenURL(url)
                }
        }
    }
}
