import Foundation

extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension String {
    func truncated(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let endIndex = index(startIndex, offsetBy: maxLength - 1)
        return String(self[..<endIndex]) + "…"
    }
}

enum HTTPError: Error {
    case invalidResponse
    case timedOut
}

enum HTTPClient {
    static func perform(_ request: URLRequest, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let session = URLSession(configuration: .ephemeral)
        let resultBox = HTTPResultBox()

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                resultBox.set(.failure(error))
                return
            }

            guard let response = response as? HTTPURLResponse, let data else {
                resultBox.set(.failure(HTTPError.invalidResponse))
                return
            }

            guard (200..<300).contains(response.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                resultBox.set(.failure(
                    NSError(
                        domain: "WisprMenuBar",
                        code: response.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.statusCode): \(body)"]
                    )
                ))
                return
            }

            resultBox.set(.success(data))
        }

        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        session.finishTasksAndInvalidate()

        if waitResult == .timedOut {
            task.cancel()
            throw HTTPError.timedOut
        }

        return try resultBox.get().get()
    }
}

enum CommandResolver {
    static func resolve(_ candidates: [String]) -> String? {
        let fileManager = FileManager.default
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }
}

extension JSONEncoder {
    static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var isoDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private final class HTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error> = .failure(HTTPError.timedOut)

    func set(_ result: Result<Data, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func get() -> Result<Data, Error> {
        lock.withLock { result }
    }
}
