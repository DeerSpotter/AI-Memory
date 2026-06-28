import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var authEmail: String?
    @Published var statusMessage = ""
    @Published var projects: [MemoryProject] = []
    @Published var selectedProject: MemoryProject?
    @Published var searchResults: [MemoryItem] = []
    @Published var isBusy = false

    private let tokenStore = TokenStore()
    private lazy var authClient = SupabaseAuthClient(
        projectURL: SupabaseConfig.projectURL,
        publishableKey: SupabaseConfig.publishableKey
    )

    private lazy var memoryClient = SupabaseMemoryClient(
        functionURL: SupabaseConfig.memoryFunctionURL,
        publishableKey: SupabaseConfig.publishableKey,
        bearerTokenProvider: { [weak self] in
            guard let self else { throw SupabaseAuthClientError.noSession }
            return try await self.validAccessToken()
        }
    )

    func restoreSession() async {
        guard let session = tokenStore.load() else {
            isAuthenticated = false
            authEmail = nil
            return
        }

        isAuthenticated = true
        authEmail = session.email
        statusMessage = "Signed in as \(session.email ?? "stored session")"
        await refreshProjects()
    }

    func signIn(email: String, password: String) async {
        await runBusy("Signing in...") {
            let session = try await authClient.signIn(email: email, password: password)
            tokenStore.save(session)
            isAuthenticated = true
            authEmail = session.email
            statusMessage = "Signed in."
            await refreshProjects()
        }
    }

    func signUp(email: String, password: String) async {
        await runBusy("Creating account...") {
            let session = try await authClient.signUp(email: email, password: password)
            tokenStore.save(session)
            isAuthenticated = true
            authEmail = session.email
            statusMessage = "Account created and signed in."
            await refreshProjects()
        }
    }

    func signOut() {
        tokenStore.clear()
        isAuthenticated = false
        authEmail = nil
        projects = []
        selectedProject = nil
        searchResults = []
        statusMessage = "Signed out."
    }

    func refreshProjects() async {
        await runBusy("Loading projects...") {
            let loaded = try await memoryClient.listProjects()
            projects = loaded
            if selectedProject == nil {
                selectedProject = loaded.first
            }
            statusMessage = loaded.isEmpty ? "No memory projects yet." : "Loaded \(loaded.count) memory project(s)."
        }
    }

    func createProject(name: String, description: String) async {
        await runBusy("Creating project...") {
            let project = try await memoryClient.createProject(name: name, description: description)
            selectedProject = project
            await refreshProjects()
            statusMessage = "Created project: \(project.name)"
        }
    }

    func saveMemory(title: String, content: String, tags: String) async {
        guard let selectedProject else {
            statusMessage = "Create or select a project first."
            return
        }

        await runBusy("Saving memory...") {
            let tagList = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            _ = try await memoryClient.saveMemory(
                projectID: selectedProject.id,
                title: title,
                content: content,
                tags: tagList
            )
            statusMessage = "Saved memory."
        }
    }

    func searchMemory(query: String) async {
        guard let selectedProject else {
            statusMessage = "Create or select a project first."
            return
        }

        await runBusy("Searching memory...") {
            searchResults = try await memoryClient.searchMemory(projectID: selectedProject.id, query: query)
            statusMessage = "Found \(searchResults.count) result(s)."
        }
    }

    private func validAccessToken() async throws -> String {
        guard var session = tokenStore.load() else {
            throw SupabaseAuthClientError.noSession
        }

        if session.expiresAt > Date().addingTimeInterval(60) {
            return session.accessToken
        }

        let refreshed = try await authClient.refreshSession(refreshToken: session.refreshToken)
        session = refreshed
        tokenStore.save(session)
        return refreshed.accessToken
    }

    private func runBusy(_ message: String, operation: @escaping () async throws -> Void) async {
        isBusy = true
        statusMessage = message
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
