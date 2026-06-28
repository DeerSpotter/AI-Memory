import Foundation

public enum SupabaseMemoryClientError: Error, LocalizedError {
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The memory service returned an invalid response."
        case .serverError(let message):
            return message
        }
    }
}

public actor SupabaseMemoryClient {
    private let functionURL: URL
    private let bearerTokenProvider: @Sendable () async throws -> String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        functionURL: URL,
        bearerTokenProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.functionURL = functionURL
        self.bearerTokenProvider = bearerTokenProvider
        self.session = session

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func createProject(name: String, description: String? = nil) async throws -> MemoryProject {
        let response: CreateProjectResponse = try await post([
            "action": "create_project",
            "name": name,
            "content": description as Any
        ])
        return response.project
    }

    public func listProjects() async throws -> [MemoryProject] {
        let response: ListProjectsResponse = try await post([
            "action": "list_projects"
        ])
        return response.projects
    }

    public func createSession(projectID: UUID, title: String) async throws -> MemorySession {
        let response: CreateSessionResponse = try await post([
            "action": "create_session",
            "project_id": projectID.uuidString,
            "title": title
        ])
        return response.session
    }

    public func saveMemory(
        projectID: UUID,
        sessionID: UUID? = nil,
        title: String,
        content: String,
        tags: [String] = []
    ) async throws -> MemoryItem {
        var body: [String: Any] = [
            "action": "save_memory",
            "project_id": projectID.uuidString,
            "title": title,
            "content": content,
            "tags": tags
        ]

        if let sessionID {
            body["session_id"] = sessionID.uuidString
        }

        let response: SaveMemoryResponse = try await post(body)
        return response.memory
    }

    public func searchMemory(projectID: UUID, query: String) async throws -> [MemoryItem] {
        let response: SearchMemoryResponse = try await post([
            "action": "search_memory",
            "project_id": projectID.uuidString,
            "query": query
        ])
        return response.memories
    }

    public func saveSessionSummary(
        projectID: UUID,
        sessionID: UUID? = nil,
        summary: String,
        decisions: [String] = [],
        openTasks: [String] = [],
        filesDiscussed: [String] = [],
        nextSteps: [String] = []
    ) async throws -> MemorySessionSummary {
        var body: [String: Any] = [
            "action": "save_session_summary",
            "project_id": projectID.uuidString,
            "summary": summary,
            "decisions": decisions,
            "open_tasks": openTasks,
            "files_discussed": filesDiscussed,
            "next_steps": nextSteps
        ]

        if let sessionID {
            body["session_id"] = sessionID.uuidString
        }

        let response: SaveSessionSummaryResponse = try await post(body)
        return response.session_summary
    }

    public func getProjectContext(projectID: UUID) async throws -> ProjectContext {
        try await post([
            "action": "get_project_context",
            "project_id": projectID.uuidString
        ])
    }

    private func post<T: Decodable>(_ body: [String: Any]) async throws -> T {
        let token = try await bearerTokenProvider()
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { value in
            if value is NSNull { return nil }
            return value
        })

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseMemoryClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            if let errorPayload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = errorPayload["error"] {
                throw SupabaseMemoryClientError.serverError(message)
            }
            throw SupabaseMemoryClientError.serverError("Memory service failed with HTTP \(httpResponse.statusCode).")
        }

        return try decoder.decode(T.self, from: data)
    }
}
