@preconcurrency import AppKit
import Foundation

enum AppStatus: Equatable {
    case ready
    case recording
    case processing
    case error(String)

    var menuDescription: String {
        switch self {
        case .ready:
            return "Flow is ready"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var headline: String {
        switch self {
        case .ready:
            return "Ready to dictate"
        case .recording:
            return "Listening"
        case .processing:
            return "Refining your text"
        case .error:
            return "Needs attention"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            return "Hold Option anywhere to capture a dictation."
        case .recording:
            return "Release Option to transcribe and insert."
        case .processing:
            return "Whisper and Ollama are preparing the final text."
        case .error(let message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "waveform.circle"
        case .recording:
            return "record.circle.fill"
        case .processing:
            return "clock.arrow.circlepath"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .ready:
            return .labelColor
        case .recording:
            return .systemRed
        case .processing:
            return .systemOrange
        case .error:
            return .systemYellow
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .ready:
            return "Flow ready"
        case .recording:
            return "Flow recording"
        case .processing:
            return "Flow processing"
        case .error:
            return "Flow error"
        }
    }
}
