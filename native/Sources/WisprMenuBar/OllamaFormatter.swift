import Foundation

final class OllamaFormatter {
    private let configuration: AppConfiguration
    private var process: Process?
    private var modelReady = false

    private let prompt = """
    You format dictated text.

    Rules:
    - Preserve the speaker's meaning and wording unless a correction is obviously needed.
    - Fix grammar, punctuation, capitalization, and sentence boundaries.
    - Remove filler artifacts only when they are clearly transcription noise.
    - Do not summarize, explain, answer, or add new content.
    - Do not wrap the output in quotes.
    - Return only the corrected text.
    - If the input is empty or unintelligible, return an empty string.
    """

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func warmup() {
        do {
            try ensureReady()
            try ensureModelAvailable()
            _ = try generate(prompt: "", timeout: 45)
        } catch {
            NSLog("Ollama warmup failed: \(error.localizedDescription)")
        }
    }

    func format(text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        try ensureReady()
        try ensureModelAvailable()

        let generated = try generate(
            prompt: """
            \(prompt)

            Raw transcript:
            <<<
            \(trimmed)
            >>>

            Corrected text:
            """,
            timeout: 45
        )
        return generated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureReady() throws {
        guard !isReachable() else { return }

        if process == nil || process?.isRunning == false {
            guard let binary = CommandResolver.resolve([
                "/opt/homebrew/bin/ollama",
                "/usr/local/bin/ollama",
            ]) else {
                throw NSError(
                    domain: "WisprMenuBar",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find ollama."]
                )
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: binary)
            task.arguments = ["serve"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run()
            process = task
        }

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if isReachable() {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        throw NSError(
            domain: "WisprMenuBar",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Ollama to start."]
        )
    }

    private func ensureModelAvailable() throws {
        if modelReady { return }
        let tags = try listModels()
        if tags.contains(configuration.ollamaModel) || tags.contains("\(configuration.ollamaModel):latest") {
            modelReady = true
            return
        }

        throw NSError(
            domain: "WisprMenuBar",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Ollama model \(configuration.ollamaModel) is not installed."]
        )
    }

    private func isReachable() -> Bool {
        guard let url = URL(string: "http://\(configuration.ollamaHost):\(configuration.ollamaPort)/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1

        do {
            _ = try HTTPClient.perform(request, timeout: 1)
            return true
        } catch {
            return false
        }
    }

    private func listModels() throws -> [String] {
        let url = URL(string: "http://\(configuration.ollamaHost):\(configuration.ollamaPort)/api/tags")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let data = try HTTPClient.perform(request, timeout: 5)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        return models.compactMap { $0["name"] as? String }
    }

    private func generate(prompt: String, timeout: TimeInterval) throws -> String {
        let url = URL(string: "http://\(configuration.ollamaHost):\(configuration.ollamaPort)/api/generate")!
        let payload: [String: Any] = [
            "model": configuration.ollamaModel,
            "prompt": prompt,
            "stream": false,
            "keep_alive": "15m",
            "options": [
                "temperature": 0,
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try HTTPClient.perform(request, timeout: timeout)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let response = json?["response"] as? String else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected Ollama response."]
            )
        }
        return response
    }
}

