import Foundation

struct PhraseEntry: Codable, Identifiable {
    let id: UUID
    let trigger: String
    let replacement: String
}

final class PhraseStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [PhraseEntry]

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        entries = []
        try ensureFileExists()
        try load()
    }

    func apply(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        return lock.withLock {
            guard let match = entries.first(where: { phrase in
                phrase.trigger.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return text
            }
            return match.replacement
        }
    }

    private func ensureFileExists() throws {
        let fileManager = FileManager.default
        let parentDirectory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        let data = try JSONEncoder.prettyEncoder.encode([PhraseEntry]())
        try data.write(to: fileURL, options: .atomic)
    }

    private func load() throws {
        let data = try Data(contentsOf: fileURL)
        entries = try JSONDecoder.isoDecoder.decode([PhraseEntry].self, from: data)
    }
}
