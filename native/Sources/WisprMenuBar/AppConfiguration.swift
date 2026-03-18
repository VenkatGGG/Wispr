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
    let minimumCaptureMs: Int
    let restoreClipboardDelayMs: Int
    let historyLimit: Int
    let historyFileURL: URL
    let phrasesFileURL: URL

    static func load() throws -> AppConfiguration {
        let fileManager = FileManager.default
        let appSupport = try appSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let repoRoot = try resolveRepositoryRoot(fileManager: fileManager, appSupport: appSupport)

        return AppConfiguration(
            whisperHost: "127.0.0.1",
            whisperPort: 8180,
            whisperModelURL: repoRoot.appendingPathComponent("models/ggml-small.en.bin"),
            whisperLanguage: "en",
            ollamaHost: "127.0.0.1",
            ollamaPort: 11434,
            ollamaModel: "qwen2.5:3b",
            minimumCaptureMs: 180,
            restoreClipboardDelayMs: 120,
            historyLimit: 20,
            historyFileURL: appSupport.appendingPathComponent("history.json"),
            phrasesFileURL: appSupport.appendingPathComponent("phrases.json")
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
        let runtimeConfigURL = appSupport.appendingPathComponent("runtime.json")
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
        ).appendingPathComponent("WisprMenuBar", isDirectory: true)
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
            domain: "WisprMenuBar",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate the repository root containing config.toml. Reinstall the native app so it can refresh its runtime configuration."]
        )
    }
}
