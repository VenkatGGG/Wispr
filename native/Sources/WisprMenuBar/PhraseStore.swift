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

    func allEntries() -> [PhraseEntry] {
        lock.withLock { entries }
    }

    func apply(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let normalizedInput = normalizedForms(for: trimmed)
        return lock.withLock {
            guard let match = entries.first(where: { phrase in
                !normalizedInput.isDisjoint(with: normalizedForms(for: phrase.trigger))
            }) else {
                return text
            }
            return match.replacement
        }
    }

    func add(trigger: String, replacement: String) throws {
        let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTrigger.isEmpty, !normalizedReplacement.isEmpty else {
            throw NSError(
                domain: "Flow",
                code: 50,
                userInfo: [NSLocalizedDescriptionKey: "Both the trigger and replacement are required."]
            )
        }

        try lock.withLock {
            entries.insert(
                PhraseEntry(id: UUID(), trigger: normalizedTrigger, replacement: normalizedReplacement),
                at: 0
            )
            try save()
        }
    }

    func update(id: UUID, trigger: String, replacement: String) throws {
        let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTrigger.isEmpty, !normalizedReplacement.isEmpty else {
            throw NSError(
                domain: "Flow",
                code: 51,
                userInfo: [NSLocalizedDescriptionKey: "Both the trigger and replacement are required."]
            )
        }

        try lock.withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = PhraseEntry(id: id, trigger: normalizedTrigger, replacement: normalizedReplacement)
            try save()
        }
    }

    func remove(id: UUID) {
        lock.withLock {
            entries.removeAll { $0.id == id }
            try? save()
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

    private func save() throws {
        let data = try JSONEncoder.prettyEncoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func normalizedForms(for value: String) -> Set<String> {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !folded.isEmpty else { return [] }

        let punctuationAndWhitespace = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)

        let trimmed = folded.trimmingCharacters(in: punctuationAndWhitespace)
        guard !trimmed.isEmpty else { return [] }

        let collapsedWhitespace = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let alphanumericOnly = collapsedWhitespace.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        var forms: Set<String> = [collapsedWhitespace]
        if !alphanumericOnly.isEmpty {
            forms.insert(alphanumericOnly)
        }
        return forms
    }
}
