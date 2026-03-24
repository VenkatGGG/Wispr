import Foundation

struct AppConfiguration {
    private struct RuntimeConfiguration: Codable {
        let repositoryRootPath: String
    }

    let whisperHost: String
    let whisperPort: Int
    let whisperModelURL: URL
    let whisperLanguage: String
    let ollamaHost: String
    let ollamaPort: Int
    let ollamaModel: String
    let useOllamaFormatter: Bool
    let formatterPromptURL: URL
    let formatterMaxInputCharacters: Int
    let minimumCaptureMs: Int
    let restoreClipboardDelayMs: Int
    let historyLimit: Int
    let historyFileURL: URL
    let phrasesFileURL: URL

    static func load() throws -> AppConfiguration {
        let fileManager = FileManager.default
        let appSupport = try appSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try migrateLegacySupportFiles(fileManager: fileManager, appSupport: appSupport)
        let repoRoot = try resolveRepositoryRoot(fileManager: fileManager, appSupport: appSupport)
        let configURL = repoRoot.appendingPathComponent("config.toml")

        return AppConfiguration(
            whisperHost: "127.0.0.1",
            whisperPort: 8180,
            whisperModelURL: repoRoot.appendingPathComponent("models/ggml-small.en.bin"),
            whisperLanguage: "en",
            ollamaHost: "127.0.0.1",
            ollamaPort: 11434,
            ollamaModel: "qwen2.5:3b",
            useOllamaFormatter: readBoolean(
                from: configURL,
                section: "formatter",
                key: "enabled"
            ) ?? false,
            formatterPromptURL: repoRoot.appendingPathComponent("prompts/formatter_system.txt"),
            formatterMaxInputCharacters: 4000,
            minimumCaptureMs: 180,
            restoreClipboardDelayMs: 120,
            historyLimit: 20,
            historyFileURL: appSupport.appendingPathComponent(AppIdentity.historyFilename),
            phrasesFileURL: appSupport.appendingPathComponent(AppIdentity.phrasesFilename)
        )
    }

    private static func resolveRepositoryRoot(fileManager: FileManager, appSupport: URL) throws -> URL {
        if let configuredRoot = loadConfiguredRepositoryRoot(appSupport: appSupport),
           fileManager.fileExists(atPath: configuredRoot.appendingPathComponent("config.toml").path) {
            return configuredRoot
        }

        if let envPath = ProcessInfo.processInfo.environment["WISPR_REPO_ROOT"] {
            let envURL = URL(fileURLWithPath: envPath)
            if fileManager.fileExists(atPath: envURL.appendingPathComponent("config.toml").path) {
                return envURL
            }
        }

        return try detectRepositoryRoot(fileManager: fileManager)
    }

    private static func loadConfiguredRepositoryRoot(appSupport: URL) -> URL? {
        let runtimeConfigURL = appSupport.appendingPathComponent(AppIdentity.runtimeConfigurationFilename)
        guard let data = try? Data(contentsOf: runtimeConfigURL),
              let runtimeConfiguration = try? JSONDecoder().decode(RuntimeConfiguration.self, from: data)
        else {
            return nil
        }

        return URL(fileURLWithPath: runtimeConfiguration.repositoryRootPath)
    }

    private static func appSupportDirectory(fileManager: FileManager) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
    }

    private static func migrateLegacySupportFiles(fileManager: FileManager, appSupport: URL) throws {
        let baseSupportDirectory = appSupport.deletingLastPathComponent()
        let legacySupport = baseSupportDirectory.appendingPathComponent(
            AppIdentity.legacySupportDirectoryName,
            isDirectory: true
        )

        guard legacySupport.path != appSupport.path,
              fileManager.fileExists(atPath: legacySupport.path)
        else {
            return
        }

        for filename in [
            AppIdentity.runtimeConfigurationFilename,
            AppIdentity.historyFilename,
            AppIdentity.phrasesFilename,
        ] {
            let sourceURL = legacySupport.appendingPathComponent(filename)
            let destinationURL = appSupport.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path)
            else {
                continue
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func detectRepositoryRoot(fileManager: FileManager) throws -> URL {
        var candidates: [URL] = []

        let bundleRoot = Bundle.main.bundleURL
        var searchRoot = bundleRoot
        for _ in 0..<6 {
            candidates.append(searchRoot)
            searchRoot.deleteLastPathComponent()
        }

        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

        for candidate in candidates {
            let configURL = candidate.appendingPathComponent("config.toml")
            if fileManager.fileExists(atPath: configURL.path) {
                return candidate
            }
        }

        throw NSError(
            domain: AppIdentity.errorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate the repository root containing config.toml. Reinstall the native app so it can refresh its runtime configuration."]
        )
    }

    private static func readBoolean(from configURL: URL, section: String, key: String) -> Bool? {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        var activeSection: String?
        for rawLine in contents.components(separatedBy: .newlines) {
            let uncommented = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let line = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                activeSection = String(line.dropFirst().dropLast())
                continue
            }

            guard activeSection == section,
                  line.hasPrefix("\(key)"),
                  let separatorIndex = line.firstIndex(of: "=")
            else {
                continue
            }

            let rawValue = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            switch rawValue {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}
