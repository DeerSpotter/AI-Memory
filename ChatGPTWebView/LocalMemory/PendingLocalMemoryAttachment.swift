import Foundation

struct PendingLocalMemoryPayload {
    let fileURLs: [URL]
    let composerText: String
}

enum PendingLocalMemoryAttachment {
    private static let entryIDKey = "PendingLocalMemoryAttachmentEntryID"

    static func mark(_ entry: LocalMemoryEntry) {
        UserDefaults.standard.set(entry.id.uuidString, forKey: entryIDKey)
    }

    static func consumePayload() -> PendingLocalMemoryPayload? {
        guard let idText = UserDefaults.standard.string(forKey: entryIDKey),
              let id = UUID(uuidString: idText) else {
            return nil
        }

        UserDefaults.standard.removeObject(forKey: entryIDKey)

        guard let entries = try? LocalMemoryStore().loadEntries(),
              let entry = entries.first(where: { $0.id == id }) else {
            return nil
        }

        let store = LocalMemoryStore()
        let markdown = store.markdownText(for: entry) ?? entry.content
        let composerText = """
        Continue this saved ChatGPT conversation context. Use the saved context below as project memory. Current instructions override older context.

        \(markdown)
        """

        return PendingLocalMemoryPayload(
            fileURLs: store.fileURLs(for: entry),
            composerText: composerText
        )
    }

    static func consumeFileURLs() -> [URL] {
        consumePayload()?.fileURLs ?? []
    }
}
