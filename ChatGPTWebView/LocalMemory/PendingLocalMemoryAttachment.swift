import Foundation

enum PendingLocalMemoryAttachment {
    private static let entryIDKey = "PendingLocalMemoryAttachmentEntryID"

    static func mark(_ entry: LocalMemoryEntry) {
        UserDefaults.standard.set(entry.id.uuidString, forKey: entryIDKey)
    }

    static func consumeFileURLs() -> [URL] {
        guard let idText = UserDefaults.standard.string(forKey: entryIDKey),
              let id = UUID(uuidString: idText) else {
            return []
        }

        UserDefaults.standard.removeObject(forKey: entryIDKey)

        guard let entries = try? LocalMemoryStore().loadEntries(),
              let entry = entries.first(where: { $0.id == id }) else {
            return []
        }

        return LocalMemoryStore().fileURLs(for: entry)
    }
}
