@preconcurrency import AppKit
import Foundation

@MainActor
final class AppController {
    private let configuration: AppConfiguration
    private let historyStore: HistoryStore
    private let phraseStore: PhraseStore
    private let presentationController: AppPresentationController
    private let dictationController: DictationController

    init() throws {
        configuration = try AppConfiguration.load()
        historyStore = try HistoryStore(fileURL: configuration.historyFileURL, limit: configuration.historyLimit)
        phraseStore = try PhraseStore(fileURL: configuration.phrasesFileURL)
        presentationController = AppPresentationController(
            historyFileURL: configuration.historyFileURL,
            phrasesFileURL: configuration.phrasesFileURL
        )
        dictationController = DictationController(
            configuration: configuration,
            historyStore: historyStore,
            phraseStore: phraseStore,
            presentationController: presentationController
        )
        presentationController.onQuit = { [weak self] in
            self?.stop()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func start() {
        presentationController.updateHistory(historyStore.recentEntries())
        presentationController.updateStatus(.ready)
        dictationController.start()
    }

    func stop() {
        dictationController.stop()
        presentationController.stop()
    }
}
