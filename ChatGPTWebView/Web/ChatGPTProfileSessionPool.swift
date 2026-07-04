import Foundation

private struct AIProfileSessionKey: Hashable {
    let providerID: AIProviderID
    let profileID: String
}

@MainActor
final class ChatGPTProfileSessionPool: ObservableObject {
    private var stores: [AIProfileSessionKey: ChatGPTWebViewStore] = [:]

    // ChatGPT compatibility surface for existing callers.
    func store(
        for profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) -> ChatGPTWebViewStore {
        store(
            for: AIProviderID.chatGPT.provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
    }

    func persistSession(profileID: String) async {
        await persistSession(providerID: .chatGPT, profileID: profileID)
    }

    func setTypingPriority(_ isTyping: Bool, profileID: String) {
        setTypingPriority(isTyping, providerID: .chatGPT, profileID: profileID)
    }

    func removeSavedProfileSession(profileID: String) async {
        await removeSavedProfileSession(providerID: .chatGPT, profileID: profileID)
    }

    func resetGuest(
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) async {
        await resetGuest(
            provider: AIProviderID.chatGPT.provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
    }

    func store(
        for provider: AIProvider,
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) -> ChatGPTWebViewStore {
        let key = AIProfileSessionKey(providerID: provider.id, profileID: profile.id)
        if let existing = stores[key] {
            return existing
        }

        let initialURL = profile.kind == .saved ? provider.loginURL : nil
        let store = ChatGPTWebViewStore(
            provider: provider,
            initialURL: initialURL,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
        stores[key] = store
        return store
    }

    func persistSession(providerID: AIProviderID, profileID: String) async {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        guard let store = stores[key] else { return }
        await store.persistProfileSession()
    }

    func persistAllSessions() async {
        for store in stores.values {
            await store.persistProfileSession()
        }
    }

    func setTypingPriority(
        _ isTyping: Bool,
        providerID: AIProviderID,
        profileID: String
    ) {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        stores[key]?.setTypingPriority(isTyping)
    }

    func removeSavedProfileSession(providerID: AIProviderID, profileID: String) async {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        let storageProfileID = "\(providerID.rawValue)::\(profileID)"

        guard let store = stores.removeValue(forKey: key) else {
            let cookieVault = ChatGPTProfileCookieVault()
            let browserStateVault = ChatGPTProfileBrowserStateVault()
            cookieVault.delete(profileID: storageProfileID)
            browserStateVault.delete(profileID: storageProfileID)
            if providerID == .chatGPT {
                cookieVault.delete(profileID: profileID)
                browserStateVault.delete(profileID: profileID)
            }
            return
        }

        await store.removeSavedProfileSession()
    }

    func resetGuest(
        provider: AIProvider,
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) async {
        let store = store(
            for: provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
        await store.resetGuestSession()
    }
}
