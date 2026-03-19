@preconcurrency import AppKit
import Foundation

private struct CaptureJob {
    let capture: RecordedCapture
    let sourceAppName: String?
}

final class DictationController: @unchecked Sendable {
    private let configuration: AppConfiguration
    private let historyStore: HistoryStore
    private let phraseStore: PhraseStore
    private let presentationController: AppPresentationController
    private let hotkeyMonitor = HotkeyMonitor()
    private let audioCaptureController = AudioCaptureController()
    private let whisperService: WhisperService
    private let ollamaFormatter: OllamaFormatter
    private let textInserter: TextInserter
    private let workQueue = DispatchQueue(label: "WisprMenuBar.Dictation")

    init(
        configuration: AppConfiguration,
        historyStore: HistoryStore,
        phraseStore: PhraseStore,
        presentationController: AppPresentationController
    ) throws {
        self.configuration = configuration
        self.historyStore = historyStore
        self.phraseStore = phraseStore
        self.presentationController = presentationController
        whisperService = WhisperService(configuration: configuration)
        ollamaFormatter = try OllamaFormatter(configuration: configuration)
        textInserter = TextInserter(restoreClipboardDelayMs: configuration.restoreClipboardDelayMs)

        hotkeyMonitor.onPress = { [weak self] in self?.beginCapture() }
        hotkeyMonitor.onCancel = { [weak self] in self?.cancelCapture() }
        hotkeyMonitor.onRelease = { [weak self] cancelled in self?.finishCapture(cancelled: cancelled) }
    }

    func start() {
        let hasMicrophoneAccess = Permissions.requestMicrophoneAccessIfNeeded()
        let hasListenAccess = Permissions.requestListenEventAccessIfNeeded()
        let hasAccessibility = Permissions.requestAccessibilityIfNeeded()
        let hasPostEventAccess = Permissions.requestPostEventAccessIfNeeded()
        Task { @MainActor [presentationController] in
            if hasMicrophoneAccess && hasListenAccess && hasAccessibility && hasPostEventAccess {
                presentationController.updateStatus(.ready)
            } else {
                var missingPermissions: [String] = []
                if !hasMicrophoneAccess {
                    missingPermissions.append("Microphone")
                }
                if !hasListenAccess {
                    missingPermissions.append("Input Monitoring")
                }
                if !hasAccessibility {
                    missingPermissions.append("Accessibility")
                }
                if !hasPostEventAccess {
                    missingPermissions.append("Input Monitoring")
                }
                let detail = missingPermissions.isEmpty
                    ? "Grant macOS permissions."
                    : "Grant \(Array(Set(missingPermissions)).joined(separator: " and ")) in System Settings."
                presentationController.updateStatus(.error(detail))
            }
        }
        hotkeyMonitor.start()

        workQueue.async { [weak self] in
            self?.ollamaFormatter.warmup()
        }
    }

    func stop() {
        hotkeyMonitor.stop()
        audioCaptureController.cancelCapture()
    }

    private func beginCapture() {
        do {
            guard Permissions.hasMicrophoneAccess() || Permissions.requestMicrophoneAccessIfNeeded() else {
                Task { @MainActor [presentationController] in
                    presentationController.updateStatus(.error("Grant Microphone access in System Settings > Privacy & Security > Microphone."))
                }
                return
            }
            try audioCaptureController.startCapture()
            Task { @MainActor [presentationController] in
                presentationController.updateStatus(.recording)
            }
        } catch {
            Task { @MainActor [presentationController] in
                presentationController.updateStatus(.error(error.localizedDescription))
            }
        }
    }

    private func cancelCapture() {
        audioCaptureController.cancelCapture()
        Task { @MainActor [presentationController] in
            presentationController.updateStatus(.ready)
        }
    }

    private func finishCapture(cancelled: Bool) {
        guard !cancelled else {
            cancelCapture()
            return
        }

        do {
            guard let capture = try audioCaptureController.finishCapture(minimumCaptureMs: configuration.minimumCaptureMs) else {
                Task { @MainActor [presentationController] in
                    presentationController.updateStatus(.ready)
                }
                return
            }

            let job = CaptureJob(
                capture: capture,
                sourceAppName: NSWorkspace.shared.frontmostApplication?.localizedName
            )

            Task { @MainActor [presentationController] in
                presentationController.updateStatus(.processing)
            }
            workQueue.async { [weak self] in
                self?.process(job)
            }
        } catch {
            Task { @MainActor [presentationController] in
                presentationController.updateStatus(.error(error.localizedDescription))
            }
        }
    }

    private func process(_ job: CaptureJob) {
        do {
            let rawTranscript = try whisperService.transcribe(wavData: job.capture.wavData)
            let formattedText = try ollamaFormatter.format(text: rawTranscript)
            let finalText = phraseStore.apply(to: formattedText)

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Task { @MainActor [presentationController] in
                    presentationController.updateStatus(.ready)
                }
                return
            }

            let insertionResult: Result<TextInsertionMethod, Error> = DispatchQueue.main.sync {
                Result {
                    try textInserter.insertText(finalText)
                }
            }

            historyStore.addEntry(
                rawTranscript: rawTranscript,
                finalText: finalText,
                sourceApp: job.sourceAppName
            )
            let entries = historyStore.recentEntries()
            Task { @MainActor [presentationController, entries, insertionResult] in
                presentationController.updateHistory(entries)
                switch insertionResult {
                case .success:
                    presentationController.updateStatus(.ready)
                case .failure(let error):
                    presentationController.updateStatus(.error(error.localizedDescription))
                }
            }
        } catch {
            Task { @MainActor [presentationController] in
                presentationController.updateStatus(.error(error.localizedDescription))
            }
        }
    }
}
