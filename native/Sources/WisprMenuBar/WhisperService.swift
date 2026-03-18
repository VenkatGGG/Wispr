import Foundation

final class WhisperService {
    private let configuration: AppConfiguration
    private var process: Process?
    private var resolvedEndpoint: (path: String, fields: [String: String])?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func transcribe(wavData: Data) throws -> String {
        try ensureRunning()

        let attempts: [(path: String, fields: [String: String])] = resolvedEndpoint.map { [$0] } ?? [
            ("/v1/audio/transcriptions", [
                "language": configuration.whisperLanguage,
                "model": "whisper-1",
                "response_format": "json",
            ]),
            ("/inference", [
                "language": configuration.whisperLanguage,
            ]),
            ("/inference", [:]),
        ]

        var errors: [String] = []
        for attempt in attempts {
            do {
                let data = try postAudio(to: attempt.path, fields: attempt.fields, wavData: wavData)
                let text = try extractText(from: data)
                if resolvedEndpoint == nil {
                    resolvedEndpoint = attempt
                }
                return text
            } catch {
                errors.append("\(attempt.path): \(error.localizedDescription)")
            }
        }

        throw NSError(
            domain: "WisprMenuBar",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Whisper transcription failed: \(errors.joined(separator: " | "))"]
        )
    }

    private func ensureRunning() throws {
        guard !isReachable() else { return }

        guard FileManager.default.fileExists(atPath: configuration.whisperModelURL.path) else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Whisper model not found at \(configuration.whisperModelURL.path)"]
            )
        }

        if process == nil || process?.isRunning == false {
            guard let binary = CommandResolver.resolve([
                "/opt/homebrew/bin/whisper-server",
                "/usr/local/bin/whisper-server",
                "/opt/homebrew/bin/whisper-whisper-server",
                "/usr/local/bin/whisper-whisper-server",
            ]) else {
                throw NSError(
                    domain: "WisprMenuBar",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find whisper-server."]
                )
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: binary)
            task.arguments = [
                "--host", configuration.whisperHost,
                "--port", String(configuration.whisperPort),
                "-m", configuration.whisperModelURL.path,
            ]
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
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for whisper-server to start."]
        )
    }

    private func isReachable() -> Bool {
        guard let url = URL(string: "http://\(configuration.whisperHost):\(configuration.whisperPort)/") else {
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

    private func postAudio(to path: String, fields: [String: String], wavData: Data) throws -> Data {
        let boundary = "wispr-\(UUID().uuidString)"
        var body = Data()

        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: "http://\(configuration.whisperHost):\(configuration.whisperPort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try HTTPClient.perform(request, timeout: 30)
    }

    private func extractText(from data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String {
                return try validatedTranscript(text)
            }
            if let segments = json["segments"] as? [[String: Any]] {
                let combined = segments.compactMap { $0["text"] as? String }.joined()
                return try validatedTranscript(combined)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return try validatedTranscript(text)
        }

        throw NSError(
            domain: "WisprMenuBar",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected whisper response."]
        )
    }

    private func validatedTranscript(_ transcript: String) throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let blankMarkers: Set<String> = [
            "",
            "[]",
            "[BLANK_AUDIO]",
            "[NO_SPEECH]",
        ]

        if blankMarkers.contains(trimmed) {
            throw NSError(
                domain: "WisprMenuBar",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "No speech was detected. Check that Flow has microphone access and that the correct input device is active."]
            )
        }

        return trimmed
    }
}
