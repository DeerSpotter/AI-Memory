import Foundation

enum LocalMemoryStoreError: LocalizedError {
    case emptyMarkdown
    var errorDescription: String? { "The exported ChatGPT conversation did not contain readable Markdown." }
}

final class LocalMemoryStore {
    private let fm: FileManager
    private let root: URL
    private let pdfs: URL
    private let markdown: URL
    private let visibleRoot: URL
    private let visiblePDFs: URL
    private let visibleMarkdown: URL
    private let index: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.root = support.appendingPathComponent("LocalMemoryVault", isDirectory: true)
        self.pdfs = root.appendingPathComponent("PDFs", isDirectory: true)
        self.markdown = root.appendingPathComponent("Markdown", isDirectory: true)
        self.index = root.appendingPathComponent("entries.json")

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.visibleRoot = documents.appendingPathComponent("ChatGPT Memory", isDirectory: true)
        self.visiblePDFs = visibleRoot.appendingPathComponent("PDFs", isDirectory: true)
        self.visibleMarkdown = visibleRoot.appendingPathComponent("Markdown", isDirectory: true)

        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder; self.decoder = decoder
    }

    func loadEntries() throws -> [LocalMemoryEntry] {
        try ensureFolders()
        guard fm.fileExists(atPath: index.path) else { return [] }
        let data = try Data(contentsOf: index)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([LocalMemoryEntry].self, from: data).sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func saveExportedConversation(projectName: String, title: String, markdownText: String, pdfData: Data, sourceURL: String?, messageCount: Int, exportedAt: String) throws -> LocalMemorySaveResult {
        let body = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw LocalMemoryStoreError.emptyMarkdown }
        var entries = try loadEntries()
        let id = UUID(), now = Date()
        let pdfName = "\(id.uuidString).pdf", mdName = "\(id.uuidString).md"
        let entry = LocalMemoryEntry(id: id, projectName: clean(projectName, "ChatGPT-WebView"), title: clean(title, "ChatGPT exported chat"), content: body, source: clean(sourceURL ?? "chatgpt_web", "chatgpt_web"), tags: ["chat-export", "chatgpt", "context", "local", "markdown", "memory"], importance: 5, createdAt: now, updatedAt: now, pdfFilename: pdfName, markdownFilename: mdName, messageCount: messageCount, exportedAt: exportedAt, attachmentFilenames: [pdfName, mdName])
        try ensureFolders()
        try pdfData.write(to: pdfs.appendingPathComponent(pdfName), options: [.atomic])
        try body.write(to: markdown.appendingPathComponent(mdName), atomically: true, encoding: .utf8)
        try mirrorVisibleFiles(pdfName: pdfName, pdfData: pdfData, markdownName: mdName, markdownText: body)
        entries.append(entry)
        try write(entries)
        return LocalMemorySaveResult(entry: entry, totalCount: entries.count, message: "Saved full ChatGPT chat to Memory, Files app storage, PDF, and Markdown.")
    }

    @discardableResult
    func saveExportedPDF(projectName: String, title: String, pdfData: Data, sourceURL: String?) throws -> LocalMemorySaveResult {
        try saveExportedConversation(projectName: projectName, title: title, markdownText: "# \(title)\n\nPDF only export.", pdfData: pdfData, sourceURL: sourceURL, messageCount: 0, exportedAt: Self.iso.string(from: Date()))
    }

    @discardableResult
    func saveEntry(projectName: String, title: String, content: String, source: String, tags: [String], importance: Int) throws -> LocalMemorySaveResult {
        var entries = try loadEntries()
        let id = UUID(), now = Date()
        let pdfName = "\(id.uuidString).pdf", mdName = "\(id.uuidString).md"
        var entry = LocalMemoryEntry(id: id, projectName: clean(projectName, "Local Project"), title: clean(title, "Untitled memory"), content: clean(content, ""), source: clean(source, "manual"), tags: Array(Set(tags + ["local", "memory"])).sorted(), importance: importance, createdAt: now, updatedAt: now, pdfFilename: pdfName, markdownFilename: mdName, exportedAt: Self.iso.string(from: now), attachmentFilenames: [pdfName, mdName])
        try ensureFolders()
        let pdfURL = pdfs.appendingPathComponent(pdfName)
        try LocalMemoryPDFRenderer.render(entry: entry, to: pdfURL)
        try entry.content.write(to: markdown.appendingPathComponent(mdName), atomically: true, encoding: .utf8)
        if let pdfData = try? Data(contentsOf: pdfURL) {
            try mirrorVisibleFiles(pdfName: pdfName, pdfData: pdfData, markdownName: mdName, markdownText: entry.content)
        }
        entry.pdfFilename = pdfName; entry.markdownFilename = mdName
        entries.append(entry); try write(entries)
        return LocalMemorySaveResult(entry: entry, totalCount: entries.count, message: "Saved context to Memory and Files app storage.")
    }

    func search(_ query: String, limit: Int = 25) throws -> [LocalMemoryEntry] { Array(try loadEntries().prefix(limit)) }
    func renderProjectContext(projectName: String, limit: Int = 20) throws -> String { try loadEntries().prefix(limit).map { $0.title }.joined(separator: "\n") }

    func pdfURL(for entry: LocalMemoryEntry) -> URL? { url(entry.pdfFilename, in: pdfs) ?? url(entry.pdfFilename, in: visiblePDFs) }
    func markdownURL(for entry: LocalMemoryEntry) -> URL? { url(entry.markdownFilename, in: markdown) ?? url(entry.markdownFilename, in: visibleMarkdown) }
    func visiblePDFURL(for entry: LocalMemoryEntry) -> URL? { url(entry.pdfFilename, in: visiblePDFs) }
    func visibleMarkdownURL(for entry: LocalMemoryEntry) -> URL? { url(entry.markdownFilename, in: visibleMarkdown) }
    func markdownText(for entry: LocalMemoryEntry) -> String? { markdownURL(for: entry).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? (entry.content.isEmpty ? nil : entry.content) }
    func fileURLs(for entry: LocalMemoryEntry) -> [URL] { [visiblePDFURL(for: entry), visibleMarkdownURL(for: entry), pdfURL(for: entry), markdownURL(for: entry)].compactMap { $0 }.uniqueByPath() }

    func deleteEntry(_ entry: LocalMemoryEntry) throws {
        var entries = try loadEntries(); entries.removeAll { $0.id == entry.id }
        for fileURL in [pdfURL(for: entry), markdownURL(for: entry), visiblePDFURL(for: entry), visibleMarkdownURL(for: entry)].compactMap({ $0 }) {
            try? fm.removeItem(at: fileURL)
        }
        try write(entries)
    }

    func startNewChatContext(for entry: LocalMemoryEntry) -> String {
        ["Start a new chat using this saved ChatGPT memory bundle.", "", "Title: \(entry.title)", "Source: \(entry.source)", "PDF: \(entry.pdfFilename ?? "none")", "Markdown: \(entry.markdownFilename ?? "none")", "", "Use the PDF and Markdown saved in the app Memory tab as context for this new chat."].joined(separator: "\n")
    }

    private func mirrorVisibleFiles(pdfName: String, pdfData: Data, markdownName: String, markdownText: String) throws {
        try ensureFolders()
        try pdfData.write(to: visiblePDFs.appendingPathComponent(pdfName), options: [.atomic])
        try markdownText.write(to: visibleMarkdown.appendingPathComponent(markdownName), atomically: true, encoding: .utf8)
    }

    private func url(_ name: String?, in folder: URL) -> URL? {
        guard let name else { return nil }
        let url = folder.appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    private func ensureFolders() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: pdfs, withIntermediateDirectories: true)
        try fm.createDirectory(at: markdown, withIntermediateDirectories: true)
        try fm.createDirectory(at: visibleRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: visiblePDFs, withIntermediateDirectories: true)
        try fm.createDirectory(at: visibleMarkdown, withIntermediateDirectories: true)
    }

    private func write(_ entries: [LocalMemoryEntry]) throws { try ensureFolders(); try encoder.encode(entries.sorted { $0.updatedAt > $1.updatedAt }).write(to: index, options: [.atomic]) }
    private func clean(_ value: String, _ fallback: String) -> String { let text = value.trimmingCharacters(in: .whitespacesAndNewlines); return text.isEmpty ? fallback : text }
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
}

private extension Array where Element == URL {
    func uniqueByPath() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.path).inserted }
    }
}
