import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let sourceApp: String?
    let rawTranscript: String
    let finalText: String
}

final class HistoryStore {
    private let fileURL: URL
    private let limit: Int
    private let lock = NSLock()
    private var entries: [HistoryEntry]

    init(fileURL: URL, limit: Int) throws {
        self.fileURL = fileURL
        self.limit = limit
        entries = []
        try load()
    }

    func recentEntries() -> [HistoryEntry] {
        lock.withLock { entries }
    }

    func addEntry(rawTranscript: String, finalText: String, sourceApp: String?) {
        lock.withLock {
            let entry = HistoryEntry(
                id: UUID(),
                createdAt: Date(),
                sourceApp: sourceApp,
                rawTranscript: rawTranscript,
                finalText: finalText
            )
            entries.insert(entry, at: 0)
            if entries.count > limit {
                entries = Array(entries.prefix(limit))
            }
            save()
        }
    }

    private func load() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        entries = try JSONDecoder.isoDecoder.decode([HistoryEntry].self, from: data)
    }

    private func save() {
        do {
            let data = try JSONEncoder.prettyEncoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save history: \(error.localizedDescription)")
        }
    }
}
